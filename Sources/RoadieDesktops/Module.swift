// SPEC-011 RoadieDesktops — module multi-desktop virtuel (pivot AeroSpace).
//
// Aucun appel SkyLight / CGS pour la bascule. Toutes les fenêtres vivent dans
// un seul Mac Space natif ; la bascule consiste à déplacer les fenêtres du
// desktop quitté hors-écran via AX (kAXPositionAttribute) et à restaurer
// celles du desktop d'arrivée à leur expectedFrame mémorisée.
//
// Composants Phase 2 + Phase 3 (Sprint 2) :
//   - DesktopState.swift    : entités RoadieDesktop, DesktopStage, WindowEntry, DesktopLayout
//   - Parser.swift          : sérialisation/désérialisation TOML
//   - EventBus.swift        : DesktopEventBus (actor) + DesktopChangeEvent
//   - WindowMover.swift     : protocole WindowMover + AXWindowMover + MockWindowMover
//   - DesktopRegistry.swift : actor — state in-memory + persistance
//   - DesktopSwitcher.swift : actor — orchestration bascule offscreen/onscreen
//   - Selector.swift        : résolution sélecteur textuel → Int
//
// Voir specs/011-virtual-desktops/ pour la spécification complète.

public enum RoadieDesktops {
    public static let version = "0.2.0"
}
