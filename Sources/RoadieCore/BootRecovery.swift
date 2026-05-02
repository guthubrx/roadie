import Foundation
import CoreGraphics

// MARK: - BootRecovery (SPEC-013 — extraction de la logique pure)

/// Logique de décision pour la recovery au boot des fenêtres orphelines /
/// dégénérées. Module pur sans dépendance AX — testable en isolation.
///
/// L'appelant (`Daemon.bootstrap`) invoque `BootRecovery.decide(...)` avec
/// l'état observable (frame AX, expectedFrame, optionnel CG bounds), reçoit
/// une `Decision` typée, et applique les side-effects AX correspondants.
///
/// Cette séparation supprime la "crassitude" mélangée à la logique :
/// - F1 (double setBounds) → encodé explicitement dans `Decision.restore` avec
///   `requiresWakeRetry: Bool` justifié par le flag d'AX-collapsed.
/// - F2 (setMinimized agressif) → ne s'applique QUE si la fenêtre a une trace
///   prouvant qu'elle était précédemment valide (expectedFrame.size.height >= 20).
///   Une fenêtre intentionnellement minimisée par l'utilisateur (sans
///   expectedFrame valide) est ignorée.
/// - F3 (balanceWeights inconditionnel) → encodé via `BootRecovery.shouldBalance`
///   qui retourne true uniquement si le tree contient au moins un weight
///   < `minHealthyWeight`.
public enum BootRecovery {

    /// Seuil minimal pour considérer une frame valide. < 20px height = la fenêtre
    /// est probablement collapsed/offscreen (les fenêtres macOS légitimes les
    /// plus petites — popovers, toolbars — restent au-dessus de ce seuil).
    public static let minValidHeight: CGFloat = 20

    /// Seuil de "fenêtre clairement offscreen vers le bas" — les fenêtres
    /// AeroSpace-hide sont placées avec Y très négatif, distinctes des fenêtres
    /// déplacées par l'utilisateur sur un Stage Manager iPad-like.
    public static let suspiciousOffscreenY: CGFloat = -500

    /// Seuil minimal en dessous duquel un weight d'arbre BSP est considéré
    /// dégénéré (typiquement 0.001 après plusieurs drags consécutifs).
    public static let minHealthyWeight: Double = 0.05

    /// Décision pour une fenêtre individuelle.
    public enum Decision: Equatable {
        /// La fenêtre est saine, ne rien faire.
        case keep
        /// Adopter les bounds CG comme source de vérité (mismatch AX/CG résolu
        /// sans wake). expectedFrame mis à jour aussi.
        case adoptCGBounds(CGRect)
        /// Restaurer la fenêtre à `target`. `requiresWake` indique qu'il faut
        /// AVANT setBounds : setMinimized(false) + setFullscreen(false) + raise.
        /// `retrySetBounds` indique le besoin d'un 2e setBounds (apps qui
        /// refusent le 1er après wake).
        case restore(target: CGRect, requiresWake: Bool, retrySetBounds: Bool)
        /// Frame trop dégénérée ET pas d'expectedFrame valide : retirer du BSP
        /// et laisser macOS la traiter naturellement (ex : minimized par user).
        case removeFromBSP
    }

    /// Snapshot d'observation d'une fenêtre pour la décision.
    public struct WindowObservation: Equatable {
        public let cgwid: UInt32
        /// Frame courant rapporté par AX.
        public let axFrame: CGRect
        /// Frame attendue (capturée au dernier hide ou setBounds explicite).
        /// `.zero` si jamais initialisée.
        public let expectedFrame: CGRect
        /// Bounds CG live (CGWindowListCopyWindowInfo). nil si indisponible.
        public let cgBounds: CGRect?

        public init(cgwid: UInt32, axFrame: CGRect, expectedFrame: CGRect, cgBounds: CGRect?) {
            self.cgwid = cgwid
            self.axFrame = axFrame
            self.expectedFrame = expectedFrame
            self.cgBounds = cgBounds
        }
    }

    /// Vrai si le centre de `frame` (en coordonnées AX, Y top-down) est dans
    /// l'union des `screenFramesAX` (pré-converties par l'appelant).
    public static func isOnScreen(_ frame: CGRect, screenFramesAX: [CGRect]) -> Bool {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screenFramesAX.contains { $0.contains(center) }
    }

    /// Vrai si la frame est manifestement dégénérée (collapsed AX, offscreen
    /// extrême). Évite les faux positifs en n'utilisant qu'un seuil conservateur.
    public static func isDegenerate(_ frame: CGRect) -> Bool {
        return frame.size.height < minValidHeight
            || frame.size.height > 100_000
            || frame.origin.y < suspiciousOffscreenY
    }

    /// Calcule la décision pour une fenêtre. Logique pure, déterministe.
    ///
    /// - Parameter primaryVisibleFrameAX: visibleFrame du primary screen
    ///   en coordonnées AX (Y top-down), pour fallback de centrage.
    public static func decide(
        observation o: WindowObservation,
        screenFramesAX: [CGRect],
        primaryVisibleFrameAX: CGRect
    ) -> Decision {
        let onScreen = isOnScreen(o.axFrame, screenFramesAX: screenFramesAX)
        let degenerate = isDegenerate(o.axFrame)

        // Cas sain : rien à faire.
        if onScreen && !degenerate {
            return .keep
        }

        // Mismatch AX/CG : si CG dit que la fenêtre fait > minValidHeight et est
        // probablement bien placée, on adopte CG sans toucher à AX (pas de wake).
        if let cg = o.cgBounds, cg.size.height >= minValidHeight {
            return .adoptCGBounds(cg)
        }

        // Choisir le target de restoration.
        let target: CGRect
        let hasValidExpected = o.expectedFrame != .zero
            && o.expectedFrame.size.height >= minValidHeight
        if hasValidExpected {
            target = o.expectedFrame
        } else {
            // Pas d'expectedFrame valide ET frame courante dégénérée → la
            // fenêtre est dans un état où on n'a aucune trace fiable de sa
            // position légitime. Plutôt que de la repositionner agressivement
            // (risque de dé-minimiser une fenêtre que l'user a minimisée), on
            // signale au caller de la retirer du BSP et de laisser macOS gérer.
            // Décision conservatrice : F2 résolu (no false positive wake).
            if degenerate && !hasValidExpected {
                return .removeFromBSP
            }
            // Hors écran mais pas dégénérée → centrer sur primary.
            target = CGRect(
                x: primaryVisibleFrameAX.midX - 400,
                y: primaryVisibleFrameAX.midY - 300,
                width: 800, height: 600)
        }

        // Wake nécessaire si la fenêtre est dégénérée (probablement AX-collapsed
        // par moveOffScreen). Sinon, simple setBounds suffit.
        let requiresWake = degenerate
        // Retry uniquement si on doit wake (apps qui refusent le 1er setBounds
        // post-wake — bug macOS connu, documenté). Si pas de wake, retry inutile.
        return .restore(target: target, requiresWake: requiresWake, retrySetBounds: requiresWake)
    }

    /// Vrai si un arbre BSP a au moins un weight < `minHealthyWeight`. L'appelant
    /// utilise ce signal pour conditionner `balanceWeights` au lieu de l'appeler
    /// inconditionnellement à chaque boot (F3 résolu : on n'agit que sur
    /// déséquilibre détecté).
    public static func shouldBalance(weights: [Double]) -> Bool {
        return weights.contains { $0 < minHealthyWeight }
    }
}
