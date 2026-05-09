import AppKit
import ApplicationServices
import RoadieAX
import RoadieCore

@MainActor
public final class FocusStageActivationObserver {
    private let maintainer: LayoutMaintainer
    private let service: SnapshotService
    private let performance: PerformanceRecorder
    private let configLoader: () -> RoadieConfig
    private var observer: AXObserver?
    private var activePID: pid_t?
    private var activationObserver: NSObjectProtocol?
    private var lastTick = Date.distantPast
    private let minimumTickInterval: TimeInterval = 0.05
    private var delayedFocusWorkItem: DispatchWorkItem?
    private var focusGeneration: UInt64 = 0
    private var lastIntent: (windowID: WindowID, at: Date)?
    private let coalescingInterval: TimeInterval = 0.12

    public init(
        maintainer: LayoutMaintainer,
        service: SnapshotService = SnapshotService(),
        performance: PerformanceRecorder = PerformanceRecorder(),
        configLoader: @escaping () -> RoadieConfig = { (try? RoadieConfigLoader.load()) ?? RoadieConfig() }
    ) {
        self.maintainer = maintainer
        self.service = service
        self.performance = performance
        self.configLoader = configLoader
    }

    public func start() {
        stop()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.watchFocusedWindowChanges(for: app.processIdentifier)
                self?.handleFocusChanged(preferredPID: app.processIdentifier, isNewActivation: true)
            }
        }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            watchFocusedWindowChanges(for: pid)
            handleFocusChanged(preferredPID: pid, isNewActivation: true)
        }
    }

    public func stop() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        delayedFocusWorkItem?.cancel()
        delayedFocusWorkItem = nil
        removeObserver()
    }

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    private func watchFocusedWindowChanges(for pid: pid_t) {
        guard configLoader().focus.stageFollowsFocus else {
            removeObserver()
            return
        }
        guard pid != activePID else { return }
        removeObserver()

        var createdObserver: AXObserver?
        let error = AXObserverCreate(pid, focusObserverCallback, &createdObserver)
        guard error == .success, let createdObserver else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let added = AXObserverAddNotification(
            createdObserver,
            appElement,
            kAXFocusedWindowChangedNotification as CFString,
            refcon
        )
        guard added == .success || added == .notificationAlreadyRegistered else { return }

        observer = createdObserver
        activePID = pid
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(createdObserver),
            .commonModes
        )
    }

    private func removeObserver() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        activePID = nil
    }

    fileprivate func handleFocusChanged(preferredPID: pid_t? = nil, isNewActivation: Bool = false, generation: UInt64? = nil) {
        guard configLoader().focus.stageFollowsFocus else { return }
        let activeGeneration: UInt64
        if isNewActivation {
            focusGeneration += 1
            activeGeneration = focusGeneration
        } else if let generation {
            guard generation == focusGeneration else { return }
            activeGeneration = generation
        } else {
            activeGeneration = focusGeneration
        }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        guard elapsed >= minimumTickInterval else {
            scheduleDelayedFocusChanged(
                after: minimumTickInterval - elapsed,
                preferredPID: preferredPID,
                generation: activeGeneration
            )
            return
        }
        lastTick = now
        debugFocus("event preferredPID=\(preferredPID.map(String.init) ?? "nil") newActivation=\(isNewActivation) generation=\(activeGeneration)")
        if directActivateFocusedContext(at: now, preferredPID: preferredPID) {
            return
        }
        _ = maintainer.tick()
    }

    private func scheduleDelayedFocusChanged(after delay: TimeInterval, preferredPID: pid_t?, generation: UInt64) {
        delayedFocusWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.focusGeneration else { return }
                self.delayedFocusWorkItem = nil
                self.handleFocusChanged(preferredPID: preferredPID, generation: generation)
            }
        }
        delayedFocusWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.005, delay), execute: workItem)
    }

    private func directActivateFocusedContext(at now: Date, preferredPID: pid_t?) -> Bool {
        let preferredWindow = preferredPID.flatMap { focusedVisibleWindow(for: $0) }
        guard let focusedID = preferredWindow?.id ?? service.focusedWindowID() else { return false }
        debugFocus("focused id=\(focusedID.rawValue) preferredWindow=\(preferredWindow?.id.rawValue.description ?? "nil")")
        if let lastIntent,
           lastIntent.windowID == focusedID,
           now.timeIntervalSince(lastIntent.at) < coalescingInterval {
            debugFocus("coalesced id=\(focusedID.rawValue)")
            return true
        }
        lastIntent = (focusedID, now)
        let started = Date()
        let session = performanceSession(startedAt: started, focusedID: focusedID)
        if fastNoOpForActiveVisibleFocus(
            session: session,
            startedAt: started,
            focusedID: focusedID,
            preferredWindow: preferredWindow
        ) {
            return true
        }
        let timedSnapshot = service.timedSnapshot(followExternalFocus: true, persistState: true)
        let snapshot = timedSnapshot.snapshot
        let snapshotAt = Date()
        let snapshotSteps = [
            PerformanceStep(name: .snapshot, startedAt: started, durationMs: snapshotAt.timeIntervalSince(started) * 1000)
        ] + timedSnapshot.steps
        guard let focused = snapshot.windows.first(where: { $0.window.id == focusedID }),
              let scope = focused.scope,
              snapshot.state.activeScope(on: scope.displayID) == scope
        else {
            debugFocus("snapshot-miss id=\(focusedID.rawValue) snapshotFocus=\(snapshot.focusedWindowID?.rawValue.description ?? "nil")")
            return false
        }
        debugFocus("scope display=\(scope.displayID.rawValue) desktop=\(scope.desktopID.rawValue) stage=\(scope.stageID.rawValue) visible=\(isVisible(focused.window, in: snapshot.displays))")

        if isVisible(focused.window, in: snapshot.displays) {
            let completed = Date()
            performance.complete(
                session.withContext(
                    PerformanceTargetContext(
                        displayID: scope.displayID.rawValue,
                        desktopID: scope.desktopID.rawValue,
                        stageID: scope.stageID.rawValue,
                        windowID: focusedID.rawValue
                    )
                ),
                result: .noOp,
                steps: snapshotSteps + [
                    PerformanceStep(name: .stateUpdate, startedAt: snapshotAt, durationMs: 0),
                    PerformanceStep(name: .layoutApply, startedAt: snapshotAt, durationMs: 0, count: 0),
                    PerformanceStep(name: .focus, startedAt: snapshotAt, durationMs: completed.timeIntervalSince(snapshotAt) * 1000)
                ],
                completedAt: completed,
                durationMs: completed.timeIntervalSince(started) * 1000
            )
            return true
        }

        let plan = service.applyPlan(
            from: snapshot,
            scope: scope,
            orderedWindowIDs: service.orderedWindowIDs(in: scope, from: snapshot),
            priorityWindowIDs: [focusedID]
        )
        let planAt = Date()
        if plan.commands.isEmpty {
            let completed = Date()
            performance.complete(
                session.withContext(
                    PerformanceTargetContext(
                        displayID: scope.displayID.rawValue,
                        desktopID: scope.desktopID.rawValue,
                        stageID: scope.stageID.rawValue,
                        windowID: focusedID.rawValue
                    )
                ),
                result: .noOp,
                steps: snapshotSteps + [
                    PerformanceStep(name: .stateUpdate, startedAt: snapshotAt, durationMs: 0),
                    PerformanceStep(name: .layoutApply, startedAt: snapshotAt, durationMs: planAt.timeIntervalSince(snapshotAt) * 1000, count: 0),
                    PerformanceStep(name: .focus, startedAt: planAt, durationMs: completed.timeIntervalSince(planAt) * 1000)
                ],
                completedAt: completed,
                durationMs: completed.timeIntervalSince(started) * 1000
            )
            return true
        }
        let result = service.apply(plan)
        _ = service.focus(focused.window)
        let completed = Date()
        performance.complete(
            session.withContext(
                PerformanceTargetContext(
                    displayID: scope.displayID.rawValue,
                    desktopID: scope.desktopID.rawValue,
                    stageID: scope.stageID.rawValue,
                    windowID: focusedID.rawValue
                )
            ),
            result: result.failed == 0 ? .success : .partial,
            steps: snapshotSteps + [
                PerformanceStep(name: .stateUpdate, startedAt: snapshotAt, durationMs: 0),
                PerformanceStep(name: .layoutApply, startedAt: snapshotAt, durationMs: completed.timeIntervalSince(snapshotAt) * 1000, count: result.attempted),
                PerformanceStep(name: .focus, startedAt: completed, durationMs: 0)
            ],
            completedAt: completed,
            durationMs: completed.timeIntervalSince(started) * 1000
        )
        return true
    }

    private func fastNoOpForActiveVisibleFocus(
        session: PerformanceRecorder.Session,
        startedAt: Date,
        focusedID: WindowID,
        preferredWindow: WindowSnapshot?
    ) -> Bool {
        var steps: [PerformanceStep] = []

        let stateStartedAt = Date()
        let persisted = service.persistentStageState()
        guard let scope = persisted.stageScope(for: focusedID) else { return false }
        guard let persistentScope = persisted.scopes.first(where: {
            $0.displayID == scope.displayID && $0.desktopID == scope.desktopID
        }) else { return false }
        let isActiveScope = persisted.currentDesktopID(for: scope.displayID) == scope.desktopID
            && persistentScope.activeStageID == scope.stageID
        steps.append(step(.stageState, startedAt: stateStartedAt))
        guard isActiveScope else { return false }

        let displaysStartedAt = Date()
        let displays = service.displays()
        steps.append(step(.displays, startedAt: displaysStartedAt))

        let windowStartedAt = Date()
        guard let focusedWindow = preferredWindow ?? service.window(id: focusedID, includeAccessibilityAttributes: false),
              focusedWindow.isTileCandidate,
              isVisible(focusedWindow, in: displays)
        else {
            steps.append(step(.windows, startedAt: windowStartedAt, status: .failed))
            return false
        }
        steps.append(step(.windows, startedAt: windowStartedAt))

        let persistStartedAt = Date()
        service.persistFocusedWindow(focusedID, in: scope)
        debugFocus("fast-noop persisted id=\(focusedID.rawValue) display=\(scope.displayID.rawValue) desktop=\(scope.desktopID.rawValue) stage=\(scope.stageID.rawValue)")
        steps.append(step(.stateUpdate, startedAt: persistStartedAt))

        let completed = Date()
        performance.complete(
            session.withContext(
                PerformanceTargetContext(
                    displayID: scope.displayID.rawValue,
                    desktopID: scope.desktopID.rawValue,
                    stageID: scope.stageID.rawValue,
                    windowID: focusedID.rawValue
                )
            ),
            result: .noOp,
            steps: [
                PerformanceStep(
                    name: .snapshot,
                    startedAt: startedAt,
                    durationMs: completed.timeIntervalSince(startedAt) * 1000
                )
            ] + steps + [
                PerformanceStep(name: .layoutApply, startedAt: completed, durationMs: 0, count: 0),
                PerformanceStep(name: .focus, startedAt: completed, durationMs: 0)
            ],
            completedAt: completed,
            durationMs: completed.timeIntervalSince(startedAt) * 1000
        )
        return true
    }

    private func step(
        _ name: PerformanceStepName,
        startedAt: Date,
        status: PerformanceStepStatus = .success
    ) -> PerformanceStep {
        PerformanceStep(
            name: name,
            startedAt: startedAt,
            durationMs: Date().timeIntervalSince(startedAt) * 1000,
            status: status
        )
    }

    private func performanceSession(startedAt: Date, focusedID: WindowID) -> PerformanceRecorder.Session {
        PerformanceRecorder.Session(
            type: .altTabActivation,
            source: .focusObserver,
            startedAt: startedAt,
            targetContext: PerformanceTargetContext(windowID: focusedID.rawValue)
        )
    }

    private func isVisible(_ window: WindowSnapshot, in displays: [DisplaySnapshot]) -> Bool {
        displays.contains { display in
            display.visibleFrame.cgRect.contains(window.frame.center)
        }
    }

    private func focusedVisibleWindow(for pid: pid_t) -> WindowSnapshot? {
        let displays = service.displays()
        if let focusedID = service.focusedWindowID(),
           let window = service.window(id: focusedID, includeAccessibilityAttributes: false),
           window.pid == pid,
           window.isTileCandidate,
           isVisible(window, in: displays) {
            return window
        }
        return service.windows(includeAccessibilityAttributes: false).first {
            $0.pid == pid
                && $0.isTileCandidate
                && isVisible($0, in: displays)
        }
    }

    fileprivate func handleObservedFocusChanged() {
        handleFocusChanged(preferredPID: activePID)
    }

    private func debugFocus(_ message: String) {
        guard ProcessInfo.processInfo.environment["ROADIE_DEBUG_FOCUS"] == "1"
            || FileManager.default.fileExists(atPath: NSString(string: "~/.roadies/debug-focus").expandingTildeInPath)
        else { return }
        let line = "focus.observer \(message)"
        fputs("\(line)\n", stdout)
        fflush(stdout)
    }
}

private extension PerformanceRecorder.Session {
    func withContext(_ targetContext: PerformanceTargetContext) -> PerformanceRecorder.Session {
        PerformanceRecorder.Session(
            id: id,
            type: type,
            source: source,
            startedAt: startedAt,
            targetContext: targetContext
        )
    }
}

private let focusObserverCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let observer = Unmanaged<FocusStageActivationObserver>
        .fromOpaque(refcon)
        .takeUnretainedValue()
    Task { @MainActor in
        observer.handleObservedFocusChanged()
    }
}
