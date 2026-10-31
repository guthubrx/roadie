import AppKit
import CoreGraphics
import RoadieCore

@_silgen_name("_AXUIElementGetWindow")
func AXUIElementGetWindowID(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

public protocol SystemSnapshotProviding: Sendable {
    func permissions(prompt: Bool) -> PermissionSnapshot
    func displays() -> [DisplaySnapshot]
    func windows() -> [WindowSnapshot]
    /// Identités CG existantes, y compris sur les Spaces inactifs ; nil si indisponible.
    func existingWindowPIDs() -> [WindowID: Int32]?
    func focusedWindowID() -> WindowID?
    /// Capture sur MainActor le contexte AppKit, puis effectue seulement la lecture AX en arrière-plan.
    @MainActor func focusedWindowReader() -> @Sendable () -> WindowID?
    func mouseLocation() -> CGPoint?
}

public extension SystemSnapshotProviding {
    func existingWindowPIDs() -> [WindowID: Int32]? { nil }
    func focusedWindowID() -> WindowID? { nil }
    @MainActor func focusedWindowReader() -> @Sendable () -> WindowID? { { self.focusedWindowID() } }
    func mouseLocation() -> CGPoint? { nil }
}

public protocol WindowFrameWriting: Sendable {
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect?
    /// Écriture directe d'une fenêtre avec la génération de placement de l'appelant (A13, T213) :
    /// elle compte au budget de cette génération comme une écriture groupée.
    func setFrame(_ frame: CGRect, of window: WindowSnapshot, generation: UInt64) -> CGRect?
    func setFrames(_ updates: [WindowFrameUpdate]) -> [WindowID: CGRect?]
    /// `generation` : génération de placement globale et monotone, transmise au registre des
    /// frames écrites (budget de 2 écritures par fenêtre et par génération, A2).
    func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64) -> [WindowID: CGRect?]
    /// Lot interactif révocable : la permission est revérifiée entre les appels AX.
    func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64,
                   isCurrent: @Sendable () -> Bool) -> [WindowID: CGRect?]
    /// Lecture AX fraîche du cadre (seconde observation d'un refus, A14). nil si illisible.
    func readFrame(of window: WindowSnapshot) -> CGRect?
    func focus(_ window: WindowSnapshot) -> Bool
    func focusOnOtherSpace(_ window: WindowSnapshot, timeout: TimeInterval) -> SpaceFocusOutcome
    func focusApplicationWindow(bundleID: String, windowID: WindowID, title: String, frame: Rect) -> Bool
    func activateApplication(bundleID: String) -> Bool
    func reset(_ window: WindowSnapshot) -> Bool
    func toggleZoom(_ window: WindowSnapshot) -> Bool
    func toggleNativeFullscreen(_ window: WindowSnapshot) -> Bool
}

public extension WindowFrameWriting {
    /// Écrivains sans registre (doubles de test) : la génération est ignorée.
    func setFrame(_ frame: CGRect, of window: WindowSnapshot, generation: UInt64) -> CGRect? {
        setFrame(frame, of: window)
    }

    func setFrames(_ updates: [WindowFrameUpdate]) -> [WindowID: CGRect?] {
        var results: [WindowID: CGRect?] = [:]
        for update in updates {
            results[update.window.id] = setFrame(update.frame, of: update.window)
        }
        return results
    }

    /// Écrivains sans registre (doubles de test) : la génération est ignorée.
    func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64) -> [WindowID: CGRect?] {
        setFrames(updates)
    }

    func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64,
                   isCurrent: @Sendable () -> Bool) -> [WindowID: CGRect?] {
        guard isCurrent() else { return [:] }
        return setFrames(updates, generation: generation)
    }

    func readFrame(of window: WindowSnapshot) -> CGRect? { nil }
    func focus(_ window: WindowSnapshot) -> Bool { false }
    func focusOnOtherSpace(_ window: WindowSnapshot, timeout: TimeInterval) -> SpaceFocusOutcome {
        SpaceFocusOutcome(opened: false, focused: false, waitedMs: 0)
    }
    func focusApplicationWindow(bundleID: String, windowID: WindowID, title: String, frame: Rect) -> Bool { false }
    func activateApplication(bundleID: String) -> Bool { false }
    func reset(_ window: WindowSnapshot) -> Bool { false }
    func toggleZoom(_ window: WindowSnapshot) -> Bool { reset(window) }
    func toggleNativeFullscreen(_ window: WindowSnapshot) -> Bool { false }
}

/// Résultat de `focusOnOtherSpace` : ouverture demandée, élément trouvé par jeton distant, focus obtenu,
/// attente totale.
public struct SpaceFocusOutcome: Sendable, Equatable {
    public var opened: Bool
    public var remote = false
    public var focused: Bool
    public var waitedMs: Int

    public init(opened: Bool, focused: Bool, waitedMs: Int) {
        self.opened = opened
        self.focused = focused
        self.waitedMs = waitedMs
    }
}

public struct WindowFrameUpdate: Sendable {
    public var window: WindowSnapshot
    public var frame: CGRect
    /// Position seule : garer une fenêtre ne doit jamais changer sa taille, même si le cadre
    /// observé était transitoire (Mission Control réduit les cadres rapportés). SPEC-062.
    public var preservesSize: Bool
    /// Première disposition : rejoindre la destination avant de grandir sur l'écran de naissance.
    public var positionsBeforeResizing: Bool

    public init(window: WindowSnapshot, frame: CGRect, preservesSize: Bool = false,
                positionsBeforeResizing: Bool = false) {
        self.window = window
        self.frame = frame
        self.preservesSize = preservesSize
        self.positionsBeforeResizing = positionsBeforeResizing
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

    /// Enregistre le résultat d'un appel AX et retourne vrai seulement s'il a réussi. Toute autre
    /// erreur (failure, invalidUIElement, actionUnsupported, délai) est un échec pour l'appelant ;
    /// seul le délai met l'application de côté (REL-010).
    func noteSucceeded(_ error: AXError, pid: pid_t) -> Bool {
        noteResult(error, pid: pid)
        return error == .success
    }
}

/// Décision de réussite d'un focus (REL-010). Un focus n'est annoncé réussi que si l'application
/// est devant, que la fenêtre est la fenêtre focalisée de l'application et que la montée au premier
/// plan a réussi. Une écriture AX en échec reste acceptée seulement si la relecture la confirme.
enum AXFocusDecision {
    // O(1).
    static func succeeded(
        frontmost: AXError,
        appIsActive: Bool,
        focusedWindow: AXError,
        focusedWindowConfirmed: Bool,
        raise: AXError
    ) -> Bool {
        raise == .success
            && (frontmost == .success || appIsActive)
            && (focusedWindow == .success || focusedWindowConfirmed)
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

    /// Passe chaque erreur portée par une valeur du résultat par le registre : un
    /// `.cannotComplete` intégré met l'application de côté comme un échec de l'appel entier.
    /// Retourne vrai si l'application est mise de côté. O(n), n = nombre de valeurs.
    static func noteEmbeddedErrors(
        in values: [AnyObject], pid: pid_t, registry: AXUnresponsiveApps
    ) -> Bool {
        var aside = false
        for raw in values {
            if let error = embeddedError(raw), registry.noteResult(error, pid: pid) { aside = true }
        }
        return aside
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
        var pid: pid_t
        var firstSeen: Date
        var stable: AXStableWindowAttributes?
        var stableFetchedAt = Date.distantPast
        var lastKnown: AXWindowAttributes?
    }

    private let lock = NSLock()
    private var entries: [CGWindowID: Entry] = [:]
    private var generation: UInt64 = 0
    func beginSnapshot() -> UInt64 { lock.withLock { generation &+= 1; return generation } }
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
    func record(_ attributes: AXWindowAttributes, for id: CGWindowID, pid: pid_t, stableIsFresh: Bool, generation expected: UInt64? = nil) {
        lock.withLock {
            guard expected == nil || expected == generation else { return }
            let date = now()
            var entry = entries[id] ?? Entry(pid: pid, firstSeen: date)
            entry.lastKnown = attributes
            if stableIsFresh, entry.stable == nil, date.timeIntervalSince(entry.firstSeen) >= Self.minimumAge {
                entry.stable = attributes.stable
                entry.stableFetchedAt = date
            }
            entries[id] = entry
        }
    }

    /// Oublie les attributs stables des fenêtres d'une application. Garde l'âge et le dernier
    /// état connu des fenêtres. O(n).
    func invalidate(pid: pid_t) {
        lock.withLock {
            generation &+= 1
            for (id, entry) in entries where entry.pid == pid { entries[id]?.stable = nil }
        }
    }

    /// Retire les fenêtres absentes du dernier snapshot. O(n).
    func retain(only ids: Set<CGWindowID>, generation expected: UInt64? = nil) {
        lock.withLock {
            guard expected == nil || expected == generation else { return }
            entries = entries.filter { ids.contains($0.key) }
        }
    }
}

/// Fenêtres AX d'une application, lues en une seule énumération `kAXWindows`.
struct AXApplicationWindows {
    let pid: pid_t
    /// Éléments dans l'ordre AX, avec leur CGWindowID quand AX le donne.
    let entries: [(id: CGWindowID?, element: AXUIElement)]
    private let byID: [CGWindowID: AXUIElement]

    /// nil si l'application est mise de côté, ne répond pas ou refuse l'énumération. O(m).
    init?(pid: pid_t, requiredWindowIDs: Set<CGWindowID>? = nil) {
        let registry = AXUnresponsiveApps.shared
        guard !registry.isQuarantined(pid) else { return nil }
        var raw: CFTypeRef?
        let error = AXCallTimings.shared.measure(pid) {
            AXUIElementCopyAttributeValue(AXMessaging.application(pid), kAXWindowsAttribute as CFString, &raw)
        }
        registry.noteResult(error, pid: pid)
        guard error == .success, let windows = raw as? [AXUIElement] else { return nil }

        var entries: [(id: CGWindowID?, element: AXUIElement)] = []
        for element in windows {
            var id = CGWindowID()
            let idError = AXUIElementGetWindowID(element, &id)
            if registry.noteResult(idError, pid: pid) { return nil }
            entries.append((idError == .success && id > 0 ? id : nil, element))
        }
        func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            guard !registry.isQuarantined(pid) else { return nil }
            var raw: CFTypeRef?
            let error = AXCallTimings.shared.measure(pid) { AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) }
            registry.noteResult(error, pid: pid)
            return error == .success ? raw : nil
        }
        let attached = Self.attachedWindowEntries(roots: entries,
            children: { value($0, kAXChildrenAttribute) as? [AXUIElement] ?? [] },
            identifier: { element in
                guard !registry.isQuarantined(pid) else { return nil }
                var id = CGWindowID()
                let error = AXUIElementGetWindowID(element, &id)
                registry.noteResult(error, pid: pid)
                return error == .success && id > 0 ? id : nil
            }, isSheet: { value($0, kAXRoleAttribute) as? String == kAXSheetRole }, requiredWindowIDs: requiredWindowIDs)
        guard !registry.isQuarantined(pid) else { return nil }
        self.init(pid: pid, entries: entries + attached)
    }

    /// Une feuille peut héberger son contenu dans un autre CGWindow (service XPC AppKit).
    /// Ces identités appartiennent à la feuille ; les contrôles de la fenêtre principale
    /// ne deviennent pas des fenêtres. O(r + c), c borné à 256 éléments, profondeur 4.
    static func attachedWindowEntries(
        roots: [(id: CGWindowID?, element: AXUIElement)],
        children: (AXUIElement) -> [AXUIElement],
        identifier: (AXUIElement) -> CGWindowID?,
        isSheet: (AXUIElement) -> Bool,
        requiredWindowIDs: Set<CGWindowID>? = nil
    ) -> [(id: CGWindowID?, element: AXUIElement)] {
        var result: [(id: CGWindowID?, element: AXUIElement)] = []
        var seen = Set(roots.compactMap(\.id))
        // Les fenêtres déjà résolues ne nécessitent aucune lecture de leurs contrôles.
        // nil conserve la découverte complète pour les autres appelants (cibles, écrivain).
        if let requiredWindowIDs, requiredWindowIDs.isSubset(of: seen) { return [] }
        var remaining = 256
        for root in roots {
            guard remaining > 0 else { return result }
            for child in children(root.element).prefix(remaining) {
                guard remaining > 0 else { return result }
                remaining -= 1
                let childID = identifier(child)
                guard childID == nil || childID != root.id, isSheet(child) else { continue }
                if let childID, seen.insert(childID).inserted { result.append((childID, child)) }
                var pending: [(AXUIElement, Int)] = [(child, 0)]
                while remaining > 0, let (node, depth) = pending.popLast() {
                    remaining -= 1
                    if let id = identifier(node), id != childID, id != root.id {
                        if seen.insert(id).inserted { result.append((id, child)) }
                        continue
                    }
                    if depth < 4 {
                        pending.append(contentsOf: children(node).prefix(remaining).map { ($0, depth + 1) })
                    }
                }
            }
        }
        return result
    }

    init(pid: pid_t, entries: [(id: CGWindowID?, element: AXUIElement)]) {
        self.pid = pid
        self.entries = entries
        var byID: [CGWindowID: AXUIElement] = [:]
        for entry in entries { if let id = entry.id { byID[id] = entry.element } }
        self.byID = byID
    }

    func element(id: CGWindowID) -> AXUIElement? {
        byID[id]
    }

    /// Vrai si l'index connaît toutes ces fenêtres (SPEC-051 A-02). O(k).
    func covers(_ ids: Set<CGWindowID>) -> Bool {
        ids.allSatisfy { byID[$0] != nil }
    }
}

/// Élément AX de chaque fenêtre d'une application, par CGWindowID (SPEC-021, cibles de toutes les
/// fenêtres visibles). Vide si l'application est mise de côté ou ne répond pas. O(m).
public func axWindowElements(pid: pid_t) -> [CGWindowID: AXUIElement] {
    guard let windows = AXApplicationWindows(pid: pid) else { return [:] }
    var elements: [CGWindowID: AXUIElement] = [:]
    for entry in windows.entries { if let id = entry.id { elements[id] = entry.element } }
    return elements
}

/// Index des fenêtres AX par application, posé par le dernier snapshot et réutilisé par
/// l'écrivain (SPEC-017 R8) : une écriture ne réénumère plus `kAXWindows`. Vidé pour un pid
/// à la création ou destruction d'une fenêtre, à la fin de l'application ou sur un élément
/// devenu invalide.
final class AXWindowIndexCache: @unchecked Sendable {
    static let shared = AXWindowIndexCache()

    private let lock = NSLock()
    private var byPID: [pid_t: AXApplicationWindows] = [:]
    private var generation: UInt64 = 0
    func beginSnapshot() -> UInt64 { lock.withLock { generation &+= 1; return generation } }

    func windows(for pid: pid_t) -> AXApplicationWindows? {
        lock.withLock { byPID[pid] }
    }

    func store(_ windows: AXApplicationWindows) {
        lock.withLock { generation &+= 1; byPID[windows.pid] = windows }
    }

    /// Remplace l'index par celui d'un snapshot complet : les applications absentes en sortent. O(p).
    func replaceAll(with windows: [AXApplicationWindows], generation expected: UInt64? = nil) {
        lock.withLock {
            guard expected == nil || expected == generation else { return }
            byPID = Dictionary(windows.map { ($0.pid, $0) }, uniquingKeysWith: { $1 })
        }
    }

    func invalidate(pid: pid_t) {
        lock.withLock { generation &+= 1; byPID[pid] = nil }
    }
}

/// Appels AX de l'écrivain, isolés pour l'écrivain espion des tests (SPEC-017 T035).
protocol AXFrameIO: Sendable {
    func enumerateWindows(pid: pid_t) -> AXApplicationWindows?
    func value(of attribute: String, on element: AXUIElement) -> (AXError, CFTypeRef?)
    func values(of attributes: [String], on element: AXUIElement) -> (AXError, [AnyObject])
    func setValue(_ value: CFTypeRef, of attribute: String, on element: AXUIElement) -> AXError
    func performAction(_ action: String, on element: AXUIElement) -> AXError
}

struct LiveAXFrameIO: AXFrameIO {
    func performAction(_ action: String, on element: AXUIElement) -> AXError {
        AXCallTimings.shared.measure(element) { AXUIElementPerformAction(element, action as CFString) }
    }

    func enumerateWindows(pid: pid_t) -> AXApplicationWindows? {
        AXApplicationWindows(pid: pid)
    }

    func value(of attribute: String, on element: AXUIElement) -> (AXError, CFTypeRef?) {
        var raw: CFTypeRef?
        let error = AXCallTimings.shared.measure(element) { AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) }
        return (error, raw)
    }

    func values(of attributes: [String], on element: AXUIElement) -> (AXError, [AnyObject]) {
        var raw: CFArray?
        let error = AXCallTimings.shared.measure(element) {
            AXUIElementCopyMultipleAttributeValues(
                element, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw
            )
        }
        return (error, error == .success ? (raw as? [AnyObject]) ?? [] : [])
    }

    func setValue(_ value: CFTypeRef, of attribute: String, on element: AXUIElement) -> AXError {
        AXCallTimings.shared.measure(element) { AXUIElementSetAttributeValue(element, attribute as CFString, value) }
    }
}

// MARK: - Provider

public final class LiveSystemSnapshotProvider: SystemSnapshotProviding {
    /// TTL des attributs stables en cache. Au-dela on relit AX (filet de securite si une
    /// notification AX a manque). Le cache lui-meme est `AXAttributeCache.shared`.
    private let cacheTTL: TimeInterval

    public init(cacheTTL: TimeInterval = 600) {
        self.cacheTTL = cacheTTL
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

    /// Présence CG seule : aucune lecture AX et aucune fenêtre ajoutée au placement. O(n).
    public func existingWindowPIDs() -> [WindowID: Int32]? {
        guard let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var owners: [WindowID: Int32] = [:]
        for info in raw {
            guard let number = info[kCGWindowNumber as String] as? UInt32, number > 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid > 0 else { continue }
            owners[WindowID(rawValue: number)] = pid
        }
        return owners
    }

    // O(n + Σm) : n fenetres CG, une enumeration kAXWindows (m elements) par application.
    public func windows() -> [WindowSnapshot] {
        // Un scan ancien ne peut publier après un événement AX ou un scan plus récent.
        let attributesGeneration = AXAttributeCache.shared.beginSnapshot()
        let indexGeneration = AXWindowIndexCache.shared.beginSnapshot()
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        // Fenetres AX par application pour ce snapshot (nil memorise = application illisible).
        var appWindows: [pid_t: AXApplicationWindows?] = [:]
        // SPEC-051 A-03 : une requête LaunchServices par application, pas par fenêtre CG.
        var bundleByPID: [pid_t: String] = [:]
        // O(n) : préparer toutes les cibles CG avant l'unique énumération AX par PID.
        // Sur-ensemble conservateur des candidats : aucune fenêtre attachée nécessaire oubliée.
        var requiredWindowIDs: [pid_t: Set<CGWindowID>] = [:]
        for info in raw {
            guard let id = info[kCGWindowNumber as String] as? UInt32, id > 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != currentPID,
                  (info[kCGWindowLayer as String] as? Int ?? 0) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= 80, rect.height >= 60
            else { continue }
            requiredWindowIDs[pid, default: []].insert(id)
        }

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
            let bundleID: String
            if let known = bundleByPID[pid] {
                bundleID = known
            } else {
                bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
                bundleByPID[pid] = bundleID
            }

            // isTileCandidate ne reflete plus que les criteres CG bruts. La policy
            // (AX subrole, regles user, exclusions bundle) est appliquee cote daemon.
            let tileCandidate = layer == 0
                && alpha > 0
                && rect.width >= 80
                && rect.height >= 60
                && !bundleID.hasPrefix("com.apple.WindowManager")

            let attrs = tileCandidate ? attributes(forCGWindowID: number, pid: pid, requiredWindowIDs: requiredWindowIDs[pid], appWindows: &appWindows, generation: attributesGeneration) : nil

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

        AXAttributeCache.shared.retain(only: Set(result.map { $0.id.rawValue }), generation: attributesGeneration)
        AXWindowIndexCache.shared.replaceAll(with: appWindows.values.compactMap { $0 }, generation: indexGeneration)
        return result
    }

    /// Index réutilisable : connu et couvrant toutes les fenêtres demandées (non vides). O(k).
    static func reusableIndex(_ cached: AXApplicationWindows?, required: Set<CGWindowID>?) -> AXApplicationWindows? {
        guard let cached, let required, !required.isEmpty, cached.covers(required) else { return nil }
        return cached
    }

    /// Attributs AX d'une fenetre : partie stable depuis le cache, etat relu a chaque appel.
    /// Application mise de cote ou illisible pendant la lecture : dernier etat connu.
    /// Retourne nil si AX n'a jamais pu repondre (app sandboxee, autorisations manquantes).
    private func attributes(
        forCGWindowID id: CGWindowID,
        pid: pid_t,
        requiredWindowIDs: Set<CGWindowID>?,
        appWindows: inout [pid_t: AXApplicationWindows?],
        generation: UInt64
    ) -> AXWindowAttributes? {
        let cache = AXAttributeCache.shared
        let registry = AXUnresponsiveApps.shared
        guard !registry.isQuarantined(pid) else { return cache.lastKnown(for: id) }

        let index: AXApplicationWindows?
        if let memo = appWindows[pid] {
            index = memo
        } else {
            // SPEC-051 A-02 : l'index du relevé précédent sert s'il connaît toutes les fenêtres
            // visibles ; une fenêtre nouvelle force une énumération. L'écrivain l'invalide déjà sur
            // création, destruction ou élément devenu invalide.
            index = Self.reusableIndex(AXWindowIndexCache.shared.windows(for: pid), required: requiredWindowIDs)
                ?? AXApplicationWindows(pid: pid, requiredWindowIDs: requiredWindowIDs)
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
        cache.record(attrs, for: id, pid: pid, stableIsFresh: fresh != nil, generation: generation)
        return attrs
    }

    private static let volatileAttributeNames: [String] = [
        kAXFocusedAttribute, kAXMainAttribute, kAXModalAttribute, "AXFullScreen",
    ]

    /// Relit les attributs d'etat en un seul aller-retour AX.
    /// nil si l'application ne repond pas (elle vient d'etre mise de cote).
    private static func readVolatile(_ element: AXUIElement, pid: pid_t) -> AXVolatileReading? {
        var raw: CFArray?
        let error = AXCallTimings.shared.measure(pid) {
            AXUIElementCopyMultipleAttributeValues(
                element, volatileAttributeNames as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw
            )
        }
        if AXUnresponsiveApps.shared.noteResult(error, pid: pid) { return nil }
        let values = error == .success ? (raw as? [AnyObject]) ?? [] : []
        if AXReadValue.noteEmbeddedErrors(in: values, pid: pid, registry: AXUnresponsiveApps.shared) { return nil }
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
        let error = AXCallTimings.shared.measure(pid) {
            AXUIElementCopyMultipleAttributeValues(
                element, stableAttributeNames as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw
            )
        }
        registry.noteResult(error, pid: pid)
        guard error == .success, let values = raw as? [AnyObject], values.count == stableAttributeNames.count else {
            return nil
        }
        if AXReadValue.noteEmbeddedErrors(in: values, pid: pid, registry: registry) { return nil }
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
            let enabledError = AXCallTimings.shared.measure(pid) {
                AXUIElementCopyAttributeValue(
                    fullscreenButton as! AXUIElement, kAXEnabledAttribute as CFString, &rawEnabled // Safe : isElement
                )
            }
            if registry.noteResult(enabledError, pid: pid) { return nil }
            fullscreenEnabled = enabledError == .success && (rawEnabled as? Bool) == true
        }
        var settable = DarwinBoolean(false)
        let settableError = AXCallTimings.shared.measure(pid) {
            AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable)
        }
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
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        return focusedWindowID(pid: pid)
    }

    @MainActor public func focusedWindowReader() -> @Sendable () -> WindowID? {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return { pid.flatMap { self.focusedWindowID(pid: $0) } }
    }

    private func focusedWindowID(pid: pid_t) -> WindowID? {
        let registry = AXUnresponsiveApps.shared
        guard !registry.isQuarantined(pid) else { return nil }
        var rawFocused: CFTypeRef?
        let error = AXCallTimings.shared.measure(pid) {
            AXUIElementCopyAttributeValue(AXMessaging.application(pid), kAXFocusedWindowAttribute as CFString, &rawFocused)
        }
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
    static let enhancedUserInterface = "AXEnhancedUserInterface"

    private let io: any AXFrameIO
    private let windowIndex: AXWindowIndexCache
    private let writtenFrames: WrittenFrameRegistry
    private let registry: AXUnresponsiveApps
    /// Génération par défaut des appels sans génération : la génération en cours, jamais 0 implicite (T213).
    private let generations: PlacementGeneration
    private let now: @Sendable () -> Date

    public init() {
        self.init(io: LiveAXFrameIO())
    }

    init(
        io: any AXFrameIO,
        windowIndex: AXWindowIndexCache = .shared,
        writtenFrames: WrittenFrameRegistry = .shared,
        registry: AXUnresponsiveApps = .shared,
        generations: PlacementGeneration = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.io = io
        self.windowIndex = windowIndex
        self.writtenFrames = writtenFrames
        self.registry = registry
        self.generations = generations
        self.now = now
    }

    public func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        setFrame(frame, of: window, generation: generations.current)
    }

    public func setFrame(_ frame: CGRect, of window: WindowSnapshot, generation: UInt64) -> CGRect? {
        setFrames([WindowFrameUpdate(window: window, frame: frame)], generation: generation)[window.id] ?? nil
    }

    public func setFrames(_ updates: [WindowFrameUpdate]) -> [WindowID: CGRect?] {
        setFrames(updates, generation: generations.current)
    }

    // O(n + Σm) : regroupement par pid, index AX du dernier snapshot (au plus une enumeration
    // kAXWindows de m elements par application et par lot), resolution par ID en O(1). Le repli
    // par cadre/titre garde O(k·m) comparaisons mais au plus O(m + k) lectures AX par lot.
    // Point commun d'écriture : une fenêtre dont le budget A13 de `generation` est épuisé n'est pas
    // écrite (résultat nil, aucun appel AX) ; l'appelant le signale (T213).
    public func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64) -> [WindowID: CGRect?] {
        setFrames(updates, generation: generation, isCurrent: { true })
    }

    public func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64,
                          isCurrent: @Sendable () -> Bool) -> [WindowID: CGRect?] {
        var results: [WindowID: CGRect?] = [:]
        let reserved = Set(updates.map { $0.window.id.rawValue })
        for (pid, group) in Dictionary(grouping: updates, by: { $0.window.pid }) {
            guard isCurrent() else { break }
            var windows: PIDWindows?
            // AXEnhancedUserInterface : lu au premier placement de l'application, retabli en fin de lot.
            var enhancedUI: (app: AXUIElement, restore: Bool)?
            defer {
                if let enhancedUI, enhancedUI.restore {
                    let error = io.setValue(kCFBooleanTrue, of: Self.enhancedUserInterface, on: enhancedUI.app)
                    registry.noteResult(error, pid: pid)
                }
            }
            for update in group {
                guard isCurrent() else { break }
                var applied: CGRect?
                if !writtenFrames.isOverBudget(windowID: update.window.id.rawValue, generation: generation),
                   !registry.isQuarantined(pid),
                   let element = element(pid: pid, id: update.window.id, title: update.window.title,
                                         frame: update.window.frame, windows: &windows, reserved: reserved) {
                    // Le snapshot peut précéder l'entrée en plein écran natif. Un état vrai
                    // relu interdit toute écriture et ne consomme pas le budget de placement.
                    let (nativeError, nativeValue) = io.value(of: "AXFullScreen", on: element)
                    let nativeFullscreen = nativeError == .success ? nativeValue.flatMap(AXReadValue.flag) : nil
                    if !registry.noteResult(nativeError, pid: pid), nativeFullscreen != true, isCurrent() {
                        if enhancedUI == nil {
                            let app = AXMessaging.application(pid)
                            enhancedUI = (app, disableEnhancedUserInterface(app, pid: pid))
                        }
                        if !registry.isQuarantined(pid) {
                            applied = write(
                                update, generation: generation, on: element, pid: pid,
                                nativeCode: nativeError.rawValue, nativeFullscreen: nativeFullscreen,
                                isCurrent: isCurrent
                            )
                            // Une écriture partielle peut avoir changé le cadre même en échec.
                            // La relecture réussie est réutilisable ; sinon la prochaine résolution relira.
                            if let applied { windows?.observations.frames.updateValue(applied, forKey: element) }
                            else { windows?.observations.frames.removeValue(forKey: element) }
                        }
                    }
                }
                results.updateValue(applied, forKey: update.window.id)
            }
        }
        return results
    }

    public func readFrame(of window: WindowSnapshot) -> CGRect? {
        var windows: PIDWindows?
        guard let element = element(pid: window.pid, id: window.id, title: window.title, frame: window.frame, windows: &windows)
        else { return nil }
        return frame(of: element, pid: window.pid)
    }

    public func focus(_ window: WindowSnapshot) -> Bool {
        var windows: PIDWindows?
        guard let element = element(pid: window.pid, id: window.id, title: window.title, frame: window.frame, windows: &windows)
        else { return false }
        return focus(element, pid: window.pid)
    }

    /// Fenêtre d'un autre espace macOS (session 106). Depuis un plein écran natif, AX ne liste pas les
    /// fenêtres du bureau ordinaire, et inversement. `activate()` et la mise au premier plan SkyLight
    /// laissent macOS sur place (relevés du 28 octobre 2026). Deux étapes, chacune suivie d'une attente
    /// qu'AX liste la fenêtre :
    /// 1. ouverture par LaunchServices, celle du Dock : bascule sur l'espace de l'application, sauf si
    ///    elle a déjà une fenêtre sur l'espace affiché (réglage « passer à un espace… » actif) ;
    /// 2. élément AX obtenu par jeton distant, puis focus et AXRaise sur la fenêtre elle-même (AltTab).
    public func focusOnOtherSpace(_ window: WindowSnapshot, timeout: TimeInterval) -> SpaceFocusOutcome {
        let start = Date()
        var outcome = SpaceFocusOutcome(opened: false, focused: false, waitedMs: 0)
        func finished() -> SpaceFocusOutcome {
            outcome.waitedMs = Int(Date().timeIntervalSince(start) * 1000)
            return outcome
        }
        func reached(until deadline: TimeInterval) -> Bool {
            repeat {
                Thread.sleep(forTimeInterval: 0.05)
                var windows: PIDWindows?
                if let element = element(pid: window.pid, id: window.id, title: window.title, frame: window.frame, windows: &windows) {
                    outcome.focused = focus(element, pid: window.pid)
                    return true
                }
            } while Date().timeIntervalSince(start) < deadline
            return false
        }
        if let url = NSRunningApplication(processIdentifier: window.pid)?.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            outcome.opened = true
            if reached(until: timeout / 2) { return finished() }
        }
        guard let remote = Self.remoteWindowElement(pid: window.pid, windowID: CGWindowID(window.id.rawValue)) else {
            return finished()
        }
        outcome.remote = true
        _ = focus(remote, pid: window.pid)
        _ = reached(until: timeout)
        return finished()
    }

    private typealias RemoteTokenElement = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private static let remoteTokenElement: RemoteTokenElement? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementCreateWithRemoteToken")
        .map { unsafeBitCast($0, to: RemoteTokenElement.self) } // RTLD_DEFAULT

    /// Fenêtre absente de kAXWindows (autre espace) : jeton distant de 20 octets (pid, 0, « coco »,
    /// identifiant d'élément), identifiants 0 à 999 comme AltTab, au plus 0,3 s. O(1000) appels AX.
    static func remoteWindowElement(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        guard let remoteTokenElement else { return nil }
        let start = Date()
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { bytes in
            bytes.storeBytes(of: pid, toByteOffset: 0, as: pid_t.self)
            bytes.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self)
        }
        for elementID in UInt64(0)..<1000 where Date().timeIntervalSince(start) < 0.3 {
            token.withUnsafeMutableBytes { $0.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self) }
            guard let element = remoteTokenElement(token as CFData)?.takeRetainedValue() else { continue }
            var id = CGWindowID()
            if AXUIElementGetWindowID(element, &id) == .success, id == windowID { return element }
        }
        return nil
    }

    public func focusApplicationWindow(bundleID: String, windowID: WindowID, title: String, frame: Rect) -> Bool {
        for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            let pid = application.processIdentifier
            var windows: PIDWindows?
            guard let element = element(pid: pid, id: windowID, title: title, frame: frame, windows: &windows)
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
        var windows: PIDWindows?
        guard let element = element(pid: pid, id: window.id, title: window.title, frame: window.frame, windows: &windows),
              let button = elementAttribute(element, buttonAttribute, pid: pid)
        else { return false }
        let error = AXUIElementPerformAction(button, kAXPressAction as CFString)
        registry.noteResult(error, pid: pid)
        return error == .success
    }

    /// Active l'application puis met la fenetre devant. Une seule activation : `activate()`
    /// (sans option ignoree depuis macOS 14) puis kAXFrontmostAttribute avant AXRaise.
    /// Abandonne au premier delai depasse.
    private func focus(_ element: AXUIElement, pid: pid_t) -> Bool {
        guard !registry.isQuarantined(pid) else { return false }
        // AXRaise ne restaure pas systématiquement une fenêtre réduite dans le Dock.
        // Une application qui ne propose pas cet attribut conserve le chemin de focus habituel.
        let (minimizedError, minimized) = io.value(of: kAXMinimizedAttribute, on: element)
        if registry.noteResult(minimizedError, pid: pid) { return false }
        // Une lecture facultative refusée ne doit pas supprimer un focus qui fonctionnait.
        // Un élément détruit, en revanche, ne peut plus être focalisé.
        guard minimizedError != .invalidUIElement else { return false }
        if minimizedError == .success, (minimized as? Bool) == true {
            let error = io.setValue(kCFBooleanFalse, of: kAXMinimizedAttribute, on: element)
            registry.noteResult(error, pid: pid)
            guard error == .success else { return false }
        }
        let application = NSRunningApplication(processIdentifier: pid)
        application?.activate()
        let frontmost = setFrontmostError(pid: pid)
        guard !registry.isQuarantined(pid) else { return false }
        let app = AXMessaging.application(pid)
        let focusedWindow = io.setValue(element, of: kAXFocusedWindowAttribute, on: app)
        if registry.noteResult(focusedWindow, pid: pid) {
            return false
        }
        let raise = io.performAction(kAXRaiseAction, on: element)
        if registry.noteResult(raise, pid: pid) { return false }
        // Fenêtre clé (session 098, ADR 020) : sans elle, une application déjà au premier plan
        // garde la frappe ailleurs. Sans effet sur la décision de réussite.
        WindowKeyFocus.makeKey(pid: pid, window: element)
        // Relectures seulement quand une écriture a échoué (REL-010) : l'état réel tranche.
        let focusedWindowConfirmed = focusedWindow != .success
            && elementAttribute(app, kAXFocusedWindowAttribute, pid: pid).map { CFEqual($0, element) } == true
        let appIsActive = frontmost != .success && application?.isActive == true
        return AXFocusDecision.succeeded(
            frontmost: frontmost,
            appIsActive: appIsActive,
            focusedWindow: focusedWindow,
            focusedWindowConfirmed: focusedWindowConfirmed,
            raise: raise
        )
    }

    private func setFrontmost(pid: pid_t) -> Bool {
        setFrontmostError(pid: pid) == .success
    }

    private func setFrontmostError(pid: pid_t) -> AXError {
        guard !registry.isQuarantined(pid) else { return .cannotComplete }
        let error = io.setValue(kCFBooleanTrue, of: kAXFrontmostAttribute, on: AXMessaging.application(pid))
        registry.noteResult(error, pid: pid)
        return error
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String, pid: pid_t) -> AXUIElement? {
        guard !registry.isQuarantined(pid) else { return nil }
        let (error, raw) = io.value(of: attribute, on: element)
        registry.noteResult(error, pid: pid)
        guard error == .success, let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    /// Fenetres AX d'une application pendant un appel, et si elles viennent d'etre enumerees.
    private struct PIDWindows {
        var index: AXApplicationWindows?
        var isFresh: Bool
        let observations = FallbackObservations()
    }

    /// Durée de vie : un lot et un index AX. nil mémorise aussi une lecture de cadre impossible.
    private final class FallbackObservations {
        var frames: [AXUIElement: CGRect?] = [:]
        var titles: [AXUIElement: String] = [:]
    }

    /// Enumere les fenetres de l'application et met l'index en cache.
    private func enumerateWindows(pid: pid_t) -> PIDWindows {
        let index = io.enumerateWindows(pid: pid)
        if let index { windowIndex.store(index) }
        return PIDWindows(index: index, isFresh: true)
    }

    /// Element AX d'une fenetre depuis l'index du dernier snapshot. Un ID absent de l'index en
    /// cache (fenetre plus recente que le snapshot) provoque une seule nouvelle enumeration
    /// pour ce pid et cet appel. O(1) si l'ID est connu, O(m) sinon.
    private func element(
        pid: pid_t, id: WindowID, title: String, frame: Rect,
        windows: inout PIDWindows?, reserved: Set<CGWindowID> = []
    ) -> AXUIElement? {
        guard !registry.isQuarantined(pid) else { return nil }
        if windows == nil {
            windows = windowIndex.windows(for: pid).map { PIDWindows(index: $0, isFresh: false) } ?? enumerateWindows(pid: pid)
        }
        if windows?.isFresh == false, windows?.index?.element(id: id.rawValue) == nil {
            windows = enumerateWindows(pid: pid)
        }
        guard let index = windows?.index else { return nil }
        return element(in: index, id: id, title: title, frame: frame, reserved: reserved, observations: windows!.observations)
    }

    // O(1) si l'ID est connu d'AX, O(m) pour le repli. Priorite : ID exact > cadre unique > titre unique.
    // Le repli ignore les elements dont l'ID est vise ailleurs dans le meme lot. Pas de repli
    // par cadre pour un cadre nul ni quand plusieurs fenetres correspondent (SPEC-016 C4).
    private func element(
        in appWindows: AXApplicationWindows,
        id: WindowID,
        title: String,
        frame: Rect,
        reserved: Set<CGWindowID> = [],
        observations: FallbackObservations
    ) -> AXUIElement? {
        if let exact = appWindows.element(id: id.rawValue) { return exact }
        let pid = appWindows.pid
        let candidates = appWindows.entries
            .filter { entry in entry.id.map { !reserved.contains($0) } ?? true }
            .map(\.element)

        if frame.width > 0, frame.height > 0 {
            var frameMatches: [AXUIElement] = []
            for candidate in candidates {
                if observations.frames[candidate] == nil {
                    observations.frames.updateValue(self.frame(of: candidate, pid: pid), forKey: candidate)
                }
                if let actual = observations.frames[candidate] ?? nil, Self.isClose(actual, frame) {
                    frameMatches.append(candidate)
                }
                if registry.isQuarantined(pid) { return nil }
            }
            if frameMatches.count == 1 { return frameMatches[0] }
        }

        guard !title.isEmpty else { return nil }
        var titleMatches: [AXUIElement] = []
        for candidate in candidates {
            if observations.titles[candidate] == nil {
                observations.titles[candidate] = self.title(of: candidate, pid: pid)
            }
            if observations.titles[candidate] == title { titleMatches.append(candidate) }
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
        let (error, rawTitle) = io.value(of: kAXTitleAttribute, on: element)
        registry.noteResult(error, pid: pid)
        guard error == .success, let title = rawTitle as? String else { return "" }
        return title
    }

    /// Desactive `AXEnhancedUserInterface` sur l'application s'il est actif : avec lui, certaines
    /// applications animent chaque changement de cadre (yabai, `AX_ENHANCED_UI_WORKAROUND`).
    /// Retourne vrai s'il faut le retablir.
    private func disableEnhancedUserInterface(_ app: AXUIElement, pid: pid_t) -> Bool {
        let (error, raw) = io.value(of: Self.enhancedUserInterface, on: app)
        if registry.noteResult(error, pid: pid) { return false }
        guard error == .success, (raw as? Bool) == true else { return false }
        let setError = io.setValue(kCFBooleanFalse, of: Self.enhancedUserInterface, on: app)
        registry.noteResult(setError, pid: pid)
        return setError == .success
    }

    /// Taille, position puis taille, comme yabai (`window_manager.c:729-762`) : la premiere taille
    /// evite qu'une fenetre trop grande soit bornee par l'ecran a sa nouvelle position, la seconde
    /// corrige une taille bornee par l'ancien ecran. Une taille refusee (fenetre non
    /// redimensionnable) n'arrete pas l'ecriture ; une position refusee, une fenetre detruite ou
    /// un delai depasse l'arretent. Puis une seule relecture. Toute tentative qui a atteint l'appel
    /// AX est enregistree dans le registre, meme en echec : elle compte au budget A13 (T213).
    private func write(
        _ update: WindowFrameUpdate, generation: UInt64, on element: AXUIElement, pid: pid_t,
        nativeCode: Int32, nativeFullscreen: Bool?, isCurrent: @Sendable () -> Bool = { true }
    ) -> CGRect? {
        var position = update.frame.origin
        var size = update.frame.size
        guard let axPosition = AXValueCreate(.cgPoint, &position),
              let axSize = AXValueCreate(.cgSize, &size)
        else { return nil }

        var codes = ["nativeFullscreen": nativeCode]
        var phases: [(String, String, AXValue)] = update.preservesSize
            ? [("position", kAXPositionAttribute, axPosition)]
            : [("sizeBefore", kAXSizeAttribute, axSize), ("position", kAXPositionAttribute, axPosition), ("sizeAfter", kAXSizeAttribute, axSize)]
        if update.positionsBeforeResizing, !update.preservesSize {
            // L'application peut contraindre une taille à l'écran d'origine. Rejoindre
            // d'abord la destination ; garder ensuite les réparations habituelles.
            phases.insert(("positionBefore", kAXPositionAttribute, axPosition), at: 0)
        }
        for (phase, attribute, value) in phases {
            guard isCurrent() else { return nil }
            let error = io.setValue(value, of: attribute, on: element)
            guard isCurrent() else { return nil }
            codes[phase] = error.rawValue
            if registry.noteResult(error, pid: pid) {
                return record(update, readBack: nil, generation: generation, codes: codes, nativeFullscreen: nativeFullscreen, isCurrent: isCurrent)
            }
            if error == .invalidUIElement {
                windowIndex.invalidate(pid: pid)
                return record(update, readBack: nil, generation: generation, codes: codes, nativeFullscreen: nativeFullscreen, isCurrent: isCurrent)
            }
            if error != .success, attribute == kAXPositionAttribute, phase != "positionBefore" {
                return record(update, readBack: nil, generation: generation, codes: codes, nativeFullscreen: nativeFullscreen, isCurrent: isCurrent)
            }
        }
        let readBack = frame(of: element, pid: pid) { codes["readBack"] = $0.rawValue }
        // Une ancienne réponse ne remplace jamais le registre d'une demande plus récente.
        guard isCurrent() else { return nil }
        return record(update, readBack: readBack, generation: generation, codes: codes, nativeFullscreen: nativeFullscreen, isCurrent: isCurrent)
    }

    /// Inscrit une tentative d'ecriture au registre et rend sa frame relue (nil en echec). O(1).
    private func record(
        _ update: WindowFrameUpdate, readBack: CGRect?, generation: UInt64,
        codes: [String: Int32], nativeFullscreen: Bool?, isCurrent: @Sendable () -> Bool = { true }
    ) -> CGRect? {
        writtenFrames.record(
            windowID: update.window.id.rawValue, requested: update.frame, readBack: readBack,
            generation: generation, at: now(), axResultCodes: codes, nativeFullscreenReading: nativeFullscreen,
            isCurrent: isCurrent
        )
        return readBack
    }

    private static let frameAttributeNames: [String] = [kAXPositionAttribute, kAXSizeAttribute]

    /// Lit le cadre AX en un seul aller-retour. Avec un pid, un delai depasse met l'application
    /// de cote et arrete la lecture.
    func frame(of element: AXUIElement, pid: pid_t?, onResult: ((AXError) -> Void)? = nil) -> CGRect? {
        let (error, values) = io.values(of: Self.frameAttributeNames, on: element)
        onResult?(error)
        if let pid {
            if registry.noteResult(error, pid: pid) { return nil }
            if AXReadValue.noteEmbeddedErrors(in: values, pid: pid, registry: registry) { return nil }
        }
        guard error == .success, values.count == 2,
              CFGetTypeID(values[0]) == AXValueGetTypeID(),
              CFGetTypeID(values[1]) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        // Safe: CFTypeID == AXValueGetTypeID() verified in the guard above.
        guard AXValueGetValue(values[0] as! AXValue, .cgPoint, &position),
              AXValueGetValue(values[1] as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }
}
