import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
@testable import RoadieDaemon

@Suite(.serialized)
struct Spec024PerformanceTests {
    private let scope = StageScope(displayID: DisplayID(rawValue: "display-main"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))

    private func window(_ id: UInt32, frame: Rect) -> WindowSnapshot {
        WindowSnapshot(id: WindowID(rawValue: id), pid: Int32(id), appName: "Test", bundleID: "com.test",
                       title: " Common   Title ", frame: frame, isOnScreen: true, isTileCandidate: true)
    }

    private func member(_ id: UInt32, frame: Rect, pid: Int32? = nil) -> PersistentStageMember {
        PersistentStageMember(windowID: WindowID(rawValue: id), bundleID: "COM.TEST", title: "common title", frame: frame, pid: pid)
    }

    private func state(_ members: [PersistentStageMember]) -> PersistentStageState {
        PersistentStageState(scopes: [PersistentStageScope(displayID: scope.displayID, stages: [PersistentStage(id: scope.stageID, members: members)])])
    }

    private func signature(_ bundle: String, _ title: String) -> String {
        [bundle, title].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).lowercased()
        }.joined(separator: "\n")
    }

    /// Référence de bestReplacement/reconcile au commit d2e7daf0, avant l'index.
    private func referenceRemaps(_ state: PersistentStageState, live: [WindowSnapshot]) -> [WindowID: WindowID] {
        let windows = live.filter(\.isTileCandidate)
        let liveIDs = Set(windows.map(\.id))
        let members = state.scopes.flatMap(\.stages).flatMap(\.members)
        var claimed = Set(members.map(\.windowID).filter { liveIDs.contains($0) })
        var bySignature: [String: [WindowSnapshot]] = [:]
        for window in windows { bySignature[signature(window.bundleID, window.title), default: []].append(window) }
        var remapped: [WindowID: WindowID] = [:]
        for member in members where !liveIDs.contains(member.windowID) && member.pid != 999 {
            let scored = (bySignature[signature(member.bundleID, member.title)] ?? [])
                .filter { !claimed.contains($0.id) }
                .map { candidate in (candidate, distance(member.frame, candidate.frame)) }
                .sorted { $0.1 < $1.1 }
            guard let best = scored.first,
                  best.1 <= 360,
                  (scored.dropFirst().first?.1 ?? .greatestFiniteMagnitude) - best.1 >= 120 else { continue }
            claimed.insert(best.0.id)
            remapped[member.windowID] = best.0.id
        }
        return remapped
    }

    private func distance(_ lhs: Rect, _ rhs: Rect) -> Double {
        abs(lhs.cgRect.midX - rhs.cgRect.midX) + abs(lhs.cgRect.midY - rhs.cgRect.midY)
            + abs(lhs.width - rhs.width) / 2 + abs(lhs.height - rhs.height) / 2
    }

    private func resultingIDs(_ initial: PersistentStageState, remaps: [WindowID: WindowID]) -> [WindowID] {
        initial.scopes.flatMap(\.stages).flatMap(\.members).map { remaps[$0.windowID] ?? $0.windowID }
    }

    @Test
    func twoNearestKeepThresholdsAmbiguityAndLivePIDProtection() {
        let origin = Rect(x: 0, y: 0, width: 100, height: 100)
        let base = state([member(1, frame: origin)])
        for x in [0.0, 10, 119.999999, 120, 360, 360.nextUp, 480] {
            let live = [window(100, frame: Rect(x: x, y: 0, width: 100, height: 100)),
                        window(101, frame: Rect(x: 480, y: 0, width: 100, height: 100))]
            var actual = base
            actual.reconcileWindowIDs(with: live, isProcessAlive: { $0 == 999 })
            #expect(actual.scopes[0].stages[0].members.map(\.windowID) == resultingIDs(base, remaps: referenceRemaps(base, live: live)))
        }
        var protected = state([member(1, frame: origin, pid: 999)])
        protected.reconcileWindowIDs(with: [window(100, frame: origin)], isProcessAlive: { $0 == 999 })
        #expect(protected.scopes[0].stages[0].members[0].windowID == WindowID(rawValue: 1))
    }

    @Test
    func randomizedGeometryMatchesHistoricalNearestPair() {
        var random: UInt64 = 24
        func number(_ bound: UInt64) -> Double {
            random = random &* 6364136223846793005 &+ 1
            return Double((random >> 20) % (bound * 1024)) / 1024
        }
        for _ in 0..<150 {
            let live = (0..<24).map { index in
                window(UInt32(100 + index), frame: Rect(x: number(1200) - 600, y: number(600) - 300,
                                                       width: number(500) + 1, height: number(300) + 1))
            }
            let old = (0..<18).map { index in
                member(UInt32(1 + index), frame: Rect(x: number(1200) - 600, y: number(600) - 300,
                                                       width: number(500) + 1, height: number(300) + 1))
            }
            let initial = state(old)
            var actual = initial
            actual.reconcileWindowIDs(with: live, isProcessAlive: { _ in false })
            #expect(actual.scopes[0].stages[0].members.map(\.windowID) == resultingIDs(initial, remaps: referenceRemaps(initial, live: live)))
        }
    }

    @Test
    func adoptedCandidatesAndSuccessiveClaimsAreExcluded() {
        let frame = Rect(x: 0, y: 0, width: 100, height: 100)
        let far = Rect(x: 300, y: 0, width: 100, height: 100)
        let live = [window(100, frame: frame), window(101, frame: far)]
        var actual = state([member(1, frame: frame), member(2, frame: frame), member(100, frame: frame)])
        let initial = actual
        actual.reconcileWindowIDs(with: live, isProcessAlive: { _ in false })
        #expect(actual.scopes[0].stages[0].members.map(\.windowID) == resultingIDs(initial, remaps: referenceRemaps(initial, live: live)))
        #expect(actual.scopes[0].stages[0].members.map(\.windowID) == [WindowID(rawValue: 101), WindowID(rawValue: 2), WindowID(rawValue: 100)])
    }

    @Test
    func exactAmbiguityGapAndNonFiniteGeometryMatchReference() {
        // Centre x=0 : l'écart d'un ULP autour de 120 reste représentable dans le score.
        let origin = Rect(x: -50, y: 0, width: 100, height: 100)
        let initial = state([member(1, frame: origin)])
        for gap in [Double(120).nextDown, 120, Double(120).nextUp] {
            let live = [window(100, frame: origin), window(101, frame: Rect(x: gap - 50, y: 0, width: 100, height: 100))]
            var actual = initial
            actual.reconcileWindowIDs(with: live, isProcessAlive: { _ in false })
            #expect(actual.scopes[0].stages[0].members.map(\.windowID) == resultingIDs(initial, remaps: referenceRemaps(initial, live: live)))
            #expect(actual.scopes[0].stages[0].members[0].windowID == WindowID(rawValue: gap < 120 ? 1 : 100))
        }
        for coordinate in [Double.infinity, -Double.infinity, Double.nan] {
            let invalid = Rect(x: coordinate, y: 0, width: 100, height: 100)
            let live = [window(100, frame: invalid), window(101, frame: origin)]
            var actual = initial
            actual.reconcileWindowIDs(with: live, isProcessAlive: { _ in false })
            #expect(actual.scopes[0].stages[0].members.map(\.windowID) == resultingIDs(initial, remaps: referenceRemaps(initial, live: live)))
            let invalidMember = state([member(1, frame: invalid)])
            var invalidActual = invalidMember
            invalidActual.reconcileWindowIDs(with: [window(101, frame: origin)], isProcessAlive: { _ in false })
            #expect(invalidActual.scopes[0].stages[0].members.map(\.windowID) == resultingIDs(invalidMember, remaps: referenceRemaps(invalidMember, live: [window(101, frame: origin)])))
        }
    }

    @Test
    func deepTreeClaimsRemoveAllOccurrencesAndPreserveFocusAndGroups() {
        let old = (0..<32).map { member(UInt32(1 + $0), frame: Rect(x: Double($0) * 1000, y: 0, width: 100, height: 100)) }
        var live = (0..<32).map { window(UInt32(100 + $0), frame: old[$0].frame) }
        live.append(window(100, frame: Rect(x: -1000, y: 0, width: 100, height: 100)))
        var initial = state(old)
        initial.scopes[0].stages[0].focusedWindowID = WindowID(rawValue: 2)
        initial.scopes[0].stages[0].previousFocusedWindowID = WindowID(rawValue: 1)
        initial.scopes[0].stages[0].groups = [WindowGroup(id: "pair", windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)], activeWindowID: WindowID(rawValue: 2))]
        var actual = initial
        actual.reconcileWindowIDs(with: live, isProcessAlive: { _ in false })
        #expect(actual.scopes[0].stages[0].members.map(\.windowID) == resultingIDs(initial, remaps: referenceRemaps(initial, live: live)))
        #expect(actual.scopes[0].stages[0].focusedWindowID == WindowID(rawValue: 101))
        #expect(actual.scopes[0].stages[0].previousFocusedWindowID == WindowID(rawValue: 100))
        #expect(actual.scopes[0].stages[0].groups[0].windowIDs == [WindowID(rawValue: 100), WindowID(rawValue: 101)])
        #expect(actual.scopes[0].stages[0].groups[0].activeWindowID == WindowID(rawValue: 101))
    }

    @Test
    func sharedCandidateIDCannotBeClaimedUnderAnotherSignature() {
        let frame = Rect(x: 0, y: 0, width: 100, height: 100)
        var otherMember = member(2, frame: frame)
        otherMember.title = "other"
        var otherCandidate = window(100, frame: frame)
        otherCandidate.title = "other"
        let live = [window(100, frame: frame), otherCandidate]
        let initial = state([member(1, frame: frame), otherMember])
        var actual = initial
        actual.reconcileWindowIDs(with: live, isProcessAlive: { _ in false })
        #expect(actual.scopes[0].stages[0].members.map(\.windowID) == resultingIDs(initial, remaps: referenceRemaps(initial, live: live)))
        #expect(actual.scopes[0].stages[0].members.map(\.windowID) == [WindowID(rawValue: 100), WindowID(rawValue: 2)])
    }

    @Test
    func oneValidationPerActiveBSPStage() throws {
        var state = RoadieState()
        state.ensureDisplay(scope.displayID)
        let inactive = StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: StageID(rawValue: "2"))
        try state.createStage(id: inactive.stageID, name: "Inactive", in: scope.displayID, desktopID: scope.desktopID)
        let entries = (1...200).map { raw in
            ScopedWindowSnapshot(window: powerWindow(UInt32(raw), x: Double(raw)), scope: raw <= 100 ? scope : inactive)
        }
        let snapshot = DaemonSnapshot(permissions: PermissionSnapshot(accessibilityTrusted: true), displays: [powerDisplay()], windows: entries, state: state)
        var calls: [StageScope] = []
        let result = LayoutMaintainer.authoritativeModelScopes(for: Set(entries.map { $0.window.id }), in: snapshot) {
            calls.append($0); return true
        }
        #expect(calls == [scope])
        #expect(result == [scope])
        try state.setMode(.masterStack, for: scope)
        let otherMode = DaemonSnapshot(permissions: snapshot.permissions, displays: snapshot.displays, windows: entries, state: state)
        #expect(LayoutMaintainer.authoritativeModelScopes(for: Set(entries.map { $0.window.id }), in: otherMode) { _ in
            Issue.record("A non-BSP stage must not be validated"); return true
        }.isEmpty)
        #expect(LayoutMaintainer.authoritativeModelScopes(for: [], in: snapshot) { _ in
            Issue.record("No changed window means no validation"); return true
        }.isEmpty)
    }

    private func medianMilliseconds(iterations: Int, _ body: () throws -> Int) rethrows -> Double {
        var checksum = try body()
        var samples: [Double] = []
        for _ in 0..<5 {
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<iterations { checksum &+= try body() }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 / Double(iterations))
        }
        print("PERF024_CHECKSUM \(checksum)")
        return samples.sorted()[2]
    }

    private func report(_ name: String, n: Int, old: Double, new: Double) {
        let variant = ProcessInfo.processInfo.environment["ROADIE_PERF_VARIANT"] ?? "after"
        print("PERF024 {\"variant\":\"\(variant)\",\"scenario\":\"\(name)\",\"n\":\(n),\"reference_ms\":\(old),\"production_ms\":\(new)}")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ROADIE_PERF_BENCHMARK"] == "1"))
    func benchmarkHistoricalAndCorrectedPaths() throws {
        for n in [50, 100, 200, 400] {
            var fresh = RoadieState()
            fresh.ensureDisplay(scope.displayID)
            let assignments = (1...n).map { (WindowID(rawValue: UInt32($0)), scope) }
            let oldMembership = try medianMilliseconds(iterations: 5) {
                var state = fresh
                for (id, scope) in assignments { try state.assignWindow(id, to: scope) }
                return state.stage(scope: scope)?.windowIDs.count ?? 0
            }
            let newMembership = try medianMilliseconds(iterations: 5) {
                var state = fresh
                try state.initializeWindowMemberships(assignments)
                return state.stage(scope: scope)?.windowIDs.count ?? 0
            }
            report("PERF-010-membership", n: n, old: oldMembership, new: newMembership)

            let paths = [tempPath("perf024-intents"), tempPath("perf024-stages"), tempPath("perf024-events")]
            defer { for path in paths { try? FileManager.default.removeItem(atPath: path) } }
            let frames = (0..<n).map { Rect(x: Double($0) * 1000 / Double(n), y: 0, width: 1000 / Double(n), height: 800) }
            let entries = frames.enumerated().map { ScopedWindowSnapshot(window: window(UInt32(1 + $0.offset), frame: $0.element), scope: scope) }
            var layoutState = fresh
            try layoutState.initializeWindowMemberships(assignments)
            let snapshot = DaemonSnapshot(permissions: PermissionSnapshot(accessibilityTrusted: true), displays: [powerDisplay()], windows: entries, state: layoutState)
            let intents = LayoutIntentStore(path: paths[0])
            intents.save(LayoutIntent(scope: scope, windowIDs: assignments.map { $0.0 }, placements: Dictionary(uniqueKeysWithValues: zip(assignments.map { $0.0 }, frames)), source: .command))
            let provider = PowerUserProvider(windows: entries.map(\.window))
            let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider),
                config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 0)),
                railSettings: RailSettings.load(raw: "[fx.rail]\nenabled = false\n"),
                intentStore: intents, stageStore: StageStore(path: paths[1]), events: EventLog(path: paths[2]), persistStateChanges: false)
            #expect(service.hasValidLayoutIntent(scope: scope, in: snapshot))
            let changed = Set(assignments.map { $0.0 })
            let oldValidation = medianMilliseconds(iterations: 1) {
                Set(snapshot.windows.compactMap { entry -> StageScope? in
                    guard changed.contains(entry.window.id), let candidate = entry.scope,
                          snapshot.state.stage(scope: candidate)?.mode == .bsp,
                          snapshot.state.activeScope(on: candidate.displayID) == candidate,
                          service.hasValidLayoutIntent(scope: candidate, in: snapshot) else { return nil }
                    return candidate
                }).count
            }
            let newValidation = medianMilliseconds(iterations: 1) {
                LayoutMaintainer.authoritativeModelScopes(for: changed, in: snapshot) {
                    service.hasValidLayoutIntent(scope: $0, in: snapshot)
                }.count
            }
            report("PERF-011-validation", n: n, old: oldValidation, new: newValidation)

            let common = Rect(x: 0, y: 0, width: 100, height: 100)
            let live = (0..<n).map { window(UInt32(1000 + $0), frame: common) }
            let oldMembers = (0..<n).map { member(UInt32(1 + $0), frame: common) }
            let ambiguous = state(oldMembers)
            let oldMatching = medianMilliseconds(iterations: 3) { referenceRemaps(ambiguous, live: live).count }
            let newMatching = medianMilliseconds(iterations: 3) {
                var actual = ambiguous
                actual.reconcileWindowIDs(with: live, isProcessAlive: { _ in false })
                return actual.scopes[0].stages[0].members.count
            }
            report("PERF-012-ambiguous", n: n, old: oldMatching, new: newMatching)
            let adopted = state(oldMembers + live.map { member($0.id.rawValue, frame: $0.frame) })
            let oldAdopted = medianMilliseconds(iterations: 3) { referenceRemaps(adopted, live: live).count }
            let newAdopted = medianMilliseconds(iterations: 3) {
                var actual = adopted
                actual.reconcileWindowIDs(with: live, isProcessAlive: { _ in false })
                return actual.scopes[0].stages[0].members.count
            }
            report("PERF-012-adopted", n: n, old: oldAdopted, new: newAdopted)
            let empty = state([])
            let oldFresh = medianMilliseconds(iterations: 3) { referenceRemaps(empty, live: live).count }
            let newFresh = medianMilliseconds(iterations: 3) {
                var actual = empty
                actual.reconcileWindowIDs(with: live, isProcessAlive: { _ in false })
                return actual.scopes.count
            }
            report("PERF-012-no-orphans", n: n, old: oldFresh, new: newFresh)
        }
    }
}
