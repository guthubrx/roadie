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
    func mouseLocation() -> CGPoint?
}

public extension SystemSnapshotProviding {
    func focusedWindowID() -> WindowID? { nil }
    func mouseLocation() -> CGPoint? { nil }
}

public protocol WindowFrameWriting: Sendable {
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect?
    func setFrames(_ updates: [WindowFrameUpdate]) -> [WindowID: CGRect?]
    func focus(_ window: WindowSnapshot) -> Bool
    func focusApplicationWindow(bundleID: String, windowID: WindowID, title: String, frame: Rect) -> Bool
    func activateApplication(bundleID: String) -> Bool
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
    func focusApplicationWindow(bundleID: String, windowID: WindowID, title: String, frame: Rect) -> Bool { false }
    func activateApplication(bundleID: String) -> Bool { false }
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
    /// Vrai si AX expose explicitement l'etat fullscreen natif macOS.
    public var isNativeFullscreen: Bool

    public init(
        hasCloseButton: Bool = false,
        hasFullscreenButton: Bool = false,
        fullscreenButtonEnabled: Bool = false,
        hasMinimizeButton: Bool = false,
        hasZoomButton: Bool = false,
        isFocused: Bool = false,
        isMain: Bool = false,
        isModal: Bool = false,
        isResizable: Bool = true,
        isNativeFullscreen: Bool = false
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
        self.isNativeFullscreen = isNativeFullscreen
    }

    enum CodingKeys: String, CodingKey {
        case hasCloseButton, hasFullscreenButton, fullscreenButtonEnabled
        case hasMinimizeButton, hasZoomButton, isFocused, isMain, isModal, isResizable, isNativeFullscreen
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
        self.isNativeFullscreen = try c.decodeIfPresent(Bool.self, forKey: .isNativeFullscreen) ?? false
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

// MARK: - Délai Accessibility et mise de côté (SPEC-016 FR-021, research R3)

/// Délai maximal de chaque appel Accessibility. Sans lui, une application suspendue bloque
/// chaque appel AX environ 6 s (délai par défaut de macOS), et Roadie avec elle.
enum AXMessaging {
    static let timeout: Float = 0.5

    /// Valeur globale du processus, posée une seule fois sur l'élément système. Elle couvre
    /// les éléments fenêtre obtenus depuis une application.
    private static let systemWideTimeout: Void = {
        _ = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), timeout)
    }()

    /// Élément application avec le délai court. Remplace `AXUIElementCreateApplication`.
    static func application(_ pid: pid_t) -> AXUIElement {
        _ = systemWideTimeout
        let element = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }
}

/// Registre des applications qui ne répondent plus à AX : pid -> date de reprise.
/// Une application est mise de côté 5 s après `kAXErrorCannotComplete` (erreur rendue aussi en
/// cas de délai dépassé). Pendant ce temps, aucun appel AX ne lui est envoyé et ses fenêtres
/// gardent leur dernier état connu. Chaque chemin abandonne au premier échec pour ce pid :
/// une application gelée coûte au plus un délai (0,5 s) par période de mise de côté.
public final class AXUnresponsiveApps: @unchecked Sendable {
    public static let shared = AXUnresponsiveApps()
    public static let quarantineDuration: TimeInterval = 5

    private let lock = NSLock()
    private var resumeAt: [pid_t: Date] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Vrai si l'application est mise de côté. O(1).
    public func isQuarantined(_ pid: pid_t) -> Bool {
        lock.withLock {
            guard let date = resumeAt[pid] else { return false }
            if now() < date { return true }
            resumeAt[pid] = nil
            return false
        }
    }

    func markUnresponsive(_ pid: pid_t) {
        lock.withLock { resumeAt[pid] = now().addingTimeInterval(Self.quarantineDuration) }
    }

    /// Enregistre le résultat d'un appel AX. Retourne vrai si l'appel a échoué par délai ou
    /// absence de réponse : l'application est alors mise de côté et l'appelant doit abandonner.
    @discardableResult
    func noteResult(_ error: AXError, pid: pid_t) -> Bool {
        guard error == .cannotComplete else { return false }
        markUnresponsive(pid)
        return true
    }
}

// MARK: - Attributs AX d'une fenêtre (SPEC-016 FR-022, research R4)

/// Attributs fixés à la création de la fenêtre : seuls ceux-ci vont dans le cache.
/// `fullscreenButtonEnabled` fait partie des boutons : il distingue un dialog d'une fenêtre.
struct AXStableWindowAttributes: Equatable, Sendable {
    var role: String?
    var subrole: String?
    var hasCloseButton = false
    var hasFullscreenButton = false
    var fullscreenButtonEnabled = false
    var hasMinimizeButton = false
    var hasZoomButton = false
    var isResizable = true
}

/// Attributs d'état, relus à chaque snapshot.
struct AXVolatileWindowAttributes: Equatable, Sendable {
    var isFocused = false
    var isMain = false
    var isModal = false
    var isNativeFullscreen = false
}

/// Lecture brute des attributs d'état : nil = illisible (à distinguer de false = faux ou absent).
struct AXVolatileReading: Equatable, Sendable {
    var isFocused: Bool?
    var isMain: Bool?
    var isModal: Bool?
    var isNativeFullscreen: Bool?

    /// Un attribut illisible garde sa dernière valeur connue, faux à défaut.
    func resolved(lastKnown: AXVolatileWindowAttributes?) -> AXVolatileWindowAttributes {
        let fallback = lastKnown ?? AXVolatileWindowAttributes()
        return AXVolatileWindowAttributes(
            isFocused: isFocused ?? fallback.isFocused,
            isMain: isMain ?? fallback.isMain,
            isModal: isModal ?? fallback.isModal,
            isNativeFullscreen: isNativeFullscreen ?? fallback.isNativeFullscreen
        )
    }
}

struct AXWindowAttributes: Equatable, Sendable {
    var stable: AXStableWindowAttributes
    var volatile: AXVolatileWindowAttributes

    var furniture: WindowFurniture {
        WindowFurniture(
            hasCloseButton: stable.hasCloseButton,
            hasFullscreenButton: stable.hasFullscreenButton,
            fullscreenButtonEnabled: stable.fullscreenButtonEnabled,
            hasMinimizeButton: stable.hasMinimizeButton,
            hasZoomButton: stable.hasZoomButton,
            isFocused: volatile.isFocused,
            isMain: volatile.isMain,
            isModal: volatile.isModal,
            isResizable: stable.isResizable,
            isNativeFullscreen: volatile.isNativeFullscreen
        )
    }
}

/// Interprétation des valeurs rendues par `AXUIElementCopyMultipleAttributeValues`.
enum AXReadValue {
    /// Erreur portée par la valeur (AXValue de type `.axError`), nil si c'est une vraie valeur.
    static func embeddedError(_ raw: AnyObject) -> AXError? {
        guard CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = raw as! AXValue // Safe : CFTypeID vérifié
        guard AXValueGetType(value) == .axError else { return nil }
        var error = AXError.success
        return AXValueGetValue(value, .axError, &error) ? error : .failure
    }

    /// Vrai si l'erreur signifie « attribut absent » (lecture valide) plutôt que « illisible ».
    static func meansAbsent(_ error: AXError) -> Bool {
        error == .attributeUnsupported || error == .noValue
    }

    /// Booléen lu : nil si illisible, false si absent.
    static func flag(_ raw: AnyObject) -> Bool? {
        if let error = embeddedError(raw) { return meansAbsent(error) ? false : nil }
        return (raw as? Bool) ?? false
    }
}

/// Cache des attributs AX par fenêtre, partagé par toutes les instances du provider d'un
/// processus pour que l'observer AX puisse l'invalider. Garde aussi le dernier état complet
/// connu, servi tant que l'application est mise de côté.
final class AXAttributeCache: @unchecked Sendable {
    static let shared = AXAttributeCache()
    /// Âge minimal avant mise en cache : une fenêtre neuve n'expose pas toujours tous ses boutons.
    static let minimumAge: TimeInterval = 0.5

    private struct Entry {
        var firstSeen: Date
        var stable: AXStableWindowAttributes?
        var stableFetchedAt = Date.distantPast
        var lastKnown: AXWindowAttributes?
    }

    private let lock = NSLock()
    private var entries: [CGWindowID: Entry] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Attributs stables en cache, nil si absents ou expirés (l'entrée expirée est retirée). O(1).
    func stableAttributes(for id: CGWindowID, ttl: TimeInterval) -> AXStableWindowAttributes? {
        lock.withLock {
            guard let entry = entries[id], let stable = entry.stable else { return nil }
            guard now().timeIntervalSince(entry.stableFetchedAt) < ttl else {
                entries[id]?.stable = nil
                return nil
            }
            return stable
        }
    }

    /// Dernier état complet connu. O(1).
    func lastKnown(for id: CGWindowID) -> AXWindowAttributes? {
        lock.withLock { entries[id]?.lastKnown }
    }

    /// Enregistre l'état lu. La partie stable n'entre en cache que si elle vient d'être lue
    /// et si la fenêtre est connue depuis au moins `minimumAge`. O(1).
    func record(_ attributes: AXWindowAttributes, for id: CGWindowID, stableIsFresh: Bool) {
        lock.withLock {
            let date = now()
            var entry = entries[id] ?? Entry(firstSeen: date)
            entry.lastKnown = attributes
            if stableIsFresh, entry.stable == nil, date.timeIntervalSince(entry.firstSeen) >= Self.minimumAge {
                entry.stable = attributes.stable
                entry.stableFetchedAt = date
            }
            entries[id] = entry
        }
    }

    /// Oublie les attributs stables. Garde l'âge et le dernier état connu des fenêtres. O(n).
    func invalidate() {
        lock.withLock {
            for id in entries.keys { entries[id]?.stable = nil }
        }
    }

    /// Retire les fenêtres absentes du dernier snapshot. O(n).
    func retain(only ids: Set<CGWindowID>) {
        lock.withLock { entries = entries.filter { ids.contains($0.key) } }
    }
}

/// Fenêtres AX d'une application, lues en une seule énumération `kAXWindows`.
struct AXApplicationWindows {
    let pid: pid_t
    /// Éléments dans l'ordre AX, avec leur CGWindowID quand AX le donne.
    let entries: [(id: CGWindowID?, element: AXUIElement)]
    private let byID: [CGWindowID: AXUIElement]

    /// nil si l'application est mise de côté, ne répond pas ou refuse l'énumération. O(m).
    init?(pid: pid_t) {
        let registry = AXUnresponsiveApps.shared
        guard !registry.isQuarantined(pid) else { return nil }
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(AXMessaging.application(pid), kAXWindowsAttribute as CFString, &raw)
        registry.noteResult(error, pid: pid)
        guard error == .success, let windows = raw as? [AXUIElement] else { return nil }

        var entries: [(id: CGWindowID?, element: AXUIElement)] = []
        var byID: [CGWindowID: AXUIElement] = [:]
        for element in windows {
            var id = CGWindowID()
            let idError = AXUIElementGetWindowID(element, &id)
            if registry.noteResult(idError, pid: pid) { return nil }
            let windowID: CGWindowID? = idError == .success && id > 0 ? id : nil
            if let windowID { byID[windowID] = element }
            entries.append((windowID, element))
        }
        self.pid = pid
        self.entries = entries
        self.byID = byID
    }

    func element(id: CGWindowID) -> AXUIElement? {
        byID[id]
    }
}

// MARK: - Provider

public final class LiveSystemSnapshotProvider: SystemSnapshotProviding, @unchecked Sendable {
    /// TTL des attributs stables en cache. Au-dela on relit AX (filet de securite si une
    /// notification AX a manque). Le cache lui-meme est `AXAttributeCache.shared`.
    private let cacheTTL: TimeInterval

    public init(cacheTTL: TimeInterval = 600) {
        self.cacheTTL = cacheTTL
    }

    /// Vide le cache des attributs stables. Appele aussi par `AXWindowEventObserver`.
    public func invalidateCache() {
        AXAttributeCache.shared.invalidate()
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

    // O(n + Σm) : n fenetres CG, une enumeration kAXWindows (m elements) par application.
    public func windows() -> [WindowSnapshot] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        // Fenetres AX par application pour ce snapshot (nil memorise = application illisible).
        var appWindows: [pid_t: AXApplicationWindows?] = [:]

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

            // Multi-process roadied (SPEC-011 atomique) : un BorderController dans le
            // process A ne doit pas considerer le RailPanel d'un process B comme une
            // fenetre etrangere occluante. Le filtre pid!=currentPID ne suffit plus
            // quand rail/border/tiler tournent dans des process separes ; on filtre
            // par appName + bundleID pour exclure toute fenetre appartenant a un
            // process roadied, quelque soit son PID.
            if appName == "roadied" || appName == "roadie" {
                return nil
            }
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

            let attrs = tileCandidate ? attributes(forCGWindowID: number, pid: pid, appWindows: &appWindows) : nil

            return WindowSnapshot(
                id: WindowID(rawValue: number),
                pid: pid,
                appName: appName,
                bundleID: bundleID,
                title: title,
                frame: Rect(rect),
                isOnScreen: true,
                isTileCandidate: tileCandidate,
                subrole: attrs?.stable.subrole,
                role: attrs?.stable.role,
                furniture: attrs?.furniture
            )
        }

        AXAttributeCache.shared.retain(only: Set(result.map { $0.id.rawValue }))
        return result
    }

    /// Attributs AX d'une fenetre : partie stable depuis le cache, etat relu a chaque appel.
    /// Application mise de cote ou illisible pendant la lecture : dernier etat connu.
    /// Retourne nil si AX n'a jamais pu repondre (app sandboxee, autorisations manquantes).
    private func attributes(
        forCGWindowID id: CGWindowID,
        pid: pid_t,
        appWindows: inout [pid_t: AXApplicationWindows?]
    ) -> AXWindowAttributes? {
        let cache = AXAttributeCache.shared
        let registry = AXUnresponsiveApps.shared
        guard !registry.isQuarantined(pid) else { return cache.lastKnown(for: id) }

        let index: AXApplicationWindows?
        if let memo = appWindows[pid] {
            index = memo
        } else {
            index = AXApplicationWindows(pid: pid)
            appWindows.updateValue(index, forKey: pid)
        }
        let lastKnown = cache.lastKnown(for: id)
        guard let element = index?.element(id: id) else {
            return registry.isQuarantined(pid) ? lastKnown : nil
        }
        guard let reading = Self.readVolatile(element, pid: pid) else { return lastKnown }

        let cached = cache.stableAttributes(for: id, ttl: cacheTTL)
        let fresh = cached == nil ? Self.readStable(element, pid: pid) : nil
        guard let stable = cached ?? fresh ?? lastKnown?.stable else { return nil }
        let attrs = AXWindowAttributes(stable: stable, volatile: reading.resolved(lastKnown: lastKnown?.volatile))
        cache.record(attrs, for: id, stableIsFresh: fresh != nil)
        return attrs
    }

    private static let volatileAttributeNames: [String] = [
        kAXFocusedAttribute, kAXMainAttribute, kAXModalAttribute, "AXFullScreen",
    ]

    /// Relit les attributs d'etat en un seul aller-retour AX.
    /// nil si l'application ne repond pas (elle vient d'etre mise de cote).
    private static func readVolatile(_ element: AXUIElement, pid: pid_t) -> AXVolatileReading? {
        var raw: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element, volatileAttributeNames as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw
        )
        if AXUnresponsiveApps.shared.noteResult(error, pid: pid) { return nil }
        let values = error == .success ? (raw as? [AnyObject]) ?? [] : []
        func flag(_ index: Int) -> Bool? {
            index < values.count ? AXReadValue.flag(values[index]) : nil
        }
        return AXVolatileReading(isFocused: flag(0), isMain: flag(1), isModal: flag(2), isNativeFullscreen: flag(3))
    }

    private static let stableAttributeNames: [String] = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXCloseButtonAttribute,
        kAXFullScreenButtonAttribute, kAXMinimizeButtonAttribute, kAXZoomButtonAttribute,
    ]

    /// Lit les attributs stables en trois allers-retours AX. nil si une valeur est illisible :
    /// une lecture partielle ne doit pas entrer dans le cache.
    private static func readStable(_ element: AXUIElement, pid: pid_t) -> AXStableWindowAttributes? {
        let registry = AXUnresponsiveApps.shared
        var raw: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element, stableAttributeNames as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw
        )
        registry.noteResult(error, pid: pid)
        guard error == .success, let values = raw as? [AnyObject], values.count == stableAttributeNames.count else {
            return nil
        }
        var unreadable = false
        func value(_ index: Int) -> AnyObject? {
            let raw = values[index]
            guard let error = AXReadValue.embeddedError(raw) else { return raw }
            if !AXReadValue.meansAbsent(error) { unreadable = true }
            return nil
        }
        func isElement(_ raw: AnyObject?) -> Bool {
            raw.map { CFGetTypeID($0) == AXUIElementGetTypeID() } ?? false
        }
        let role = value(0) as? String
        let subrole = value(1) as? String
        let closeButton = value(2)
        let fullscreenButton = value(3)
        let minimizeButton = value(4)
        let zoomButton = value(5)
        guard !unreadable else { return nil }

        var fullscreenEnabled = false
        if isElement(fullscreenButton) {
            var rawEnabled: CFTypeRef?
            let enabledError = AXUIElementCopyAttributeValue(
                fullscreenButton as! AXUIElement, kAXEnabledAttribute as CFString, &rawEnabled // Safe : isElement
            )
            if registry.noteResult(enabledError, pid: pid) { return nil }
            fullscreenEnabled = enabledError == .success && (rawEnabled as? Bool) == true
        }
        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable)
        if registry.noteResult(settableError, pid: pid) { return nil }

        return AXStableWindowAttributes(
            role: role,
            subrole: subrole,
            hasCloseButton: isElement(closeButton),
            hasFullscreenButton: isElement(fullscreenButton),
            fullscreenButtonEnabled: fullscreenEnabled,
            hasMinimizeButton: isElement(minimizeButton),
            hasZoomButton: isElement(zoomButton),
            isResizable: settableError == .success && settable.boolValue
        )
    }

    public func focusedWindowID() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let registry = AXUnresponsiveApps.shared
        guard !registry.isQuarantined(pid) else { return nil }
        var rawFocused: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(AXMessaging.application(pid), kAXFocusedWindowAttribute as CFString, &rawFocused)
        registry.noteResult(error, pid: pid)
        guard error == .success,
              let focused = rawFocused,
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }

        let focusedElement = focused as! AXUIElement // Safe: CFTypeID verified above
        // Voie rapide : si AX donne directement le windowID, on retourne sans appel a windows().
        var id = CGWindowID()
        let idError = AXUIElementGetWindowID(focusedElement, &id)
        if registry.noteResult(idError, pid: pid) { return nil }
        if idError == .success, id > 0 {
            return WindowID(rawValue: id)
        }

        // Voie lente : on enumere uniquement les fenetres de l'app courante (CG seul, pas AX).
        // Repli par cadre ou par titre seulement si une seule fenetre correspond.
        let appWindows = lightweightWindows(forPID: pid)
        let writer = AXWindowFrameWriter()
        if let focusedFrame = writer.frame(of: focusedElement, pid: pid) {
            let frameMatches = appWindows.filter { framesAreClose(focusedFrame, $0.frame) }
            if frameMatches.count == 1 { return frameMatches[0].id }
        }
        guard !registry.isQuarantined(pid) else { return nil }

        let focusedTitle = writer.title(of: focusedElement, pid: pid)
        let titleMatches = appWindows.filter { !focusedTitle.isEmpty && $0.title == focusedTitle }
        return titleMatches.count == 1 ? titleMatches.first?.id : nil
    }

    public func mouseLocation() -> CGPoint? {
        NSEvent.mouseLocation
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

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        AXWindowFrameWriter.isClose(lhs, Rect(rhs))
    }
}

// MARK: - Ecriture

public struct AXWindowFrameWriter: WindowFrameWriting {
    /// Ecart maximal pour reconnaitre une fenetre par son cadre quand l'ID AX manque.
    static let frameMatchTolerance: CGFloat = 48

    public init() {}

    public func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        setFrames([WindowFrameUpdate(window: window, frame: frame)])[window.id] ?? nil
    }

    // O(n + Σm) : regroupement par pid, une enumeration kAXWindows (m elements) par application,
    // puis resolution par ID en O(1). Le repli par cadre/titre, en O(m), reste l'exception.
    public func setFrames(_ updates: [WindowFrameUpdate]) -> [WindowID: CGRect?] {
        var results: [WindowID: CGRect?] = [:]
        let reserved = Set(updates.map { $0.window.id.rawValue })
        let registry = AXUnresponsiveApps.shared
        for (pid, group) in Dictionary(grouping: updates, by: { $0.window.pid }) {
            let appWindows = AXApplicationWindows(pid: pid)
            for update in group {
                var applied: CGRect?
                if let appWindows, !registry.isQuarantined(pid),
                   let element = element(in: appWindows, window: update.window, reserved: reserved) {
                    applied = set(update.frame, on: element, pid: pid)
                }
                results.updateValue(applied, forKey: update.window.id)
            }
        }
        return results
    }

    public func focus(_ window: WindowSnapshot) -> Bool {
        guard let appWindows = AXApplicationWindows(pid: window.pid),
              let element = element(in: appWindows, window: window)
        else { return false }
        return focus(element, pid: window.pid)
    }

    public func focusApplicationWindow(bundleID: String, windowID: WindowID, title: String, frame: Rect) -> Bool {
        for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            let pid = application.processIdentifier
            guard let appWindows = AXApplicationWindows(pid: pid),
                  let element = element(in: appWindows, id: windowID, title: title, frame: frame)
            else { continue }
            return focus(element, pid: pid)
        }
        return false
    }

    public func activateApplication(bundleID: String) -> Bool {
        guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return false
        }
        // activate() est cooperatif depuis macOS 14 et peut etre refuse a un daemon :
        // kAXFrontmostAttribute rend l'activation fiable.
        let activated = application.activate()
        return setFrontmost(pid: application.processIdentifier) || activated
    }

    public func reset(_ window: WindowSnapshot) -> Bool {
        toggleZoom(window)
    }

    public func toggleZoom(_ window: WindowSnapshot) -> Bool {
        press(kAXZoomButtonAttribute, of: window)
    }

    public func toggleNativeFullscreen(_ window: WindowSnapshot) -> Bool {
        press(kAXFullScreenButtonAttribute, of: window)
    }

    private func press(_ buttonAttribute: String, of window: WindowSnapshot) -> Bool {
        let pid = window.pid
        guard let appWindows = AXApplicationWindows(pid: pid),
              let element = element(in: appWindows, window: window),
              let button = elementAttribute(element, buttonAttribute, pid: pid)
        else { return false }
        let error = AXUIElementPerformAction(button, kAXPressAction as CFString)
        AXUnresponsiveApps.shared.noteResult(error, pid: pid)
        return error == .success
    }

    /// Active l'application puis met la fenetre devant. Une seule activation : `activate()`
    /// (sans option ignoree depuis macOS 14) puis kAXFrontmostAttribute avant AXRaise.
    /// Abandonne au premier delai depasse.
    private func focus(_ element: AXUIElement, pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activate()
        _ = setFrontmost(pid: pid)
        let registry = AXUnresponsiveApps.shared
        guard !registry.isQuarantined(pid) else { return false }
        let app = AXMessaging.application(pid)
        if registry.noteResult(AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, element), pid: pid) {
            return false
        }
        return !registry.noteResult(AXUIElementPerformAction(element, kAXRaiseAction as CFString), pid: pid)
    }

    private func setFrontmost(pid: pid_t) -> Bool {
        let registry = AXUnresponsiveApps.shared
        guard !registry.isQuarantined(pid) else { return false }
        let error = AXUIElementSetAttributeValue(
            AXMessaging.application(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue as CFTypeRef
        )
        registry.noteResult(error, pid: pid)
        return error == .success
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String, pid: pid_t) -> AXUIElement? {
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
        AXUnresponsiveApps.shared.noteResult(error, pid: pid)
        guard error == .success, let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private func element(in appWindows: AXApplicationWindows, window: WindowSnapshot, reserved: Set<CGWindowID> = []) -> AXUIElement? {
        element(in: appWindows, id: window.id, title: window.title, frame: window.frame, reserved: reserved)
    }

    // O(1) si l'ID est connu d'AX, O(m) pour le repli. Priorite : ID exact > cadre unique > titre unique.
    // Le repli ignore les elements dont l'ID est vise ailleurs dans le meme lot. Pas de repli
    // par cadre pour un cadre nul ni quand plusieurs fenetres correspondent (SPEC-016 C4).
    private func element(
        in appWindows: AXApplicationWindows,
        id: WindowID,
        title: String,
        frame: Rect,
        reserved: Set<CGWindowID> = []
    ) -> AXUIElement? {
        if let exact = appWindows.element(id: id.rawValue) { return exact }
        let pid = appWindows.pid
        let registry = AXUnresponsiveApps.shared
        let candidates = appWindows.entries
            .filter { entry in entry.id.map { !reserved.contains($0) } ?? true }
            .map(\.element)

        if frame.width > 0, frame.height > 0 {
            var frameMatches: [AXUIElement] = []
            for candidate in candidates {
                if let actual = self.frame(of: candidate, pid: pid), Self.isClose(actual, frame) {
                    frameMatches.append(candidate)
                }
                if registry.isQuarantined(pid) { return nil }
            }
            if frameMatches.count == 1 { return frameMatches[0] }
        }

        guard !title.isEmpty else { return nil }
        var titleMatches: [AXUIElement] = []
        for candidate in candidates {
            if self.title(of: candidate, pid: pid) == title { titleMatches.append(candidate) }
            if registry.isQuarantined(pid) { return nil }
        }
        return titleMatches.count == 1 ? titleMatches[0] : nil
    }

    static func isClose(_ actual: CGRect, _ expected: Rect) -> Bool {
        abs(actual.minX - expected.x) < frameMatchTolerance
            && abs(actual.minY - expected.y) < frameMatchTolerance
            && abs(actual.width - expected.width) < frameMatchTolerance
            && abs(actual.height - expected.height) < frameMatchTolerance
    }

    func title(of element: AXUIElement, pid: pid_t) -> String {
        var rawTitle: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &rawTitle)
        AXUnresponsiveApps.shared.noteResult(error, pid: pid)
        guard error == .success, let title = rawTitle as? String else { return "" }
        return title
    }

    /// Position, taille puis position (la seconde position corrige une taille bornee par
    /// l'ancien ecran), sans pause, puis une seule relecture du cadre. Arret au premier echec.
    private func set(_ frame: CGRect, on element: AXUIElement, pid: pid_t) -> CGRect? {
        var position = CGPoint(x: frame.minX, y: frame.minY)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let axPosition = AXValueCreate(.cgPoint, &position),
              let axSize = AXValueCreate(.cgSize, &size)
        else { return nil }

        let registry = AXUnresponsiveApps.shared
        for (attribute, value) in [(kAXPositionAttribute, axPosition), (kAXSizeAttribute, axSize), (kAXPositionAttribute, axPosition)] {
            let error = AXUIElementSetAttributeValue(element, attribute as CFString, value)
            registry.noteResult(error, pid: pid)
            guard error == .success else { return nil }
        }
        return self.frame(of: element, pid: pid)
    }

    public func frame(of element: AXUIElement) -> CGRect? {
        frame(of: element, pid: nil)
    }

    /// Lit le cadre AX. Avec un pid, un delai depasse met l'application de cote et arrete la lecture.
    func frame(of element: AXUIElement, pid: pid_t?) -> CGRect? {
        let registry = AXUnresponsiveApps.shared
        var rawPosition: CFTypeRef?
        let positionError = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &rawPosition)
        if let pid { registry.noteResult(positionError, pid: pid) }
        guard positionError == .success else { return nil }
        var rawSize: CFTypeRef?
        let sizeError = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &rawSize)
        if let pid { registry.noteResult(sizeError, pid: pid) }
        guard sizeError == .success,
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
