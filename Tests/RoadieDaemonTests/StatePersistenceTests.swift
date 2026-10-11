import Foundation
import os
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon
import RoadieStages

/// Lot A SPEC-016 : transactions d'état, fichier illisible, écriture conditionnelle,
/// réconciliation d'identité, grâce des épinglages, journal d'événements.
@Suite
struct StatePersistenceTests {
    private let display = DisplayID(rawValue: "display-main")

    private func window(_ raw: UInt32, pid: Int32 = 500, title: String = "Doc", x: Double = 0) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: raw),
            pid: pid,
            appName: "App",
            bundleID: "com.test.app",
            title: title,
            frame: Rect(x: x, y: 0, width: 400, height: 300),
            isOnScreen: true,
            isTileCandidate: true
        )
    }

    private func stateWithMember(pid: Int32?) -> PersistentStageState {
        PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(
                        windowID: WindowID(rawValue: 10),
                        bundleID: "com.test.app",
                        title: "Doc",
                        frame: Rect(x: 0, y: 0, width: 400, height: 300),
                        pid: pid
                    ),
                ]),
            ]),
        ])
    }

    private func fileNumber(_ path: String) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.systemFileNumber] as? Int
    }

    // MARK: - Transactions (FR-013)

    @Test
    func concurrentMutationsFromTwoStoresLoseNothing() {
        let path = tempPath("state-concurrent")
        defer { try? FileManager.default.removeItem(atPath: path) }
        // Deux instances = deux "processus" ; chaque prise de verrou ouvre son propre descripteur.
        let stores = [StageStore(path: path), StageStore(path: path)]

        DispatchQueue.concurrentPerform(iterations: 100) { index in
            stores[index % 2].mutate { state in
                state.setLabel("L\(index)", displayID: display, desktopID: DesktopID(rawValue: index + 1))
            }
        }

        #expect(StageStore(path: path).state().desktopLabels.count == 100)
    }

    // MARK: - Cache de l'état (SPEC-017 A7)

    /// Deux lectures d'un fichier inchangé : un seul décodage. Une écriture par `mutate` publie
    /// la valeur : la lecture suivante ne décode pas.
    @Test
    func cachedLoadsDecodeUnchangedFileOnce() throws {
        let url = URL(fileURLWithPath: tempPath("state-cache-decodes"))
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(CountedPayload(value: 1)).write(to: url, options: .atomic)
        let start = CountedPayload.decodes.withLock { $0 }

        _ = JSONPersistence.load(CountedPayload.self, from: url, default: CountedPayload(value: 0))
        _ = JSONPersistence.load(CountedPayload.self, from: url, default: CountedPayload(value: 0))
        let afterLoads = CountedPayload.decodes.withLock { $0 }
        JSONPersistence.mutate(CountedPayload.self, at: url, default: CountedPayload(value: 0), label: "test") { $0.value = 2 }
        let loaded = JSONPersistence.load(CountedPayload.self, from: url, default: CountedPayload(value: 0))

        #expect(afterLoads - start == 1)
        #expect(CountedPayload.decodes.withLock { $0 } == afterLoads)
        #expect(loaded.value == 2)
    }

    /// Une écriture d'un autre processus (hors de ce cache), faite entre un `load` et un `mutate`,
    /// n'est pas perdue : par rename (nouvel inode) ou en place (même inode, mtime différent).
    @Test
    func externalWriteBetweenLoadAndMutateIsNotLost() throws {
        let path = tempPath("state-cache-external")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let url = URL(fileURLWithPath: path)
        let store = StageStore(path: path)
        store.mutate { $0.setLabel("A", displayID: display, desktopID: DesktopID(rawValue: 1)) }

        var external = store.state()
        external.setLabel("B", displayID: display, desktopID: DesktopID(rawValue: 2))
        try JSONEncoder().encode(external).write(to: url, options: .atomic)
        store.mutate { $0.setLabel("C", displayID: display, desktopID: DesktopID(rawValue: 3)) }

        _ = store.state()
        external = store.state()
        external.setLabel("D", displayID: display, desktopID: DesktopID(rawValue: 2))
        try JSONEncoder().encode(external).write(to: url)
        store.mutate { $0.setLabel("E", displayID: display, desktopID: DesktopID(rawValue: 4)) }

        #expect(Set(StageStore(path: path).state().desktopLabels.map(\.label)) == ["A", "C", "D", "E"])
    }

    /// Un `mutate` sans changement n'encode ni n'écrit : date de modification identique à la ns.
    @Test
    func unchangedMutateKeepsModificationTime() {
        let path = tempPath("state-cache-mtime")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = StageStore(path: path)
        store.save(stateWithMember(pid: 1))
        func modified() -> [Int] {
            var info = stat()
            guard stat(path, &info) == 0 else { return [] }
            return [info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec, Int(info.st_ino)]
        }
        let before = modified()

        store.mutate { _ in }
        store.mutate { $0.activeDisplayID = nil }

        #expect(!before.isEmpty)
        #expect(modified() == before)
    }

    /// Une valeur en cache ne masque pas un fichier devenu illisible : comportement SPEC-016 intact.
    @Test
    func cachedValueDoesNotHideFileThatBecameUnreadable() throws {
        let path = tempPath("state-cache-corrupt")
        let directory = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        defer {
            try? FileManager.default.removeItem(atPath: path)
            for file in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] where file.hasPrefix("\(name).corrupt-") {
                try? FileManager.default.removeItem(atPath: "\(directory)/\(file)")
            }
        }
        let store = StageStore(path: path)
        store.save(stateWithMember(pid: 1))
        #expect(store.state() == stateWithMember(pid: 1))
        let garbage = "{\"scopes\": [ truncated"
        try garbage.write(toFile: path, atomically: true, encoding: .utf8)

        #expect(store.state() == PersistentStageState())
        #expect(store.loadFailure != nil)
        store.mutate { $0.activeDisplayID = display }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == garbage)
    }

    /// 100 mutations concurrentes, mêlées de lectures servies par le cache : rien n'est perdu.
    @Test
    func concurrentMutationsWithCachedReadsLoseNothing() {
        let path = tempPath("state-cache-concurrent")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let stores = [StageStore(path: path), StageStore(path: path)]

        DispatchQueue.concurrentPerform(iterations: 200) { index in
            if index.isMultiple(of: 2) {
                stores[0].mutate { state in
                    state.setLabel("L\(index)", displayID: display, desktopID: DesktopID(rawValue: index + 1))
                }
            } else {
                _ = stores[1].state()
            }
        }

        #expect(StageStore(path: path).state().desktopLabels.count == 100)
    }

    // MARK: - Écriture conditionnelle (FR-014)

    @Test
    func saveWithIdenticalContentDoesNotRewriteFile() {
        let path = tempPath("state-unchanged")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = StageStore(path: path)
        let state = stateWithMember(pid: 1)
        store.save(state)
        let before = fileNumber(path)

        store.save(state)
        store.mutate { _ in }

        #expect(before != nil)
        // L'écriture atomique remplace l'inode : un inode identique prouve l'absence d'écriture.
        #expect(fileNumber(path) == before)
        store.mutate { $0.activeDisplayID = display }
        #expect(fileNumber(path) != before)
    }

    @Test
    func repeatedObservationOfUnchangedWindowsLeavesStateEqual() {
        let live = window(10, pid: 1)
        var state = stateWithMember(pid: 1)
        state.setPin(window: live, homeScope: StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")), pinScope: .desktop)
        func observe(_ state: inout PersistentStageState, at now: Date) {
            state.pruneMissingWindows(keeping: [live.id], now: now)
            state.pruneMissingPins(keeping: [live.id], now: now)
            var scope = state.scopes[0]
            scope.updateFrame(window: live)
            state.update(scope)
            state.updatePinFrame(window: live, now: now)
        }
        observe(&state, at: Date())
        let settled = state

        observe(&state, at: Date().addingTimeInterval(30))

        #expect(state == settled)
    }

    @Test
    func layoutIntentPruneKeepsAbsentDisplayForTenMinutesWithoutRewrite() {
        let path = tempPath("intents-prune")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = LayoutIntentStore(path: path)
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        store.save(LayoutIntent(scope: scope, windowIDs: [], placements: [:]))
        let now = Date()

        store.prune(keepingDisplayIDs: [display], now: now)
        let unchanged = fileNumber(path)
        store.prune(keepingDisplayIDs: [display], now: now)
        #expect(fileNumber(path) == unchanged)

        store.prune(keepingDisplayIDs: [], now: now)
        store.prune(keepingDisplayIDs: [], now: now.addingTimeInterval(599))
        #expect(store.intent(for: scope) != nil)
        store.prune(keepingDisplayIDs: [], now: now.addingTimeInterval(600))
        #expect(store.intent(for: scope) == nil)
    }

    // MARK: - Fichier illisible (FR-015)

    @Test
    func unreadableStateIsBackedUpAndNeverOverwritten() throws {
        let path = tempPath("state-corrupt")
        let directory = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        defer {
            try? FileManager.default.removeItem(atPath: path)
            for file in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] where file.hasPrefix("\(name).corrupt-") {
                try? FileManager.default.removeItem(atPath: "\(directory)/\(file)")
            }
        }
        let garbage = "{\"scopes\": [ truncated"
        try garbage.write(toFile: path, atomically: true, encoding: .utf8)
        let store = StageStore(path: path)

        #expect(store.state() == PersistentStageState())
        #expect(store.loadFailure != nil)
        store.save(stateWithMember(pid: 1))
        store.mutate { $0.activeDisplayID = display }

        #expect(try String(contentsOfFile: path, encoding: .utf8) == garbage)
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory)
            .filter { $0.hasPrefix("\(name).corrupt-") }
        #expect(backups.count == 1)
        if let backup = backups.first {
            #expect(try String(contentsOfFile: "\(directory)/\(backup)", encoding: .utf8) == garbage)
        }

        // Fichier réparé (ici supprimé) : les écritures reprennent.
        try FileManager.default.removeItem(atPath: path)
        #expect(store.loadFailure == nil)
        store.mutate { $0.activeDisplayID = display }
        #expect(store.state().activeDisplayID == display)
    }

    // MARK: - Identité des fenêtres (FR-006)

    @Test
    func reconciliationRefusedWhileMemberProcessIsAlive() {
        var state = stateWithMember(pid: 4242)

        state.reconcileWindowIDs(with: [window(99, pid: 4242)], isProcessAlive: { _ in true })

        #expect(state.stageScope(for: WindowID(rawValue: 10)) != nil)
        #expect(state.stageScope(for: WindowID(rawValue: 99)) == nil)
    }

    @Test
    func reconciliationAcceptedWhenMemberProcessIsGone() {
        var state = stateWithMember(pid: 4242)

        state.reconcileWindowIDs(with: [window(99, pid: 5000)], isProcessAlive: { _ in false })

        #expect(state.stageScope(for: WindowID(rawValue: 99)) != nil)
        #expect(state.scopes[0].stages[0].members[0].pid == 5000)
    }

    @Test
    func reconciliationRequiresFrameProximityEvenForSingleCandidate() {
        var state = stateWithMember(pid: nil)

        state.reconcileWindowIDs(with: [window(99, x: 1_000)], isProcessAlive: { _ in false })

        #expect(state.stageScope(for: WindowID(rawValue: 10)) != nil)
        #expect(state.stageScope(for: WindowID(rawValue: 99)) == nil)
    }

    @Test
    func memberRecordsPidAndKeepsPresentationStateWhenOmitted() {
        var scope = PersistentStageScope(displayID: display)
        scope.assign(window: window(10, pid: 777), to: StageID(rawValue: "1"), presentationState: .maximized)
        scope.updateFrame(window: window(10, pid: 777, x: 20))
        scope.assign(window: window(10, pid: 777), to: StageID(rawValue: "2"))

        let member = scope.stages.flatMap(\.members).first { $0.windowID == WindowID(rawValue: 10) }
        #expect(member?.pid == 777)
        #expect(member?.presentationState == .maximized)
    }

    @Test
    func assignRecordsPreviousFocusOnlyWhenFocusChanges() {
        let stage = StageID(rawValue: "1")
        var scope = PersistentStageScope(displayID: display)
        scope.assign(window: window(10), to: stage)
        scope.assign(window: window(11), to: stage)
        #expect(scope.stages.first { $0.id == stage }?.focusedWindowID == WindowID(rawValue: 11))
        #expect(scope.stages.first { $0.id == stage }?.previousFocusedWindowID == WindowID(rawValue: 10))

        // Adoption sans prise de focus : focus et précédent inchangés.
        scope.assign(window: window(12), to: stage, focusWindow: false)
        #expect(scope.stages.first { $0.id == stage }?.focusedWindowID == WindowID(rawValue: 11))
        #expect(scope.stages.first { $0.id == stage }?.previousFocusedWindowID == WindowID(rawValue: 10))
    }

    @Test
    func legacyMemberWithoutPidDecodes() throws {
        let json = #"{"windowID":10,"bundleID":"com.test.app","title":"Doc","frame":{"x":0,"y":0,"width":1,"height":1}}"#
        let member = try JSONDecoder().decode(PersistentStageMember.self, from: Data(json.utf8))
        #expect(member.pid == nil)
    }

    // MARK: - Épinglages (FR-007)

    @Test
    func pinsSurviveFortyFiveSecondsOfAbsence() {
        let home = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        var state = PersistentStageState()
        state.setPin(window: window(10), homeScope: home, pinScope: .desktop)
        let start = Date()

        #expect(state.pruneMissingPins(keeping: [], now: start).isEmpty)
        #expect(state.pruneMissingPins(keeping: [], now: start.addingTimeInterval(44)).isEmpty)
        // Retour de la fenêtre : la grâce repart de zéro.
        #expect(state.pruneMissingPins(keeping: [WindowID(rawValue: 10)], now: start.addingTimeInterval(44)).isEmpty)
        #expect(state.pruneMissingPins(keeping: [], now: start.addingTimeInterval(50)).isEmpty)
        let pruned = state.pruneMissingPins(keeping: [], now: start.addingTimeInterval(95))

        #expect(pruned.map(\.windowID) == [WindowID(rawValue: 10)])
        #expect(state.windowPins.isEmpty)
    }

    // MARK: - Journal d'événements (T017)

    @Test
    func eventLogRotationUnderConcurrencyKeepsEveryLineWhole() throws {
        let path = tempPath("events-rotation") + "l"
        defer {
            for suffix in ["", ".1", ".lock"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        }
        let logs = [EventLog(path: path, maxBytes: 2_000, retainedBackups: 1), EventLog(path: path, maxBytes: 2_000, retainedBackups: 1)]

        DispatchQueue.concurrentPerform(iterations: 200) { index in
            logs[index % 2].append(RoadieEvent(type: "test.event", details: ["index": String(index)]))
        }

        let lines = [path, path + ".1"]
            .compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }
            .flatMap { $0.split(separator: "\n") }
        #expect(!lines.isEmpty)
        #expect(FileManager.default.fileExists(atPath: path + ".1"))
        for line in lines {
            #expect((try? JSONSerialization.jsonObject(with: Data(line.utf8))) != nil)
        }
    }

    @Test
    func subscriptionResetsAfterRotationAndSkipsPartialLine() throws {
        let path = tempPath("events-subscription") + "l"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let log = EventLog(path: path)
        let service = EventSubscriptionService(path: path)
        log.append(RoadieEvent(type: "first"))
        log.append(RoadieEvent(type: "second"))
        let afterTwo = service.readAvailable(from: EventSubscriptionCursor()).cursor

        // Rotation : le fichier repart plus court que le curseur.
        try FileManager.default.removeItem(atPath: path)
        log.append(RoadieEvent(type: "third"))
        let afterRotation = service.readAvailable(from: afterTwo)
        #expect(afterRotation.events.map(\.type) == ["third"])

        // Ligne partielle : non consommée tant que le saut de ligne n'est pas écrit.
        let handle = try #require(FileHandle(forWritingAtPath: path))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"type":"partial""#.utf8))
        try handle.close()
        let partial = service.readAvailable(from: afterRotation.cursor)
        #expect(partial.events.isEmpty)
        #expect(partial.cursor == afterRotation.cursor)
    }

    // MARK: - Réparations sous transaction (FR-013, T202)

    /// La réparation d'état part de l'état relu sous verrou : une écriture faite par un autre
    /// acteur pendant le snapshot AX est conservée, et la réparation est bien appliquée.
    @Test
    func stateAuditHealKeepsChangesWrittenDuringSnapshot() {
        let path = tempPath("state-audit-heal-concurrent")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = StageStore(path: path)
        // Scope d'un écran absent dont la stage active n'existe pas : réparé par `heal`, pas par
        // la réconciliation du snapshot.
        let gone = DisplayID(rawValue: "display-gone")
        var initial = stateWithMember(pid: 500)
        initial.scopes.append(PersistentStageScope(
            displayID: gone,
            activeStageID: StageID(rawValue: "9"),
            stages: [PersistentStage(id: StageID(rawValue: "1"))]
        ))
        store.save(initial)
        let provider = ConcurrentWriteProvider(
            display: DisplaySnapshot(
                id: display,
                index: 1,
                name: "Main",
                frame: Rect(x: 0, y: 0, width: 1000, height: 500),
                visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
                isMain: true
            ),
            windowList: [window(10)]
        )
        provider.onWindows = {
            store.mutate { $0.setLabel("concurrent", displayID: display, desktopID: DesktopID(rawValue: 1)) }
        }
        let service = SnapshotService(provider: provider, frameWriter: provider, stageStore: store)

        let report = StateAuditService(service: service, stageStore: store).heal()
        let state = store.state()

        #expect(report.repaired >= 1)
        #expect(state.scopes.first { $0.displayID == gone }?.activeStageID == StageID(rawValue: "1"))
        #expect(state.label(displayID: display, desktopID: DesktopID(rawValue: 1)) == "concurrent")
    }

    // MARK: - Activité des commandes (LayoutCommandActivity)

    /// Activité par scope (FR-040) : un scope marqué n'est pas une activité globale ; une activité
    /// globale l'emporte ; une entrée expirée est retirée à l'écriture suivante.
    @Test
    func layoutCommandActivityTracksScopesSeparatelyFromGlobalActivity() {
        let path = tempPath("layout-activity-scopes")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let activity = LayoutCommandActivity(path: path)
        let now = Date()
        let scopeA = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let otherStageOnA = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2"))
        let scopeB = StageScope(displayID: DisplayID(rawValue: "display-b"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))

        activity.markActive(reason: "scoped", scopes: [scopeA], now: now, holdSeconds: 2)
        let scoped = activity.activity(now: now)
        activity.markActive(reason: "short", scopes: [scopeB], now: now, holdSeconds: 0.5)
        activity.markActive(reason: "later", scopes: [scopeA], now: now.addingTimeInterval(1), holdSeconds: 2)
        let afterExpiry = activity.activity(now: now.addingTimeInterval(1))
        activity.markActive(reason: "global", now: now, holdSeconds: 2)
        let global = activity.activity(now: now)

        #expect(scoped?.isGlobal == false)
        #expect(scoped?.covers(otherStageOnA) == true)
        #expect(scoped?.covers(scopeB) == false)
        #expect(afterExpiry?.scopes == [scopeA])
        #expect(global?.isGlobal == true)
        #expect(global?.covers(scopeB) == true)
    }

    /// Un fichier écrit par une version antérieure (délai puis raison) reste lu comme global.
    @Test
    func layoutCommandActivityReadsLegacyGlobalFile() throws {
        let path = tempPath("layout-activity-legacy")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let now = Date()
        try "\(now.addingTimeInterval(3).timeIntervalSince1970)\nlegacy\n".write(toFile: path, atomically: true, encoding: .utf8)

        let activity = LayoutCommandActivity(path: path).activity(now: now)

        #expect(activity?.isGlobal == true)
        #expect(activity?.scopes.isEmpty == true)
    }

    @Test
    func layoutCommandActivityKeepsLongestExpiryAcrossConcurrentWriters() {
        let path = tempPath("layout-activity")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let activities = [LayoutCommandActivity(path: path), LayoutCommandActivity(path: path)]
        let now = Date()

        DispatchQueue.concurrentPerform(iterations: 50) { index in
            activities[index % 2].markActive(reason: "t\(index)", now: now, holdSeconds: Double(index))
        }

        let expiry = activities[0].activeUntil(now: now)
        #expect(expiry.map { abs($0.timeIntervalSince(now) - 49) < 0.01 } == true)
    }
}

/// Fournisseur AX factice : exécute `onWindows` une fois pendant l'énumération des fenêtres,
/// comme un autre processus qui écrit l'état pendant le snapshot. N'écrit aucun cadre.
private final class ConcurrentWriteProvider: SystemSnapshotProviding, WindowFrameWriting, @unchecked Sendable {
    private let display: DisplaySnapshot
    private let windowList: [WindowSnapshot]
    var onWindows: (() -> Void)?

    init(display: DisplaySnapshot, windowList: [WindowSnapshot]) {
        self.display = display
        self.windowList = windowList
    }

    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { [display] }

    func windows() -> [WindowSnapshot] {
        let action = onWindows
        onWindows = nil
        action?()
        return windowList
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? { nil }
}

/// Charge utile qui compte ses décodages (test du cache, A7).
private struct CountedPayload: Codable, Equatable {
    static let decodes = OSAllocatedUnfairLock(initialState: 0)
    var value: Int

    init(value: Int) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        value = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .value)
        Self.decodes.withLock { $0 += 1 }
    }
}
