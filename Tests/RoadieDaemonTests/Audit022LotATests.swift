import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon
import RoadieStages

private struct LotAProvider: SystemSnapshotProviding {
    var displaySnapshots: [DisplaySnapshot]
    var windowSnapshots: [WindowSnapshot] = []

    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { displaySnapshots }
    func windows() -> [WindowSnapshot] { windowSnapshots }
    func focusedWindowID() -> WindowID? { nil }
    func mouseLocation() -> CGPoint? { nil }
}

/// Session 022, lot A : constats PERF-001, REL-005, REL-006, MIN-002, REL-013.
@Suite
struct Audit022LotATests {
    // MARK: REL-005

    /// Le snapshot d'automatisation garde les noms persistés, les stages vides et le label du desktop.
    @Test
    func automationSnapshotKeepsPersistedNamesEmptyStagesAndDesktopLabel() {
        let display = powerDisplay("display-a")
        let desktop = DesktopID(rawValue: 1)
        let stageStore = StageStore(path: tempPath("lot-a-automation-names"))
        stageStore.mutate { $0.setLabel("Dev", displayID: display.id, desktopID: desktop) }
        let service = SnapshotService(
            provider: LotAProvider(displaySnapshots: [display]),
            config: RoadieConfig(stageManager: StageManagerConfig(workspaces: [
                StageDefinition(id: "1", displayName: "Work"),
                StageDefinition(id: "2", displayName: "Com"),
            ])),
            stageStore: stageStore
        )

        let automation = service.snapshot().automationSnapshot(service: AutomationSnapshotService(stageStore: stageStore))

        #expect(automation.stages.map(\.id) == ["1", "2"])
        #expect(automation.stages.map(\.name) == ["Work", "Com"])
        #expect(automation.desktops.map(\.label) == ["Dev"])
        #expect(automation.activeStageId == "1")
        try? FileManager.default.removeItem(at: stageStore.fileURL)
    }

    /// Une stage renommée et occupée par une fenêtre garde son nom dans l'état runtime.
    @Test
    func runtimeStateUsesRenamedStageName() {
        let display = powerDisplay("display-a")
        let window = powerWindow(1, x: 100)
        let stageStore = StageStore(path: tempPath("lot-a-renamed-stage"))
        let service = SnapshotService(
            provider: LotAProvider(displaySnapshots: [display], windowSnapshots: [window]),
            stageStore: stageStore
        )
        _ = service.snapshot()
        stageStore.mutate { state in
            guard let index = state.scopes.firstIndex(where: { $0.displayID == display.id }) else { return }
            state.scopes[index].stages[0].name = "Mail"
        }

        let snapshot = service.snapshot()
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))

        #expect(snapshot.state.stage(scope: scope)?.name == "Mail")
        #expect(snapshot.state.stage(scope: scope)?.windowIDs == [window.id])
        try? FileManager.default.removeItem(at: stageStore.fileURL)
    }

    // MARK: REL-013

    /// Deux écrans ont chacun desktop 1 / stage 1 : chaque ligne indique son écran.
    @Test
    func automationStagesAndGroupsCarryTheirDisplayAndDesktop() throws {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 1000)
        let desktop = DesktopID(rawValue: 1)
        let stage = StageID(rawValue: "1")
        var state = RoadieState()
        state.ensureDisplay(main.id)
        state.ensureDisplay(side.id)
        let sideScope = StageScope(displayID: side.id, desktopID: desktop, stageID: stage)
        try state.assignWindow(WindowID(rawValue: 1), to: sideScope)
        try state.assignWindow(WindowID(rawValue: 2), to: sideScope)
        try state.setGroups([WindowGroup(id: "g1", windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)])], for: sideScope)
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [main, side],
            windows: [],
            state: state
        )

        let automation = AutomationSnapshotService(rules: [], stageStore: StageStore(path: tempPath("lot-a-stage-display")))
            .snapshot(from: snapshot)

        #expect(automation.stages.map(\.displayId) == [main.id.rawValue, side.id.rawValue])
        #expect(automation.stages.map(\.desktopId) == ["1", "1"])
        #expect(automation.groups.map(\.displayId) == [side.id.rawValue])
        #expect(automation.groups.map(\.desktopId) == ["1"])
    }

    /// Un ancien JSON sans `displayId` se décode toujours (champ ajouté, pas imposé).
    @Test
    func automationStageDecodesWithoutDisplayID() throws {
        let json = #"{"id":"1","desktopId":"1","name":"Stage 1","mode":"bsp","windowIds":[]}"#
        let stage = try JSONDecoder().decode(AutomationStageSnapshot.self, from: Data(json.utf8))
        #expect(stage.displayId == nil)
        let group = try JSONDecoder().decode(
            AutomationGroupSnapshot.self,
            from: Data(#"{"id":"g","stageId":"1","memberIds":[],"presentation":"stack"}"#.utf8)
        )
        #expect(group.displayId == nil)
        #expect(group.desktopId == nil)
    }

    // MARK: REL-006

    /// Triplet du constat : B<A par Y, C<B par Y, A<C par X. L'ordre ne dépend plus de l'ordre d'entrée.
    @Test
    func spatialOrderIsIndependentOfInputOrder() throws {
        let display = powerDisplay("display-main")
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        // Centres : A (500, 600), B (540, 550), C (580, 500).
        let windows = [
            powerWindow(1, x: 480, y: 580, width: 40, height: 40),
            powerWindow(2, x: 520, y: 530, width: 40, height: 40),
            powerWindow(3, x: 560, y: 480, width: 40, height: 40),
        ]
        let service = SnapshotService(
            provider: LotAProvider(displaySnapshots: [display]),
            stageStore: StageStore(path: tempPath("lot-a-spatial-order"))
        )
        var orders: Set<[WindowID]> = []
        for permutation in permutations(windows.map(\.id)) {
            var state = RoadieState()
            state.ensureDisplay(display.id)
            try state.setMode(.bsp, for: scope)
            for id in permutation {
                try state.assignWindow(id, to: scope)
            }
            let snapshot = DaemonSnapshot(
                permissions: PermissionSnapshot(accessibilityTrusted: true),
                displays: [display],
                windows: windows.map { ScopedWindowSnapshot(window: $0, scope: scope) },
                state: state
            )
            orders.insert(service.orderedWindowIDs(in: scope, from: snapshot))
        }

        #expect(orders.count == 1)
    }

    /// Colonnes nettes (écarts > seuil) : ordre inchangé, colonne par colonne puis de haut en bas.
    @Test
    func spatialOrderKeepsColumnsThenRows() throws {
        let display = powerDisplay("display-main")
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let windows = [
            powerWindow(1, x: 500, y: 0, width: 500, height: 400),
            powerWindow(2, x: 0, y: 0, width: 500, height: 800),
            powerWindow(3, x: 500, y: 400, width: 500, height: 400),
        ]
        var state = RoadieState()
        state.ensureDisplay(display.id)
        try state.setMode(.bsp, for: scope)
        for window in windows {
            try state.assignWindow(window.id, to: scope)
        }
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [display],
            windows: windows.map { ScopedWindowSnapshot(window: $0, scope: scope) },
            state: state
        )
        let service = SnapshotService(
            provider: LotAProvider(displaySnapshots: [display]),
            stageStore: StageStore(path: tempPath("lot-a-spatial-columns"))
        )

        #expect(service.orderedWindowIDs(in: scope, from: snapshot).map(\.rawValue) == [2, 1, 3])
    }

    // MARK: PERF-001

    /// Le calcul par colonnes donne le même verdict que l'ancien parcours cellule × cadres.
    @Test
    func untiledCellDetectionMatchesReference() {
        var generator = LotARandom(seed: 0x5EED_022A)
        let container = CGRect(x: 0, y: 0, width: 1000, height: 800)
        var verdicts: [Bool] = []
        for round in 0..<600 {
            let gap = CGFloat(generator.next() % 40)
            let frames: [CGRect]
            if round.isMultiple(of: 3) {
                // Cadres quelconques : trous et chevauchements.
                frames = (0..<Int(generator.next() % 8) + 2).map { _ in
                    CGRect(
                        x: CGFloat(generator.next() % 900), y: CGFloat(generator.next() % 700),
                        width: CGFloat(generator.next() % 600) + 10, height: CGFloat(generator.next() % 500) + 10
                    )
                }
            } else {
                // Pavage par découpes successives, décalé de quelques points, parfois privé d'un cadre.
                var tiles = Self.guillotine(container, pieces: Int(generator.next() % 9) + 2, gap: gap, generator: &generator)
                    .map { $0.offsetBy(dx: CGFloat(Int(generator.next() % 7) - 3), dy: CGFloat(Int(generator.next() % 7) - 3)) }
                if generator.next() % 3 == 0 { tiles.remove(at: Int(generator.next() % UInt64(tiles.count))) }
                frames = tiles
            }
            let expected = referenceLeavesLargeUntiledCells(frames, in: container, allowedGap: gap)
            #expect(SnapshotService.framesLeaveLargeUntiledCells(frames, in: container, allowedGap: gap) == expected)
            verdicts.append(expected)
        }
        // Le jeu couvre les deux verdicts.
        #expect(verdicts.contains(true) && verdicts.contains(false))

        for gap in [CGFloat(0), 10, 30] {
            for frames in [Self.grid(columns: 3, rows: 2, gap: gap, in: container), Self.grid(columns: 4, rows: 4, gap: gap, in: container)] {
                #expect(!SnapshotService.framesLeaveLargeUntiledCells(frames, in: container, allowedGap: gap))
                #expect(referenceLeavesLargeUntiledCells(frames, in: container, allowedGap: gap) == false)
                let holed = Array(frames.dropLast())
                #expect(SnapshotService.framesLeaveLargeUntiledCells(holed, in: container, allowedGap: gap))
                #expect(referenceLeavesLargeUntiledCells(holed, in: container, allowedGap: gap))
            }
        }
    }

    /// Famille du constat : m colonnes coupées à des hauteurs différentes, sans trou.
    @Test
    func columnFamilyWithoutHoleStaysValid() {
        for m in [2, 10, 40] {
            let (frames, container) = Self.columnFamily(m)
            #expect(!SnapshotService.framesLeaveLargeUntiledCells(frames, in: container, allowedGap: 0))
            #expect(!referenceLeavesLargeUntiledCells(frames, in: container, allowedGap: 0))
        }
    }

    // MARK: MIN-002

    /// L'encodeur générique garde les options : clés triées, compact ou indenté.
    @Test
    func snapshotEncodingKeepsFormat() throws {
        let plan = ApplyPlan(commands: [ApplyCommand(window: powerWindow(7, x: 10), frame: Rect(x: 1, y: 2, width: 3, height: 4))])
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [powerDisplay()],
            windows: [],
            state: RoadieState()
        )
        for pretty in [true, false] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
            #expect(try SnapshotEncoding.json(plan, pretty: pretty) == String(decoding: try encoder.encode(plan), as: UTF8.self))
            #expect(try SnapshotEncoding.json(snapshot, pretty: pretty) == String(decoding: try encoder.encode(snapshot), as: UTF8.self))
        }
        #expect(try SnapshotEncoding.json(ApplyPlan(commands: []), pretty: false) == #"{"commands":[]}"#)
    }

    // MARK: Aides

    private static func grid(columns: Int, rows: Int, gap: CGFloat, in container: CGRect) -> [CGRect] {
        let width = (container.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let height = (container.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        return (0..<columns).flatMap { column in
            (0..<rows).map { row in
                CGRect(x: CGFloat(column) * (width + gap), y: CGFloat(row) * (height + gap), width: width, height: height)
            }
        }
    }

    /// Découpe un rectangle en `pieces` tuiles par coupes successives, séparées de `gap`.
    private static func guillotine(_ rect: CGRect, pieces: Int, gap: CGFloat, generator: inout LotARandom) -> [CGRect] {
        guard pieces > 1 else { return [rect] }
        let first = pieces / 2
        let ratio = CGFloat(generator.next() % 60 + 20) / 100
        if rect.width >= rect.height {
            let width = (rect.width - gap) * ratio
            let left = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
            let right = CGRect(x: rect.minX + width + gap, y: rect.minY, width: rect.width - width - gap, height: rect.height)
            return guillotine(left, pieces: first, gap: gap, generator: &generator)
                + guillotine(right, pieces: pieces - first, gap: gap, generator: &generator)
        }
        let height = (rect.height - gap) * ratio
        let top = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
        let bottom = CGRect(x: rect.minX, y: rect.minY + height + gap, width: rect.width, height: rect.height - height - gap)
        return guillotine(top, pieces: first, gap: gap, generator: &generator)
            + guillotine(bottom, pieces: pieces - first, gap: gap, generator: &generator)
    }

    static func columnFamily(_ m: Int) -> (frames: [CGRect], container: CGRect) {
        let height = CGFloat(50 * (m + 1))
        let container = CGRect(x: 0, y: 0, width: CGFloat(100 * m), height: height)
        let frames = (0..<m).flatMap { column -> [CGRect] in
            let split = CGFloat(50 * (column + 1))
            let x = CGFloat(100 * column)
            return [
                CGRect(x: x, y: 0, width: 100, height: split),
                CGRect(x: x, y: split, width: 100, height: height - split),
            ]
        }
        return (frames, container)
    }

    private func permutations(_ values: [WindowID]) -> [[WindowID]] {
        guard values.count > 1 else { return [values] }
        return values.indices.flatMap { index -> [[WindowID]] in
            var rest = values
            let head = rest.remove(at: index)
            return permutations(rest).map { [head] + $0 }
        }
    }
}

/// Copie de l'ancien algorithme (avant PERF-001), O(n³) : référence d'équivalence.
func referenceLeavesLargeUntiledCells(_ frames: [CGRect], in container: CGRect, allowedGap: CGFloat) -> Bool {
    guard frames.count > 1 else { return false }
    func edges(_ values: [CGFloat]) -> [CGFloat] {
        values.sorted().reduce(into: [CGFloat]()) { result, value in
            if result.last.map({ abs($0 - value) > 1 }) ?? true { result.append(value) }
        }
    }
    func contains(_ outer: CGRect, _ inner: CGRect, _ tolerance: CGFloat) -> Bool {
        inner.minX >= outer.minX - tolerance && inner.minY >= outer.minY - tolerance
            && inner.maxX <= outer.maxX + tolerance && inner.maxY <= outer.maxY + tolerance
    }
    let tolerance = max(LayoutTolerance.untiledCell, allowedGap)
    let xEdges = edges([container.minX, container.maxX] + frames.flatMap { [$0.minX, $0.maxX] })
    let yEdges = edges([container.minY, container.maxY] + frames.flatMap { [$0.minY, $0.maxY] })
    for xIndex in 0..<max(0, xEdges.count - 1) {
        let width = xEdges[xIndex + 1] - xEdges[xIndex]
        guard width > tolerance else { continue }
        for yIndex in 0..<max(0, yEdges.count - 1) {
            let height = yEdges[yIndex + 1] - yEdges[yIndex]
            guard height > tolerance else { continue }
            let cell = CGRect(x: xEdges[xIndex], y: yEdges[yIndex], width: width, height: height)
            let center = CGPoint(x: cell.midX, y: cell.midY)
            guard contains(container, cell, 1), !frames.contains(where: { frame in
                center.x >= frame.minX - 1 && center.y >= frame.minY - 1
                    && center.x <= frame.maxX + 1 && center.y <= frame.maxY + 1
            }) else { continue }
            return true
        }
    }
    return false
}

/// Générateur pseudo-aléatoire déterministe (xorshift64) pour des jeux reproductibles.
struct LotARandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
