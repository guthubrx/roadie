import AppKit
import ApplicationServices
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
                self?.handleFocusChanged()
            }
        }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            watchFocusedWindowChanges(for: pid)
        }
    }

    public func stop() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
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

    fileprivate func handleFocusChanged() {
        guard configLoader().focus.stageFollowsFocus else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTick) >= minimumTickInterval else { return }
        lastTick = now
        if directActivateFocusedContext(at: now) {
            return
        }
        _ = maintainer.tick()
    }

    private func directActivateFocusedContext(at now: Date) -> Bool {
        guard let focusedID = service.focusedWindowID() else { return false }
        if let lastIntent,
           lastIntent.windowID == focusedID,
           now.timeIntervalSince(lastIntent.at) < coalescingInterval {
            return true
        }
        lastIntent = (focusedID, now)
        let started = Date()
        let snapshot = service.snapshot(followExternalFocus: true, persistState: true)
        guard let focused = snapshot.windows.first(where: { $0.window.id == focusedID }),
              let scope = focused.scope,
              snapshot.state.activeScope(on: scope.displayID) == scope
        else { return false }

        let plan = service.applyPlan(
            from: snapshot,
            scope: scope,
            orderedWindowIDs: service.orderedWindowIDs(in: scope, from: snapshot),
            priorityWindowIDs: [focusedID]
        )
        let result = service.apply(plan)
        _ = service.focus(focused.window)
        let completed = Date()
        performance.complete(
            performance.start(
                .altTabActivation,
                source: .focusObserver,
                targetContext: PerformanceTargetContext(
                    displayID: scope.displayID.rawValue,
                    desktopID: scope.desktopID.rawValue,
                    stageID: scope.stageID.rawValue,
                    windowID: focusedID.rawValue
                )
            ),
            result: result.failed == 0 ? .success : .partial,
            steps: [
                PerformanceStep(name: .snapshot, startedAt: started, durationMs: 0),
                PerformanceStep(name: .stateUpdate, startedAt: started, durationMs: 0),
                PerformanceStep(name: .layoutApply, startedAt: started, durationMs: completed.timeIntervalSince(started) * 1000, count: result.attempted),
                PerformanceStep(name: .focus, startedAt: completed, durationMs: 0)
            ],
            completedAt: completed,
            durationMs: completed.timeIntervalSince(started) * 1000
        )
        return true
    }
}

private let focusObserverCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let observer = Unmanaged<FocusStageActivationObserver>
        .fromOpaque(refcon)
        .takeUnretainedValue()
    Task { @MainActor in
        observer.handleFocusChanged()
    }
}
