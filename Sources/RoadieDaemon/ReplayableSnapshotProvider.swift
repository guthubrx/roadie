import AppKit
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler

/// Fournisseur qui garde son dernier relevé et peut le rejouer une fois (R11, T210) : la copie de
/// travail d'une passe qui change l'état logique (règle, déplacement adopté, dérive d'écran) se
/// reconstruit sur les fenêtres déjà relevées, sans second relevé AX. Hors rejeu, il délègue.
public final class ReplayableSnapshotProvider: SystemSnapshotProviding, @unchecked Sendable {
    private struct Scan {
        var permissions: PermissionSnapshot?
        var displays: [DisplaySnapshot]?
        var windows: [WindowSnapshot]?
        var existingWindowPIDs: [WindowID: Int32]??
        var focusedWindowID: WindowID??
        var mouseLocation: CGPoint??
    }

    private let base: any SystemSnapshotProviding
    private let lock = NSLock()
    private var last = Scan()
    private var replay = Scan()

    public init(base: any SystemSnapshotProviding) {
        self.base = base
    }

    /// Chaque lecture suivante rend, une fois, sa valeur du dernier relevé. O(1).
    public func replayLastScan() {
        lock.withLock { replay = last }
    }

    public func permissions(prompt: Bool) -> PermissionSnapshot {
        served(\.permissions) ?? recorded(\.permissions, base.permissions(prompt: prompt))
    }

    public func displays() -> [DisplaySnapshot] {
        served(\.displays) ?? recorded(\.displays, base.displays())
    }

    public func windows() -> [WindowSnapshot] {
        served(\.windows) ?? recorded(\.windows, base.windows())
    }

    public func existingWindowPIDs() -> [WindowID: Int32]? {
        served(\.existingWindowPIDs) ?? recorded(\.existingWindowPIDs, base.existingWindowPIDs())
    }

    public func focusedWindowID() -> WindowID? {
        served(\.focusedWindowID) ?? recorded(\.focusedWindowID, base.focusedWindowID())
    }

    @MainActor public func focusedWindowReader() -> @Sendable () -> WindowID? {
        let read = base.focusedWindowReader()
        return { self.recorded(\.focusedWindowID, read()) }
    }

    public func mouseLocation() -> CGPoint? {
        served(\.mouseLocation) ?? recorded(\.mouseLocation, base.mouseLocation())
    }

    /// Valeur rejouée et consommée, nil hors rejeu.
    private func served<Value>(_ field: WritableKeyPath<Scan, Value?>) -> Value? {
        lock.withLock {
            defer { replay[keyPath: field] = nil }
            return replay[keyPath: field]
        }
    }

    private func recorded<Value>(_ field: WritableKeyPath<Scan, Value?>, _ value: Value) -> Value {
        lock.withLock { last[keyPath: field] = value }
        return value
    }
}
