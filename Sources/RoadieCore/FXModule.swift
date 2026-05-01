import Foundation
import CoreGraphics

/// ABI C stable entre le daemon et les modules `.dynamicLibrary`.
/// Chaque module exporte une fonction `module_init` via `@_cdecl` qui retourne
/// un pointeur vers cette struct. La struct ne doit jamais être réorganisée
/// entre versions mineures (cf SPEC-004 contracts/fx-module-protocol.md).
public struct FXModuleVTable {
    public let name: UnsafePointer<CChar>
    public let version: UnsafePointer<CChar>
    public let subscribe: @convention(c) (UnsafeMutableRawPointer) -> Void
    public let shutdown: @convention(c) () -> Void

    public init(name: UnsafePointer<CChar>,
                version: UnsafePointer<CChar>,
                subscribe: @escaping @convention(c) (UnsafeMutableRawPointer) -> Void,
                shutdown: @escaping @convention(c) () -> Void) {
        self.name = name
        self.version = version
        self.subscribe = subscribe
        self.shutdown = shutdown
    }
}

/// Wrapper Swift-friendly autour d'une vtable C chargée depuis un dylib.
public final class FXModule: @unchecked Sendable {
    public let name: String
    public let version: String
    public let path: URL
    public let loadedAt: Date
    private let vtable: FXModuleVTable
    private let dylibHandle: UnsafeMutableRawPointer

    public init(vtable: FXModuleVTable, dylibHandle: UnsafeMutableRawPointer, path: URL) {
        self.vtable = vtable
        self.dylibHandle = dylibHandle
        self.path = path
        self.loadedAt = Date()
        self.name = String(cString: vtable.name)
        self.version = String(cString: vtable.version)
    }

    public func subscribe(busPtr: UnsafeMutableRawPointer) {
        vtable.subscribe(busPtr)
    }

    public func shutdown() {
        vtable.shutdown()
    }

    public var handle: UnsafeMutableRawPointer { dylibHandle }
}

/// Événements exposés aux modules FX. Subset stable de l'EventBus interne du daemon.
public enum FXEventKind: String, Sendable {
    case windowCreated = "window_created"
    case windowDestroyed = "window_destroyed"
    case windowFocused = "window_focused"
    case windowMoved = "window_moved"
    case windowResized = "window_resized"
    case stageChanged = "stage_changed"
    case desktopChanged = "desktop_changed"
    case configReloaded = "config_reloaded"
}

/// Payload immuable d'un événement passé à un module FX.
/// Champs optionnels selon le kind. Le module fait sa propre dispatch.
public struct FXEvent: Sendable {
    public let kind: FXEventKind
    public let timestamp: TimeInterval
    public let wid: CGWindowID?
    public let bundleID: String?
    public let frame: CGRect?
    public let isFloating: Bool?
    public let stageID: String?
    public let desktopUUID: String?

    public init(kind: FXEventKind,
                timestamp: TimeInterval = Date().timeIntervalSince1970,
                wid: CGWindowID? = nil,
                bundleID: String? = nil,
                frame: CGRect? = nil,
                isFloating: Bool? = nil,
                stageID: String? = nil,
                desktopUUID: String? = nil) {
        self.kind = kind
        self.timestamp = timestamp
        self.wid = wid
        self.bundleID = bundleID
        self.frame = frame
        self.isFloating = isFloating
        self.stageID = stageID
        self.desktopUUID = desktopUUID
    }
}

/// Bus d'événements exposé aux modules FX.
/// Pointeur opaque côté C ; côté Swift on caste via `FXEventBus.from(opaquePtr:)`.
public final class FXEventBus: @unchecked Sendable {
    public typealias Handler = @Sendable (FXEvent) -> Void
    private var handlers: [(FXEventKind, UUID, Handler)] = []
    private let lock = NSLock()

    public init() {}

    @discardableResult
    public func subscribe(to kinds: [FXEventKind], handler: @escaping Handler) -> UUID {
        let id = UUID()
        lock.lock(); defer { lock.unlock() }
        for kind in kinds { handlers.append((kind, id, handler)) }
        return id
    }

    public func unsubscribe(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        handlers.removeAll { $0.1 == id }
    }

    public func publish(_ event: FXEvent) {
        let snapshot: [Handler] = lock.withLock {
            handlers.filter { $0.0 == event.kind }.map { $0.2 }
        }
        for h in snapshot { h(event) }
    }

    /// Cast d'un pointeur opaque (passé au module via vtable.subscribe) vers le bus Swift.
    public static func from(opaquePtr: UnsafeMutableRawPointer) -> FXEventBus {
        Unmanaged<FXEventBus>.fromOpaque(opaquePtr).takeUnretainedValue()
    }

    public func toOpaquePointer() -> UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        self.lock(); defer { self.unlock() }; return body()
    }
}
