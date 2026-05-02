import Foundation

/// Protocol injecté dans DesktopSwitcher pour orchestrer la bascule de stages
/// lors d'une bascule de desktop. Découple RoadieDesktops de RoadieStagePlugin.
/// L'implémentation concrète (StageOpsBridge) vit dans roadied/main.swift.
/// SPEC-011 refactor.
public protocol DesktopStageOps: Sendable {
    /// Retourne l'ID du stage actuellement actif, ou nil si aucun.
    func currentStageID() async -> Int?
    /// Cache toutes les fenêtres du stage actif et met currentStageID à nil.
    func deactivateAll() async
    /// Affiche les fenêtres du stage `stageID` (suppose currentStageID == nil).
    func activate(_ stageID: Int) async
}
