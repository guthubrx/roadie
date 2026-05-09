import AppKit
import CoreGraphics
import RoadieCore

@_silgen_name("_AXUIElementGetWindow")
private func AXUIElementGetWindowID(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

public protocol SystemSnapshotProviding: Sendable {
    func permissions(prompt: Bool) -> PermissionSnapshot
    func displays() -> [DisplaySnapshot]
    func windows() -> [WindowSnapshot]
    func windows(includeAccessibilityAttributes: Bool) -> [WindowSnapshot]
    func focusedWindowID() -> WindowID?
}

public extension SystemSnapshotProviding {
    func windows(includeAccessibilityAttributes: Bool) -> [WindowSnapshot] { windows() }
    func focusedWindowID() -> WindowID? { nil }
}

public protocol WindowFrameWriting: Sendable {
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect?
    func setFrames(_ updates: [WindowFrameUpdate]) -> [WindowID: CGRect?]
    func focus(_ window: WindowSnapshot) -> Bool
    func reset(_ window: WindowSnapshot) -> Bool
}

public extension WindowFrameWriting {
    func setFrames(_ updates: [WindowFrameUpdate]) -> [WindowID: CGRect?] {
        var results: [WindowID: CGRect?] = [:]
        for update in updates {
            results[update.window.id] = setFrame(update.frame, of: update.window)
        }
        return results
    }

    func focus(_ window: WindowSnapshot) -> Bool { false }
    func reset(_ window: WindowSnapshot) -> Bool { false }
}

public struct WindowFrameUpdate: Sendable {
    public var window: WindowSnapshot
    public var frame: CGRect

    public init(window: WindowSnapshot, frame: CGRect) {
        self.window = window
        self.frame = frame
    }
}

public struct DisplaySnapshot: Equatable, Codable, Sendable {
    public var id: DisplayID
    public var index: Int
    public var name: String
    public var frame: Rect
    public var visibleFrame: Rect
    public var isMain: Bool

    public init(id: DisplayID, index: Int, name: String, frame: Rect, visibleFrame: Rect, isMain: Bool) {
        self.id = id
        self.index = index
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
    }
}

public struct WindowSnapshot: Equatable, Codable, Sendable {
    public var id: WindowID
    public var pid: Int32
    public var appName: String
    public var bundleID: String
    public var title: String
    public var role: String?
    public var subrole: String?
    public var frame: Rect
    public var isOnScreen: Bool
    public var isTileCandidate: Bool

    public init(
        id: WindowID,
        pid: Int32,
        appName: String,
        bundleID: String,
        title: String,
        role: String? = nil,
        subrole: String? = nil,
        frame: Rect,
        isOnScreen: Bool,
        isTileCandidate: Bool
    ) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.isOnScreen = isOnScreen
        self.isTileCandidate = isTileCandidate
    }
}

public struct LiveSystemSnapshotProvider: SystemSnapshotProviding {
    private struct AXWindowAttributes {
        var id: CGWindowID?
        var title: String
        var frame: CGRect?
        var role: String?
        var subrole: String?
    }

    public init() {}

    public func permissions(prompt: Bool) -> PermissionSnapshot {
        AXPermissions.snapshot(prompt: prompt)
    }

    public func displays() -> [DisplaySnapshot] {
        let mainID = NSScreen.main.flatMap(Self.displayID(for:))
        return NSScreen.screens.enumerated().compactMap { index, screen in
            guard let id = Self.displayID(for: screen) else { return nil }
            let frame = Self.nsToAX(screen.frame)
            let visibleFrame = Self.visibleAXFrame(for: screen, displayFrame: frame)
            return DisplaySnapshot(
                id: id,
                index: index + 1,
                name: screen.localizedName,
                frame: Rect(frame),
                visibleFrame: Rect(visibleFrame),
                isMain: id == mainID
            )
        }
    }

    public func windows() -> [WindowSnapshot] {
        windows(includeAccessibilityAttributes: true)
    }

    public func windows(includeAccessibilityAttributes: Bool) -> [WindowSnapshot] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        var axWindowsByPID: [Int32: [AXWindowAttributes]] = [:]
        return raw.compactMap { info -> WindowSnapshot? in
            guard let number = info[kCGWindowNumber as String] as? UInt32,
                  number > 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  pid != currentPID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            let appName = info[kCGWindowOwnerName as String] as? String ?? ""
            let title = info[kCGWindowName as String] as? String ?? ""
            let app = NSRunningApplication(processIdentifier: pid)
            let bundleID = app?.bundleIdentifier ?? ""
            let attributes = includeAccessibilityAttributes
                ? Self.axAttributes(
                    forWindowID: number,
                    pid: pid,
                    fallbackTitle: title,
                    fallbackFrame: rect,
                    cache: &axWindowsByPID
                )
                : (role: nil, subrole: nil)
            let tileCandidate = layer == 0
                && alpha > 0
                && rect.width >= 80
                && rect.height >= 60
                && !bundleID.hasPrefix("com.apple.WindowManager")

            return WindowSnapshot(
                id: WindowID(rawValue: number),
                pid: pid,
                appName: appName,
                bundleID: bundleID,
                title: title,
                role: attributes.role,
                subrole: attributes.subrole,
                frame: Rect(rect),
                isOnScreen: true,
                isTileCandidate: tileCandidate
            )
        }
    }

    public func focusedWindowID() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var rawFocused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &rawFocused) == .success,
              let focused = rawFocused
        else { return nil }

        let focusedElement = focused as! AXUIElement
        if let id = windowID(of: focusedElement) {
            return WindowID(rawValue: id)
        }

        let appWindows = windows().filter { $0.pid == app.processIdentifier }
        let focusedFrame = AXWindowFrameWriter().frame(of: focusedElement)
        if let focusedFrame,
           let match = appWindows.first(where: { framesAreClose(focusedFrame, $0.frame.cgRect) }) {
            return match.id
        }

        let focusedTitle = title(of: focusedElement)
        let titleMatches = appWindows.filter { !focusedTitle.isEmpty && $0.title == focusedTitle }
        return titleMatches.count == 1 ? titleMatches.first?.id : nil
    }

    private static func displayID(for screen: NSScreen) -> DisplayID? {
        guard let raw = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(raw)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        return DisplayID(rawValue: string)
    }

    private static func nsToAX(_ rect: CGRect) -> CGRect {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let primary else { return rect }
        return CGRect(
            x: rect.origin.x,
            y: primary.frame.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func visibleAXFrame(for screen: NSScreen, displayFrame: CGRect) -> CGRect {
        var visibleFrame = nsToAX(screen.visibleFrame)
        let menuBarHeight: CGFloat = 30
        if abs(visibleFrame.minY - displayFrame.minY) < 1 {
            visibleFrame.origin.y += menuBarHeight
            visibleFrame.size.height = max(0, visibleFrame.height - menuBarHeight)
        }
        return visibleFrame
    }

    private func title(of element: AXUIElement) -> String {
        var rawTitle: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &rawTitle) == .success,
              let title = rawTitle as? String
        else { return "" }
        return title
    }

    private func windowID(of element: AXUIElement) -> CGWindowID? {
        var id = CGWindowID()
        return AXUIElementGetWindowID(element, &id) == .success && id > 0 ? id : nil
    }

    private static func axAttributes(
        forWindowID id: CGWindowID,
        pid: Int32,
        fallbackTitle: String,
        fallbackFrame: CGRect,
        cache: inout [Int32: [AXWindowAttributes]]
    ) -> (role: String?, subrole: String?) {
        let windows = axWindows(pid: pid, cache: &cache)
        if let match = windows.first(where: { $0.id == id }) {
            return (match.role, match.subrole)
        }
        if !fallbackTitle.isEmpty,
           let match = windows.first(where: { $0.title == fallbackTitle }) {
            return (match.role, match.subrole)
        }
        let match = windows.first { candidate in
            guard let frame = candidate.frame else { return false }
            return abs(frame.minX - fallbackFrame.minX) < 48
                && abs(frame.minY - fallbackFrame.minY) < 48
                && abs(frame.width - fallbackFrame.width) < 48
                && abs(frame.height - fallbackFrame.height) < 48
        }
        return (match?.role, match?.subrole)
    }

    private static func axWindows(
        pid: Int32,
        cache: inout [Int32: [AXWindowAttributes]]
    ) -> [AXWindowAttributes] {
        if let cached = cache[pid] {
            return cached
        }
        let app = AXUIElementCreateApplication(pid)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let windows = rawWindows as? [AXUIElement]
        else {
            cache[pid] = []
            return []
        }

        let attributes = windows.map { element in
            var rawID = CGWindowID()
            let id = AXUIElementGetWindowID(element, &rawID) == .success && rawID > 0 ? rawID : nil
            return AXWindowAttributes(
                id: id,
                title: axString(kAXTitleAttribute, of: element) ?? "",
                frame: axFrame(of: element),
                role: axString(kAXRoleAttribute, of: element),
                subrole: axString(kAXSubroleAttribute, of: element)
            )
        }
        cache[pid] = attributes
        return attributes
    }

    private static func axString(_ attribute: String, of element: AXUIElement) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let value = raw as? String,
              !value.isEmpty
        else { return nil }
        return value
    }

    private static func axFrame(of element: AXUIElement) -> CGRect? {
        var rawPosition: CFTypeRef?
        var rawSize: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &rawPosition) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &rawSize) == .success,
              let rawPosition,
              let rawSize
        else { return nil }
        let positionValue = rawPosition as! AXValue
        let sizeValue = rawSize as! AXValue
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 48
            && abs(lhs.minY - rhs.minY) < 48
            && abs(lhs.width - rhs.width) < 48
            && abs(lhs.height - rhs.height) < 48
    }
}

public struct AXWindowFrameWriter: WindowFrameWriting {
    public init() {}

    public func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        guard let element = element(matching: window) else { return nil }
        return set(frame, on: element)
    }

    public func setFrames(_ updates: [WindowFrameUpdate]) -> [WindowID: CGRect?] {
        let resolved = updates.map { update in
            (update: update, element: element(matching: update.window))
        }
        return Dictionary(uniqueKeysWithValues: resolved.map { item in
            guard let element = item.element else {
                return (item.update.window.id, nil)
            }
            return (item.update.window.id, set(item.update.frame, on: element))
        })
    }

    public func focus(_ window: WindowSnapshot) -> Bool {
        guard let element = element(matching: window) else { return false }
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [.activateIgnoringOtherApps])
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, element)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        return true
    }

    public func reset(_ window: WindowSnapshot) -> Bool {
        guard let element = element(matching: window) else { return false }
        return AXUIElementPerformAction(element, "AXZoomWindow" as CFString) == .success
    }

    private func element(matching window: WindowSnapshot) -> AXUIElement? {
        let app = AXUIElementCreateApplication(window.pid)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let windows = rawWindows as? [AXUIElement]
        else { return nil }

        for element in windows {
            if windowID(of: element) == window.id.rawValue {
                return element
            }
        }

        for element in windows {
            if matchesByFrame(element, expected: window) {
                return element
            }
        }

        let titleMatches = windows.filter { element in
            title(of: element) == window.title && !window.title.isEmpty
        }
        return titleMatches.count == 1 ? titleMatches.first : nil
    }

    private func windowID(of element: AXUIElement) -> CGWindowID? {
        var id = CGWindowID()
        return AXUIElementGetWindowID(element, &id) == .success && id > 0 ? id : nil
    }

    private func matchesByFrame(_ element: AXUIElement, expected: WindowSnapshot) -> Bool {
        if let frame = frame(of: element) {
            return abs(frame.minX - expected.frame.x) < 48
                && abs(frame.minY - expected.frame.y) < 48
                && abs(frame.width - expected.frame.width) < 48
                && abs(frame.height - expected.frame.height) < 48
        }
        return false
    }

    private func title(of element: AXUIElement) -> String {
        var rawTitle: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &rawTitle) == .success,
              let title = rawTitle as? String
        else { return "" }
        return title
    }

    private func set(_ frame: CGRect, on element: AXUIElement) -> CGRect? {
        var position = CGPoint(x: frame.minX, y: frame.minY)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let axPosition = AXValueCreate(.cgPoint, &position),
              let axSize = AXValueCreate(.cgSize, &size)
        else { return nil }

        let initialPosResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axPosition)
        Thread.sleep(forTimeInterval: 0.01)
        let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axSize)
        let posResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axPosition)
        guard initialPosResult == .success && posResult == .success && sizeResult == .success else { return nil }

        if let actual = self.frame(of: element), framesAreClose(actual, frame) {
            return actual
        }

        Thread.sleep(forTimeInterval: 0.02)
        _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axSize)
        _ = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axPosition)
        return self.frame(of: element)
    }

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 2
            && abs(lhs.minY - rhs.minY) <= 2
            && abs(lhs.width - rhs.width) <= 2
            && abs(lhs.height - rhs.height) <= 2
    }

    public func frame(of element: AXUIElement) -> CGRect? {
        var rawPosition: CFTypeRef?
        var rawSize: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &rawPosition) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &rawSize) == .success,
              let axPosition = rawPosition,
              let axSize = rawSize,
              CFGetTypeID(axPosition) == AXValueGetTypeID(),
              CFGetTypeID(axSize) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(axPosition as! AXValue, .cgPoint, &position),
              AXValueGetValue(axSize as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }
}
