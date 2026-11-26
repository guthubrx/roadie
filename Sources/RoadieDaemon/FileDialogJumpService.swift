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

/// Dossier proposé pour le saut direct dans un dialogue fichier (Spec 168), avec ses alias FR/EN.
public struct FileDialogFolderSuggestion: Equatable, Sendable {
    public let path: String
    public let title: String
    public let aliases: [String]

    public init(path: String, title: String, aliases: [String] = []) {
        self.path = path
        self.title = title
        self.aliases = aliases
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
    private static let saveButtonTitles: Set<String> = ["save", "save…", "save...", "enregistrer", "enregistrer…", "export", "exporter"]
    private static let openButtonTitles: Set<String> = ["open", "ouvrir", "choose", "choisir", "select", "sélectionner", "import", "importer"]
    private static let cancelButtonTitles: Set<String> = ["cancel", "annuler"]
    private static let newFolderButtonTitles: Set<String> = ["new folder", "nouveau dossier"]

    public init() {}

    /// Classification pure d'une fenêtre ou feuille AX pour décider s'il s'agit d'un dialogue fichier.
    public static func classify(
        role: String?,
        subrole: String?,
        identifier: String?,
        title: String?,
        hasFileBrowser: Bool,
        hasSaveField: Bool,
        hasDialogButtons: Bool = false,
        hasSaveButton: Bool = false
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
            if hasSaveButton || normID.contains("save") || saveKeywords.contains(where: { normTitle.contains($0) }) {
                return .save
            }
            return .open
        }
        guard isSheetOrDialog else { return nil }
        if hasFileBrowser || hasDialogButtons {
            if hasSaveButton || saveKeywords.contains(where: { normTitle.contains($0) }) {
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

    /// Dossiers favoris macOS standards (Desktop/Bureau, Downloads/Téléchargements, Documents, Nextcloud, Home)
    /// toujours disponibles dans un dialogue « Ouvrir / Enregistrer sous », même s'ils ne sont pas récents.
    public static func standardFavoriteFolders(
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> [FileDialogFolderSuggestion] {
        let home = (homeDirectory as NSString).standardizingPath
        let specs: [(rel: String?, title: String, aliases: [String])] = [
            ("Desktop", "Desktop", ["desktop", "bureau"]),
            ("Downloads", "Downloads", ["downloads", "telechargements", "téléchargements"]),
            ("Documents", "Documents", ["documents", "docs"]),
            ("Nextcloud", "Nextcloud", ["nextcloud"]),
            (nil, tr("Dossier personnel", "Home"), ["home", "accueil", "maison", (home as NSString).lastPathComponent.lowercased()]),
        ]
        var result: [FileDialogFolderSuggestion] = []
        for spec in specs {
            let raw = spec.rel.map { (home as NSString).appendingPathComponent($0) } ?? home
            guard let resolved = resolveTargetFolder(for: raw, isFolderHint: true, fileManager: fileManager) else { continue }
            result.append(FileDialogFolderSuggestion(path: resolved, title: spec.title, aliases: spec.aliases))
        }
        return result
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

    /// Collecte les suggestions complètes (favoris macOS + projets + récents), avec alias bilingues
    /// afin que `Desktop` / `Bureau`, `Downloads` / `Téléchargements` et `Documents` soient toujours proposés.
    public static func suggestedFolderEntries(
        stageFolders: [String],
        recentFolders: [String],
        favoriteFolders: [FileDialogFolderSuggestion]? = nil,
        limit: Int = 16,
        fileManager: FileManager = .default
    ) -> [FileDialogFolderSuggestion] {
        let favorites = favoriteFolders ?? standardFavoriteFolders(fileManager: fileManager)
        let favoritesByPath = Dictionary(uniqueKeysWithValues: favorites.map { ($0.path, $0) })
        var seen = Set<String>()
        var result: [FileDialogFolderSuggestion] = []

        func appendEntry(_ entry: FileDialogFolderSuggestion) {
            guard result.count < limit else { return }
            guard seen.insert(entry.path).inserted else { return }
            result.append(entry)
        }

        // 1. Dossiers favoris macOS essentiels (Desktop, Downloads, Documents...) immédiatement accessibles.
        for fav in favorites.prefix(3) {
            appendEntry(fav)
        }
        // 2. Dossiers des projets Roadie et dossiers récents.
        for raw in stageFolders + recentFolders {
            guard result.count < limit else { break }
            guard let folder = resolveTargetFolder(for: raw, isFolderHint: true, fileManager: fileManager) else { continue }
            if let fav = favoritesByPath[folder] {
                appendEntry(fav)
            } else {
                let name = (folder as NSString).lastPathComponent
                let title = name.isEmpty ? folder : name
                appendEntry(FileDialogFolderSuggestion(path: folder, title: title, aliases: [title.lowercased()]))
            }
        }
        // 3. Reste des favoris (Nextcloud, Home).
        for fav in favorites.dropFirst(3) {
            appendEntry(fav)
        }
        return result
    }

    /// Filtre les dossiers candidats d'un dialogue fichier selon la saisie utilisateur (titre, alias FR/EN ou chemin).
    public static func matchingFolders(
        query: String,
        in candidates: [FileDialogFolderSuggestion],
        limit: Int = 5
    ) -> [FileDialogFolderSuggestion] {
        let normQuery = TargetHintService.normalized(query)
        guard !normQuery.isEmpty else { return [] }
        let words = normQuery.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }

        let scored: [(entry: FileDialogFolderSuggestion, score: Int)] = candidates.compactMap { entry in
            let titleNorm = TargetHintService.normalized(entry.title)
            let aliasesNorm = entry.aliases.map(TargetHintService.normalized)
            let pathNorm = TargetHintService.normalized(entry.path)
            let haystack = ([titleNorm] + aliasesNorm + [pathNorm]).joined(separator: " ")
            guard words.allSatisfy({ haystack.contains($0) }) else { return nil }
            let exact = titleNorm == normQuery || aliasesNorm.contains(normQuery)
            let prefix = titleNorm.hasPrefix(normQuery) || aliasesNorm.contains(where: { $0.hasPrefix(normQuery) })
            let score = exact ? 3 : (prefix ? 2 : 1)
            return (entry, score)
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : false }
            .prefix(limit)
            .map(\.entry)
    }

    /// Sonde AX ponctuelle (timeout 120 ms) sur la fenêtre active, ses feuilles (`AXSheets` / `AXSheet`),
    /// l'élément focalisé et `AXWindows` du processus (couvre aussi les dialogues XPC sandboxés comme TextEdit).
    public func detect(pid: pid_t, appName: String) -> FileDialogContext? {
        guard pid > 0, AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.12)

        var candidates: [AXUIElement] = []
        var seen = CFIdentitySet()
        func addCandidate(_ element: AXUIElement?) {
            guard let element, seen.insert(element) else { return }
            candidates.append(element)
        }

        // 1. Chaîne ascendante depuis l'élément focalisé (détecte immédiatement le champ « Save As » XPC).
        if let focusedElement = Self.copyElement(appElement, kAXFocusedUIElementAttribute) {
            let focusedID = (Self.copyString(focusedElement, kAXIdentifierAttribute) ?? "").lowercased()
            let focusedDesc = (Self.copyString(focusedElement, kAXDescriptionAttribute) ?? "").lowercased()
            if focusedID.contains("saveasnametextfield") || focusedID.contains("namefieldstringvalue")
                || focusedDesc.contains("save as") || focusedDesc.contains("enregistrer sous") {
                return FileDialogContext(pid: pid, appName: appName, kind: .save, title: "")
            }
            addCandidate(Self.copyElement(focusedElement, kAXWindowAttribute))
            var cursor: AXUIElement? = focusedElement
            for _ in 0..<6 {
                guard let parent = cursor.flatMap({ Self.copyElement($0, kAXParentAttribute) }) else { break }
                let role = Self.copyString(parent, kAXRoleAttribute) ?? ""
                if role == kAXSheetRole || role == kAXWindowRole {
                    addCandidate(parent)
                }
                cursor = parent
            }
        }

        // 2. Feuilles attachées (AXSheets et enfants AXSheet) de la fenêtre active/principale.
        let primaryWindows = [
            Self.copyElement(appElement, kAXFocusedWindowAttribute),
            Self.copyElement(appElement, kAXMainWindowAttribute),
        ].compactMap(\.self)
        for win in primaryWindows {
            if let sheets = Self.copyElementArray(win, "AXSheets") {
                for sheet in sheets { addCandidate(sheet) }
            }
            if let children = Self.copyElementArray(win, kAXChildrenAttribute) {
                for child in children where Self.copyString(child, kAXRoleAttribute) == kAXSheetRole {
                    addCandidate(child)
                }
            }
            addCandidate(win)
        }

        // 3. Toutes les fenêtres AX exposées par l'application (inclut les dialogues Powerbox XPC).
        if let windows = Self.copyElementArray(appElement, kAXWindowsAttribute) {
            for win in windows.prefix(10) {
                if let sheets = Self.copyElementArray(win, "AXSheets") {
                    for sheet in sheets { addCandidate(sheet) }
                }
                addCandidate(win)
            }
        }

        for element in candidates {
            AXUIElementSetMessagingTimeout(element, 0.12)
            let role = Self.copyString(element, kAXRoleAttribute)
            let subrole = Self.copyString(element, kAXSubroleAttribute)
            let identifier = Self.copyString(element, kAXIdentifierAttribute)
            let title = Self.copyString(element, kAXTitleAttribute)
            let probe = Self.probePanelChildren(element, maxNodes: 120)
            if let kind = Self.classify(
                role: role,
                subrole: subrole,
                identifier: identifier,
                title: title,
                hasFileBrowser: probe.hasFileBrowser,
                hasSaveField: probe.hasSaveField,
                hasDialogButtons: probe.hasDialogButtons,
                hasSaveButton: probe.hasSaveButton
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

        let appElement = AXUIElementCreateApplication(context.pid)
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        // Mémoriser l'élément focalisé AVANT ⌘⇧G (ex. le champ « Save As: Untitled ») afin de ne
        // JAMAIS écrire le chemin dans le nom du fichier en cours d'enregistrement.
        let previousFocused = Self.copyElement(appElement, kAXFocusedUIElementAttribute)

        // 1. Envoyer ⌘⇧G (keycode 5 = 'g') pour ouvrir la feuille native « Aller au dossier ».
        Self.postKey(keyCode: 5, flags: [.maskCommand, .maskShift])
        Thread.sleep(forTimeInterval: 0.06)

        // 2. Attendre l'apparition du NOUVEAU champ texte de la feuille « Aller au dossier » (500 ms max).
        let deadline = Date().addingTimeInterval(0.5)
        var targetField: AXUIElement?
        while Date() < deadline {
            if let focused = Self.copyElement(appElement, kAXFocusedUIElementAttribute) {
                let isSameAsBefore = previousFocused.map { CFEqual($0, focused) } ?? false
                let role = Self.copyString(focused, kAXRoleAttribute) ?? ""
                if !isSameAsBefore && (role == kAXComboBoxRole || role == kAXTextFieldRole) {
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

    private struct PanelProbeResult {
        var hasFileBrowser = false
        var hasSaveField = false
        var hasSaveButton = false
        var hasOpenButton = false
        var hasCancelButton = false
        var hasNewFolderButton = false

        var hasDialogButtons: Bool {
            (hasSaveButton || hasOpenButton) && (hasCancelButton || hasNewFolderButton)
        }
    }

    private static func probePanelChildren(_ root: AXUIElement, maxNodes: Int) -> PanelProbeResult {
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        var probe = PanelProbeResult()

        while let (node, depth) = stack.popLast(), visited < maxNodes {
            visited += 1
            let role = copyString(node, kAXRoleAttribute) ?? ""
            let identifier = (copyString(node, kAXIdentifierAttribute) ?? "").lowercased()
            let title = (copyString(node, kAXTitleAttribute) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let desc = (copyString(node, kAXDescriptionAttribute) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if role == "AXBrowser" || (role == "AXOutline" && (identifier.contains("file") || identifier.contains("sidebar"))) || identifier.contains("open-panel") {
                probe.hasFileBrowser = true
            }
            if identifier.contains("saveasnametextfield") || identifier.contains("save-panel") || identifier.contains("namefieldstringvalue")
                || (role == kAXTextFieldRole && (desc.contains("save as") || desc.contains("enregistrer sous"))) {
                probe.hasSaveField = true
            }
            if role == kAXButtonRole {
                if saveButtonTitles.contains(title) { probe.hasSaveButton = true }
                if openButtonTitles.contains(title) { probe.hasOpenButton = true }
                if cancelButtonTitles.contains(title) { probe.hasCancelButton = true }
                if newFolderButtonTitles.contains(title) { probe.hasNewFolderButton = true }
            }
            if probe.hasFileBrowser && probe.hasSaveField { break }
            guard depth < 6, let children = copyElementArray(node, kAXChildrenAttribute) else { continue }
            for child in children.prefix(24) {
                stack.append((child, depth + 1))
            }
        }
        return probe
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
