import CoreGraphics
import AppKit

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
        // Cleanup zombie activeID : si l'écran référencé a disparu, le retirer.
        if let aid = activeID, !displays.contains(where: { $0.id == aid }) {
            activeID = nil
        }
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

    /// Positionne l'écran actif (appelé par le focus observer, T042).
    /// Retourne `true` si l'id a changé (pour permettre l'émission d'un event).
    @discardableResult
    public func setActive(id: CGDirectDisplayID) -> Bool {
        let changed = activeID != id
        activeID = id
        return changed
    }

    // MARK: Per-display config (SPEC-012 T038, FR-019)

    /// Applique les overrides de config `[[displays]]` sur les `Display` déjà chargés.
    /// Pour chaque display, cherche la première règle qui matche (index > uuid > name)
    /// et copie les overrides dans une nouvelle instance `Display`.
    public func applyRules(_ rules: [DisplayRule]) {
        guard !rules.isEmpty else { return }
        displays = displays.map { d in
            guard let rule = rules.first(where: { matches(rule: $0, display: d) }) else {
                return d
            }
            let strategy = rule.defaultStrategy.map { TilerStrategy(rawValue: $0) } ?? d.tilerStrategy
            return Display(
                id: d.id,
                index: d.index,
                uuid: d.uuid,
                name: d.name,
                frame: d.frame,
                visibleFrame: d.visibleFrame,
                isMain: d.isMain,
                isActive: d.isActive,
                tilerStrategy: strategy,
                gapsOuter: rule.gapsOuter ?? d.gapsOuter,
                gapsInner: rule.gapsInner ?? d.gapsInner
            )
        }
    }

    /// Teste si une `DisplayRule` correspond à un `Display`.
    /// La priorité est : matchIndex, puis matchUUID, puis matchName.
    private func matches(rule: DisplayRule, display: Display) -> Bool {
        if let idx = rule.matchIndex { return idx == display.index }
        if let uuid = rule.matchUUID { return uuid == display.uuid }
        if let name = rule.matchName { return name == display.name }
        return false
    }
}

