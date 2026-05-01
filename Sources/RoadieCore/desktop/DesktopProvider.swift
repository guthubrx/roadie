import Foundation

/// Source de vérité pour la liste des desktops macOS et le desktop courant.
/// Protocole pour permettre l'injection d'un mock dans les tests
/// (cf. research.md décision 7).
@MainActor
public protocol DesktopProvider: AnyObject {
    /// UUID du desktop macOS actuellement actif. nil si la lecture SkyLight échoue.
    func currentDesktopUUID() -> String?

    /// Liste tous les desktops actuellement connus de macOS, dans l'ordre Mission Control.
    /// Les labels sont posés par roadie (pas par macOS), donc retourne nil par défaut ;
    /// `DesktopManager` les enrichira via les DesktopState persistés.
    func listDesktops() -> [DesktopInfo]

    /// Demande à macOS de basculer vers le desktop d'UUID `uuid`.
    /// Best-effort : si l'API privée refuse ou si l'UUID est inconnu, ne fait rien
    /// (un `desktop_changed` sera quand même émis si l'utilisateur navigue manuellement).
    func requestFocus(uuid: String)
}
