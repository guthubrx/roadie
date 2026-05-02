import AppKit
import CoreGraphics
import CoreFoundation

// MARK: - Display (SPEC-012 FR-001, R-001)

/// Représente un écran physique connecté.
/// Sendable + Codable pour permettre la sérialisation et le passage inter-acteurs.
/// Source de vérité : `DisplayRegistry` (in-memory, recalculé à chaque
/// `didChangeScreenParameters`).
public struct Display: Sendable, Codable, Equatable {

    // MARK: Identité

    /// Identifiant Quartz — stable pendant la session (remis à zéro au reboot).
    public let id: CGDirectDisplayID
    /// Index 1-based dans `NSScreen.screens` au moment du `refresh()`.
    public let index: Int
    /// UUID stable cross-reboot obtenu via `CGDisplayCreateUUIDFromDisplayID`.
    /// Sert de clé persistante pour retrouver l'écran d'origine (FR-001, R-001).
    public let uuid: String
    /// Nom localisé de l'écran ("Built-in Retina Display", "Dell U2723D"…).
    public let name: String

    // MARK: Géométrie (coords globales Quartz / NS)

    /// Rect de l'écran en coordonnées globales Quartz (origin bas-gauche sur macOS).
    public let frame: CGRect
    /// Rect visible après soustraction menu bar + dock.
    public let visibleFrame: CGRect

    // MARK: État

    /// `true` si c'est l'écran principal (`NSScreen.main`).
    public let isMain: Bool
    /// `true` si cet écran contient la fenêtre frontmost.
    public let isActive: Bool

    // MARK: Tiling — paramètres par écran

    /// Stratégie de tiling pour cet écran (peut être overridée via config `[[displays]]`).
    public let tilerStrategy: TilerStrategy
    /// Marge extérieure en pixels.
    public let gapsOuter: Int
    /// Espacement entre fenêtres en pixels.
    public let gapsInner: Int

    // MARK: Init canonique

    public init(id: CGDirectDisplayID,
                index: Int,
                uuid: String,
                name: String,
                frame: CGRect,
                visibleFrame: CGRect,
                isMain: Bool,
                isActive: Bool,
                tilerStrategy: TilerStrategy,
                gapsOuter: Int,
                gapsInner: Int) {
        self.id = id
        self.index = index
        self.uuid = uuid
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
        self.isActive = isActive
        self.tilerStrategy = tilerStrategy
        self.gapsOuter = gapsOuter
        self.gapsInner = gapsInner
    }

    // MARK: Convenience depuis NSScreen (R-001)

    /// Construit un `Display` depuis un `NSScreen`.
    /// - Parameters:
    ///   - nsScreen: écran source
    ///   - index: position 1-based dans `NSScreen.screens`
    ///   - isActive: `true` si l'écran contient la fenêtre frontmost
    ///   - strategy: stratégie de tiling à appliquer
    ///   - gapsOuter: marge extérieure px
    ///   - gapsInner: espacement interne px
    public static func from(nsScreen: NSScreen,
                            index: Int,
                            isActive: Bool,
                            strategy: TilerStrategy,
                            gapsOuter: Int,
                            gapsInner: Int) -> Display {
        let rawScreenNumber = nsScreen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ]
        let displayID = rawScreenNumber as? CGDirectDisplayID ?? 0
        if displayID == 0 {
            // Pas de log structure ici (RoadieCore Logger non importable depuis ce
            // contexte sans cycle), on stderr direct. Utile pour reperer un ecran
            // dont NSScreenNumber est manquant — devrait etre tres rare.
            FileHandle.standardError.write(Data(
                "Display.from: NSScreenNumber absent ou type inattendu pour ecran '\(nsScreen.localizedName)' — displayID=0, UUID nil\n".utf8))
        }

        let uuid = displayUUIDString(for: displayID)
        let isMain = (nsScreen == NSScreen.main)

        return Display(
            id: displayID,
            index: index,
            uuid: uuid,
            name: nsScreen.localizedName,
            frame: nsScreen.frame,
            visibleFrame: nsScreen.visibleFrame,
            isMain: isMain,
            isActive: isActive,
            tilerStrategy: strategy,
            gapsOuter: gapsOuter,
            gapsInner: gapsInner
        )
    }
}

// MARK: - Helpers privés

/// Retourne l'UUID stable d'un `CGDirectDisplayID` sous forme de String.
/// Utilise `CGDisplayCreateUUIDFromDisplayID` (CoreGraphics public API).
private func displayUUIDString(for displayID: CGDirectDisplayID) -> String {
    guard displayID != 0,
          let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
    else { return "00000000-0000-0000-0000-000000000000" }
    let str = CFUUIDCreateString(nil, cfUUID) as String? ?? "00000000-0000-0000-0000-000000000000"
    return str
}
