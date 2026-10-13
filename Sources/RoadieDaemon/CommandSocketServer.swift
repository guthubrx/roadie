import Foundation
import Darwin

/// Requête du canal CLI vers daemon : une ligne JSON (contrat `cli-daemon-socket.md`).
public struct CommandSocketRequest: Codable, Equatable, Sendable {
    public var version: Int
    public var argv: [String]
    public var cwd: String?

    public init(version: Int = CommandSocketServer.protocolVersion, argv: [String], cwd: String? = nil) {
        self.version = version
        self.argv = argv
        self.cwd = cwd
    }
}

/// Réponse du daemon : une ligne JSON, puis fermeture de la connexion.
public struct CommandSocketResponse: Codable, Equatable, Sendable {
    public var version: Int
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(version: Int = CommandSocketServer.protocolVersion, exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.version = version
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Serveur du socket `~/.roadies/roadied.sock` (0600), démarré par `roadied run` et `roadied tiler`.
/// Lecture et écriture sur une file dédiée ; seule l'exécution du router passe sur le fil
/// principal, une requête à la fois (même ordre que les ticks, un seul écrivain d'état).
public final class CommandSocketServer: @unchecked Sendable {
    public static let protocolVersion = 1
    static let maxRequestBytes = 64 * 1024
    static let ioTimeout: TimeInterval = 2

    public static var defaultPath: String {
        NSString(string: "~/.roadies/roadied.sock").expandingTildeInPath
    }

    @MainActor private static var running: CommandSocketServer?

    public let path: String
    private let listenFD: Int32
    private let router: CLICommandRouter
    private let queue = DispatchQueue(label: "com.roadie.command-socket")
    private var source: DispatchSourceRead?

    private init(path: String, listenFD: Int32, router: CLICommandRouter) {
        self.path = path
        self.listenFD = listenFD
        self.router = router
    }

    /// Ouvre le socket et commence à servir. `nil` (avec message sur stderr) si l'ouverture échoue :
    /// le daemon continue sans canal, la CLI signalera l'erreur.
    @MainActor
    @discardableResult
    public static func start(router: CLICommandRouter, path: String = defaultPath) -> CommandSocketServer? {
        running?.stop()
        guard let fd = listen(at: path) else { return nil }
        let server = CommandSocketServer(path: path, listenFD: fd, router: router)
        server.resume()
        running = server
        return server
    }

    /// Hors `@MainActor` : les gestionnaires créés ici s'exécutent sur la file dédiée
    /// sans contrôle d'isolation du fil principal (sinon arrêt du processus en Swift 6).
    private func resume() {
        let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
        let fd = listenFD
        let path = path
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler {
            close(fd)
            unlink(path)
        }
        self.source = source
        source.resume()
    }

    /// Ferme le socket et supprime son fichier.
    public func stop() {
        source?.cancel()
        source = nil
    }

    private static func listen(at path: String) -> Int32? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            FileHandle.standardError.write(Data("roadied: command socket path too long: \(path)\n".utf8))
            return nil
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        // Socket périmé d'une instance précédente : le verrou d'instance garantit un seul serveur.
        unlink(path)
        // umask 0177 pendant bind : le fichier naît en 0600, sans fenêtre de course.
        let previousMask = umask(0o177)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previousMask)
        guard bound == 0, Darwin.listen(fd, 16) == 0 else {
            FileHandle.standardError.write(Data("roadied: command socket unavailable at \(path): \(String(cString: strerror(errno)))\n".utf8))
            close(fd)
            return nil
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        return fd
    }

    // Sur la file dédiée : accepte les connexions en attente, une à la fois.
    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { return }
            serve(client)
            close(client)
        }
    }

    private func serve(_ client: Int32) {
        CommandSocketIO.prepare(client)
        let deadline = Date().addingTimeInterval(Self.ioTimeout)
        let response: CommandSocketResponse
        switch CommandSocketIO.readLine(client, limit: Self.maxRequestBytes, deadline: deadline) {
        case .line(let data):
            response = respond(to: data)
        case .tooLarge:
            response = CommandSocketResponse(exitCode: 64, stderr: "roadie: request larger than \(Self.maxRequestBytes) bytes\n")
        case .failed:
            return
        }
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(response)
        } catch {
            // FR-015 : jamais d'échec muet ; le client reçoit une erreur minimale.
            fputs("roadied: failed to encode command response: \(error)\n", stderr)
            let fallback = CommandSocketResponse(exitCode: 70, stderr: "roadie: roadied failed to encode its response\n")
            guard let data = try? JSONEncoder().encode(fallback) else { return }
            encoded = data
        }
        _ = CommandSocketIO.writeAll(client, encoded + Data([0x0A]), deadline: Date().addingTimeInterval(Self.ioTimeout))
    }

    private func respond(to data: Data) -> CommandSocketResponse {
        guard let request = try? JSONDecoder().decode(CommandSocketRequest.self, from: data) else {
            return CommandSocketResponse(exitCode: 64, stderr: "roadie: invalid request\n")
        }
        guard request.version == Self.protocolVersion else {
            return CommandSocketResponse(exitCode: 70, stderr: "roadie: protocol version \(request.version) not supported\n")
        }
        guard CLICommandRouter.isDaemonRouted(request.argv) else {
            return CommandSocketResponse(exitCode: 64, stderr: "roadie: command not accepted by roadied: \(request.argv.first ?? "")\n")
        }
        let argv = Self.resolvingPaths(request.argv, cwd: request.cwd)
        let router = self.router
        let result = DispatchQueue.main.sync {
            MainActor.assumeIsolated { router.run(argv) }
        }
        return CommandSocketResponse(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr)
    }

    /// `--config PATH` relatif : résolu depuis le répertoire du client, pas celui du daemon.
    static func resolvingPaths(_ argv: [String], cwd: String?) -> [String] {
        guard let cwd, let index = argv.firstIndex(of: "--config"), argv.indices.contains(index + 1) else { return argv }
        let value = argv[index + 1]
        guard !value.hasPrefix("/"), !value.hasPrefix("~") else { return argv }
        var resolved = argv
        resolved[index + 1] = URL(fileURLWithPath: value, relativeTo: URL(fileURLWithPath: cwd, isDirectory: true)).path
        return resolved
    }
}

/// Côté `roadie` : envoie au daemon les commandes routées, sinon exécute en local.
public enum CommandSocketClient {
    public enum Outcome: Equatable, Sendable {
        /// Connexion impossible ou requête non transmise.
        case unreachable
        /// Requête transmise, pas de réponse lisible dans le délai.
        case noResponse
        case response(CommandSocketResponse)
    }

    public static let connectTimeout: TimeInterval = 0.5
    public static let responseTimeout: TimeInterval = 5

    public static var defaultLockPath: String {
        NSString(string: "~/.roadies/roadied.lock").expandingTildeInPath
    }

    /// Choix daemon ou local. Repli local seulement si l'absence du daemon est établie
    /// (ni pid vivant, ni socket qui accepte une connexion) ; daemon présent mais muet = erreur,
    /// jamais de double exécution.
    public static func execute(
        argv: [String],
        cwd: String?,
        socketPath: String = CommandSocketServer.defaultPath,
        lockPath: String = defaultLockPath,
        local: () -> CLIResponse
    ) -> CLIResponse {
        guard CLICommandRouter.isDaemonRouted(argv),
              isDaemonLockHeld(path: lockPath) || isDaemonSocketAccepting(path: socketPath)
        else {
            return local()
        }
        switch send(CommandSocketRequest(argv: argv, cwd: cwd), path: socketPath) {
        case .unreachable:
            return CLIResponse(exitCode: 69, stderr: "roadie: roadied is running but does not accept commands on \(socketPath); see roadie doctor\n")
        case .noResponse:
            return CLIResponse(exitCode: 75, stderr: "roadie: roadied did not answer within \(Int(responseTimeout)) s; the command may still run\n")
        case .response(let response) where response.version != CommandSocketServer.protocolVersion:
            return CLIResponse(exitCode: 69, stderr: "roadie: roadied speaks protocol \(response.version), expected \(CommandSocketServer.protocolVersion); run roadie daemon restart\n")
        case .response(let response):
            return CLIResponse(exitCode: response.exitCode, stdout: response.stdout, stderr: response.stderr)
        }
    }

    /// Vrai si un daemon tient le verrou `roadied.lock` : son fichier pid voisin (`roadied.pid`,
    /// écrit par `ComponentLockFile` après l'acquisition) désigne un process vivant.
    /// Pas de sonde `flock` (T217) : le daemon prend le verrou en `LOCK_EX|LOCK_NB`, donc un
    /// `LOCK_SH` tenu même brièvement par la CLI ferait échouer un démarrage concurrent
    /// (« already running »). Un pid recyclé donne au pire l'erreur 69, jamais une double exécution.
    public static func isDaemonLockHeld(path: String = defaultLockPath) -> Bool {
        let pidPath = (path as NSString).deletingPathExtension + ".pid"
        guard let raw = try? String(contentsOfFile: pidPath, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        return ProcessLiveness.isAlive(pid)
    }

    /// Vrai si un process écoute sur le socket de commandes. Complète `isDaemonLockHeld` quand le
    /// fichier pid manque (daemon autonome dont `scripts/start` a supprimé le pid, ou fenêtre
    /// entre `flock` et l'écriture du pid). Aucun `flock` ici (voir `isDaemonLockHeld`) : un socket
    /// périmé sans écouteur refuse la connexion (ECONNREFUSED), donc ne fait pas croire à un daemon.
    /// La connexion est refermée sans requête : le serveur la traite comme un client muet.
    /// Limite : un daemon qui tient le verrou mais n'a pas encore ouvert son socket n'est pas vu.
    static func isDaemonSocketAccepting(path: String, timeout: TimeInterval = connectTimeout) -> Bool {
        guard let fd = connect(to: path, timeout: timeout) else { return false }
        close(fd)
        return true
    }

    /// Envoie une requête et attend la réponse (connexion 0,5 s, réponse 5 s).
    public static func send(
        _ request: CommandSocketRequest,
        path: String = CommandSocketServer.defaultPath,
        connectTimeout: TimeInterval = connectTimeout,
        responseTimeout: TimeInterval = responseTimeout
    ) -> Outcome {
        guard let fd = connect(to: path, timeout: connectTimeout) else { return .unreachable }
        defer { close(fd) }
        CommandSocketIO.prepare(fd)
        guard let payload = try? JSONEncoder().encode(request),
              CommandSocketIO.writeAll(fd, payload + Data([0x0A]), deadline: Date().addingTimeInterval(connectTimeout))
        else { return .unreachable }
        let deadline = Date().addingTimeInterval(responseTimeout)
        guard case .line(let data) = CommandSocketIO.readLine(fd, limit: .max, deadline: deadline),
              let response = try? JSONDecoder().decode(CommandSocketResponse.self, from: data)
        else { return .noResponse }
        return .response(response)
    }

    private static func connect(to path: String, timeout: TimeInterval) -> Int32? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            guard errno == EINPROGRESS || errno == EAGAIN,
                  CommandSocketIO.wait(fd, events: Int16(POLLOUT), deadline: Date().addingTimeInterval(timeout))
            else {
                close(fd)
                return nil
            }
            var socketError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0, socketError == 0 else {
                close(fd)
                return nil
            }
        }
        return fd
    }
}

/// Lecture et écriture bornées dans le temps, communes au serveur et au client.
enum CommandSocketIO {
    enum ReadResult {
        case line(Data)
        case tooLarge
        case failed
    }

    /// Mode non bloquant (les délais passent par `poll`) et pas de SIGPIPE.
    static func prepare(_ fd: Int32) {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    static func wait(_ fd: Int32, events: Int16, deadline: Date) -> Bool {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let ready = poll(&descriptor, 1, Int32(max(1, remaining * 1000)))
            if ready > 0 { return true }
            if ready < 0, errno == EINTR { continue }
            return false
        }
    }

    /// Lit jusqu'au premier `\n` (exclu) ou la fin du flux.
    /// Complexité : O(n), n = taille de la ligne. Le saut de ligne est cherché dans le seul
    /// fragment reçu (avant : dans tout le préfixe déjà reçu, soit O(n²) pour des fragments fixes).
    static func readLine(_ fd: Int32, limit: Int, deadline: Date) -> ReadResult {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = recv(fd, &chunk, chunk.count, 0)
            if count > 0 {
                if let newline = chunk[0..<count].firstIndex(of: 0x0A) {
                    data.append(contentsOf: chunk[0..<newline])
                    return data.count > limit ? .tooLarge : .line(data)
                }
                data.append(contentsOf: chunk[0..<count])
                guard data.count <= limit else { return .tooLarge }
            } else if count == 0 {
                return data.isEmpty ? .failed : .line(data)
            } else if errno == EAGAIN || errno == EINTR {
                guard wait(fd, events: Int16(POLLIN), deadline: deadline) else { return .failed }
            } else {
                return .failed
            }
        }
    }

    static func writeAll(_ fd: Int32, _ data: Data, deadline: Date) -> Bool {
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
            if written > 0 {
                offset += written
            } else if written < 0, errno == EAGAIN || errno == EINTR {
                guard wait(fd, events: Int16(POLLOUT), deadline: deadline) else { return false }
            } else {
                return false
            }
        }
        return true
    }
}
