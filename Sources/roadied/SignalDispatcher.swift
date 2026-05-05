import Foundation
import RoadieCore

/// SPEC-026 US6 — exécute des commandes shell async sur events EventBus.
/// Lifecycle :
///   1. `start()` subscribe à EventBus + lance la boucle de dispatch.
///   2. À chaque event, cherche les hooks matching dans `hooksByEvent`.
///   3. Pour chaque hook : `Process` async + timeout 5s + env injection.
///
/// Sécurité : timeout strict 5s, fire-and-forget, pas de capture stdout.
@MainActor
public final class SignalDispatcher {
    private static let supportedEvents: Set<String> = [
        "window_focused", "window_created", "window_destroyed",
        "stage_changed", "desktop_changed", "display_changed",
    ]
    private static let timeoutSeconds: Double = 5.0

    private var hooksByEvent: [String: [SignalDef]] = [:]
    private var enabled: Bool = true
    private var subscriptionTask: Task<Void, Never>?

    public init() {}

    public func loadConfig(_ config: SignalsConfig) {
        enabled = config.enabled
        var indexed: [String: [SignalDef]] = [:]
        for hook in config.hooks {
            guard Self.supportedEvents.contains(hook.event) else {
                logWarn("signal_unsupported_event", ["event": hook.event])
                continue
            }
            indexed[hook.event, default: []].append(hook)
        }
        hooksByEvent = indexed
        logInfo("signals_loaded", [
            "enabled": String(enabled),
            "hooks_count": String(config.hooks.count),
            "events": indexed.keys.sorted().joined(separator: ","),
        ])
    }

    public func start() {
        guard subscriptionTask == nil else { return }
        let stream = EventBus.shared.subscribe()
        subscriptionTask = Task { @MainActor [weak self] in
            for await event in stream {
                self?.dispatch(event: event)
            }
        }
        logInfo("signal_dispatcher_started")
    }

    public func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    private func dispatch(event: DesktopEvent) {
        guard enabled else { return }
        guard let hooks = hooksByEvent[event.name], !hooks.isEmpty else { return }
        let env = buildEnv(event: event)
        for hook in hooks {
            execute(cmd: hook.cmd, event: event.name, env: env)
        }
    }

    private func buildEnv(event: DesktopEvent) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["ROADIE_EVENT"] = event.name
        for (k, v) in event.payload {
            // Map keys vers ROADIE_* en uppercase (ex: wid → ROADIE_WID).
            env["ROADIE_\(k.uppercased())"] = v
        }
        return env
    }

    private func execute(cmd: String, event: String, env: [String: String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", cmd]
        process.environment = env
        // Pas de capture stdout/stderr (fire-and-forget).
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            logInfo("signal_executed", [
                "event": event,
                "cmd": String(cmd.prefix(80)),
                "pid": String(process.processIdentifier),
            ])
        } catch {
            logWarn("signal_spawn_failed", [
                "event": event,
                "error": String(describing: error),
            ])
            return
        }
        // Timeout 5s : tue le process s'il tourne encore.
        let pidCapture = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeoutSeconds) {
            if process.isRunning {
                process.terminate()
                // Si toujours running après 200ms, SIGKILL.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                    if process.isRunning {
                        kill(pidCapture, SIGKILL)
                    }
                }
                Task { @MainActor in
                    logWarn("signal_timeout", [
                        "event": event,
                        "pid": String(pidCapture),
                        "timeout_s": String(Self.timeoutSeconds),
                    ])
                }
            }
        }
    }
}
