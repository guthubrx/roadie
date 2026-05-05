import Foundation
import AppKit
import ApplicationServices
import RoadieCore

/// SPEC-026 US3 — gestion des scratchpads (workspaces toggleables).
/// Lifecycle :
///   1. `loadConfig(_:)` indexe les `[[scratchpads]]` par nom.
///   2. `toggle(name:)` :
///      - non-lancé → spawn cmd, watch EventBus.window_created 5s pour attacher la wid.
///      - visible → cache via setBounds offscreen + sauvegarde lastVisibleFrame.
///      - caché → restore frame.
@MainActor
public final class ScratchpadManager {
    private weak var registry: WindowRegistry?

    private var defs: [String: ScratchpadDef] = [:]
    private var states: [String: ScratchpadState] = [:]
    private var pendingSpawn: [String: Date] = [:]   // name → spawn timestamp pour timeout 5s
    private static let spawnTimeoutSeconds: TimeInterval = 5.0
    private static let offscreenOrigin = CGPoint(x: -10000, y: -10000)

    public init(registry: WindowRegistry) {
        self.registry = registry
    }

    public func loadConfig(_ scratchpads: [ScratchpadDef]) {
        var indexed: [String: ScratchpadDef] = [:]
        for s in scratchpads {
            indexed[s.name] = s
            if states[s.name] == nil {
                states[s.name] = ScratchpadState(name: s.name)
            }
        }
        defs = indexed
        logInfo("scratchpads_loaded", ["count": String(scratchpads.count)])
    }

    /// Indique si une wid devient un scratchpad attaché. Appelé par le hook
    /// window_created du daemon. Si une scratchpad est en attente, attache.
    public func tryAttachOnWindowCreated(wid: WindowID, bundleID: String?) {
        // Cleanup timeouts.
        let now = Date()
        for (name, ts) in pendingSpawn where now.timeIntervalSince(ts) > Self.spawnTimeoutSeconds {
            pendingSpawn.removeValue(forKey: name)
            logWarn("scratchpad_spawn_timeout", ["name": name])
        }
        guard !pendingSpawn.isEmpty else { return }
        // Match sur le 1er pending dont le bundleID matche.
        for (name, _) in pendingSpawn {
            guard let def = defs[name] else { continue }
            let expected = def.matchBundleID ?? heuristicBundleID(from: def.cmd)
            guard let bid = bundleID, !bid.isEmpty else { continue }
            if expected == nil || bid == expected || bid.contains(expected ?? "") {
                states[name]?.wid = wid
                states[name]?.isVisible = true
                pendingSpawn.removeValue(forKey: name)
                logInfo("scratchpad_attached", [
                    "name": name,
                    "wid": String(wid),
                    "bundle_id": bid,
                ])
                return
            }
        }
    }

    public func toggle(name: String) -> ToggleResult {
        guard let def = defs[name] else {
            return .error("scratchpad '\(name)' not configured")
        }
        guard let state = states[name] else {
            return .error("scratchpad state missing")
        }

        // Cas 1 : pas encore de wid attachée → spawn.
        guard let wid = state.wid else {
            return spawn(def: def)
        }

        // Cas 2 : wid mais plus enregistrée (app quittée) → spawn à nouveau.
        guard let registry = registry, registry.get(wid) != nil else {
            states[name]?.wid = nil
            return spawn(def: def)
        }

        // Cas 3 : visible → cache.
        if state.isVisible {
            return hide(name: name, wid: wid)
        }
        // Cas 4 : caché → restore.
        return show(name: name, wid: wid)
    }

    private func spawn(def: ScratchpadDef) -> ToggleResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", def.cmd]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .error("spawn failed: \(error)")
        }
        pendingSpawn[def.name] = Date()
        logInfo("scratchpad_spawning", ["name": def.name, "cmd": String(def.cmd.prefix(80))])
        return .spawning(name: def.name)
    }

    private func hide(name: String, wid: WindowID) -> ToggleResult {
        guard let registry = registry, let state = registry.get(wid) else {
            return .error("wid not in registry")
        }
        states[name]?.lastVisibleFrame = state.frame
        if let element = registry.axElement(for: wid) {
            // Park offscreen.
            var offFrame = state.frame
            offFrame.origin = Self.offscreenOrigin
            AXReader.setBounds(element, frame: offFrame)
            registry.updateFrame(wid, frame: offFrame)
        }
        states[name]?.isVisible = false
        logInfo("scratchpad_hidden", ["name": name, "wid": String(wid)])
        return .hidden(name: name, wid: wid)
    }

    private func show(name: String, wid: WindowID) -> ToggleResult {
        guard let registry = registry else { return .error("registry gone") }
        let saved = states[name]?.lastVisibleFrame
        if let element = registry.axElement(for: wid) {
            if let frame = saved {
                AXReader.setBounds(element, frame: frame)
                registry.updateFrame(wid, frame: frame)
            }
            // Raise + focus.
            AXReader.raise(element)
            if let s = registry.get(wid),
               let app = NSRunningApplication(processIdentifier: s.pid) {
                app.activate()
            }
        }
        states[name]?.isVisible = true
        logInfo("scratchpad_shown", ["name": name, "wid": String(wid)])
        return .shown(name: name, wid: wid)
    }

    /// Heuristique pour extraire un bundleID probable de la commande shell.
    /// `open -na 'iTerm'` → "iTerm" (peu fiable mais sufficient pour la plupart).
    private func heuristicBundleID(from cmd: String) -> String? {
        // Cherche -n[a]? 'AppName'
        if let r = cmd.range(of: "-na?\\s+['\"]([^'\"]+)['\"]", options: .regularExpression) {
            let match = String(cmd[r])
            if let nameRange = match.range(of: "['\"]([^'\"]+)['\"]", options: .regularExpression) {
                let name = String(match[nameRange]).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                return name
            }
        }
        return nil
    }

    public enum ToggleResult {
        case spawning(name: String)
        case shown(name: String, wid: WindowID)
        case hidden(name: String, wid: WindowID)
        case error(String)
    }
}

/// SPEC-026 US3 — état runtime d'un scratchpad.
public struct ScratchpadState: Sendable {
    public var name: String
    public var wid: WindowID?
    public var isVisible: Bool = false
    public var lastVisibleFrame: CGRect?

    public init(name: String) {
        self.name = name
    }
}
