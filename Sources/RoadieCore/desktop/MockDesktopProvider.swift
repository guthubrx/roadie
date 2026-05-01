import Foundation

/// Mock injectable pour tests unitaires : pas d'appel SkyLight, scénarios scriptables.
@MainActor
public final class MockDesktopProvider: DesktopProvider {
    public var desktops: [DesktopInfo]
    public var currentUUID: String?

    /// Trace des appels `requestFocus` pour vérification dans les tests.
    public private(set) var focusRequests: [String] = []

    public init(desktops: [DesktopInfo] = [], currentUUID: String? = nil) {
        self.desktops = desktops
        self.currentUUID = currentUUID
    }

    public func currentDesktopUUID() -> String? { currentUUID }

    public func listDesktops() -> [DesktopInfo] { desktops }

    public func requestFocus(uuid: String) {
        focusRequests.append(uuid)
        if desktops.contains(where: { $0.uuid == uuid }) {
            currentUUID = uuid
        }
    }

    /// Simule une transition utilisateur (Mission Control). Met à jour `currentUUID` puis
    /// laisse l'observer NSWorkspace fire (le test invoque manuellement `handleSpaceChange`).
    public func simulateTransition(to uuid: String) {
        currentUUID = uuid
    }
}
