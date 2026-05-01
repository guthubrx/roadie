import Foundation
import Network

/// Handler appelé par le serveur pour traiter une requête.
@MainActor
public protocol CommandHandler: AnyObject {
    func handle(_ request: Request) async -> Response
}

/// Serveur Unix socket. Utilise Network.framework.
public final class Server: @unchecked Sendable {
    private let socketPath: String
    private weak var handler: CommandHandler?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "roadies.server")

    public init(socketPath: String, handler: CommandHandler) {
        self.socketPath = (socketPath as NSString).expandingTildeInPath
        self.handler = handler
    }

    public func start() throws {
        let dir = (socketPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: socketPath)

        let endpoint = NWEndpoint.unix(path: socketPath)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = endpoint
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)

        listener.newConnectionHandler = { [weak self] connection in
            self?.acceptConnection(connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: logInfo("server listening", ["path": self.socketPath])
            case .failed(let err): logError("server failed", ["err": "\(err)"])
            default: break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
        // Restreindre les permissions du socket à l'utilisateur courant
        chmod(socketPath, 0o600)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private func acceptConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection)
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                logDebug("server receive error", ["err": "\(error)"])
                connection.cancel()
                return
            }
            if let data = data, !data.isEmpty {
                self.processRequest(data: data, on: connection)
            }
            if isComplete {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection)
            }
        }
    }

    private func processRequest(data: Data, on connection: NWConnection) {
        let lines = data.split(separator: 0x0A)   // newlines = JSON-lines boundaries
        for line in lines {
            guard let request = try? JSONDecoder().decode(Request.self, from: Data(line)) else {
                let resp = Response.error(.invalidArgument, "invalid JSON request")
                self.send(resp, on: connection)
                continue
            }
            // V2 events stream : mode push (FR-014). La connexion reste ouverte tant
            // que le client ne ferme pas. Pas de buffer côté daemon (auto-flush).
            if request.command == "events.subscribe" {
                self.startEventStream(on: connection, request: request)
                continue
            }
            Task { @MainActor [weak self] in
                guard let self = self, let handler = self.handler else {
                    let resp = Response.error(.internalError, "no handler")
                    self?.send(resp, on: connection)
                    return
                }
                let resp = await handler.handle(request)
                self.send(resp, on: connection)
            }
        }
    }

    /// Mode push : ack + souscription EventBus, chaque event devient une ligne
    /// JSON envoyée immédiatement sur la connexion. La Task se termine quand le
    /// stream se ferme (continuation cancelled au cancel de la connexion).
    private func startEventStream(on connection: NWConnection, request: Request) {
        let ack = Response.success(["subscribed": AnyCodable(true)])
        self.send(ack, on: connection)
        Task { @MainActor [weak self] in
            let stream = EventBus.shared.subscribe()
            for await event in stream {
                let line = event.toJSONLine()
                guard let data = line.data(using: .utf8) else { continue }
                self?.sendRaw(data, on: connection)
            }
        }
    }

    private func sendRaw(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func send(_ response: Response, on connection: NWConnection) {
        let encoder = JSONEncoder()
        guard var data = try? encoder.encode(response) else { return }
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
}
