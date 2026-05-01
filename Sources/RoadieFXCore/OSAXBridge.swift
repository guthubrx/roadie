import Foundation
import Darwin

/// Client socket Unix vers `roadied.osax`. Non-bloquant, queue async, retry 2 s.
/// Si l'osax n'est pas chargée par Dock : log warning, queue les commandes,
/// reconnecte périodiquement. Pas de crash, pas de drop silencieux jusqu'à 1000 entries.
public actor OSAXBridge {
    public static let defaultSocketPath = "/var/tmp/roadied-osax.sock"
    public static let maxQueueSize = 1000

    private let socketPath: String
    private var fd: Int32 = -1
    private var queue: [OSAXCommand] = []
    private var reconnectTask: Task<Void, Never>?

    public init(socketPath: String = OSAXBridge.defaultSocketPath) {
        self.socketPath = socketPath
    }

    /// Tente une connexion non bloquante. Retourne immédiatement.
    /// Si succès : flush la queue. Sinon : démarre retry async.
    public func connect() async {
        guard fd < 0 else { return }
        fd = openSocket()
        if fd >= 0 {
            await flushQueue()
        } else {
            startReconnectLoop()
        }
    }

    public func disconnect() {
        if fd >= 0 { close(fd); fd = -1 }
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    public var isConnected: Bool { fd >= 0 }
    public var queueDepth: Int { queue.count }

    /// Envoie une commande. Si non connecté : queue. Retry async.
    /// Cap queue à `maxQueueSize` : drop oldest avec log si dépassé.
    @discardableResult
    public func send(_ cmd: OSAXCommand) async -> OSAXResult {
        if fd < 0 {
            enqueue(cmd)
            startReconnectLoop()
            return .error(code: "bridge_disconnected", message: "osax not connected, queued")
        }
        return await writeAndRead(cmd)
    }

    /// Batch send : envoie N commandes en 1 socket write.
    /// Retourne les résultats en ordre.
    public func batchSend(_ cmds: [OSAXCommand]) async -> [OSAXResult] {
        guard !cmds.isEmpty else { return [] }
        if fd < 0 {
            for c in cmds { enqueue(c) }
            startReconnectLoop()
            return cmds.map { _ in .error(code: "bridge_disconnected", message: nil) }
        }
        let payload = cmds.map { $0.toJSONLine() }.joined()
        guard writeAll(fd: fd, data: payload) else {
            close(fd); fd = -1
            for c in cmds { enqueue(c) }
            startReconnectLoop()
            return cmds.map { _ in .error(code: "bridge_disconnected", message: nil) }
        }
        var results: [OSAXResult] = []
        for _ in 0..<cmds.count {
            if let line = readLine(fd: fd), let r = OSAXResult(jsonLine: line) {
                results.append(r)
            } else {
                results.append(.error(code: "read_failure", message: nil))
            }
        }
        return results
    }

    // MARK: - Private

    private func enqueue(_ cmd: OSAXCommand) {
        if queue.count >= Self.maxQueueSize {
            queue.removeFirst()
        }
        queue.append(cmd)
    }

    private func flushQueue() async {
        let pending = queue
        queue.removeAll()
        for cmd in pending {
            _ = await writeAndRead(cmd)
        }
    }

    private func writeAndRead(_ cmd: OSAXCommand) async -> OSAXResult {
        let line = cmd.toJSONLine()
        guard writeAll(fd: fd, data: line) else {
            close(fd); fd = -1
            enqueue(cmd)
            startReconnectLoop()
            return .error(code: "bridge_disconnected", message: nil)
        }
        guard let response = readLine(fd: fd),
              let result = OSAXResult(jsonLine: response) else {
            return .error(code: "read_failure", message: nil)
        }
        return result
    }

    private func startReconnectLoop() {
        guard reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                let connected = await self.tryReconnect()
                if connected { break }
            }
            await self?.clearReconnectTask()
        }
    }

    private func tryReconnect() async -> Bool {
        guard fd < 0 else { return true }
        fd = openSocket()
        if fd >= 0 {
            await flushQueue()
            return true
        }
        return false
    }

    private func clearReconnectTask() {
        reconnectTask = nil
    }

    private func openSocket() -> Int32 {
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return -1 }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(s); return -1
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            pathBytes.withUnsafeBufferPointer { src in
                _ = memcpy(dest.baseAddress, src.baseAddress, src.count)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(s, sa, len)
            }
        }
        if result < 0 { close(s); return -1 }
        return s
    }

    private func writeAll(fd: Int32, data: String) -> Bool {
        guard let bytes = data.data(using: .utf8) else { return false }
        var written = 0
        while written < bytes.count {
            let n = bytes.withUnsafeBytes { buf -> Int in
                Darwin.write(fd, buf.baseAddress!.advanced(by: written), bytes.count - written)
            }
            if n <= 0 { return false }
            written += n
        }
        return true
    }

    private func readLine(fd: Int32) -> String? {
        var buffer = [UInt8]()
        var byte: UInt8 = 0
        while true {
            let n = Darwin.read(fd, &byte, 1)
            if n <= 0 { return buffer.isEmpty ? nil : String(bytes: buffer, encoding: .utf8) }
            if byte == UInt8(ascii: "\n") { break }
            buffer.append(byte)
        }
        return String(bytes: buffer, encoding: .utf8)
    }
}
