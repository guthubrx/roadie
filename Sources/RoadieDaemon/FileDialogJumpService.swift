import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import RoadieCore

/// Type de boîte de dialogue système de fichiers détectée sur macOS (Spec 168).
public enum FileDialogKind: String, Codable, Equatable, Sendable {
    case open
    case save
}

/// Contexte d'un dialogue macOS « Ouvrir / Enregistrer sous » détecté à l'ouverture du lanceur.
public struct FileDialogContext: Equatable, Sendable {
    public let pid: pid_t
    public let appName: String
    public let kind: FileDialogKind
    public let title: String

    public init(pid: pid_t, appName: String, kind: FileDialogKind, title: String = "") {
        self.pid = pid
        self.appName = appName
        self.kind = kind
        self.title = title
    }

    public var label: String {
        switch kind {
        case .open:
            return tr("Ouvrir dans \(appName)", "Open in \(appName)")
        case .save:
            return tr("Enregistrer dans \(appName)", "Save in \(appName)")
        }
    }
}

/// Résultat d'une tentative de téléportation dans une boîte de dialogue fichier.
public struct FileDialogJumpResult: Equatable, Sendable {
    public let succeeded: Bool
    public let resolvedFolder: String?
    public let reason: String

    public init(succeeded: Bool, resolvedFolder: String? = nil, reason: String) {
        self.succeeded = succeeded
        self.resolvedFolder = resolvedFolder
        self.reason = reason
    }
}

/// Interface injectable permettant de tester le module sans toucher une vraie fenêtre AX.
public protocol FileDialogNavigating: Sendable {
    func detect(pid: pid_t, appName: String) -> FileDialogContext?
    func jump(to folderPath: String, in context: FileDialogContext) -> FileDialogJumpResult
}

/// Module isolé (Spec 168) : détection ponctuelle d'un dialogue `NSOpenPanel` / `NSSavePanel`
/// et saut direct de dossier via le panneau natif macOS *Aller au dossier* (`⌘⇧G`), en préservant
/// le nom du fichier en cours d'enregistrement et sans toucher au presse-papiers utilisateur.
/// Zéro timer, zéro polling : appelé uniquement à l'ouverture de la barre si `file_dialog_jump = true`.
public struct FileDialogJumpService: FileDialogNavigating, Sendable {
    private static let openKeywords = ["open", "ouvrir", "choose", "choisir", "attach", "joindre", "select", "sélectionner", "import", "importer"]
    private static let saveKeywords = ["save", "enregistrer", "export", "exporter", "download", "télécharger", "print", "imprimer"]
    private static let panelIdentifierHints = ["open-panel", "save-panel", "nsopenpanel", "nssavepanel", "filedialog", "open_panel", "save_panel"]

    public init() {}

    /// Classification pure d'une fenêtre ou feuille AX pour décider s'il s'agit d'un dialogue fichier.
    public static func classify(
        role: String?,
        subrole: String?,
        identifier: String?,
        title: String?,
        hasFileBrowser: Bool,
        hasSaveField: Bool
    ) -> FileDialogKind? {
        let normRole = (role ?? "").lowercased()
        let normSubrole = (subrole ?? "").lowercased()
        let normID = (identifier ?? "").lowercased()
        let normTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let isSheetOrDialog = normRole == "axsheet"
            || normSubrole == "axdialog"
            || normSubrole == "axsheet"
            || normSubrole == "axsystemdialog"
        let hasPanelID = panelIdentifierHints.contains { normID.contains($0) }

        if hasSaveField {
            return .save
        }
        if hasPanelID {
            if normID.contains("save") || saveKeywords.contains(where: { normTitle.contains($0) }) {
                return .save
            }
            return .open
        }
        guard isSheetOrDialog else { return nil }
        if hasFileBrowser {
            if saveKeywords.contains(where: { normTitle.contains($0) }) {
                return .save
            }
            return .open
        }
        if saveKeywords.contains(where: { normTitle.contains($0) }) {
            return .save
        }
        if openKeywords.contains(where: { normTitle.contains($0) }) {
            return .open
        }
        return nil
    }

    /// Résout le dossier cible : pour un dossier retourne son chemin normalisé, pour un fichier
    /// retourne son dossier parent. Rejette les chemins vides ou inexistants.
    public static func resolveTargetFolder(
        for rawPath: String,
        isFolderHint: Bool? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let standardized = (expanded as NSString).standardizingPath
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: standardized, isDirectory: &isDir) {
            if isDir.boolValue {
                return standardized
            }
            let parent = (standardized as NSString).deletingLastPathComponent
            var parentIsDir: ObjCBool = false
            if !parent.isEmpty, fileManager.fileExists(atPath: parent, isDirectory: &parentIsDir), parentIsDir.boolValue {
                return parent
            }
            return nil
        }
        if let isFolderHint {
            let candidate = isFolderHint ? standardized : (standardized as NSString).deletingLastPathComponent
            var candidateIsDir: ObjCBool = false
            if !candidate.isEmpty, fileManager.fileExists(atPath: candidate, isDirectory: &candidateIsDir), candidateIsDir.boolValue {
                return candidate
            }
        }
        return nil
    }

    /// Collecte une liste dédupliquée de dossiers pertinents (dossiers du projet actif + récents).
    public static func suggestedFolders(
        stageFolders: [String],
        recentFolders: [String],
        limit: Int = 6,
        fileManager: FileManager = .default
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in stageFolders + recentFolders {
            guard result.count < limit else { break }
            guard let folder = resolveTargetFolder(for: raw, isFolderHint: true, fileManager: fileManager) else { continue }
            if seen.insert(folder).inserted {
                result.append(folder)
            }
        }
        return result
    }

    /// Sonde AX ponctuelle (timeout 120 ms) sur la fenêtre active ou feuille `AXSheet` du processus.
    public func detect(pid: pid_t, appName: String) -> FileDialogContext? {
        guard pid > 0, AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.12)

        guard let focusedWindow = Self.copyElement(appElement, kAXFocusedWindowAttribute)
            ?? Self.copyElement(appElement, kAXMainWindowAttribute)
        else { return nil }

        // Priorité à une feuille AXSheet attachée à la fenêtre active (cas standard NSOpenPanel/NSSavePanel).
        var candidates: [AXUIElement] = []
        if let children = Self.copyElementArray(focusedWindow, kAXChildrenAttribute) {
            for child in children where Self.copyString(child, kAXRoleAttribute) == kAXSheetRole {
                candidates.append(child)
            }
        }
        candidates.append(focusedWindow)

        for element in candidates {
            AXUIElementSetMessagingTimeout(element, 0.12)
            let role = Self.copyString(element, kAXRoleAttribute)
            let subrole = Self.copyString(element, kAXSubroleAttribute)
            let identifier = Self.copyString(element, kAXIdentifierAttribute)
            let title = Self.copyString(element, kAXTitleAttribute)
            let probe = Self.probePanelChildren(element, maxNodes: 60)
            if let kind = Self.classify(
                role: role,
                subrole: subrole,
                identifier: identifier,
                title: title,
                hasFileBrowser: probe.hasFileBrowser,
                hasSaveField: probe.hasSaveField
            ) {
                return FileDialogContext(pid: pid, appName: appName, kind: kind, title: title ?? "")
            }
        }
        return nil
    }

    /// Téléporte le dialogue actif vers `folderPath` via `⌘⇧G` + écriture AX directe + `Entrée`.
    public func jump(to folderPath: String, in context: FileDialogContext) -> FileDialogJumpResult {
        guard let resolved = Self.resolveTargetFolder(for: folderPath) else {
            return FileDialogJumpResult(succeeded: false, reason: "folder_not_found")
        }
        guard AXIsProcessTrusted() else {
            return FileDialogJumpResult(succeeded: false, resolvedFolder: resolved, reason: "accessibility_denied")
        }
        guard let app = NSRunningApplication(processIdentifier: context.pid), !app.isTerminated else {
            return FileDialogJumpResult(succeeded: false, resolvedFolder: resolved, reason: "app_terminated")
        }

        // Réactiver l'application pour que le panneau reçoive ⌘⇧G.
        app.activate(options: [])
        Thread.sleep(forTimeInterval: 0.08)

        // 1. Envoyer ⌘⇧G (keycode 5 = 'g') pour ouvrir la feuille native « Aller au dossier ».
        Self.postKey(keyCode: 5, flags: [.maskCommand, .maskShift])

        // 2. Attendre brièvement l'apparition du champ texte de la feuille « Aller au dossier » (400 ms max).
        let appElement = AXUIElementCreateApplication(context.pid)
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        let deadline = Date().addingTimeInterval(0.45)
        var targetField: AXUIElement?
        while Date() < deadline {
            if let focused = Self.copyElement(appElement, kAXFocusedUIElementAttribute) {
                let role = Self.copyString(focused, kAXRoleAttribute) ?? ""
                if role == kAXComboBoxRole || role == kAXTextFieldRole {
                    targetField = focused
                    break
                }
            }
            Thread.sleep(forTimeInterval: 0.025)
        }

        guard let field = targetField else {
            return FileDialogJumpResult(succeeded: false, resolvedFolder: resolved, reason: "goto_sheet_not_found")
        }

        // 3. Injecter le chemin directement via AX (ne touche jamais le presse-papiers utilisateur).
        let setStatus = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, resolved as CFTypeRef)
        guard setStatus == .success else {
            return FileDialogJumpResult(succeeded: false, resolvedFolder: resolved, reason: "ax_value_write_failed")
        }
        Thread.sleep(forTimeInterval: 0.04)

        // 4. Valider « Aller au dossier » par Entrée (keycode 36).
        Self.postKey(keyCode: 36, flags: [])
        return FileDialogJumpResult(succeeded: true, resolvedFolder: resolved, reason: "ok")
    }

    // MARK: - Helpers AX & événements clavier bornés

    private static func probePanelChildren(_ root: AXUIElement, maxNodes: Int) -> (hasFileBrowser: Bool, hasSaveField: Bool) {
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        var hasBrowser = false
        var hasSave = false

        while let (node, depth) = stack.popLast(), visited < maxNodes {
            visited += 1
            let role = copyString(node, kAXRoleAttribute) ?? ""
            let identifier = (copyString(node, kAXIdentifierAttribute) ?? "").lowercased()
            if role == "AXBrowser" || (role == "AXOutline" && identifier.contains("file")) || identifier.contains("open-panel") {
                hasBrowser = true
            }
            if identifier.contains("saveasnametextfield") || identifier.contains("save-panel") || identifier.contains("namefieldstringvalue") {
                hasSave = true
            }
            if hasBrowser && hasSave { break }
            guard depth < 4, let children = copyElementArray(node, kAXChildrenAttribute) else { continue }
            for child in children.prefix(16) {
                stack.append((child, depth + 1))
            }
        }
        return (hasBrowser, hasSave)
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func copyElementArray(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let list = value as? [AXUIElement]
        else { return nil }
        return list
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
