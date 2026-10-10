import CoreGraphics

/// Seuils de tolérance du moteur de disposition, définis en un seul endroit (SPEC-016 FR-041).
/// Les valeurs en points sont des écarts de cadre ; celles liées aux marges se calculent depuis la config.
public enum LayoutTolerance {
    /// Écart au-delà duquel un cadre observé est considéré comme modifié hors de Roadie.
    public static let observedChange: CGFloat = 16
    /// Écart maximal entre un cadre et l'écran pour parler de fenêtre « qui couvre l'écran ».
    /// Ne suffit jamais seul à déclarer un plein écran (SPEC-016 FR-001).
    public static let fullscreenFrame: CGFloat = 48
    /// Rétrécissement refusé par une application au-delà duquel on mémorise un refus de taille.
    public static let clampShrink: CGFloat = 24
    /// Agrandissement minimal (en points) avant de considérer une croissance comme refusée.
    public static let growthMinimum: CGFloat = 64
    /// Agrandissement minimal relatif avant de considérer une croissance comme refusée.
    public static let growthRatio: CGFloat = 0.35
    /// Déplacement en deçà duquel une demande reprend la position d'une demande déjà refusée.
    public static let clampedPositionDrift: CGFloat = 64
    /// Côté minimal supposé d'une fenêtre tilée quand aucun refus n'a révélé son minimum.
    public static let minimumTileSide: CGFloat = 120
    /// Durée de mémoire d'un refus de taille ou d'un échec d'application, en secondes (FR-004).
    public static let refusalMemorySeconds: Double = 30

    /// Tolérance sur l'écart entre deux fenêtres voisines, dérivée de la marge intérieure configurée.
    public static func innerGapTolerance(gapsInner: CGFloat) -> CGFloat {
        max(8, gapsInner * 0.5)
    }

    /// Part minimale du petit côté du conteneur qu'une tuile d'intent doit garder (avec `minimumTileSide`).
    public static let minimumTileSideRatio: CGFloat = 0.18
    /// Cellule non couverte (en points) au-delà de laquelle un intent ne pave plus le conteneur,
    /// sauf si la marge intérieure configurée est plus grande.
    public static let untiledCell: CGFloat = 24
    /// Écart de centres en deçà duquel deux fenêtres sont sur la même rangée ou la même colonne.
    public static let spatialAlignment: CGFloat = 48
    /// Écart maximal entre cadre demandé et cadre obtenu pour compter une application comme réussie.
    public static let appliedFrame: CGFloat = 48

    // Seuils du maintien de la disposition (SPEC-016 T205, T216).

    /// Égalité de deux cadres à l'arrondi près des applications : rien à appliquer en deçà.
    public static let frameMatch: CGFloat = 2
    /// Écart en deçà duquel une fenêtre est déjà au cadre visé ou observé (bruit d'application).
    public static let frameNear: CGFloat = 8
    /// Écart en deçà duquel une fenêtre n'a pas bougé depuis un échec ou une annulation mémorisés.
    public static let unchangedSinceRefusal: CGFloat = 4
    /// Écart en deçà duquel une commande redemande le même cadre qu'une demande mémorisée.
    public static let sameRequest: CGFloat = 48
    /// Moitié : part minimale d'une aire ou d'une dimension pour qu'un élément soit dominant
    /// (fenêtre qui couvre l'écran, fenêtre bloquante qui traverse la zone visible).
    public static let halfCoverage: CGFloat = 0.5
    /// Alignement d'un bord de fenêtre sur le bord du conteneur dans un arbre BSP modifiable.
    public static let edgeAlignment: CGFloat = 24
    /// Part visible minimale pour qu'une fenêtre soit utilisable : un quart de sa taille, bornée
    /// entre `usableVisibleMinimum` et le maximum de son axe.
    public static let usableVisibleFraction: CGFloat = 0.25
    public static let usableVisibleMinimum: CGFloat = 32
    public static let usableVisibleWidthMaximum: CGFloat = 120
    public static let usableVisibleHeightMaximum: CGFloat = 80

    /// Durée dérivée de l'intervalle du tick : `ticks` intervalles, jamais moins de `minimum` secondes.
    public struct TickDuration: Sendable {
        public let minimum: Double
        public let ticks: Double

        public func seconds(intervalSeconds: Double) -> Double {
            max(minimum, intervalSeconds * ticks)
        }
    }

    /// Protection d'un intent de commande contre un réarrangement immédiat.
    public static let commandIntentHold = TickDuration(minimum: 4, ticks: 10)
    /// Attente après un redimensionnement manuel avant de l'adopter.
    public static let manualResizeDebounce = TickDuration(minimum: 0.35, ticks: 0.9)
    /// Attente après un changement d'écrans avant de rattacher une fenêtre à son écran physique.
    public static let displayDriftReconcileHold = TickDuration(minimum: 8, ticks: 16)
    /// Stabilisation d'un scope après un changement de membres (FR-017).
    public static let stageMembershipSettle = TickDuration(minimum: 2, ticks: 4)
    /// Pause du maintien pendant qu'une topologie d'écrans se stabilise.
    public static let displayTopologySettle = TickDuration(minimum: 1.5, ticks: 4)
    /// Mémoire courte d'un cadre refusé ou échoué, pour ne pas le redemander en boucle.
    public static let recentRefusal = TickDuration(minimum: 3, ticks: 8)
    /// Intervalle minimal entre deux événements répétitifs de suspension, en secondes.
    public static let repeatedEventInterval: Double = 1

    // Validation d'un intent sauvegardé et écart de « chrome » d'une fenêtre focalisée (SPEC-016 T302).

    /// Débord toléré d'une tuile d'intent hors du conteneur.
    public static let intentContainerSlack: CGFloat = 4
    /// Ajouté à la marge intérieure configurée : espace non couvert toléré entre tuiles d'intent.
    public static let intentUntiledGapSlack: CGFloat = 16
    /// Part minimale de l'aire canonique que les tuiles d'un intent doivent couvrir.
    public static let intentMinimumAreaRatio: CGFloat = 0.95
    /// Aire de chevauchement (points²) au-delà de laquelle deux tuiles d'intent se recouvrent.
    public static let intentOverlapArea: CGFloat = 16
    /// Écarts maximaux (x, y ou hauteur, largeur, hauteur) d'une fenêtre focalisée attribués à son
    /// « chrome » (barre d'onglets, d'outils) plutôt qu'à un déplacement : aucune réapplication.
    public static let focusChromeDeltaX: Double = 8
    public static let focusChromeDeltaY: Double = 12
    public static let focusChromeDeltaWidth: Double = 2
    public static let focusChromeDeltaHeight: Double = 80

    /// Grâce avant de retirer un membre ou un épinglage dont la fenêtre a disparu, en secondes (FR-007).
    public static let missingWindowGraceSeconds: Double = 45
}
