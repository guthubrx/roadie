import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Session 022, round 3, lot C : ensemble cohérent de générations du journal d'événements lors
/// d'une rotation pendant la collecte (R2-04). Aucun test ne touche à `~/.roadies`.
@Suite(.serialized)
struct Audit022R3LotCTests {
    private final class Box<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: T
        init(_ value: T) { stored = value }
        var value: T {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    private func tempDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func appendTypes(_ types: [String], to path: String) {
        let log = EventLog(path: path)
        types.forEach { log.append(RoadieEvent(type: $0)) }
    }

    /// Rotation simulée entre l'ouverture de `.1` et celle de `.2` (trois sauvegardes) : sans
    /// correction, les descripteurs sont `[B, B, A]` et B est lu deux fois. Chaque événement
    /// doit être lu une seule fois, dans l'ordre.
    @Test
    func rotationDuringCollectionDoesNotReadGenerationTwice() throws {
        let directory = try tempDirectory("r3c-events-rotation")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.jsonl").path
        var service = EventSubscriptionService(path: path)

        appendTypes(["a1"], to: path)
        let first = service.readAvailable(from: service.start())
        appendTypes(["a2"], to: path)
        // A -> .2, B -> .1, courant = C.
        try FileManager.default.moveItem(atPath: path, toPath: path + ".2")
        appendTypes(["b1"], to: path)
        try FileManager.default.moveItem(atPath: path, toPath: path + ".1")
        appendTypes(["c1"], to: path)

        // Ligne de d1 préparée hors du journal : `EventLog.append` prendrait le verrou exclusif,
        // que la collecte tient en partage (interblocage dans le même processus).
        let spare = directory.appendingPathComponent("spare.jsonl").path
        appendTypes(["d1"], to: spare)
        let d1Line = try Data(contentsOf: URL(fileURLWithPath: spare))
        let rotated = Box(false)
        service.generationOpenHook = { index in
            guard index == 1, !rotated.value else { return }
            rotated.value = true
            // Nouvelle rotation : A -> .3, B -> .2, C -> .1, courant = D.
            let manager = FileManager.default
            try? manager.moveItem(atPath: path + ".2", toPath: path + ".3")
            try? manager.moveItem(atPath: path + ".1", toPath: path + ".2")
            try? manager.moveItem(atPath: path, toPath: path + ".1")
            manager.createFile(atPath: path, contents: d1Line)
        }

        let second = service.readAvailable(from: first.cursor)
        #expect(rotated.value)
        #expect(second.events.map(\.type) == ["a2", "b1", "c1"])
        // d1 (fichier courant au moment de la rotation) n'est pas perdu : lu à l'appel suivant.
        service.generationOpenHook = nil
        let third = service.readAvailable(from: second.cursor)
        #expect(third.events.map(\.type) == ["d1"])
    }

    /// L'ouverture des générations se fait sous le verrou de rotation partagé : un écrivain qui
    /// fait tourner le journal attend la fin de la collecte.
    @Test
    func writerRotationWaitsForGenerationCollection() throws {
        let directory = try tempDirectory("r3c-events-lock")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.jsonl").path
        var service = EventSubscriptionService(path: path)

        appendTypes(["a1"], to: path)
        let first = service.readAvailable(from: service.start())
        try FileManager.default.moveItem(atPath: path, toPath: path + ".1")
        appendTypes(["b1"], to: path)

        let writerDone = Box(false)
        let doneDuringCollection = Box<Bool?>(nil)
        service.generationOpenHook = { _ in
            guard doneDuringCollection.value == nil else { return }
            Thread.detachNewThread {
                // maxBytes: 1 force une rotation, donc la prise du verrou exclusif.
                EventLog(path: path, maxBytes: 1).append(RoadieEvent(type: "w1"))
                writerDone.value = true
            }
            Thread.sleep(forTimeInterval: 0.3)
            doneDuringCollection.value = writerDone.value
        }

        let second = service.readAvailable(from: first.cursor)
        #expect(doneDuringCollection.value == false)
        #expect(second.events.map(\.type) == ["b1"])
        let deadline = Date().addingTimeInterval(5)
        while !writerDone.value, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        #expect(writerDone.value)
    }
}
