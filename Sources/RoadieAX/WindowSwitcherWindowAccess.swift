import AppKit
import CoreGraphics
import RoadieCore

public struct WindowSwitcherAXState: Equatable, Sendable {
    public var appName: String?
    public var title: String?
    public var isMinimized: Bool
    public var isFullscreen: Bool
    public var isHidden: Bool

    public init(appName: String? = nil, title: String? = nil, isMinimized: Bool = false, isFullscreen: Bool = false, isHidden: Bool = false) {
        self.appName = appName
        self.title = title
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.isHidden = isHidden
    }
}

public enum WindowSwitcherAXOutcome: Equatable, Sendable {
    case performed
    case targetMissing
    case refused(Int32)
    case applicationRefused
}

/// Accès AX ciblé par identité de fenêtre (CGWindowID + pid). Aucun force kill.
public enum WindowSwitcherWindowAccess {
    public static func states(pid: pid_t, windowIDs: Set<WindowID>) -> [WindowID: WindowSwitcherAXState] {
        guard !AXUnresponsiveApps.shared.isQuarantined(pid) else { return [:] }
        let required = Set(windowIDs.map { CGWindowID($0.rawValue) })
        guard let windows = AXApplicationWindows(pid: pid, requiredWindowIDs: required) else { return [:] }
        let application = NSRunningApplication(processIdentifier: pid)
        var result: [WindowID: WindowSwitcherAXState] = [:]
        for entry in windows.entries {
            guard let id = entry.id, required.contains(id) else { continue }
            result[WindowID(rawValue: id)] = WindowSwitcherAXState(
                appName: application?.localizedName,
                title: attribute(entry.element, kAXTitleAttribute, pid: pid) as? String,
                isMinimized: attribute(entry.element, kAXMinimizedAttribute, pid: pid) as? Bool ?? false,
                isFullscreen: attribute(entry.element, kAXFullScreenAttribute, pid: pid) as? Bool ?? false,
                isHidden: application?.isHidden ?? false
            )
        }
        return result
    }

    public static func close(_ windowID: WindowID, pid: pid_t) -> WindowSwitcherAXOutcome {
        withWindow(windowID, pid: pid) { element in
            guard let button = attribute(element, kAXCloseButtonAttribute, pid: pid) as? AXUIElement else {
                return .refused(kAXErrorNoValue.rawValue)
            }
            let error = AXUIElementPerformAction(button, kAXPressAction as CFString)
            AXUnresponsiveApps.shared.noteResult(error, pid: pid)
            return error == .success ? .performed : .refused(error.rawValue)
        }
    }

    public static func minimize(_ windowID: WindowID, pid: pid_t) -> WindowSwitcherAXOutcome {
        withWindow(windowID, pid: pid) { element in
            let error = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            AXUnresponsiveApps.shared.noteResult(error, pid: pid)
            return error == .success ? .performed : .refused(error.rawValue)
        }
    }

    public static func hideApplication(pid: pid_t, bundleID: String) -> WindowSwitcherAXOutcome {
        guard let application = application(pid: pid, bundleID: bundleID) else { return .targetMissing }
        return application.hide() ? .performed : .applicationRefused
    }

    public static func unhideApplication(pid: pid_t, bundleID: String) -> WindowSwitcherAXOutcome {
        guard let application = application(pid: pid, bundleID: bundleID) else { return .targetMissing }
        return application.unhide() ? .performed : .applicationRefused
    }

    /// Arrêt normal demandé à l'application. Jamais `forceTerminate`.
    public static func quitApplication(pid: pid_t, bundleID: String) -> WindowSwitcherAXOutcome {
        guard let application = application(pid: pid, bundleID: bundleID) else { return .targetMissing }
        return application.terminate() ? .performed : .applicationRefused
    }

    private static func withWindow(
        _ windowID: WindowID,
        pid: pid_t,
        _ body: (AXUIElement) -> WindowSwitcherAXOutcome
    ) -> WindowSwitcherAXOutcome {
        guard !AXUnresponsiveApps.shared.isQuarantined(pid) else { return .refused(kAXErrorCannotComplete.rawValue) }
        guard let windows = AXApplicationWindows(pid: pid, requiredWindowIDs: [CGWindowID(windowID.rawValue)]) else {
            return .refused(kAXErrorCannotComplete.rawValue)
        }
        guard let element = windows.element(id: CGWindowID(windowID.rawValue)) else { return .targetMissing }
        return body(element)
    }

    private static func application(pid: pid_t, bundleID: String) -> NSRunningApplication? {
        guard let application = NSRunningApplication(processIdentifier: pid),
              application.bundleIdentifier == bundleID
        else { return nil }
        return application
    }

    private static func attribute(_ element: AXUIElement, _ name: String, pid: pid_t) -> CFTypeRef? {
        let registry = AXUnresponsiveApps.shared
        guard !registry.isQuarantined(pid) else { return nil }
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &raw)
        registry.noteResult(error, pid: pid)
        return error == .success ? raw : nil
    }
}
