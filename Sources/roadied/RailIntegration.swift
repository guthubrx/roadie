import Foundation
import RoadieCore
import RoadieRail

// SPEC-024 — Bootstrap du rail in-process. Remplace l'ancien binaire
// roadie-rail séparé qui était lancé indépendamment et parlait au daemon
// via socket Unix. En V2, le rail vit dans le même process que le daemon
// et accède directement aux sous-systèmes via `CommandHandler` (proxy).
//
// Appelé une fois en fin de bootstrap du daemon, après que les permissions
// AX/Screen Recording soient validées et le tiling/stages opérationnels.

@MainActor
enum RailIntegration {
    /// Crée un RailController, lance ses panels + edge monitor + event subscription.
    /// Le RailController retourné DOIT être stocké dans une propriété forte du
    /// caller (sinon ARC le déalloue immédiatement).
    static func start(handler: CommandHandler) -> RailController {
        let controller = RailController(handler: handler)
        controller.start()
        return controller
    }
}
