import Foundation

/// Organisation indépendante du style des cartes (vignettes, icônes, liste).
public enum WindowSwitcherPresentation: String, CaseIterable, Codable, Sendable {
    case classic
    case stageColumns = "stage_columns"
    case desktopTabs = "desktop_tabs"
    case hierarchy
    case sections
    case overview

    public var label: String {
        switch self {
        case .classic: "Grille classique"
        case .stageColumns: "Colonnes par stage"
        case .desktopTabs: "Bureaux en onglets"
        case .hierarchy: "Navigation hiérarchique"
        case .sections: "Grille par sections"
        case .overview: "Vue d'ensemble des bureaux"
        }
    }
}
