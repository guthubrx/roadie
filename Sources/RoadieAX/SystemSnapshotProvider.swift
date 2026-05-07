import AppKit
import CoreGraphics
import RoadieCore

public protocol SystemSnapshotProviding: Sendable {
    func permissions(prompt: Bool) -> PermissionSnapshot
    func displays() -> [DisplaySnapshot]
    func windows() -> [WindowSnapshot]
}

public protocol WindowFrameWriting: Sendable {
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect?
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
    public var frame: Rect
    public var isOnScreen: Bool
    public var isTileCandidate: Bool

    public init(
        id: WindowID,
        pid: Int32,
        appName: String,
        bundleID: String,
        title: String,
        frame: Rect,
        isOnScreen: Bool,
        isTileCandidate: Bool
    ) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.frame = frame
        self.isOnScreen = isOnScreen
        self.isTileCandidate = isTileCandidate
    }
}

public struct LiveSystemSnapshotProvider: SystemSnapshotProviding {
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
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
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
                frame: Rect(rect),
                isOnScreen: true,
                isTileCandidate: tileCandidate
            )
        }
        .sorted { lhs, rhs in
            if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
            return lhs.id < rhs.id
        }
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
}

public struct AXWindowFrameWriter: WindowFrameWriting {
    public init() {}

    public func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        let app = AXUIElementCreateApplication(window.pid)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let windows = rawWindows as? [AXUIElement]
        else { return nil }

        for element in windows {
            if matches(element, expected: window) {
                return set(frame, on: element)
            }
        }
        return nil
    }

    private func matches(_ element: AXUIElement, expected: WindowSnapshot) -> Bool {
        if let frame = frame(of: element) {
            return abs(frame.minX - expected.frame.x) < 48
                && abs(frame.minY - expected.frame.y) < 48
                && abs(frame.width - expected.frame.width) < 48
                && abs(frame.height - expected.frame.height) < 48
        }

        var rawTitle: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &rawTitle) == .success,
           let title = rawTitle as? String,
           title == expected.title {
            return true
        }
        return false
    }

    private func set(_ frame: CGRect, on element: AXUIElement) -> CGRect? {
        var position = CGPoint(x: frame.minX, y: frame.minY)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let axPosition = AXValueCreate(.cgPoint, &position),
              let axSize = AXValueCreate(.cgSize, &size)
        else { return nil }

        let posResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axPosition)
        let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axSize)
        guard posResult == .success && sizeResult == .success else { return nil }
        return self.frame(of: element)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
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
