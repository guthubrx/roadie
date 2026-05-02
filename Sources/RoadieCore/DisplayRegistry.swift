import CoreGraphics

// MARK: - DisplayRegistry (SPEC-012 R-001..R-003, FR-001..FR-003, FR-005)

/// Acteur Swift détenant la liste des écrans physiques connus.
/// Source de vérité in-memory, reconstruite à chaque `refresh()`.
///
/// Règle d'utilisation :
/// - `refresh()` est appelé au boot depuis `roadied/main.swift`, puis à
///   chaque `NSApplication.didChangeScreenParametersNotification` (T009).
/// - `displayContaining(point:)` utilise les coordonnées NS (origine bas-gauche).
public actor DisplayRegistry {

    // MARK: État

    /// Liste des écrans actifs, triée par `index` (1-based).
    public private(set) var displays: [Display]

    /// Identifiant de l'écran qui contient la fenêtre frontmost.
    public private(set) var activeID: CGDirectDisplayID?

    // MARK: Dépendances

    private let provider: any DisplayProvider
    private let defaultStrategy: TilerStrategy
    private let defaultGapsOuter: Int
    private let defaultGapsInner: Int

    // MARK: Init

    public init(provider: any DisplayProvider = NSScreenDisplayProvider(),
                defaultStrategy: TilerStrategy = .bsp,
                defaultGapsOuter: Int = 8,
                defaultGapsInner: Int = 4) {
        self.provider = provider
        self.defaultStrategy = defaultStrategy
        self.defaultGapsOuter = defaultGapsOuter
        self.defaultGapsInner = defaultGapsInner
        self.displays = []
        self.activeID = nil
    }

    // MARK: Mise à jour

    /// Re-énumère les écrans depuis le provider et met à jour `displays`.
    /// Appelé au boot + à chaque `didChangeScreenParametersNotification`.
    public func refresh() {
        let screens = provider.currentScreens()
        var next: [Display] = []
        for (i, screen) in screens.enumerated() {
            let isActive: Bool
            if let aid = activeID {
                let did = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? CGDirectDisplayID
                isActive = did == aid
            } else {
                isActive = false
            }
            next.append(.from(
                nsScreen: screen,
                index: i + 1,
                isActive: isActive,
                strategy: defaultStrategy,
                gapsOuter: defaultGapsOuter,
                gapsInner: defaultGapsInner
            ))
        }
        displays = next
    }

    // MARK: Accesseurs (FR-001..FR-003)

    /// Nombre d'écrans connus.
    public var count: Int { displays.count }

    /// Écran à l'index 1-based (FR-010 : range check à la charge de l'appelant).
    public func display(at index: Int) -> Display? {
        displays.first { $0.index == index }
    }

    /// Écran par son `CGDirectDisplayID` (stable pendant la session).
    public func display(forID id: CGDirectDisplayID) -> Display? {
        displays.first { $0.id == id }
    }

    /// Écran par son UUID stable cross-reboot.
    public func display(forUUID uuid: String) -> Display? {
        displays.first { $0.uuid == uuid }
    }

    /// Retourne l'écran dont le `frame` contient `point` (FR-005).
    /// Le point doit être en coordonnées NS (origine bas-gauche).
    /// Si aucun écran ne contient le point, retourne le principal (`isMain`).
    public func displayContaining(point: CGPoint) -> Display? {
        if let hit = displays.first(where: { $0.frame.contains(point) }) {
            return hit
        }
        return displays.first { $0.isMain } ?? displays.first
    }

    // MARK: Mutations

    /// Positionne l'écran actif (appelé par le focus observer, T041+).
    public func setActive(id: CGDirectDisplayID) {
        activeID = id
    }
}

// MARK: - Import AppKit conditionnel pour NSDeviceDescriptionKey dans refresh()

import AppKit
