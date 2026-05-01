import Foundation
import RoadieCore

/// Charge les modules FX `.dylib` depuis `~/.local/lib/roadie/`.
/// Détecte l'état SIP de manière informative (non bloquant).
/// Si `dlopen` échoue : log + continue avec les autres modules.
public final class FXLoader: @unchecked Sendable {
    public private(set) var modules: [FXModule] = []
    public let bus: FXEventBus

    public init(bus: FXEventBus = FXEventBus()) {
        self.bus = bus
    }

    public enum SIPState: String {
        case enabled       // SIP fully on : modules chargés mais OSAX ne se connectera pas
        case disabledFS    = "disabled-fs"
        case disabledDebug = "disabled-debug"
        case disabledNVRAM = "disabled-nvram"
        case fullyDisabled = "fully-disabled"
        case unknown
    }

    /// Détecte l'état SIP via `csrutil status`. Pas bloquant pour le chargement.
    public static func detectSIP() -> SIPState {
        let task = Process()
        task.launchPath = "/usr/bin/csrutil"
        task.arguments = ["status"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run(); task.waitUntilExit() } catch { return .unknown }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let lower = output.lowercased()
        if lower.contains("system integrity protection status: disabled") {
            return .fullyDisabled
        }
        if lower.contains("filesystem protections: disabled") { return .disabledFS }
        if lower.contains("debugging restrictions: disabled") { return .disabledDebug }
        if lower.contains("nvram protections: disabled") { return .disabledNVRAM }
        if lower.contains("system integrity protection status: enabled") { return .enabled }
        return .unknown
    }

    /// Scan dylib_dir, dlopen + dlsym + register chaque module. Idempotent.
    @discardableResult
    public func loadAll(config: FXConfig) -> [FXModule] {
        guard !config.disableLoading else { return [] }
        let dir = config.expandedDylibDir
        let fm = FileManager.default
        var loaded: [FXModule] = []
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else {
            return []
        }
        for entry in entries where entry.hasSuffix(".dylib") {
            let path = (dir as NSString).appendingPathComponent(entry)
            if let module = loadOne(at: path) {
                modules.append(module)
                module.subscribe(busPtr: bus.toOpaquePointer())
                loaded.append(module)
            }
        }
        return loaded
    }

    /// Charge un module individuel. Retourne nil et log warning en cas d'erreur.
    public func loadOne(at path: String) -> FXModule? {
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
            let err = String(cString: dlerror())
            FileHandle.standardError.write(Data("fx_loader: dlopen failed for \(path): \(err)\n".utf8))
            return nil
        }
        guard let initSym = dlsym(handle, "module_init") else {
            FileHandle.standardError.write(Data("fx_loader: module_init missing in \(path)\n".utf8))
            dlclose(handle)
            return nil
        }
        typealias InitFn = @convention(c) () -> UnsafeMutableRawPointer?
        let initFn = unsafeBitCast(initSym, to: InitFn.self)
        guard let rawPtr = initFn() else {
            FileHandle.standardError.write(Data("fx_loader: module_init returned null in \(path)\n".utf8))
            dlclose(handle)
            return nil
        }
        let vtablePtr = rawPtr.assumingMemoryBound(to: FXModuleVTable.self)
        let url = URL(fileURLWithPath: path)
        let module = FXModule(vtable: vtablePtr.pointee, dylibHandle: handle, path: url)
        return module
    }

    /// Décharge tous les modules : appelle shutdown puis dlclose.
    public func unloadAll() {
        for module in modules {
            module.shutdown()
            dlclose(module.handle)
        }
        modules.removeAll()
    }

    /// État actuel pour `roadie fx status`.
    public func statusJSON(sipState: SIPState, osaxConnected: Bool) -> [String: Any] {
        let modulesArray: [[String: Any]] = modules.map { m in
            [
                "name": m.name,
                "version": m.version,
                "loaded_at": ISO8601DateFormatter().string(from: m.loadedAt)
            ]
        }
        return [
            "sip": sipState.rawValue,
            "osax": osaxConnected ? "healthy" : "absent",
            "modules": modulesArray
        ]
    }
}
