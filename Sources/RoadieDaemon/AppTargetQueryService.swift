import AppKit
import Foundation
import RoadieCore

public struct AppTargetQueryReport: Codable, Equatable, Sendable {
    public var targets: [RoadieTarget]
    public var partial: Bool
    public var error: String?

    public init(targets: [RoadieTarget] = [], partial: Bool = false, error: String? = nil) {
        self.targets = targets
        self.partial = partial
        self.error = error
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

        let startedAt = Date()
        var stack: [(AXUIElement, String, Int)] = [(window, "0", 0)]
        var candidates: [AppElementCandidate] = []
        var seen = Set<CFHashCode>()
        var visited = 0
        var partial = false
        let ignoredActions: Set<String> = ["AXShowMenu", "AXScrollToVisible", "AXShowDefaultUI", "AXShowAlternateUI"]
        let timeout = TimeInterval(config.timeoutMs) / 1000

        while let (element, path, depth) = stack.popLast() {
            let fingerprint = CFHash(element)
            guard seen.insert(fingerprint).inserted else { continue }
            visited += 1
            if candidates.count >= config.maxTargets || Date().timeIntervalSince(startedAt) > timeout {
                partial = true
                break
            }
            let role = copyStringAttribute(element, kAXRoleAttribute) ?? "AXUnknown"
            let title = copyStringAttribute(element, kAXTitleAttribute)
                ?? copyStringAttribute(element, kAXDescriptionAttribute)
                ?? ""
            let value = copyStringAttribute(element, kAXValueAttribute)
            let actions = copyActionNames(element).filter { !ignoredActions.contains($0) }
            let frame = copyFrame(element)
            if (!actions.isEmpty || config.includeRoles.contains(role)) && frame != nil {
                candidates.append(AppElementCandidate(
                    id: "\(app.processIdentifier)/\(path)",
                    role: role,
                    title: title,
                    value: value,
                    frame: frame,
                    actions: actions
                ))
            }
            guard depth < config.maxDepth else { continue }
            let children = copyChildren(element, boost: effectiveBoost)
            for (index, child) in children.enumerated().reversed() {
                stack.append((child, "\(path).\(index)", depth + 1))
            }
        }

        var targets = AppTargetQueryService.targets(from: candidates, config: config)
        let labels = TargetHintService.labels(count: targets.count, alphabet: config.hintCharacters)
        for index in targets.indices {
            targets[index].label = labels[index]
        }
        return AppTargetQueryReport(
            targets: targets,
            partial: partial,
            error: partial ? "partial_timeout_or_limit" : nil
        )
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
