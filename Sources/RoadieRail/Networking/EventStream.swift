import Foundation

// SPEC-014 T023 — Abonnement au stream d'événements roadie via `roadie events --follow`.
// Reconnexion automatique si le process meurt.

/// Subscribe aux événements du daemon roadied via le CLI roadie events --follow.
final class EventStream {
    // Types d'événements pertinents pour le rail.
    private static let defaultTypes = [
        "stage_changed", "desktop_changed", "window_assigned", "window_unassigned",
        "window_created", "window_destroyed", "wallpaper_click", "stage_renamed",
        "stage_created", "stage_deleted", "stage_assigned",
        "thumbnail_updated", "config_reloaded", "window_focused",
    ].joined(separator: ",")

    var onEvent: ((String, [String: Any]) -> Void)?

    private var process: Process?
    private var isRunning = false
    private var reconnectTask: Task<Void, Never>?

    /// Démarre le stream. Reconnexion automatique sur crash du process.
    func start() {
        isRunning = true
        launchProcess()
    }

    /// Arrête le stream et annule toute reconnexion.
    func stop() {
        isRunning = false
        reconnectTask?.cancel()
        reconnectTask = nil
        process?.terminate()
        process = nil
    }

    // MARK: - Private

    private func launchProcess() {
        let roadiePath = resolveRoadiePath()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: roadiePath)
        proc.arguments = ["events", "--follow", "--types", Self.defaultTypes]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] _ in
            self?.scheduleReconnect()
        }

        do {
            try proc.run()
        } catch {
            scheduleReconnect()
            return
        }

        process = proc
        readLines(from: pipe.fileHandleForReading)
    }

    private func readLines(from handle: FileHandle) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var buffer = Data()
            while let self = self, self.isRunning {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.subdata(in: 0..<nl)
                    buffer.removeSubrange(0...nl)
                    if !line.isEmpty {
                        self.parseLine(line)
                    }
                }
            }
        }
    }

    private func parseLine(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventName = obj["event"] as? String
        else { return }
        let payload = obj["payload"] as? [String: Any] ?? [:]
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(eventName, payload)
        }
    }

    private func scheduleReconnect() {
        guard isRunning else { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self = self, self.isRunning else { return }
            self.launchProcess()
        }
    }

    /// Résout le chemin du binaire roadie (local bin ou PATH).
    private func resolveRoadiePath() -> String {
        let local = (NSString(string: "~/.local/bin/roadie").expandingTildeInPath as String)
        if FileManager.default.isExecutableFile(atPath: local) { return local }
        return "/usr/local/bin/roadie"
    }
}
