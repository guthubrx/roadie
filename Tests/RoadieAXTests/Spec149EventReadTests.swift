import ApplicationServices
import Foundation
import os
import Testing
@testable import RoadieAX

private final class FrameRead149: Sendable {
    let state = OSAllocatedUnfairLock(initialState: (reads: 0, onMain: false))
    let gate = DispatchSemaphore(value: 0)
    func read() -> CGRect? {
        let n = state.withLock { value in
            value.reads += 1
            value.onMain = value.onMain || Thread.isMainThread
            return value.reads
        }
        if n == 1 { gate.wait() }
        return CGRect(x: 10, y: 20, width: 300, height: 400)
    }
}

@Suite @MainActor struct Spec149EventReadTests {
    private var event: AXWindowEvent { .init(name: kAXWindowMovedNotification as String, pid: 9999, windowID: 1) }
    private func wait(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }

    @Test func slowEventReadLeavesMainFreeAndCoalescesTheBurst() async {
        let reader = FrameRead149()
        var received: [AXWindowEvent] = []
        let observer = AXWindowEventObserver(writtenFrames: WrittenFrameRegistry(), mouseButtonsPressed: { false }) { received.append($0) }
        defer { observer.stop(); reader.gate.signal() }
        observer.enqueueFrameRead(event, read: reader.read)
        await wait { reader.state.withLock { $0.reads } == 1 }
        for _ in 0..<100 { observer.enqueueFrameRead(event, read: reader.read) }
        #expect(received.isEmpty)
        #expect(!reader.state.withLock { $0.onMain })
        reader.gate.signal()
        await wait { received.count == 2 }
        #expect(reader.state.withLock { $0.reads } == 2)
    }

    @Test func stoppingDiscardsTheResultOfAnAlreadyRunningRead() async {
        let reader = FrameRead149()
        var received: [AXWindowEvent] = []
        let observer = AXWindowEventObserver(writtenFrames: WrittenFrameRegistry(), mouseButtonsPressed: { false }) { received.append($0) }
        observer.enqueueFrameRead(event, read: reader.read)
        await wait { reader.state.withLock { $0.reads } == 1 }
        observer.stop()
        reader.gate.signal()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(received.isEmpty)
    }

    @Test func aLateFrameCannotConfirmTheRefusalOfANewerWrite() async {
        let reader = FrameRead149(), registry = WrittenFrameRegistry()
        let a = CGRect(x: 10, y: 20, width: 300, height: 400), b = a.offsetBy(dx: 50, dy: 0)
        let start = Date()
        registry.record(windowID: 1, requested: a, readBack: a, generation: 1, at: start)
        var received: [AXWindowEvent] = []
        let observer = AXWindowEventObserver(writtenFrames: registry, mouseButtonsPressed: { false }) { received.append($0) }
        defer { observer.stop() }
        observer.enqueueFrameRead(event, read: reader.read)
        await wait { reader.state.withLock { $0.reads } == 1 }
        registry.record(windowID: 1, requested: b, readBack: a, generation: 2, at: Date())
        reader.gate.signal()
        await wait { received.count == 1 }
        #expect(registry.entry(for: 1)?.refusalConfirmedAt == nil)
    }
}
