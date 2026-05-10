import AppKit
import CoreGraphics
import RoadieCore

@_silgen_name("_AXUIElementGetWindow")
private func AXUIElementGetWindowID(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

public protocol SystemSnapshotProviding: Sendable {
    func permissions(prompt: Bool) -> PermissionSnapshot
    func displays() -> [DisplaySnapshot]
    func windows() -> [WindowSnapshot]
    func focusedWindowID() -> WindowID?
}

public extension SystemSnapshotProviding {
    func focusedWindowID() -> WindowID? { nil }
}

public protocol WindowFrameWriting: Sendable {
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect?
    func setFrames(_ updates: [WindowFrameUpdate]) -> [WindowID: CGRect?]
    func focus(_ window: WindowSnapshot) -> Bool
    func reset(_ window: WindowSnapshot) -> Bool
    func toggleZoom(_ window: WindowSnapshot) -> Bool
    func toggleNativeFullscreen(_ window: WindowSnapshot) -> Bool
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
    func toggleZoom(_ window: WindowSnapshot) -> Bool { reset(window) }
    func toggleNativeFullscreen(_ window: WindowSnapshot) -> Bool { false }
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
    public var frame: Rect
    public var isOnScreen: Bool
    public var isTileCandidate: Bool
    /// Sous-role AX (ex: "AXStandardWindow", "AXDialog", "AXFloatingWindow").
    /// nil si AX n'a pas pu repondre (app sandboxee, autorisations manquantes).
    public var subrole: String?
    /// Role AX (ex: "AXWindow"). Optionnel, surtout utile pour les regles user.
    public var role: String?
    /// Mobilier AX (boutons + flags d'etat). nil si AX absent.
    public var furniture: WindowFurniture?

    public init(
        id: WindowID,
        pid: Int32,
        appName: String,
        bundleID: String,
        title: String,
        frame: Rect,
        isOnScreen: Bool,
        isTileCandidate: Bool,
        subrole: String? = nil,
        role: String? = nil,
        furniture: WindowFurniture? = nil
    ) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.frame = frame
        self.isOnScreen = isOnScreen
        self.isTileCandidate = isTileCandidate
        self.subrole = subrole
        self.role = role
        self.furniture = furniture
    }

    enum CodingKeys: String, CodingKey {
        case id, pid, appName, bundleID, title, frame, isOnScreen, isTileCandidate, subrole, role, furniture
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(WindowID.self, forKey: .id)
        self.pid = try c.decode(Int32.self, forKey: .pid)
        self.appName = try c.decode(String.self, forKey: .appName)
        self.bundleID = try c.decode(String.self, forKey: .bundleID)
        self.title = try c.decode(String.self, forKey: .title)
        self.frame = try c.decode(Rect.self, forKey: .frame)
        self.isOnScreen = try c.decode(Bool.self, forKey: .isOnScreen)
        self.isTileCandidate = try c.decode(Bool.self, forKey: .isTileCandidate)
        self.subrole = try c.decodeIfPresent(String.self, forKey: .subrole)
        self.role = try c.decodeIfPresent(String.self, forKey: .role)
        self.furniture = try c.decodeIfPresent(WindowFurniture.self, forKey: .furniture)
    }
}

/// Mobilier AX d'une fenetre : presence de boutons + flags d'etat.
/// Inspiree de aerospace/AxUiElementWindowType.swift pour distinguer fenetres reelles
/// vs popups/menus/tooltips qui n'ont aucun bouton.
public struct WindowFurniture: Equatable, Codable, Sendable {
    public var hasCloseButton: Bool
    public var hasFullscreenButton: Bool
    /// Vrai si le bouton fullscreen existe ET est activable. Aerospace utilise ce signal
    /// pour distinguer une vraie fenetre (button enabled) d'un dialog (button present mais
    /// disabled : Settings, About this Mac, IntelliJ Rebase dialog, Finder copy file dialog).
    public var fullscreenButtonEnabled: Bool
    public var hasMinimizeButton: Bool
    public var hasZoomButton: Bool
    public var isFocused: Bool
    public var isMain: Bool
    /// Vrai pour les dialogs/sheets modaux qui bloquent une app. Ces fenetres ne doivent
    /// pas participer au tiling automatique, meme si elles ont temporairement le focus.
    public var isModal: Bool
    /// Vrai si AX accepte de modifier la taille de la fenetre. Les petites fenetres non
    /// redimensionnables sont souvent des dialogs/progress panels meme si elles se
    /// declarent AXStandardWindow.
    public var isResizable: Bool

    public init(
        hasCloseButton: Bool = false,
        hasFullscreenButton: Bool = false,
        fullscreenButtonEnabled: Bool = false,
        hasMinimizeButton: Bool = false,
        hasZoomButton: Bool = false,
        isFocused: Bool = false,
        isMain: Bool = false,
        isModal: Bool = false,
        isResizable: Bool = true
    ) {
        self.hasCloseButton = hasCloseButton
        self.hasFullscreenButton = hasFullscreenButton
        self.fullscreenButtonEnabled = fullscreenButtonEnabled
        self.hasMinimizeButton = hasMinimizeButton
        self.hasZoomButton = hasZoomButton
        self.isFocused = isFocused
        self.isMain = isMain
        self.isModal = isModal
        self.isResizable = isResizable
    }

    enum CodingKeys: String, CodingKey {
        case hasCloseButton, hasFullscreenButton, fullscreenButtonEnabled
        case hasMinimizeButton, hasZoomButton, isFocused, isMain, isModal, isResizable
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hasCloseButton = try c.decodeIfPresent(Bool.self, forKey: .hasCloseButton) ?? false
        self.hasFullscreenButton = try c.decodeIfPresent(Bool.self, forKey: .hasFullscreenButton) ?? false
        self.fullscreenButtonEnabled = try c.decodeIfPresent(Bool.self, forKey: .fullscreenButtonEnabled) ?? false
        self.hasMinimizeButton = try c.decodeIfPresent(Bool.self, forKey: .hasMinimizeButton) ?? false
        self.hasZoomButton = try c.decodeIfPresent(Bool.self, forKey: .hasZoomButton) ?? false
        self.isFocused = try c.decodeIfPresent(Bool.self, forKey: .isFocused) ?? false
        self.isMain = try c.decodeIfPresent(Bool.self, forKey: .isMain) ?? false
        self.isModal = try c.decodeIfPresent(Bool.self, forKey: .isModal) ?? false
        self.isResizable = try c.decodeIfPresent(Bool.self, forKey: .isResizable) ?? true
    }

    /// Vrai si au moins un bouton ou flag d'etat indique une "vraie" fenetre.
    /// Logique d'aerospace : sans aucun de ces signaux, c'est un popup/menu/tooltip.
    public var isLikelyRealWindow: Bool {
        hasCloseButton || hasFullscreenButton || hasMinimizeButton || hasZoomButton || isFocused || isMain
    }

    /// Heuristique aerospace fine : si le bouton fullscreen existe mais est desactive,
    /// la fenetre est probablement un dialog (Settings, About, IntelliJ Rebase...).
    public var fullscreenButtonDisabled: Bool {
        hasFullscreenButton && !fullscreenButtonEnabled
    }
}

public final class LiveSystemSnapshotProvider: SystemSnapshotProviding, @unchecked Sendable {
    /// Cache long-vivant des attributs AX par CGWindowID. Le subrole/role/mobilier d'une
    /// fenetre est essentiellement immuable apres creation -- on evite de re-queryer AX
    /// 8 fois par fenetre par tick (~30% CPU sinon avec ~30 fenetres a 2 ticks/sec).
    /// Invalide via AXWindowEventObserver (kAXUIElementDestroyedNotification).
    private struct CacheEntry {
        let attrs: AXWindowAttributes
        let fetchedAt: Date
    }
    private let cacheLock = NSLock()
    private var attributeCache: [CGWindowID: CacheEntry] = [:]
    /// TTL d'une entree de cache. Au-dela on re-queryera AX (filet de securite contre
    /// les desync de cache si un AX event a manque).
    private let cacheTTL: TimeInterval

    public init(cacheTTL: TimeInterval = 600) {
        self.cacheTTL = cacheTTL
    }

    /// Vide le cache. Appele par le daemon en reponse aux notifications AX (kAXUIElementDestroyedNotification).
    public func invalidateCache() {
        cacheLock.lock()
        attributeCache.removeAll(keepingCapacity: true)
        cacheLock.unlock()
    }

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
        // Cache pid->[windowID->attrs] pour cette enumeration (1 query AX par app par snapshot
        // pour les fenetres pas encore en cache long-vivant).
        var perSnapshotCache: [pid_t: [CGWindowID: AXWindowAttributes]] = [:]
        let now = Date()
        // Snapshot atomique du cache long-vivant pour eviter de tenir le lock pendant tout le scan.
        cacheLock.lock()
        let liveCache = attributeCache
        cacheLock.unlock()

        let result = raw.compactMap { info -> WindowSnapshot? in
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

            // isTileCandidate ne reflete plus que les criteres CG bruts. La policy
            // (AX subrole, regles user, exclusions bundle) est appliquee cote daemon.
            let tileCandidate = layer == 0
                && alpha > 0
                && rect.width >= 80
                && rect.height >= 60
                && !bundleID.hasPrefix("com.apple.WindowManager")

            // Lookup cache long-vivant puis fallback sur enumeration AX.
            var attrs: AXWindowAttributes?
            if tileCandidate {
                if let cached = liveCache[number], now.timeIntervalSince(cached.fetchedAt) < cacheTTL {
                    attrs = cached.attrs
                } else {
                    attrs = Self.attributes(forCGWindowID: number, pid: pid, cache: &perSnapshotCache)
                }
            }

            return WindowSnapshot(
                id: WindowID(rawValue: number),
                pid: pid,
                appName: appName,
                bundleID: bundleID,
                title: title,
                frame: Rect(rect),
                isOnScreen: true,
                isTileCandidate: tileCandidate,
                subrole: attrs?.subrole,
                role: attrs?.role,
                furniture: attrs?.furniture
            )
        }

        // Met a jour le cache long-vivant avec les nouvelles entrees decouvertes ce snapshot.
        if !perSnapshotCache.isEmpty {
            cacheLock.lock()
            for (_, byWindow) in perSnapshotCache {
                for (windowID, attrs) in byWindow {
                    attributeCache[windowID] = CacheEntry(attrs: attrs, fetchedAt: now)
                }
            }
            // GC : enleve les entrees plus presentes dans le snapshot courant.
            let liveIDs = Set(result.map { $0.id.rawValue })
            attributeCache = attributeCache.filter { liveIDs.contains($0.key) }
            cacheLock.unlock()
        }

        return result
    }

    /// Resout les attributs AX (role, subrole, mobilier) d'une fenetre identifiee par son CGWindowID.
    /// Memoise par pid pour limiter les appels AX (1 enumeration par app, pas par fenetre).
    /// Retourne nil si AX n'a pas pu repondre (app sandboxee, autorisations manquantes).
    private static func attributes(
        forCGWindowID windowID: CGWindowID,
        pid: pid_t,
        cache: inout [pid_t: [CGWindowID: AXWindowAttributes]]
    ) -> AXWindowAttributes? {
        if let entries = cache[pid] {
            return entries[windowID]
        }
        var entries: [CGWindowID: AXWindowAttributes] = [:]
        let axApp = AXUIElementCreateApplication(pid)
        var rawWindows: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &rawWindows) == .success,
           let axWindows = rawWindows as? [AXUIElement] {
            for axWindow in axWindows {
                var cgID = CGWindowID()
                guard AXUIElementGetWindowID(axWindow, &cgID) == .success, cgID > 0 else { continue }
                var rawSubrole: CFTypeRef?
                var rawRole: CFTypeRef?
                let subrole = AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &rawSubrole) == .success
                    ? rawSubrole as? String
                    : nil
                let role = AXUIElementCopyAttributeValue(axWindow, kAXRoleAttribute as CFString, &rawRole) == .success
                    ? rawRole as? String
                    : nil
                let fullscreenBtn = elementAttribute(axWindow, kAXFullScreenButtonAttribute)
                let furniture = WindowFurniture(
                    hasCloseButton: hasAttribute(axWindow, kAXCloseButtonAttribute),
                    hasFullscreenButton: fullscreenBtn != nil,
                    fullscreenButtonEnabled: fullscreenBtn.map { boolAttribute($0, kAXEnabledAttribute) } ?? false,
                    hasMinimizeButton: hasAttribute(axWindow, kAXMinimizeButtonAttribute),
                    hasZoomButton: hasAttribute(axWindow, kAXZoomButtonAttribute),
                    isFocused: boolAttribute(axWindow, kAXFocusedAttribute),
                    isMain: boolAttribute(axWindow, kAXMainAttribute),
                    isModal: boolAttribute(axWindow, kAXModalAttribute),
                    isResizable: isAttributeSettable(axWindow, kAXSizeAttribute)
                )
                entries[cgID] = AXWindowAttributes(role: role, subrole: subrole, furniture: furniture)
            }
        }
        cache[pid] = entries
        return entries[windowID]
    }

    /// Vrai si l'attribut existe (sa valeur n'est pas nil). Utile pour les boutons de fenetre.
    private static func hasAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var raw: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success && raw != nil
    }

    /// Lit un attribut element (typiquement un bouton). Retourne nil si absent.
    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        return (raw as! AXUIElement) // Safe : CFTypeID verifie
    }

    /// Lit un attribut booleen, defaut false en cas d'echec.
    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let value = raw as? Bool
        else { return false }
        return value
    }

    /// Vrai si AX indique que l'attribut peut etre modifie.
    private static func isAttributeSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    public func focusedWindowID() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var rawFocused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &rawFocused) == .success,
              let focused = rawFocused,
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }

        let focusedElement = focused as! AXUIElement // Safe: CFTypeID verified above
        // Voie rapide : si AX donne directement le windowID, on retourne sans appel a windows().
        if let id = windowID(of: focusedElement) {
            return WindowID(rawValue: id)
        }

        // Voie lente : on enumere uniquement les fenetres de l'app courante (CG seul, pas AX).
        // Eviter l'appel a self.windows() qui re-querie le subrole de toutes les fenetres.
        let appWindows = lightweightWindows(forPID: app.processIdentifier)
        let focusedFrame = AXWindowFrameWriter().frame(of: focusedElement)
        if let focusedFrame,
           let match = appWindows.first(where: { framesAreClose(focusedFrame, $0.frame) }) {
            return match.id
        }

        let focusedTitle = title(of: focusedElement)
        let titleMatches = appWindows.filter { !focusedTitle.isEmpty && $0.title == focusedTitle }
        return titleMatches.count == 1 ? titleMatches.first?.id : nil
    }

    /// Liste CG-only (pas d'AX) des fenetres d'un PID, pour les voies de fallback de focusedWindowID.
    private struct CGWindowLite {
        let id: WindowID
        let frame: CGRect
        let title: String
    }
    private func lightweightWindows(forPID pid: pid_t) -> [CGWindowLite] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? UInt32,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            let title = info[kCGWindowName as String] as? String ?? ""
            return CGWindowLite(id: WindowID(rawValue: number), frame: rect, title: title)
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

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 48
            && abs(lhs.minY - rhs.minY) < 48
            && abs(lhs.width - rhs.width) < 48
            && abs(lhs.height - rhs.height) < 48
    }
}

private struct AXWindowAttributes {
    let role: String?
    let subrole: String?
    let furniture: WindowFurniture
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
        toggleZoom(window)
    }

    public func toggleZoom(_ window: WindowSnapshot) -> Bool {
        guard let element = element(matching: window),
              let zoomButton = elementAttribute(element, kAXZoomButtonAttribute)
        else { return false }
        return AXUIElementPerformAction(zoomButton, kAXPressAction as CFString) == .success
    }

    public func toggleNativeFullscreen(_ window: WindowSnapshot) -> Bool {
        guard let element = element(matching: window),
              let fullscreenButton = elementAttribute(element, kAXFullScreenButtonAttribute)
        else { return false }
        return AXUIElementPerformAction(fullscreenButton, kAXPressAction as CFString) == .success
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        return (raw as! AXUIElement)
    }

    // Complexite : O(n) en simple passe (n = fenetres de l'application).
    // Priorite : ID exact > frame proche > titre unique.
    private func element(matching window: WindowSnapshot) -> AXUIElement? {
        let app = AXUIElementCreateApplication(window.pid)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let windows = rawWindows as? [AXUIElement]
        else { return nil }

        var frameMatch: AXUIElement?
        var titleMatches: [AXUIElement] = []
        let lookupTitle = !window.title.isEmpty
        for element in windows {
            if windowID(of: element) == window.id.rawValue {
                return element // priorite la plus haute, sortie immediate
            }
            if frameMatch == nil, matchesByFrame(element, expected: window) {
                frameMatch = element
            }
            if lookupTitle, title(of: element) == window.title {
                titleMatches.append(element)
            }
        }
        if let frameMatch { return frameMatch }
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
        // Safe: CFTypeID == AXValueGetTypeID() verified in the guard above.
        let posValue = axPosition as! AXValue
        let sizeValue = axSize as! AXValue
        guard AXValueGetValue(posValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }
}
