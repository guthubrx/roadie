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
    func window(id: WindowID, includeAccessibilityAttributes: Bool) -> WindowSnapshot?
    func focusedWindowID() -> WindowID?
}

public extension SystemSnapshotProviding {
    func windows(includeAccessibilityAttributes: Bool) -> [WindowSnapshot] { windows() }
    func window(id: WindowID, includeAccessibilityAttributes: Bool) -> WindowSnapshot? {
        windows(includeAccessibilityAttributes: includeAccessibilityAttributes).first { $0.id == id }
    }
    func focusedWindowID() -> WindowID? { nil }
}

public protocol WindowFrameWriting: Sendable {
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect?
    func setFrames(_ updates: [WindowFrameUpdate]) -> [WindowID: CGRect?]
    func focus(_ window: WindowSnapshot) -> Bool
    func focus(windowID: WindowID, pid: Int32) -> Bool
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
    func focus(windowID: WindowID, pid: Int32) -> Bool { false }
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
    private static let displayCache = DisplayCache()
    private static let permissionCache = PermissionCache()
    private static let windowCache = WindowSnapshotCache()

    private struct AXWindowAttributes {
        var id: CGWindowID?
        var title: String
        var frame: CGRect?
        var role: String?
        var subrole: String?
    }

    public init() {}

    public func permissions(prompt: Bool) -> PermissionSnapshot {
        if !prompt, let cached = Self.permissionCache.get() {
            return cached
        }
        let snapshot = AXPermissions.snapshot(prompt: prompt)
        if !prompt {
            Self.permissionCache.set(snapshot)
        }
        return snapshot
    }

    public func displays() -> [DisplaySnapshot] {
        if let cached = Self.displayCache.get() {
            return cached
        }
        let mainID = NSScreen.main.flatMap(Self.displayID(for:))
        let snapshots: [DisplaySnapshot] = NSScreen.screens.enumerated().compactMap { index, screen in
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
        Self.displayCache.set(snapshots)
        return snapshots
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
        let snapshots = raw.compactMap { info -> WindowSnapshot? in
            Self.windowSnapshot(
                from: info,
                currentPID: currentPID,
                includeAccessibilityAttributes: includeAccessibilityAttributes,
                axWindowsByPID: &axWindowsByPID
            )
        }
        if !includeAccessibilityAttributes {
            Self.windowCache.set(snapshots)
        }
        return snapshots
    }

    public func window(id: WindowID, includeAccessibilityAttributes: Bool) -> WindowSnapshot? {
        if !includeAccessibilityAttributes, let cached = Self.windowCache.get(id: id) {
            return cached
        }
        let options: CGWindowListOption = [.optionIncludingWindow, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, CGWindowID(id.rawValue)) as? [[String: Any]] else {
            return nil
        }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        var axWindowsByPID: [Int32: [AXWindowAttributes]] = [:]
        let snapshot = raw.lazy.compactMap { info in
            Self.windowSnapshot(
                from: info,
                currentPID: currentPID,
                includeAccessibilityAttributes: includeAccessibilityAttributes,
                axWindowsByPID: &axWindowsByPID
            )
        }
        .first { $0.id == id }
        if !includeAccessibilityAttributes, let snapshot {
            Self.windowCache.set([snapshot])
        }
        return snapshot
    }

    public func focusedWindowID() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var rawFocused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &rawFocused) == .success,
              let focused = rawFocused
        else { return nil }

        let focusedElement = focused as! AXUIElement
        let appWindows = windows(includeAccessibilityAttributes: false)
            .filter { $0.pid == app.processIdentifier }
        if let id = windowID(of: focusedElement),
           appWindows.contains(where: { $0.id.rawValue == id }) {
            return WindowID(rawValue: id)
        }

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

    private static func windowSnapshot(
        from info: [String: Any],
        currentPID: pid_t,
        includeAccessibilityAttributes: Bool,
        axWindowsByPID: inout [Int32: [AXWindowAttributes]]
    ) -> WindowSnapshot? {
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
            ? axAttributes(
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

private final class DisplayCache: @unchecked Sendable {
    private struct Payload: Codable {
        var cachedAt: Date
        var displays: [DisplaySnapshot]
    }

    private let lock = NSLock()
    private var cachedAt = Date.distantPast
    private var cached: [DisplaySnapshot] = []
    private let ttl: TimeInterval = 2
    private let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/roadies/display-cache.json")

    func get() -> [DisplaySnapshot]? {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if !cached.isEmpty, now.timeIntervalSince(cachedAt) < ttl {
            return cached
        }
        guard let data = try? Data(contentsOf: path),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              !payload.displays.isEmpty,
              now.timeIntervalSince(payload.cachedAt) < ttl
        else { return nil }
        cached = payload.displays
        cachedAt = payload.cachedAt
        return payload.displays
    }

    func set(_ displays: [DisplaySnapshot]) {
        lock.lock()
        cached = displays
        cachedAt = Date()
        let payload = Payload(cachedAt: cachedAt, displays: displays)
        if let data = try? JSONEncoder().encode(payload) {
            try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: path, options: [.atomic])
        }
        lock.unlock()
    }
}

private final class PermissionCache: @unchecked Sendable {
    private struct Payload: Codable {
        var cachedAt: Date
        var snapshot: PermissionSnapshot
    }

    private let lock = NSLock()
    private var cachedAt = Date.distantPast
    private var cached: PermissionSnapshot?
    private let ttl: TimeInterval = 5
    private let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/roadies/permission-cache.json")

    func get() -> PermissionSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if let cached, now.timeIntervalSince(cachedAt) < ttl {
            return cached
        }
        guard let data = try? Data(contentsOf: path),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              now.timeIntervalSince(payload.cachedAt) < ttl
        else { return nil }
        cached = payload.snapshot
        cachedAt = payload.cachedAt
        return payload.snapshot
    }

    func set(_ snapshot: PermissionSnapshot) {
        lock.lock()
        cached = snapshot
        cachedAt = Date()
        let payload = Payload(cachedAt: cachedAt, snapshot: snapshot)
        if let data = try? JSONEncoder().encode(payload) {
            try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: path, options: [.atomic])
        }
        lock.unlock()
    }
}

private final class WindowSnapshotCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedAtByID: [WindowID: Date] = [:]
    private var cachedByID: [WindowID: WindowSnapshot] = [:]
    private let ttl: TimeInterval = 0.35

    func get(id: WindowID) -> WindowSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached = cachedByID[id],
              let cachedAt = cachedAtByID[id],
              Date().timeIntervalSince(cachedAt) < ttl
        else { return nil }
        return cached
    }

    func set(_ windows: [WindowSnapshot]) {
        lock.lock()
        let now = Date()
        for window in windows {
            cachedByID[window.id] = window
            cachedAtByID[window.id] = now
        }
        let staleIDs = cachedAtByID.compactMap { id, cachedAt in
            now.timeIntervalSince(cachedAt) > ttl ? id : nil
        }
        for id in staleIDs {
            cachedAtByID.removeValue(forKey: id)
            cachedByID.removeValue(forKey: id)
        }
        lock.unlock()
    }
}

private final class AXWindowElementCache: @unchecked Sendable {
    private struct Entry {
        var pid: Int32
        var element: AXUIElement
    }

    private let lock = NSLock()
    private var cachedByID: [WindowID: Entry] = [:]

    func get(id: WindowID, pid: Int32) -> AXUIElement? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached = cachedByID[id], cached.pid == pid else { return nil }
        var rawID = CGWindowID()
        guard AXUIElementGetWindowID(cached.element, &rawID) == .success,
              rawID == id.rawValue
        else {
            cachedByID.removeValue(forKey: id)
            return nil
        }
        return cached.element
    }

    func set(_ element: AXUIElement, id: WindowID, pid: Int32) {
        lock.lock()
        cachedByID[id] = Entry(pid: pid, element: element)
        lock.unlock()
    }

    func remove(id: WindowID) {
        lock.lock()
        cachedByID.removeValue(forKey: id)
        lock.unlock()
    }
}

public struct AXWindowFrameWriter: WindowFrameWriting {
    private static let elementCache = AXWindowElementCache()

    public init() {}

    public func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        guard let element = element(matching: window) else { return nil }
        return set(frame, on: element)
    }

    public func setFrames(_ updates: [WindowFrameUpdate]) -> [WindowID: CGRect?] {
        var results: [WindowID: CGRect?] = [:]
        var prepared: [(update: WindowFrameUpdate, element: AXUIElement, position: AXValue, size: AXValue)] = []

        for update in updates {
            guard let element = element(matching: update.window) else {
                results[update.window.id] = nil
                continue
            }
            var point = CGPoint(x: update.frame.minX, y: update.frame.minY)
            var size = CGSize(width: update.frame.width, height: update.frame.height)
            guard let axPosition = AXValueCreate(.cgPoint, &point),
                  let axSize = AXValueCreate(.cgSize, &size)
            else {
                results[update.window.id] = nil
                continue
            }
            prepared.append((update, element, axPosition, axSize))
        }

        guard !prepared.isEmpty else { return results }

        for item in prepared {
            _ = AXUIElementSetAttributeValue(item.element, kAXPositionAttribute as CFString, item.position)
        }
        Thread.sleep(forTimeInterval: 0.01)

        var retry: [(update: WindowFrameUpdate, element: AXUIElement, position: AXValue, size: AXValue)] = []
        for item in prepared {
            let sizeResult = AXUIElementSetAttributeValue(item.element, kAXSizeAttribute as CFString, item.size)
            let posResult = AXUIElementSetAttributeValue(item.element, kAXPositionAttribute as CFString, item.position)
            guard sizeResult == .success && posResult == .success else {
                results[item.update.window.id] = nil
                continue
            }
            if let actual = frame(of: item.element), framesAreClose(actual, item.update.frame) {
                results[item.update.window.id] = actual
            } else {
                retry.append(item)
            }
        }

        guard !retry.isEmpty else { return results }
        Thread.sleep(forTimeInterval: 0.02)
        for item in retry {
            _ = AXUIElementSetAttributeValue(item.element, kAXSizeAttribute as CFString, item.size)
            _ = AXUIElementSetAttributeValue(item.element, kAXPositionAttribute as CFString, item.position)
            results[item.update.window.id] = frame(of: item.element)
        }
        return results
    }

    public func focus(_ window: WindowSnapshot) -> Bool {
        guard let element = element(matching: window) else { return false }
        return focus(element: element, pid: window.pid)
    }

    public func focus(windowID: WindowID, pid: Int32) -> Bool {
        guard let element = exactElement(windowID: windowID, pid: pid) else { return false }
        return focus(element: element, pid: pid)
    }

    private func focus(element: AXUIElement, pid: Int32) -> Bool {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, element)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        return true
    }

    public func reset(_ window: WindowSnapshot) -> Bool {
        guard let element = element(matching: window) else { return false }
        return AXUIElementPerformAction(element, "AXZoomWindow" as CFString) == .success
    }

    private func element(matching window: WindowSnapshot) -> AXUIElement? {
        if let cached = Self.elementCache.get(id: window.id, pid: window.pid) {
            return cached
        }
        if let exact = exactElement(windowID: window.id, pid: window.pid) {
            return exact
        }

        let app = AXUIElementCreateApplication(window.pid)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let windows = rawWindows as? [AXUIElement]
        else { return nil }

        for element in windows {
            if windowID(of: element) == window.id.rawValue {
                Self.elementCache.set(element, id: window.id, pid: window.pid)
                return element
            }
        }

        for element in windows {
            if matchesByFrame(element, expected: window) {
                Self.elementCache.set(element, id: window.id, pid: window.pid)
                return element
            }
        }

        let titleMatches = windows.filter { element in
            title(of: element) == window.title && !window.title.isEmpty
        }
        if titleMatches.count == 1, let element = titleMatches.first {
            Self.elementCache.set(element, id: window.id, pid: window.pid)
            return element
        }
        return nil
    }

    private func exactElement(windowID targetWindowID: WindowID, pid: Int32) -> AXUIElement? {
        if let cached = Self.elementCache.get(id: targetWindowID, pid: pid) {
            return cached
        }
        let app = AXUIElementCreateApplication(pid)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let windows = rawWindows as? [AXUIElement]
        else { return nil }

        var matched: AXUIElement?
        for element in windows {
            guard let rawID = windowID(of: element) else { continue }
            let id = WindowID(rawValue: rawID)
            Self.elementCache.set(element, id: id, pid: pid)
            if id == targetWindowID {
                matched = element
            }
        }
        if let matched {
            return matched
        }
        Self.elementCache.remove(id: targetWindowID)
        return nil
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
