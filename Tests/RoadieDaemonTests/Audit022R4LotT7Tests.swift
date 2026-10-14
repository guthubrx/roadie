import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// R4-T7 (REL-036) : un lecteur qui a déjà lu un glisser actif adopte la fin anticipée écrite par
/// `release`, au lieu de garder l'ancienne échéance en mémoire.
@Suite
struct Audit022R4LotT7Tests {
    @Test
    func readerAdoptsExplicitReleaseAfterReadingActiveDrag() {
        let path = NSTemporaryDirectory() + "roadie-r4t7-\(UUID().uuidString)/window-drag-activity"
        let producer = WindowDragActivity(path: path)
        let consumer = WindowDragActivity(path: path)
        let t0 = Date(timeIntervalSince1970: 1_000)
        producer.markActive(windowID: WindowID(rawValue: 1), now: t0, holdSeconds: 1.5)
        // Le lecteur voit le glisser et mémorise l'échéance t0 + 1,5.
        #expect(consumer.isActive(now: t0.addingTimeInterval(0.1)))

        producer.release(now: t0.addingTimeInterval(0.2))

        #expect(!consumer.isActive(now: t0.addingTimeInterval(0.3)))
        #expect(!consumer.isActive(now: t0.addingTimeInterval(0.3), includingReleaseGrace: false))
    }

    @Test
    func suspensionEndFollowsExplicitRelease() {
        let path = NSTemporaryDirectory() + "roadie-r4t7-\(UUID().uuidString)/window-drag-activity"
        let producer = WindowDragActivity(path: path)
        let consumer = WindowDragActivity(path: path)
        let t0 = Date(timeIntervalSince1970: 1_000)
        producer.markActive(windowID: WindowID(rawValue: 1), now: t0, holdSeconds: 1.5)
        #expect(consumer.isActive(now: t0.addingTimeInterval(0.1)))

        let released = t0.addingTimeInterval(0.2)
        producer.release(now: released)

        let end = consumer.suspensionEnd()
        #expect(end.map { $0 > released && $0.timeIntervalSince(released) < 0.001 } == true)
    }

    @Test
    func recognizedDropGraceStillSeenByReaderThatReadEarlier() {
        let path = NSTemporaryDirectory() + "roadie-r4t7-\(UUID().uuidString)/window-drag-activity"
        let producer = WindowDragActivity(path: path)
        let consumer = WindowDragActivity(path: path)
        let t0 = Date(timeIntervalSince1970: 1_000)
        producer.markActive(windowID: WindowID(rawValue: 1), now: t0, holdSeconds: 0.5)
        #expect(consumer.isActive(now: t0.addingTimeInterval(0.1)))

        producer.finish(now: t0.addingTimeInterval(0.4), graceSeconds: 0.9, droppedWindowID: WindowID(rawValue: 1))

        #expect(consumer.isActive(now: t0.addingTimeInterval(1.0)))
        #expect(!consumer.isActive(now: t0.addingTimeInterval(1.0), includingReleaseGrace: false))
        #expect(!consumer.isActive(now: t0.addingTimeInterval(1.4)))
    }
}
