import Testing
import RoadieCore
import RoadieDaemon
import RoadieStages

@Suite
struct WindowGroupCommandTests {
    private func makeService() -> (groups: WindowGroupCommandService, store: StageStore) {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100), powerWindow(2, x: 500), powerWindow(3, x: 700)])
        let store = StageStore(path: tempPath("window-group-commands"))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        _ = service.snapshot()
        return (WindowGroupCommandService(service: service, store: store), store)
    }

    /// Groupes persistés de toutes les stages, relus depuis le store (et non depuis la valeur de retour).
    private func storedGroups(_ store: StageStore) -> [WindowGroup] {
        store.state().scopes.flatMap { $0.stages.flatMap(\.groups) }
    }

    private func storedGroup(_ id: String, in store: StageStore) -> WindowGroup? {
        storedGroups(store).first { $0.id == id }
    }

    @Test
    func groupCommandsCreateAddFocusRemoveAndDissolve() {
        let (groups, store) = makeService()
        let one = WindowID(rawValue: 1)
        let two = WindowID(rawValue: 2)
        let three = WindowID(rawValue: 3)

        let created = groups.create(id: "terminals", windowIDs: [one, two])
        #expect(created.changed)
        #expect(created.message == "group terminals: members=1,2")
        #expect(storedGroup("terminals", in: store)?.windowIDs == [one, two])
        #expect(storedGroup("terminals", in: store)?.activeWindowID == one)

        let added = groups.add(windowID: three, to: "terminals")
        #expect(added.changed)
        #expect(added.message == "group terminals: members=1,2,3")
        #expect(storedGroup("terminals", in: store)?.windowIDs == [one, two, three])
        #expect(storedGroup("terminals", in: store)?.activeWindowID == one)

        #expect(groups.focus(windowID: three, in: "terminals").changed)
        #expect(storedGroup("terminals", in: store)?.activeWindowID == three)

        // Retirer un membre non actif garde le membre actif ; il reste 2 membres donc le groupe survit.
        let removed = groups.remove(windowID: two, from: "terminals")
        #expect(removed.changed)
        #expect(storedGroup("terminals", in: store)?.windowIDs == [one, three])
        #expect(storedGroup("terminals", in: store)?.activeWindowID == three)

        let dissolved = groups.dissolve(id: "terminals")
        #expect(dissolved.changed)
        #expect(dissolved.message == "group dissolve terminals")
        #expect(storedGroup("terminals", in: store) == nil)
        #expect(storedGroups(store).isEmpty)
    }

    @Test
    func removingActiveMemberMovesActiveToFirstRemaining() {
        let (groups, store) = makeService()
        let one = WindowID(rawValue: 1)
        let two = WindowID(rawValue: 2)
        let three = WindowID(rawValue: 3)
        _ = groups.create(id: "g", windowIDs: [one, two, three])
        _ = groups.focus(windowID: two, in: "g")

        _ = groups.remove(windowID: two, from: "g")

        #expect(storedGroup("g", in: store)?.windowIDs == [one, three])
        #expect(storedGroup("g", in: store)?.activeWindowID == one)
    }

    @Test
    func removingDownToOneMemberDissolvesTheGroup() {
        let (groups, store) = makeService()
        let one = WindowID(rawValue: 1)
        let two = WindowID(rawValue: 2)
        _ = groups.create(id: "pair", windowIDs: [one, two])

        let result = groups.remove(windowID: two, from: "pair")

        // Un groupe de moins de 2 membres n'existe plus : la commande réussit et le store ne le garde pas.
        #expect(result.changed)
        #expect(storedGroup("pair", in: store) == nil)
    }

    @Test
    func invalidGroupCommandsLeaveStateUntouched() {
        let (groups, store) = makeService()
        let one = WindowID(rawValue: 1)
        let two = WindowID(rawValue: 2)
        let three = WindowID(rawValue: 3)
        _ = groups.create(id: "pair", windowIDs: [one, two])
        let before = storedGroups(store)

        let removeFromMissing = groups.remove(windowID: one, from: "absent")
        #expect(!removeFromMissing.changed)
        #expect(removeFromMissing.message == "group absent: not found")

        let focusInMissing = groups.focus(windowID: one, in: "absent")
        #expect(!focusInMissing.changed)
        #expect(focusInMissing.message == "group absent: not found")

        let dissolveMissing = groups.dissolve(id: "absent")
        #expect(!dissolveMissing.changed)
        #expect(dissolveMissing.message == "group dissolve absent: not found")

        // Focus d'une fenêtre qui n'est pas membre : l'état actif ne bouge pas.
        _ = groups.focus(windowID: three, in: "pair")
        #expect(storedGroup("pair", in: store)?.activeWindowID == one)

        #expect(storedGroups(store).filter { $0.id != "pair" }.isEmpty)
        #expect(storedGroup("pair", in: store) == before.first { $0.id == "pair" })
    }

    @Test
    func addingTheSameMemberTwiceDoesNotDuplicateIt() {
        let (groups, store) = makeService()
        let one = WindowID(rawValue: 1)
        let two = WindowID(rawValue: 2)
        _ = groups.create(id: "pair", windowIDs: [one, two])

        _ = groups.add(windowID: two, to: "pair")

        #expect(storedGroup("pair", in: store)?.windowIDs.filter { $0 == two }.count == 1)
    }

    @Test
    func listReportsStoredGroups() {
        let (groups, _) = makeService()
        _ = groups.create(id: "pair", windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)])

        let listing = groups.list()

        #expect(!listing.changed)
        let lines = listing.message.split(separator: "\n").map(String.init)
        #expect(lines.first == "SCOPE\tGROUP\tACTIVE\tMEMBERS")
        #expect(lines.count == 2)
        #expect(lines.last?.hasSuffix("\tpair\t1\t1,2") == true)
    }
}
