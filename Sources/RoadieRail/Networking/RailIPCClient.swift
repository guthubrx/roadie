import Foundation
import Network

// SPEC-014 T022 — Client IPC socket Unix vers le daemon roadied.
// Pattern stateless : 1 connexion par requête (identique à SocketClient du CLI roadie).
// Reconnexion exponentielle : 100ms → 500ms → 2s plafonnée 5s (FR-006).

/// Erreurs du client IPC.
enum RailIPCError: Error, Equatable {
    case daemonNotRunning
    case timeout
    case invalidResponse(detail: String)
    case networkError(String)
}

/// Client IPC asynchrone vers le daemon roadied via socket Unix.
final class RailIPCClient {
    static let socketPath: String = (NSString(string: "~/.roadies/daemon.sock")
        .expandingTildeInPath as String)
    static let timeoutSeconds: TimeInterval = 5

    /// Délais de reconnexion exponentielle en secondes.
    private static let retryDelays: [TimeInterval] = [0.1, 0.5, 2.0]
    private static let maxRetryDelay: TimeInterval = 5.0

    /// Envoie une commande et retourne le payload de la réponse.
    /// Lance `RailIPCError` si le daemon est indisponible ou si la réponse est invalide.
    func send(command: String, args: [String: String] = [:]) async throws -> [String: Any] {
        let request = buildRequest(command: command, args: args)
        return try await sendWithRetry(request: request, retryIndex: 0)
    }

    // MARK: - Private

    private func buildRequest(command: String, args: [String: String]) -> Data {
        let dict: [String: Any] = [
            "version": "roadie/1",
            "command": command,
            "args": args,
        ]
        var data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        data.append(0x0A)
        return data
    }

    private func sendWithRetry(request: Data, retryIndex: Int) async throws -> [String: Any] {
        do {
            return try await sendOnce(request: request)
        } catch RailIPCError.daemonNotRunning {
            guard retryIndex < Self.retryDelays.count else { throw RailIPCError.daemonNotRunning }
            let delay = Self.retryDelays[retryIndex]
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return try await sendWithRetry(request: request, retryIndex: retryIndex + 1)
        }
    }

    private func sendOnce(request: Data) async throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: Self.socketPath) else {
            throw RailIPCError.daemonNotRunning
        }

        let endpoint = NWEndpoint.unix(path: Self.socketPath)
        let connection = NWConnection(to: endpoint, using: .tcp)

        return try await withCheckedThrowingContinuation { continuation in
            var responded = false

            connection.stateUpdateHandler = { [weak connection] state in
                switch state {
                case .ready:
                    connection?.send(content: request, completion: .contentProcessed { err in
                        if let err = err {
                            if !responded {
                                responded = true
                                connection?.cancel()
                                continuation.resume(throwing: err)
                            }
                            return
                        }
                        connection?.receive(
                            minimumIncompleteLength: 1,
                            maximumLength: 131_072
                        ) { data, _, _, error in
                            guard !responded else { return }
                            responded = true
                            connection?.cancel()
                            if let error = error {
                                continuation.resume(throwing: error)
                                return
                            }
                            guard let data = data,
                                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                            else {
                                continuation.resume(throwing: RailIPCError.invalidResponse(detail: "decode failed"))
                                return
                            }
                            // Extraire le payload de la réponse roadie/1.
                            let payload = obj["payload"] as? [String: Any] ?? obj
                            continuation.resume(returning: payload)
                        }
                    })
                case .failed(let err):
                    guard !responded else { return }
                    responded = true
                    connection?.cancel()
                    let msg = "\(err)"
                    if msg.contains("refused") || msg.contains("ENOENT") || msg.contains("ECONNREFUSED") {
                        continuation.resume(throwing: RailIPCError.daemonNotRunning)
                    } else {
                        continuation.resume(throwing: RailIPCError.networkError(msg))
                    }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))

            // Timeout de sécurité.
            Task {
                try? await Task.sleep(nanoseconds: UInt64(Self.timeoutSeconds * 1_000_000_000))
                guard !responded else { return }
                responded = true
                connection.cancel()
                continuation.resume(throwing: RailIPCError.timeout)
            }
        }
    }
}
