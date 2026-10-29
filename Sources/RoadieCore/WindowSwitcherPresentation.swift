import Foundation
import RoadieCore

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
        case .classic: tr("Grille classique", "Classic grid")
        case .stageColumns: tr("Colonnes par stage", "Columns by stage")
        case .desktopTabs: tr("Bureaux en onglets", "Desktops as tabs")
        case .hierarchy: tr("Navigation hiérarchique", "Hierarchical navigation")
        case .sections: tr("Grille par sections", "Grid by sections")
        case .overview: tr("Vue d'ensemble des bureaux", "Desktop overview")
        }
    }
}
