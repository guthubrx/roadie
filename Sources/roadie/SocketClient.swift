import Foundation
import Network
import RoadieCore

enum SocketClient {
    enum Error: Swift.Error {
        case daemonNotRunning
        case timeout
        case invalidResponse
    }

    static let socketPath: String = (NSString(string: "~/.roadies/daemon.sock").expandingTildeInPath as String)
    static let timeoutSeconds: TimeInterval = 5

    /// Envoie une requête synchrone. Bloque jusqu'à réponse ou timeout.
    static func send(_ request: Request) throws -> Response {
        // Vérifier que le socket existe
        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw Error.daemonNotRunning
        }

        let endpoint = NWEndpoint.unix(path: socketPath)
        let connection = NWConnection(to: endpoint, using: .tcp)

        let semaphore = DispatchSemaphore(value: 0)
        var capturedResponse: Response?
        var capturedError: Swift.Error?

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                // Encode + send + receive
                guard var data = try? JSONEncoder().encode(request) else {
                    capturedError = Error.invalidResponse
                    semaphore.signal()
                    return
                }
                data.append(0x0A)
                connection.send(content: data, completion: .contentProcessed { err in
                    if let err = err {
                        capturedError = err
                        semaphore.signal()
                    }
                })
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, error in
                    if let error = error {
                        capturedError = error
                    } else if let data = data,
                              let response = try? JSONDecoder().decode(Response.self, from: data) {
                        capturedResponse = response
                    } else {
                        capturedError = Error.invalidResponse
                    }
                    semaphore.signal()
                }
            case .failed(let err):
                capturedError = err
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: .global())

        let result = semaphore.wait(timeout: .now() + timeoutSeconds)
        connection.cancel()

        if result == .timedOut { throw Error.timeout }
        if let err = capturedError {
            // NWError "POSIXErrorCode: Connection refused" = daemon down
            if "\(err)".contains("refused") || "\(err)".contains("ENOENT") {
                throw Error.daemonNotRunning
            }
            throw err
        }
        guard let response = capturedResponse else { throw Error.invalidResponse }
        return response
    }
}
