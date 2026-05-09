import AppKit
import ApplicationServices
import RoadieCore

@MainActor
public final class FocusStageActivationObserver {
    private let maintainer: LayoutMaintainer
    private let configLoader: () -> RoadieConfig
    private var observer: AXObserver?
    private var activePID: pid_t?
    private var activationObserver: NSObjectProtocol?
    private var lastTick = Date.distantPast
    private let minimumTickInterval: TimeInterval = 0.05

    public init(
        maintainer: LayoutMaintainer,
        configLoader: @escaping () -> RoadieConfig = { (try? RoadieConfigLoader.load()) ?? RoadieConfig() }
    ) {
        self.maintainer = maintainer
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
        _ = maintainer.tick()
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
