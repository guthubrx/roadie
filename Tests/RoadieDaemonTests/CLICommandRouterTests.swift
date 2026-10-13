import Foundation
import Darwin
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

/// Lot H (SPEC-016 T095) : codes de retour de la CLI, canal socket et repli local.
/// Aucun test n'exécute une commande qui lit ou écrit l'état réel de `~/.roadies`.
@MainActor
@Suite(.serialized)
struct CLICommandRouterTests {
    private func router() -> CLICommandRouter {
        CLICommandRouter(makeService: { _ in
            let provider = PowerUserProvider(windows: [powerWindow(1, x: 0)])
            return SnapshotService(
                provider: provider,
                frameWriter: PowerUserWriter(provider: provider),
                config: RoadieConfig(),
                intentStore: LayoutIntentStore(path: tempPath("cli-intents")),
                stageStore: StageStore(path: tempPath("cli-stages")),
                events: EventLog(path: tempPath("cli-events")),
                persistStateChanges: false
            )
        })
    }

    /// Chemin court : `sun_path` est limité à 104 octets.
    private func socketPath() -> String {
        "/tmp/roadie-test-\(UUID().uuidString.prefix(8)).sock"
    }

    @Test
    func helpVariantsExitZeroOnStdout() {
        for args in [["help"], ["-h"], ["--help"], []] {
            let response = router().run(args)
            #expect(response.exitCode == 0, "\(args)")
            #expect(response.stdout.hasPrefix("usage:"), "\(args)")
            #expect(response.stderr.isEmpty, "\(args)")
        }
    }

    @Test
    func maximizeIsAdvertisedAndRouted() {
        #expect(router().run(["help", "toggle"]).stdout.contains("maximize|fullscreen|native-fullscreen"))
        let response = router().run(["toggle", "maximize"])
        #expect(response.exitCode == 0)
        #expect(response.stdout.contains("maximize"))
        #expect(response.stderr.isEmpty)
        #expect(CLICommandRouter.isDaemonRouted(["toggle", "maximize"]))
        #expect(!CLICommandRouter.isDaemonRouted(["toggle", "maximize", "--help"]))
    }

    @Test
    func helpIsGeneratedFromCommandTable() {
        let full = router().run(["--help"]).stdout
        #expect(!full.contains("wrap"))
        #expect(full.contains("roadie toggle floating  (not implemented)"))
        #expect(full.contains("roadie restore snapshot|status|apply|unhide-all"))

        let stage = router().run(["help", "stage"])
        #expect(stage.exitCode == 0)
        let lines = stage.stdout.split(separator: "\n").dropFirst()
        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { $0.hasPrefix("  roadie stage ") })

        #expect(router().run(["stage", "--help"]).stdout == stage.stdout)
    }

    /// Une commande annoncée « not implemented » échoue de la même façon partout (audit AI-001).
    @Test
    func unimplementedCommandsExitOne() {
        #expect(router().run(["window", "close"]).exitCode == 1)
        #expect(router().run(["toggle", "floating"]).exitCode == 1)
    }

    @Test
    func versionPrintsSingleVersionConstant() {
        let response = router().run(["--version"])
        #expect(response.exitCode == 0)
        #expect(response.stdout == "roadie \(RoadieVersion.current)\n")
    }

    @Test
    func usageErrorsExit64OnStderr() {
        let unknown = router().run(["frobnicate"])
        #expect(unknown.exitCode == 64)
        #expect(unknown.stdout.isEmpty)
        #expect(unknown.stderr.hasPrefix("roadie: unknown command frobnicate\nusage:"))

        let unknownHelp = router().run(["help", "frobnicate"])
        #expect(unknownHelp.exitCode == 64)

        let missingDirection = router().run(["focus"])
        #expect(missingDirection.exitCode == 64)
        #expect(missingDirection.stderr == "roadie: focus requires left|right|up|down\n")

        let conflicting = router().run(["cleanup", "--dry-run", "--apply"])
        #expect(conflicting.exitCode == 64)
    }

    @Test
    func actionWithoutChangeExitsZeroAndFailureExitsOne() {
        #expect(CLICommandRouter.actionExitCode(changed: true, message: "focus left") == 0)
        #expect(CLICommandRouter.actionExitCode(changed: false, message: "no neighbor left") == 0)
        #expect(CLICommandRouter.actionExitCode(changed: false, message: "warp left: no structural change") == 0)
        #expect(CLICommandRouter.actionExitCode(changed: false, message: "display 2: already on target display") == 0)
        #expect(CLICommandRouter.actionExitCode(changed: false, message: "stage switch-position 9: not found") == 1)
        #expect(CLICommandRouter.actionExitCode(changed: false, message: "focus: unknown window 12") == 1)
    }

    @Test
    func windowsListJSONIsTheWindowList() throws {
        let response = router().run(["windows", "list", "--json"])
        #expect(response.exitCode == 0)
        let decoded = try JSONSerialization.jsonObject(with: Data(response.stdout.utf8))
        #expect((decoded as? [Any])?.count == 1)
    }

    @Test
    func daemonRoutingIsAnExplicitList() {
        #expect(CLICommandRouter.isDaemonRouted(["focus", "left"]))
        #expect(CLICommandRouter.isDaemonRouted(["stage", "switch", "2"]))
        #expect(CLICommandRouter.isDaemonRouted(["bookmark", "set", "t"]))
        #expect(CLICommandRouter.isDaemonRouted(["bookmark", "focus", "t"]))
        #expect(CLICommandRouter.isDaemonRouted(["restore", "unhide-all"]))
        #expect(CLICommandRouter.isDaemonRouted(["state", "dump"]))
        #expect(!CLICommandRouter.isDaemonRouted(["state", "heal"]))
        #expect(!CLICommandRouter.isDaemonRouted(["restore", "apply", "--yes"]))
        #expect(!CLICommandRouter.isDaemonRouted(["events", "subscribe"]))
        #expect(!CLICommandRouter.isDaemonRouted(["targets", "interactive"]))
        #expect(!CLICommandRouter.isDaemonRouted(["daemon", "restart"]))
        #expect(!CLICommandRouter.isDaemonRouted(["doctor"]))
        #expect(!CLICommandRouter.isDaemonRouted(["focus", "--help"]))
        #expect(!CLICommandRouter.isDaemonRouted([]))
    }

    /// SPEC-017 : `balance` passe par le daemon (registre des frames écrites partagé, A4) ;
    /// `mode mutableBsp` reste accepté et sélectionne le moteur à arbre (A8).
    @Test
    func balanceIsDaemonRoutedAndMutableBspModeSelectsTree() {
        #expect(CLICommandRouter.isDaemonRouted(["balance"]))
        let store = StageStore(path: tempPath("cli-mode-alias"))
        let router = CLICommandRouter(makeService: { _ in
            let provider = PowerUserProvider(windows: [powerWindow(1, x: 0)])
            return SnapshotService(
                provider: provider,
                frameWriter: PowerUserWriter(provider: provider),
                config: RoadieConfig(),
                intentStore: LayoutIntentStore(path: tempPath("cli-mode-alias-intents")),
                stageStore: store,
                events: EventLog(path: tempPath("cli-mode-alias-events")),
                persistStateChanges: false
            )
        })

        let response = router.run(["mode", "mutableBsp"])

        #expect(response.exitCode == 0)
        #expect(store.state().scopes.first?.stages.first?.mode == .spatialBsp)
    }

    /// T211 : une commande de lecture reçoit un service non persistant ; une action, le service normal.
    @Test
    func readCommandsGetReadOnlyService() {
        #expect(CLICommandRouter.isReadOnly(["windows", "list"]))
        #expect(CLICommandRouter.isReadOnly(["state", "dump"]))
        #expect(CLICommandRouter.isReadOnly(["query", "state"]))
        #expect(CLICommandRouter.isReadOnly(["stage", "list"]))
        #expect(!CLICommandRouter.isReadOnly(["state", "heal"]))
        #expect(!CLICommandRouter.isReadOnly(["stage", "switch", "2"]))
        #expect(!CLICommandRouter.isReadOnly(["focus", "left"]))

        var requested: [Bool] = []
        let router = CLICommandRouter(makeService: { readOnly in
            requested.append(readOnly)
            let provider = PowerUserProvider(windows: [powerWindow(1, x: 0)])
            return SnapshotService(
                provider: provider,
                frameWriter: PowerUserWriter(provider: provider),
                config: RoadieConfig(),
                intentStore: LayoutIntentStore(path: tempPath("cli-ro-intents")),
                stageStore: StageStore(path: tempPath("cli-ro-stages")),
                events: EventLog(path: tempPath("cli-ro-events")),
                persistStateChanges: !readOnly
            )
        })
        _ = router.run(["windows", "list"])
        _ = router.run(["focus", "left"])
        #expect(requested == [true, false])
    }

    @Test
    func relativeConfigPathIsResolvedFromClientDirectory() {
        let argv = CommandSocketServer.resolvingPaths(["rules", "list", "--config", "conf/r.toml"], cwd: "/Users/x")
        #expect(argv == ["rules", "list", "--config", "/Users/x/conf/r.toml"])
    }

    @Test
    func socketRoundTripRunsRouterAndRefusesOthers() async throws {
        let path = socketPath()
        let server = try #require(CommandSocketServer.start(router: router(), path: path))
        defer { server.stop() }

        var info = stat()
        #expect(stat(path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o600)

        let routed = await Task.detached {
            CommandSocketClient.send(CommandSocketRequest(argv: ["focus"], cwd: "/"), path: path)
        }.value
        #expect(routed == .response(CommandSocketResponse(
            exitCode: 64,
            stderr: "roadie: focus requires left|right|up|down\n"
        )))

        let refused = await Task.detached {
            CommandSocketClient.send(CommandSocketRequest(argv: ["events", "subscribe"]), path: path)
        }.value
        guard case .response(let refusal) = refused else {
            Issue.record("expected a response, got \(refused)")
            return
        }
        #expect(refusal.exitCode == 64)

        let mismatch = await Task.detached {
            CommandSocketClient.send(CommandSocketRequest(version: 99, argv: ["focus", "left"]), path: path)
        }.value
        guard case .response(let versionError) = mismatch else {
            Issue.record("expected a response, got \(mismatch)")
            return
        }
        #expect(versionError.exitCode == 70)

        let oversized = await Task.detached {
            CommandSocketClient.send(
                CommandSocketRequest(argv: ["focus", String(repeating: "a", count: 70 * 1024)]),
                path: path
            )
        }.value
        guard case .response(let tooLarge) = oversized else {
            Issue.record("expected a response, got \(oversized)")
            return
        }
        #expect(tooLarge.exitCode == 64)
    }

    @Test
    func fallsBackLocallyOnlyWhenDaemonLockIsFree() {
        var localRuns = 0
        let local = { () -> CLIResponse in
            localRuns += 1
            return CLIResponse(exitCode: 0, stdout: "local\n")
        }
        let missingSocket = socketPath()

        // Pas de fichier de verrou : daemon absent, exécution locale.
        let noLock = CommandSocketClient.execute(
            argv: ["focus", "left"], cwd: nil,
            socketPath: missingSocket, lockPath: tempPath("cli-no-lock"), local: local
        )
        #expect(noLock.stdout == "local\n")

        // Verrou présent mais libre : daemon absent, exécution locale.
        let lockPath = tempPath("cli-lock")
        FileManager.default.createFile(atPath: lockPath, contents: nil)
        let freeLock = CommandSocketClient.execute(
            argv: ["focus", "left"], cwd: nil,
            socketPath: missingSocket, lockPath: lockPath, local: local
        )
        #expect(freeLock.stdout == "local\n")
        #expect(localRuns == 2)

        // Pid d'un process mort à côté du verrou : daemon absent, exécution locale.
        let pidPath = (lockPath as NSString).deletingPathExtension + ".pid"
        try? "999999\n".write(toFile: pidPath, atomically: true, encoding: .utf8)
        let stalePid = CommandSocketClient.execute(
            argv: ["focus", "left"], cwd: nil,
            socketPath: missingSocket, lockPath: lockPath, local: local
        )
        #expect(stalePid.stdout == "local\n")
        #expect(localRuns == 3)

        // Daemon vivant (pid du fichier) sans socket : erreur 69, jamais de réexécution locale.
        // T217 : la sonde ne prend aucun flock, le verrou reste disponible pour un démarrage.
        try? "\(getpid())\n".write(toFile: pidPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: pidPath) }
        let held = CommandSocketClient.execute(
            argv: ["focus", "left"], cwd: nil,
            socketPath: missingSocket, lockPath: lockPath, local: local
        )
        #expect(held.exitCode == 69)
        #expect(localRuns == 3)
        let starter = open(lockPath, O_RDWR)
        defer { close(starter) }
        #expect(flock(starter, LOCK_EX | LOCK_NB) == 0)

        // Commande hors liste : toujours locale, même daemon présent.
        let notRouted = CommandSocketClient.execute(
            argv: ["--version"], cwd: nil,
            socketPath: missingSocket, lockPath: lockPath, local: local
        )
        #expect(notRouted.stdout == "local\n")
        #expect(localRuns == 4)
    }

    @Test
    func daemonStatusReadingDetectsStoppedAndStaleDaemon() throws {
        let path = tempPath("cli-daemon-status")
        let now = Date()
        #expect(DaemonStatusReading.read(path: path, now: now).state == "no_status")

        let status = DaemonStatus(
            pid: 4242,
            mode: "run",
            startedAt: now.addingTimeInterval(-200),
            updatedAt: now.addingTimeInterval(-10),
            accessibilityTrusted: true,
            screenRecordingGranted: true,
            config: DaemonStatus.ConfigState(valid: true, path: "/tmp/roadies.toml", error: nil)
        )
        try status.write(to: path)
        #expect(DaemonStatusReading.read(path: path, now: now, isAlive: { _ in true }).state == "running")
        #expect(DaemonStatusReading.read(path: path, now: now, isAlive: { _ in false }).state == "pid_not_alive")
        #expect(DaemonStatusReading.read(path: path, now: now.addingTimeInterval(120), isAlive: { _ in true }).state == "status_stale")
    }

    /// Audit QUAL-101 : un verbe `layout` autre que `plan`/`apply` ne relève pas les fenêtres
    /// avant de s'exécuter (le raccourci ne fait que le relevé de la commande elle-même).
    @Test
    func layoutVerbDoesNotScanBeforeItsCommand() {
        func service(_ name: String, _ provider: RouterScanCounter) -> SnapshotService {
            SnapshotService(
                provider: provider,
                frameWriter: PowerUserWriter(provider: provider.base),
                config: RoadieConfig(),
                intentStore: LayoutIntentStore(path: tempPath("\(name)-intents")),
                stageStore: StageStore(path: tempPath("\(name)-stages")),
                events: EventLog(path: tempPath("\(name)-events")),
                persistStateChanges: false
            )
        }
        let direct = RouterScanCounter(PowerUserProvider(windows: [powerWindow(1, x: 0), powerWindow(2, x: 600)]))
        _ = LayoutCommandService(service: service("cli-layout-direct", direct)).flatten()
        let routed = RouterScanCounter(PowerUserProvider(windows: [powerWindow(1, x: 0), powerWindow(2, x: 600)]))
        let router = CLICommandRouter(makeService: { _ in service("cli-layout-routed", routed) })

        _ = router.run(["layout", "flatten"])

        #expect(direct.windowsCalls > 0)
        #expect(routed.windowsCalls == direct.windowsCalls)
    }
}

/// Fournisseur qui compte les relevés de fenêtres (énumérations AX) d'un `PowerUserProvider`.
private final class RouterScanCounter: SystemSnapshotProviding, @unchecked Sendable {
    let base: PowerUserProvider
    private(set) var windowsCalls = 0

    init(_ base: PowerUserProvider) { self.base = base }

    func permissions(prompt: Bool) -> PermissionSnapshot { base.permissions(prompt: prompt) }
    func displays() -> [DisplaySnapshot] { base.displays() }
    func windows() -> [WindowSnapshot] {
        windowsCalls += 1
        return base.windows()
    }
    func focusedWindowID() -> WindowID? { base.focusedWindowID() }
}
