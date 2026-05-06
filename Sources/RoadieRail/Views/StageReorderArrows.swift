import SwiftUI
import RoadieCore

/// SPEC-027 US3 — Flèches de réordonnancement de stage dans le rail.
///
/// Apparaissent au survol d'une cellule de stage. `↑` remonte la stage d'un
/// cran, `↓` descend d'un cran. La flèche correspondant à une extrémité
/// (déjà première / déjà dernière) est rendue avec opacité réduite et tap
/// désactivé.
///
/// Pourquoi ce composant et pas un drag-drop ?
/// SwiftUI sur LSUIElement+NSPanel ne dispatche pas correctement les drops
/// de Transferable custom (UTI exporté ou String préfixé) — le `dropDestination`
/// reste muet. Le pattern bouton est moins satisfaisant ergonomiquement
/// mais marche à 100 % et reste découvrable au hover.
struct StageReorderArrows: View {
    let canMoveUp:   Bool
    let canMoveDown: Bool
    let onMoveUp:    () -> Void
    let onMoveDown:  () -> Void

    var body: some View {
        VStack(spacing: 2) {
            arrowButton(systemName: "chevron.up",
                        enabled:    canMoveUp,
                        action:     onMoveUp)
            arrowButton(systemName: "chevron.down",
                        enabled:    canMoveDown,
                        action:     onMoveDown)
        }
        .padding(.leading, 4)
        .padding(.top, 4)
    }

    private func arrowButton(systemName: String,
                             enabled:    Bool,
                             action:     @escaping () -> Void) -> some View {
        // Image + onTapGesture direct (pas Button) pour éviter le conflit
        // potentiel avec le `.onTapGesture` parent du renderer (switch stage)
        // qui peut consommer les clics avant que le Button ne les voie.
        Image(systemName: systemName)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 18, height: 14)
            .background(Color.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .opacity(enabled ? 0.85 : 0.20)
            .contentShape(Rectangle())
            .onTapGesture {
                guard enabled else { return }
                logInfo("rail_arrow_tap", ["arrow": systemName])
                action()
            }
            .help(systemName == "chevron.up"
                  ? "Remonter cette stage dans le rail"
                  : "Descendre cette stage dans le rail")
    }
}
