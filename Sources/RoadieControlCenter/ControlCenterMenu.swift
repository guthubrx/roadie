import Foundation
import RoadieCore

public enum ControlCenterMenuAction: String, CaseIterable, Sendable {
    case openSettings
    case reloadConfig
    case reapplyLayout
    case revealConfig
    case revealState
    case openLogs
    case runDoctor
    case quitSafely
}

public struct ControlCenterMenuItem: Equatable, Sendable {
    public var title: String
    public var action: ControlCenterMenuAction?
    public var isEnabled: Bool

    public init(title: String, action: ControlCenterMenuAction? = nil, isEnabled: Bool = true) {
        self.title = title
        self.action = action
        self.isEnabled = isEnabled
    }
}

public struct ControlCenterMenuModel: Equatable, Sendable {
    public var items: [ControlCenterMenuItem]

    public init(state: ControlCenterState) {
        var items: [ControlCenterMenuItem] = [
            ControlCenterMenuItem(title: "Roadie: \(state.daemonStatus.rawValue)"),
            ControlCenterMenuItem(title: "Config: \(state.configStatus.rawValue)"),
            ControlCenterMenuItem(title: "Desktop: \(state.activeDesktop ?? "-") / Stage: \(state.activeStage ?? "-")"),
            ControlCenterMenuItem(title: "Windows: \(state.windowCount)")
        ]
        if let lastError = state.lastError {
            items.append(ControlCenterMenuItem(title: "Erreur: \(lastError)", isEnabled: false))
        }
        items.append(contentsOf: [
            ControlCenterMenuItem(title: "Reglages", action: .openSettings),
            ControlCenterMenuItem(title: "Recharger la config", action: .reloadConfig, isEnabled: state.actions.canReloadConfig),
            ControlCenterMenuItem(title: "Reappliquer le layout", action: .reapplyLayout, isEnabled: state.actions.canReapplyLayout),
            ControlCenterMenuItem(title: "Reveler la config", action: .revealConfig, isEnabled: state.actions.canRevealConfig),
            ControlCenterMenuItem(title: "Reveler l'etat", action: .revealState, isEnabled: state.actions.canRevealState),
            ControlCenterMenuItem(title: "Ouvrir les logs", action: .openLogs),
            ControlCenterMenuItem(title: "Doctor", action: .runDoctor),
            ControlCenterMenuItem(title: "Quitter Roadie", action: .quitSafely, isEnabled: state.actions.canQuitSafely)
        ])
        self.items = items
    }
}
