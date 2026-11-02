import AppKit
import RoadieAX
import RoadieCore

/// Réserve une paire gauche pour Roadie. Sous le seuil, la paire est rendue à l'application.
@MainActor
public final class ModifierWindowGestureController {
    static let replayMarker: Int64 = 0x52444D4F44434C4B
    private struct Press {
        let id = UUID()
        let point: CGPoint
        let event: CGEvent
        let source: ScopedWindowSnapshot
        let snapshot: DaemonSnapshot
        let operation: ModifierWindowOperation
        var dragging = false
        var lastEventAt: Date
        var observedHardwareDown: Bool
    }
    private let service: SnapshotService
    private let runtime: ModifierWindowRuntime
    private let input: UserInputActivity
    private let replay: (CGEvent) -> Void
    private let snapshotProvider: () -> DaemonSnapshot?
    private let clock: () -> Date
    private let physicalLeftPressed: () -> Bool
    private let onPress: () -> Void
    private var config: TilingConfig
    private var press: Press?
    private var draining = false
    private var preparing = false
    private var sequence: UInt64 = 0
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var context: UnsafeMutableRawPointer?
    private var refreshTimer: Timer?
    private var tapFailureReported = false
    private var nextTapAttemptAt = Date.distantPast

    public init(service: SnapshotService, runtime: ModifierWindowRuntime, input: UserInputActivity = .shared,
         replay: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) },
         snapshotProvider: (() -> DaemonSnapshot?)? = nil,
         clock: @escaping () -> Date = Date.init,
         physicalLeftPressed: @escaping () -> Bool = { CGEventSource.buttonState(.hidSystemState, button: .left) },
         onPress: @escaping () -> Void = {}) {
        self.service = service; self.runtime = runtime; self.input = input; self.replay = replay
        config = service.effectiveConfig.tiling
        self.snapshotProvider = snapshotProvider ?? { service.cachedGestureSnapshot() }
        self.clock = clock; self.physicalLeftPressed = physicalLeftPressed; self.onPress = onPress
    }

    public func start() {
        guard refreshTimer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refreshTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    private func refresh() {
        checkPhysicalRelease()
        let next = service.effectiveConfig.tiling
        if config != next, press != nil { cancel() }
        config = next
        if config.dragMoveModifier == .disabled && config.dragResizeModifier == .disabled {
            if press == nil && !draining { removeTap() }
            nextTapAttemptAt = .distantPast
            return
        }
        guard tap == nil, clock() >= nextTapAttemptAt else { return }
        nextTapAttemptAt = clock().addingTimeInterval(5)
        let token = KeyEventTapOwners.shared.register(self)
        let mask = [CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let owner = KeyEventTapOwners.shared.owner(for: refcon) as? ModifierWindowGestureController else { return Unmanaged.passUnretained(event) }
            let consumed = MainActor.assumeIsolated { owner.handle(type, event: event) }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback, userInfo: token) else {
            KeyEventTapOwners.shared.remove(token)
            if !tapFailureReported {
                EventLog().append(RoadieEvent(type: "modifier_gesture.unavailable", details: ["reason": "tap_create_failed"]))
                tapFailureReported = true
            }
            return
        }
        tapFailureReported = false; nextTapAttemptAt = .distantPast
        self.tap = tap; context = token
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Aucune E/S ni attente AX dans ce callback ; le runtime est préparé au premier mouvement.
    @discardableResult
    func handle(_ type: CGEventType, event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker { return false }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancel()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if type == .leftMouseDown {
            sequence &+= 1
            press = nil; draining = false
            lastPoint = nil; releasePending = false; preparing = false
            if !runtime.isActive { input.setCapturedPointerHeld(false) }
            guard let operation = ModifierWindowOperation.resolve(flags: event.flags, config: service.publishedConfig.tiling),
                  let snapshot = snapshotProvider(),
                  let target = ModifierWindowRuntime.target(at: event.location, snapshot: snapshot),
                  let saved = event.copy() else {
                if runtime.isActive {
                    Task { @MainActor [weak self] in
                        guard let self, self.press == nil else { return }
                        if !self.runtime.isEnding { self.runtime.cancelImmediately(reason: "new_press") }
                    }
                }
                return false
            }
            press = Press(point: event.location, event: saved, source: target, snapshot: snapshot, operation: operation,
                          lastEventAt: clock(), observedHardwareDown: physicalLeftPressed())
            let id = press?.id
            Task { @MainActor [weak self] in
                guard let self, self.press?.id == id else { return }
                self.onPress()
                FrameTransitionRuntime.shared.cancel()
            }
            input.recordInput()
            input.setCapturedPointerHeld(true)
            return true
        }
        if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53, press != nil {
            cancel(); return true
        }
        if type == .leftMouseDragged {
            if draining { return true }
            guard var current = press else { return false }
            current.lastEventAt = clock()
            if !current.dragging, hypot(event.location.x - current.point.x, event.location.y - current.point.y) > 8 {
                current.dragging = true; press = current; preparing = true
                let id = current.id
                // La tâche est créée une seule fois ; les mouvements suivants remplacent le point.
                Task { @MainActor [weak self] in
                    guard let self, let active = self.press, active.id == id else { return }
                    var snapshot = active.snapshot
                    var source = active.source
                    if self.runtime.isEnding {
                        // Le dépôt précédent doit sauver son arbre avant toute nouvelle génération.
                        while self.runtime.isEnding {
                            try? await Task.sleep(for: .milliseconds(10))
                            guard self.press?.id == id else { return }
                        }
                        guard let fresh = await self.service.readerSnapshot(followFocus: false, isCurrent: { self.press?.id == id }),
                              self.press?.id == id,
                              let target = ModifierWindowRuntime.target(at: active.point, snapshot: fresh),
                              target.window.id == active.source.window.id, target.window.pid == active.source.window.pid else { self.cancel(); return }
                        snapshot = fresh; source = target
                    } else { self.runtime.cancelImmediately(reason: "new_gesture") }
                    self.preparing = false
                    guard self.runtime.begin(source: source, snapshot: snapshot, at: active.point, operation: active.operation) else {
                        self.cancel(); return
                    }
                    if let point = self.lastPoint { self.runtime.update(at: point) }
                    if self.releasePending { self.finishDrag() }
                }
            }
            press = current
            lastPoint = event.location
            if current.dragging { runtime.update(at: event.location) }
            return true
        }
        if type == .leftMouseUp {
            if draining { input.recordInput(); draining = false; if !runtime.isActive { input.setCapturedPointerHeld(false) }; return true }
            guard let current = press else { return false }
            input.recordInput()
            if !current.dragging {
                press = nil; input.setCapturedPointerHeld(false)
                if let latest = snapshotProvider() {
                    replayClick(current, up: event, snapshot: latest)
                } else if let up = event.copy() {
                    let sequence = self.sequence
                    Task { @MainActor [weak self] in
                        guard let self, let latest = await self.service.readerSnapshot(followFocus: false,
                            isCurrent: { self.sequence == sequence }), self.sequence == sequence else { return }
                        self.replayClick(current, up: up, snapshot: latest)
                    }
                }
            } else {
                lastPoint = event.location; releasePending = true
                runtime.update(at: event.location)
                if !preparing, runtime.isActive { finishDrag() }
                else if !preparing { press = nil; releasePending = false; lastPoint = nil; input.setCapturedPointerHeld(false) }
            }
            return true
        }
        return false
    }

    private func replayClick(_ current: Press, up: CGEvent, snapshot: DaemonSnapshot) {
        guard let target = ModifierWindowRuntime.target(at: current.point, snapshot: snapshot),
              target.window.id == current.source.window.id, target.window.pid == current.source.window.pid else {
            Task { @MainActor in EventLog().append(RoadieEvent(type: "modifier_gesture.click_discarded",
                scope: current.source.scope, details: ["reason": "target_changed"])) }
            return
        }
        for original in [current.event, up] {
            if let copy = original.copy() { copy.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker); replay(copy) }
        }
        Task { @MainActor in
            EventLog().append(RoadieEvent(type: "modifier_gesture.click_replayed", scope: current.source.scope,
                details: ["windowID": String(current.source.window.id.rawValue), "downType": String(current.event.type.rawValue),
                          "flags": String(current.event.flags.rawValue)]))
        }
    }

    private var lastPoint: CGPoint?
    private var releasePending = false
    /// Un up perdu ne suspend pas le tiler indéfiniment. Ne croire un relâchement physique
    /// qu'après avoir observé le bouton réellement enfoncé dans cette séquence.
    func checkPhysicalRelease() {
        guard var current = press else { return }
        if physicalLeftPressed() { current.observedHardwareDown = true; press = current; return }
        guard current.observedHardwareDown, clock().timeIntervalSince(current.lastEventAt) > 0.3 else { return }
        if current.dragging, runtime.isActive { finishDrag() }
        else { cancel(); draining = false }
    }
    private func finishDrag() {
        if let id = runtime.identifier {
            Task { @MainActor [weak self] in self?.runtime.end(matching: id) }
        }
        press = nil; releasePending = false; lastPoint = nil; preparing = false
    }
    private func cancel() {
        draining = press != nil || draining
        press = nil; releasePending = false; lastPoint = nil; preparing = false
        if let id = runtime.identifier {
            Task { @MainActor [weak self] in self?.runtime.end(cancelled: true, matching: id) }
        }
        if !runtime.isActive { input.setCapturedPointerHeld(false) }
    }
    public func stop() {
        sequence &+= 1
        refreshTimer?.invalidate(); refreshTimer = nil
        runtime.cancelImmediately(reason: "shutdown")
        press = nil; draining = false; lastPoint = nil; releasePending = false; preparing = false
        input.setCapturedPointerHeld(false); removeTap()
    }
    private func removeTap() {
        if let context { KeyEventTapOwners.shared.remove(context) }; context = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes); CFRunLoopSourceInvalidate(source) }
        tap = nil; source = nil
    }
}
