import Foundation
import RoadieCore

// SPEC-024 — Proxy daemon in-process. Remplace RailIPCClient quand le rail
// tourne dans le même process que le daemon (mode mono-binaire). Bypass total
// du socket Unix : appel direct au CommandHandler du daemon, retour de la
// Response convertie en [String: Any] pour préserver l'API du RailController.
//
// Conséquences vs RailIPCClient socket :
// - Pas de sérialisation JSON, pas de round-trip socket : ~5-10 ms gagnés / requête.
// - Pas de timeout socket possible : le handler tourne sur @MainActor, awaitable.
// - Les erreurs Response.error sont mappées sur RailIPCError.invalidResponse pour
//   ne pas casser les call-sites qui attendent ce type.

/// Erreurs du proxy daemon. Hérité du nom V1 pour préserver les sites
/// `catch RailIPCError.daemonNotRunning` dans le RailController.
enum RailIPCError: Error, Equatable {
    case daemonNotRunning
    case timeout
    case invalidResponse(detail: String)
    case networkError(String)
}

@MainActor
final class RailDaemonProxy {
    private weak var handler: CommandHandler?

    init(handler: CommandHandler) {
        self.handler = handler
    }

    /// Envoie une commande au daemon in-process. Retourne le payload (vide si
    /// status=success sans data), throws `RailIPCError` si la commande échoue.
    /// Compat strict avec `RailIPCClient.send` : même signature, même type d'erreur.
    func send(command: String, args: [String: String] = [:]) async throws -> [String: Any] {
        guard let handler = handler else {
            throw RailIPCError.daemonNotRunning
        }
        let request = Request(command: command, args: args.isEmpty ? nil : args)
        let response = await handler.handle(request)
        switch response.status {
        case .success:
            // Convertit [String: AnyCodable]? en [String: Any]. Préserve les types
            // natifs (String, Int, Bool, Array, Dict, NSNull) que les callers
            // castent ensuite via `as? Type`.
            return response.payload?.mapValues { $0.value } ?? [:]
        case .error:
            let detail = response.errorMessage ?? response.errorCode ?? "unknown error"
            throw RailIPCError.invalidResponse(detail: detail)
        }
    }
}
