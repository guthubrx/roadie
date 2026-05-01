import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Type du hook appelé à chaque transition de desktop. Le daemon le branche pour
/// orchestrer save → load → re-layout. `from` est nil au boot (transition initiale).
public typealias DesktopTransitionHandler = @MainActor (_ from: String?, _ to: String) async -> Void

/// Observe le desktop macOS courant et notifie le daemon à chaque transition.
/// La détection passe par `NSWorkspace.activeSpaceDidChangeNotification` (public,
/// stable depuis macOS 10.6) couplé à `CGSGetActiveSpace` pour récupérer l'UUID
/// (research.md décision 1).
@MainActor
public final class DesktopManager {

    private let provider: DesktopProvider
    public private(set) var currentUUID: String?
    public private(set) var recentUUID: String?
    /// Pose le label utilisateur pour un UUID (en mémoire, persisté côté DesktopState).
    private var labels: [String: String] = [:]
    /// Hook appelé à chaque transition. Branché par roadied/main.
    public var onTransition: DesktopTransitionHandler?
    public var backAndForth: Bool

    private var observerToken: NSObjectProtocol?

    public init(provider: DesktopProvider, backAndForth: Bool = true) {
        self.provider = provider
        self.backAndForth = backAndForth
    }

    deinit {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Lifecycle

    /// Démarre l'observation NSWorkspace et déclenche la transition initiale (from=nil, to=current).
    public func start() {
        loadPersistedLabels()
        #if canImport(AppKit)
        observerToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.handleSpaceChange() }
        }
        #endif
        // Transition initiale (boot) — synchrone pour avoir un état cohérent dès le départ.
        Task { @MainActor in await self.handleSpaceChange() }
    }

    /// Charge les labels persistés depuis `~/.config/roadies/desktops/<uuid>/label.txt`
    /// (cf. CommandRouter.persistDesktopLabel). Permet aux labels de survivre au redémarrage.
    private func loadPersistedLabels() {
        let home = NSString(string: "~").expandingTildeInPath
        let root = "\(home)/.config/roadies/desktops"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { return }
        for entry in entries {
            let labelPath = "\(root)/\(entry)/label.txt"
            if let label = try? String(contentsOfFile: labelPath, encoding: .utf8) {
                let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { labels[entry] = trimmed }
            }
        }
    }

    /// Récupère l'UUID courant via SkyLight et déclenche `onTransition` si différent.
    /// Mesure la latence (FR-003 / SC-001) et log warning si > 200 ms.
    /// Publie un event `desktop_changed` sur l'EventBus partagé (FR-015).
    public func handleSpaceChange() async {
        guard let newUUID = provider.currentDesktopUUID() else { return }
        guard newUUID != currentUUID else { return }
        let from = currentUUID
        let started = Date()
        recentUUID = from
        currentUUID = newUUID

        // Lookup index/label avant et après pour enrichir le payload event.
        let desktops = provider.listDesktops()
        let toInfo = desktops.first(where: { $0.uuid == newUUID })
        let fromInfo: DesktopInfo? = from.flatMap { f in desktops.first(where: { $0.uuid == f }) }
        var payload: [String: String] = [
            "to": newUUID,
            "to_index": String(toInfo?.index ?? 0),
            "to_label": labels[newUUID] ?? "",
        ]
        if let f = from {
            payload["from"] = f
            payload["from_index"] = String(fromInfo?.index ?? 0)
            payload["from_label"] = labels[f] ?? ""
        }
        EventBus.shared.publish(DesktopEvent(name: "desktop_changed", payload: payload))

        await onTransition?(from, newUUID)
        let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
        if latencyMs > 200 {
            logWarn("desktop transition slow",
                    ["from": from ?? "nil", "to": newUUID, "ms": String(latencyMs)])
        } else {
            logDebug("desktop transition",
                     ["from": from ?? "nil", "to": newUUID, "ms": String(latencyMs)])
        }
    }

    // MARK: - Selectors (FR-010 / FR-013)

    /// Résout un selector CLI (`prev|next|recent|first|last|<index>|<label>`) en UUID cible.
    /// Retourne nil si le selector est inconnu. Gère `back_and_forth` quand le selector
    /// match le desktop courant.
    public func resolveSelector(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let desktops = provider.listDesktops()
        guard !desktops.isEmpty else { return nil }

        let target: String?
        switch s {
        case "recent", "back": target = recentUUID
        case "first": target = desktops.first?.uuid
        case "last": target = desktops.last?.uuid
        case "next":
            if let cur = currentUUID, let i = desktops.firstIndex(where: { $0.uuid == cur }) {
                target = desktops[(i + 1) % desktops.count].uuid
            } else { target = desktops.first?.uuid }
        case "prev":
            if let cur = currentUUID, let i = desktops.firstIndex(where: { $0.uuid == cur }) {
                target = desktops[(i - 1 + desktops.count) % desktops.count].uuid
            } else { target = desktops.last?.uuid }
        default:
            if let n = Int(s), n >= 1, n <= desktops.count {
                target = desktops[n - 1].uuid
            } else if let entry = desktops.first(where: { labels[$0.uuid] == s }) {
                target = entry.uuid
            } else {
                target = nil
            }
        }

        // Back-and-forth : si la cible est le desktop courant et que back_and_forth est on,
        // bascule au recent à la place.
        if backAndForth, let t = target, t == currentUUID, let r = recentUUID {
            return r
        }
        return target
    }

    /// Demande à macOS de basculer vers l'UUID cible. Best-effort.
    public func focus(uuid: String) {
        provider.requestFocus(uuid: uuid)
    }

    // MARK: - Labels

    public func label(for uuid: String) -> String? { labels[uuid] }

    public func setLabel(_ name: String?, for uuid: String) {
        if let n = name, !n.isEmpty { labels[uuid] = n } else { labels.removeValue(forKey: uuid) }
    }

    /// Liste enrichie : combine `provider.listDesktops()` avec les labels en mémoire.
    public func listDesktops() -> [DesktopInfo] {
        provider.listDesktops().map { info in
            DesktopInfo(uuid: info.uuid, index: info.index, label: labels[info.uuid])
        }
    }
}
