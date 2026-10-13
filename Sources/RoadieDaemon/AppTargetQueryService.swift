import AppKit
import Foundation
import RoadieCore

public struct AppTargetQueryReport: Codable, Equatable, Sendable {
    public var targets: [RoadieTarget]
    public var partial: Bool
    public var error: String?
    /// Statistiques du parcours AX ; absentes quand aucun parcours n'a eu lieu.
    public var scan: AppTargetScanStats?

    public init(targets: [RoadieTarget] = [], partial: Bool = false, error: String? = nil, scan: AppTargetScanStats? = nil) {
        self.targets = targets
        self.partial = partial
        self.error = error
        self.scan = scan
    }
}

/// Mesure d'un parcours applicatif, journalisée en `targets.app_scan` pour régler
/// `max_depth` et `timeout_ms` avec des chiffres (contrat `specs/018-electron-app-hints/contracts`).
public struct AppTargetScanStats: Codable, Equatable, Sendable {
    public var bundleID: String
    public var isElectron: Bool
    /// `enabled`, `unsupported` ou `skipped`.
    public var manualAccessibility: String
    public var visited: Int
    public var candidates: Int
    public var offscreen: Int
    public var maxDepthReached: Int
    /// Éléments à `max_depth` dont les enfants n'ont pas été lus.
    public var atMaxDepth: Int
    /// Une zone web (`AXWebArea`) a été lue : Electron a publié son contenu.
    public var sawWebArea: Bool
    public var elapsedMs: Int
    /// `complete`, `timeout` ou `limit`.
    public var stopReason: String
    public var retries: Int

    public init(
        bundleID: String, isElectron: Bool, manualAccessibility: String,
        visited: Int, candidates: Int, offscreen: Int, maxDepthReached: Int, atMaxDepth: Int,
        sawWebArea: Bool, elapsedMs: Int, stopReason: String, retries: Int
    ) {
        self.bundleID = bundleID
        self.isElectron = isElectron
        self.manualAccessibility = manualAccessibility
        self.visited = visited
        self.candidates = candidates
        self.offscreen = offscreen
        self.maxDepthReached = maxDepthReached
        self.atMaxDepth = atMaxDepth
        self.sawWebArea = sawWebArea
        self.elapsedMs = elapsedMs
        self.stopReason = stopReason
        self.retries = retries
    }

    public var eventDetails: [String: String] {
        [
            "bundleID": bundleID,
            "isElectron": String(isElectron),
            "manualAccessibility": manualAccessibility,
            "visited": String(visited),
            "candidates": String(candidates),
            "offscreen": String(offscreen),
            "maxDepthReached": String(maxDepthReached),
            "atMaxDepth": String(atMaxDepth),
            "sawWebArea": String(sawWebArea),
            "elapsedMs": String(elapsedMs),
            "stopReason": stopReason,
            "retries": String(retries),
        ]
    }
}

public struct AppElementCandidate: Equatable, Sendable {
    public var id: String
    public var role: String
    public var title: String
    public var value: String?
    public var frame: Rect?
    public var actions: [String]

    public init(id: String, role: String, title: String, value: String? = nil, frame: Rect? = nil, actions: [String]) {
        self.id = id
        self.role = role
        self.title = title
        self.value = value
        self.frame = frame
        self.actions = actions
    }
}

public protocol AppTargetProviding {
    func candidates(config: AppTargetsConfig) -> AppTargetQueryReport
    func click(_ target: RoadieTarget, action: TargetActionVerb) -> TargetActionResult
}

public struct AppTargetQueryService {
    private let provider: any AppTargetProviding

    public init(provider: any AppTargetProviding = LiveAppTargetProvider()) {
        self.provider = provider
    }

    public func query(config: AppTargetsConfig, enabledOverride: Bool = false) -> AppTargetQueryReport {
        guard config.enabled || enabledOverride else {
            return AppTargetQueryReport(error: "app_targets_disabled")
        }
        return provider.candidates(config: config)
    }

    public func click(_ target: RoadieTarget, action: TargetActionVerb = .click) -> TargetActionResult {
        provider.click(target, action: action)
    }

    /// Electron construit son arbre AX en arrière-plan après `AXManualAccessibility` : juste après
    /// l'activation, seuls les boutons de la fenêtre existent. Un parcours complet (ni coupé par la
    /// profondeur, le temps ou la limite) sans zone web (`AXWebArea`) est relancé, deux fois au plus.
    /// Un parcours coupé ne prouve rien et ne relance pas ; une application native ne relance jamais.
    public static func shouldRetryScan(isElectron: Bool, sawWebArea: Bool, exploredFully: Bool, retries: Int) -> Bool {
        isElectron && !sawWebArea && exploredFully && retries < 2
    }

    /// Le code retour de `AXManualAccessibility` ne prouve pas son effet (issue Electron #37465) :
    /// Electron se reconnaît à son framework embarqué.
    public static func isElectronBundle(at url: URL?) -> Bool {
        guard let url else { return false }
        let framework = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: framework.path)
    }

    /// Partie visible d'un élément dans la fenêtre, nil s'il est entièrement dehors. Le clic Roadie
    /// vise le centre du cadre retenu : rogné, il reste dans la fenêtre au lieu de tomber sur une
    /// autre. Sans cadre de fenêtre connu, le cadre est gardé tel quel.
    public static func visibleFrame(_ frame: Rect, in windowFrame: Rect?) -> Rect? {
        guard let windowFrame else { return frame }
        let visible = frame.cgRect.intersection(windowFrame.cgRect)
        return visible.isNull || visible.isEmpty ? nil : Rect(visible)
    }

    public static func targets(from candidates: [AppElementCandidate], config: AppTargetsConfig) -> [RoadieTarget] {
        let allowedRoles = Set(config.includeRoles)
        return candidates
            .filter { allowedRoles.contains($0.role) || !$0.actions.isEmpty }
            .prefix(config.maxTargets)
            .map { candidate in
                let title = candidate.title.isEmpty ? candidate.role : candidate.title
                return RoadieTarget(
                    id: "app:\(candidate.id)",
                    kind: .appElement,
                    title: title,
                    subtitle: [candidate.role, candidate.value].compactMap(\.self).joined(separator: " - "),
                    source: .app,
                    matchText: RoadieTarget.normalizedMatchText([candidate.id, candidate.role, title, candidate.value ?? ""]),
                    frame: candidate.frame,
                    actions: [.click, .doubleClick, .rightClick, .inspect],
                    diagnostics: candidate.actions.map { "action=\($0)" } + ["role=\(candidate.role)"]
                )
            }
    }
}

public struct LiveAppTargetProvider: AppTargetProviding {
    public init() {}

    public func candidates(config: AppTargetsConfig) -> AppTargetQueryReport {
        guard AXIsProcessTrusted() else {
            return AppTargetQueryReport(error: "accessibility_denied")
        }
        guard config.scope == "frontmost_window" else {
            return AppTargetQueryReport(error: "unsupported_scope")
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return AppTargetQueryReport(error: "no_frontmost_application")
        }
        let effectiveBoost = config.axBoostEnabled || config.additionalBoostBundleIDs.contains(app.bundleIdentifier ?? "")
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = copyElementAttribute(appElement, kAXFocusedWindowAttribute) else {
            return AppTargetQueryReport(error: "no_focused_window")
        }

        // Complexité : O(r * n), n = éléments lus par passe (borné par max_targets, max_depth et
        // timeout_ms), r ≤ 3 passes. Seule une application Electron dont l'arbre est vide relance.
        // Les relances et leurs attentes partagent une échéance : timeout_ms + 300 ms au total, à un
        // appel AX près (un appel synchrone lent n'est pas interrompu).
        let startedAt = Date()
        let timeout = TimeInterval(config.timeoutMs) / 1000
        let retryDeadline = startedAt.addingTimeInterval(timeout + 0.3)
        let isElectron = AppTargetQueryService.isElectronBundle(at: app.bundleURL)
        let manualAccessibility = effectiveBoost && isElectron ? requestPublication(app.processIdentifier) : "skipped"
        var pass = scan(window: window, pid: app.processIdentifier, config: config, boost: effectiveBoost,
                        deadline: startedAt.addingTimeInterval(timeout))
        var retries = 0
        while AppTargetQueryService.shouldRetryScan(
            isElectron: isElectron && effectiveBoost,
            sawWebArea: pass.sawWebArea,
            exploredFully: pass.stopReason == "complete" && pass.atMaxDepth == 0,
            retries: retries
        ), Date().addingTimeInterval(0.15) < retryDeadline {
            Thread.sleep(forTimeInterval: 0.15)
            retries += 1
            pass = scan(window: window, pid: app.processIdentifier, config: config, boost: effectiveBoost, deadline: retryDeadline)
        }

        var targets = AppTargetQueryService.targets(from: pass.candidates, config: config)
        let labels = TargetHintService.labels(count: targets.count, alphabet: config.hintCharacters)
        for index in targets.indices {
            targets[index].label = labels[index]
        }
        let partial = pass.stopReason != "complete"
        return AppTargetQueryReport(
            targets: targets,
            partial: partial,
            error: partial ? "partial_timeout_or_limit" : nil,
            scan: AppTargetScanStats(
                bundleID: app.bundleIdentifier ?? "",
                isElectron: isElectron,
                manualAccessibility: manualAccessibility,
                visited: pass.visited,
                candidates: pass.candidates.count,
                offscreen: pass.offscreen,
                maxDepthReached: pass.maxDepthReached,
                atMaxDepth: pass.atMaxDepth,
                sawWebArea: pass.sawWebArea,
                elapsedMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                stopReason: pass.stopReason,
                retries: retries
            )
        )
    }

    /// Electron ne publie son arbre AX qu'à la demande d'un outil d'assistance
    /// (https://www.electronjs.org/docs/latest/tutorial/accessibility). Redemandée à chaque parcours :
    /// une demande faite au lancement de l'application peut être ignorée (mesure du 2026-10-12 sur
    /// draw.io, voir research.md). Délai AX court : une application figée ne bloque pas le parcours.
    private func requestPublication(_ pid: pid_t) -> String {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.5)
        return AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success
            ? "enabled" : "unsupported"
    }

    private struct ScanPass {
        var candidates: [AppElementCandidate] = []
        var visited = 0
        var offscreen = 0
        var maxDepthReached = 0
        var atMaxDepth = 0
        var sawWebArea = false
        var stopReason = "complete"
    }

    private func scan(window: AXUIElement, pid: pid_t, config: AppTargetsConfig, boost: Bool, deadline: Date) -> ScanPass {
        let windowFrame = copyFrame(window)
        var stack: [(AXUIElement, String, Int)] = [(window, "0", 0)]
        var pass = ScanPass()
        var seen = Set<CFHashCode>()
        let ignoredActions: Set<String> = ["AXShowMenu", "AXScrollToVisible", "AXShowDefaultUI", "AXShowAlternateUI"]
        let includedRoles = Set(config.includeRoles)

        while let (element, path, depth) = stack.popLast() {
            let fingerprint = CFHash(element)
            guard seen.insert(fingerprint).inserted else { continue }
            if pass.candidates.count >= config.maxTargets {
                pass.stopReason = "limit"
                break
            }
            if Date() > deadline {
                pass.stopReason = "timeout"
                break
            }
            pass.visited += 1
            pass.maxDepthReached = max(pass.maxDepthReached, depth)
            let role = copyStringAttribute(element, kAXRoleAttribute) ?? "AXUnknown"
            pass.sawWebArea = pass.sawWebArea || role == "AXWebArea"
            let title = copyStringAttribute(element, kAXTitleAttribute)
                ?? copyStringAttribute(element, kAXDescriptionAttribute)
                ?? ""
            let value = copyStringAttribute(element, kAXValueAttribute)
            let actions = copyActionNames(element).filter { !ignoredActions.contains($0) }
            if (!actions.isEmpty || includedRoles.contains(role)), let frame = copyFrame(element) {
                if let visible = AppTargetQueryService.visibleFrame(frame, in: windowFrame) {
                    pass.candidates.append(AppElementCandidate(
                        id: "\(pid)/\(path)",
                        role: role,
                        title: title,
                        value: value,
                        frame: visible,
                        actions: actions
                    ))
                } else {
                    pass.offscreen += 1
                }
            }
            guard depth < config.maxDepth else {
                pass.atMaxDepth += 1
                continue
            }
            let children = copyChildren(element, boost: boost)
            for (index, child) in children.enumerated().reversed() {
                stack.append((child, "\(path).\(index)", depth + 1))
            }
        }
        return pass
    }

    public func click(_ target: RoadieTarget, action: TargetActionVerb) -> TargetActionResult {
        guard let frame = target.frame?.cgRect else {
            return TargetActionResult(changed: false, message: "app click: no frame", target: target, error: "no_frame")
        }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        switch action {
        case .click:
            postClick(at: point, button: .left, down: .leftMouseDown, up: .leftMouseUp, clickCount: 1)
        case .doubleClick:
            postClick(at: point, button: .left, down: .leftMouseDown, up: .leftMouseUp, clickCount: 1)
            postClick(at: point, button: .left, down: .leftMouseDown, up: .leftMouseUp, clickCount: 2)
        case .rightClick:
            postClick(at: point, button: .right, down: .rightMouseDown, up: .rightMouseUp, clickCount: 1)
        default:
            return TargetActionResult(changed: false, message: "app click: unsupported \(action.rawValue)", target: target, error: "unsupported_action")
        }
        return TargetActionResult(changed: true, message: "app \(action.rawValue) \(target.id)", target: target)
    }

    private func postClick(
        at point: CGPoint,
        button: CGMouseButton,
        down: CGEventType,
        up: CGEventType,
        clickCount: Int64
    ) {
        let downEvent = CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: point, mouseButton: button)
        let upEvent = CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: point, mouseButton: button)
        downEvent?.setIntegerValueField(.mouseEventClickState, value: clickCount)
        upEvent?.setIntegerValueField(.mouseEventClickState, value: clickCount)
        downEvent?.post(tap: .cghidEventTap)
        upEvent?.post(tap: .cghidEventTap)
    }

    private func copyElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return nil }
        return (value as! AXUIElement)
    }

    private func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func copyChildren(_ element: AXUIElement, boost: Bool) -> [AXUIElement] {
        let attributes = boost ? [
            kAXChildrenAttribute,
            "AXVisibleChildren",
            "AXChildrenInNavigationOrder",
            "AXRows",
            "AXColumns",
            "AXContents",
            "AXTabs",
        ] : [kAXChildrenAttribute]
        var result: [AXUIElement] = []
        var seen = Set<CFHashCode>()
        for attribute in attributes {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                  let value
            else { continue }
            if let children = value as? [AXUIElement] {
                for child in children where seen.insert(CFHash(child)).inserted {
                    result.append(child)
                }
            } else if CFGetTypeID(value) == AXUIElementGetTypeID() {
                let child = value as! AXUIElement
                if seen.insert(CFHash(child)).inserted {
                    result.append(child)
                }
            }
        }
        return result
    }

    private func copyActionNames(_ element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success,
              let names = value as? [String]
        else { return [] }
        return names
    }

    private func copyFrame(_ element: AXUIElement) -> Rect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 0,
              size.height > 0
        else { return nil }
        return Rect(CGRect(origin: point, size: size))
    }
}
