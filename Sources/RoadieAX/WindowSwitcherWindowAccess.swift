import AppKit
import CoreGraphics
import RoadieCore

public struct WindowSwitcherAXState: Equatable, Sendable {
    public var appName: String?
    public var title: String?
    public var isMinimized: Bool
    public var isFullscreen: Bool
    public var isHidden: Bool
    public var visibilityKnown: Bool
    /// Faux si l'application a répondu sans lister cette fenêtre (autre bureau ou fenêtre retirée).
    public var isListed: Bool

    public init(appName: String? = nil, title: String? = nil, isMinimized: Bool = false, isFullscreen: Bool = false, isHidden: Bool = false, visibilityKnown: Bool = true, isListed: Bool = true) {
        self.appName = appName
        self.title = title
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.isHidden = isHidden
        self.visibilityKnown = visibilityKnown
        self.isListed = isListed
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
    private static let stateAttributeNames: [String] = [
        kAXMinimizedAttribute, kAXTitleAttribute, "AXFullScreen",
    ]

    public static func states(pid: pid_t, windowIDs: Set<WindowID>) -> [WindowID: WindowSwitcherAXState] {
        guard !windowIDs.isEmpty, !AXUnresponsiveApps.shared.isQuarantined(pid) else { return [:] }
        let required = Set(windowIDs.map { CGWindowID($0.rawValue) })
        // Lot J : réutilise l'index AX s'il couvre déjà toutes les fenêtres demandées, sinon
        // énumère `kAXWindows` sans parcourir 256 enfants (une fenêtre d'un autre Space n'est pas une feuille).
        guard let windows = AXWindowIndexCache.shared.reusableWindows(for: pid, required: required)
            ?? AXApplicationWindows(pid: pid, requiredWindowIDs: required, discoverAttachedSheets: false)
        else { return [:] }
        let application = NSRunningApplication(processIdentifier: pid)
        let appName = application?.localizedName
        let isHidden = application?.isHidden ?? false
        let hasApp = application != nil
        var result: [WindowID: WindowSwitcherAXState] = [:]
        for entry in windows.entries {
            guard let id = entry.id, required.contains(id) else { continue }
            guard let values = readStateAttributes(entry.element, pid: pid) else { continue }
            result[WindowID(rawValue: id)] = parseState(
                values: values, appName: appName, isHidden: isHidden, hasApp: hasApp
            )
        }
        for id in required where result[WindowID(rawValue: id)] == nil {
            result[WindowID(rawValue: id)] = WindowSwitcherAXState(
                appName: appName, isHidden: isHidden,
                visibilityKnown: false, isListed: false
            )
        }
        return result
    }

    /// Lit minimisé/titre/plein-écran en un seul aller-retour AX groupé (Lot J).
    private static func readStateAttributes(_ element: AXUIElement, pid: pid_t) -> [AnyObject]? {
        let registry = AXUnresponsiveApps.shared
        guard !registry.isQuarantined(pid) else { return nil }
        var raw: CFArray?
        let error = AXCallTimings.shared.measure(pid) {
            AXUIElementCopyMultipleAttributeValues(
                element, stateAttributeNames as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw
            )
        }
        if registry.noteResult(error, pid: pid) { return nil }
        let values = error == .success ? (raw as? [AnyObject]) ?? [] : []
        if AXReadValue.noteEmbeddedErrors(in: values, pid: pid, registry: registry) { return nil }
        return values
    }

    static func parseState(
        values: [AnyObject],
        appName: String?,
        isHidden: Bool,
        hasApp: Bool
    ) -> WindowSwitcherAXState {
        let minimized: Bool? = if values.count > 0, AXReadValue.embeddedError(values[0]) == nil {
            values[0] as? Bool
        } else { nil }
        let title: String? = if values.count > 1, AXReadValue.embeddedError(values[1]) == nil {
            values[1] as? String
        } else { nil }
        let fullscreen = (values.count > 2 ? AXReadValue.flag(values[2]) : nil) ?? false
        return WindowSwitcherAXState(
            appName: appName,
            title: title,
            isMinimized: minimized ?? false,
            isFullscreen: fullscreen,
            isHidden: isHidden,
            visibilityKnown: minimized != nil && hasApp
        )
    }

    public static func close(_ windowID: WindowID, pid: pid_t) -> WindowSwitcherAXOutcome {
        withWindow(windowID, pid: pid) { element in
            guard let raw = attribute(element, kAXCloseButtonAttribute, pid: pid),
                  CFGetTypeID(raw) == AXUIElementGetTypeID() else {
                return .refused(AXError.noValue.rawValue)
            }
            let button = unsafeBitCast(raw, to: AXUIElement.self)
            guard !AXUnresponsiveApps.shared.isQuarantined(pid) else { return .refused(AXError.cannotComplete.rawValue) }
            let error = AXUIElementPerformAction(button, kAXPressAction as CFString)
            AXUnresponsiveApps.shared.noteResult(error, pid: pid)
            return error == .success ? .performed : .refused(error.rawValue)
        }
    }

    public static func minimize(_ windowID: WindowID, pid: pid_t) -> WindowSwitcherAXOutcome {
        withWindow(windowID, pid: pid) { element in
            guard let minimized = attribute(element, kAXMinimizedAttribute, pid: pid) as? Bool else {
                return .refused(AXError.noValue.rawValue)
            }
            guard !AXUnresponsiveApps.shared.isQuarantined(pid) else { return .refused(AXError.cannotComplete.rawValue) }
            let error = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString,
                                                    minimized ? kCFBooleanFalse : kCFBooleanTrue)
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
        guard !AXUnresponsiveApps.shared.isQuarantined(pid) else { return .refused(AXError.cannotComplete.rawValue) }
        guard let windows = AXApplicationWindows(pid: pid, requiredWindowIDs: [CGWindowID(windowID.rawValue)]) else {
            return .refused(AXError.cannotComplete.rawValue)
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
