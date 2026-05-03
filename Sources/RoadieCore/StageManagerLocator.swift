import Foundation

// SPEC-021 : service locator permettant à WindowState (RoadieCore) d'interroger
// le StageManager (RoadieStagePlugin) sans créer de dépendance circulaire.
// WindowState.stageID (computed) délègue à StageManagerLocator.shared?.stageIDOf(wid:).
// Le daemon branche StageManagerLocator.shared = stageManager au boot.

/// Protocol sans isolation actor : la méthode est appelée depuis la computed property
/// de WindowState (nonisolated). Le daemon est single-threaded sur MainActor, donc
/// l'appel est toujours sur le bon thread en pratique.
public protocol StageManagerProtocol: AnyObject {
    func stageIDOf(wid: WindowID) -> StageID?
}

/// Locator singleton initialisé au boot du daemon.
/// Weak reference : pas de retain cycle entre RoadieCore et RoadieStagePlugin.
/// `nonisolated(unsafe)` : le daemon est single-threaded sur MainActor ; la var
/// est settée une fois au boot avant tout accès concurrent possible.
public enum StageManagerLocator {
    nonisolated(unsafe) public static weak var shared: (any StageManagerProtocol)?
}
