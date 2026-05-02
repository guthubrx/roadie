import AppKit

// MARK: - DisplayProvider (SPEC-012 R-011)

/// Protocol d'abstraction pour l'énumération des écrans.
/// Permet l'injection de mocks dans les tests sans dépendance à `NSScreen.screens`.
public protocol DisplayProvider: Sendable {
    func currentScreens() -> [NSScreen]
}

// MARK: - Production impl

/// Implémentation production : délègue directement à `NSScreen.screens`.
public struct NSScreenDisplayProvider: DisplayProvider {
    public init() {}

    public func currentScreens() -> [NSScreen] {
        NSScreen.screens
    }
}

// MARK: - Mock impl (tests)

/// Implémentation mock injectable en tests.
/// `@unchecked Sendable` car `screens` est mutable mais les tests
/// contrôlent l'accès séquentiellement.
public final class MockDisplayProvider: DisplayProvider, @unchecked Sendable {
    public var screens: [NSScreen]

    public init(screens: [NSScreen] = []) {
        self.screens = screens
    }

    public func currentScreens() -> [NSScreen] {
        screens
    }
}
