import Foundation
import RoadieCore

/// Sélection multiple du lanceur (SPEC-091) : applications, fenêtres et fichiers réunis, dans l'ordre
/// d'ajout, gardés quand la saisie change.
struct LauncherSelection: Equatable, Sendable {
    private(set) var subjects: [LauncherSubject] = []

    var isEmpty: Bool { subjects.isEmpty }
    var count: Int { subjects.count }

    /// Identité d'un objet sélectionnable ; nil pour ce qui ne se sélectionne pas (stage, cible…). O(1).
    static func key(_ subject: LauncherSubject) -> String? {
        switch subject {
        case .app(let app): "app:\(app.bundleID)"
        case .file(let file): "file:\(file.path)"
        case .target(let target) where target.kind == .window: "window:\(target.id)"
        case .target, .project, .url, .text, .openItem: nil
        }
    }

    func contains(_ subject: LauncherSubject) -> Bool {
        guard let key = Self.key(subject) else { return false }
        return subjects.contains { Self.key($0) == key }
    }

    /// ⌥↑ : ajoute ou retire. Rend vrai si l'objet est maintenant choisi. O(s).
    @discardableResult
    mutating func toggle(_ subject: LauncherSubject) -> Bool {
        guard let key = Self.key(subject) else { return false }
        if let index = subjects.firstIndex(where: { Self.key($0) == key }) {
            subjects.remove(at: index)
            return false
        }
        subjects.append(subject)
        return true
    }

    /// ⌥↓ : ajoute s'il n'y est pas. O(s).
    mutating func add(_ subject: LauncherSubject) {
        guard Self.key(subject) != nil, !contains(subject) else { return }
        subjects.append(subject)
    }

    mutating func removeLast() { if !subjects.isEmpty { subjects.removeLast() } }
    mutating func clear() { subjects = [] }

    var hasWindows: Bool { subjects.contains { if case .target = $0 { true } else { false } } }

    /// Chemins des fichiers du lot. O(s).
    var filePaths: [String] { subjects.compactMap { if case .file(let file) = $0 { file.path } else { nil } } }

    /// Verbes du lot proposés s'ils valent pour au moins un objet, dans cet ordre (FR-004).
    static let verbs: [LauncherVerb] = [.sendTo, .bringHere, .close, .minimize, .quit, .hide, .copyPath, .reveal,
                                        .copyFile, .copyTo, .moveFileTo, .copyReplace, .moveReplace, .openWith, .email, .trash,
                                        .makeAlias, .addTag]

    /// Objets concernés par un verbe du lot. Envoyer et Amener ici valent pour tous ; Fermer et Réduire
    /// pour les fenêtres ; Quitter et Masquer pour les applications ; Copier et Montrer pour les
    /// fichiers. O(s).
    func applicable(_ verb: LauncherVerb) -> [LauncherSubject] {
        subjects.filter { subject in
            switch (verb, subject) {
            case (.sendTo, _), (.bringHere, _): true
            case (.close, .target), (.minimize, .target): true
            case (.quit, .app), (.hide, .app): true
            case (.copyPath, .file), (.reveal, .file): true
            // Session 131 : actions d'Alfred sur des fichiers, en une seule fois.
            case (.copyFile, .file), (.copyTo, .file), (.moveFileTo, .file), (.copyReplace, .file), (.moveReplace, .file),
                 (.openWith, .file), (.email, .file), (.trash, .file), (.makeAlias, .file), (.addTag, .file): true
            default: false
            }
        }
    }

    /// Titre d'un verbe du lot avec le nombre d'objets concernés.
    static func title(_ verb: LauncherVerb, count: Int) -> String {
        let n = " (\(count))"
        return switch verb {
        case .sendTo: tr("Envoyer vers…", "Send to…") + n
        case .bringHere: tr("Amener ici", "Bring here") + n
        case .close: tr("Fermer les fenêtres", "Close windows") + n
        case .minimize: tr("Réduire les fenêtres", "Minimize windows") + n
        case .quit: tr("Quitter les applications", "Quit apps") + n
        case .hide: tr("Masquer les applications", "Hide apps") + n
        case .copyPath: tr("Copier les chemins", "Copy paths") + n
        case .reveal: tr("Montrer dans le Finder", "Reveal in Finder") + n
        default: verb.title + n
        }
    }

    /// Actions du lot pour un verbe et une destination : une fenêtre est envoyée, une application ou un
    /// fichier s'ouvre dans la stage visée (pas sur un bureau ou un écran). O(s).
    func actions(_ verb: LauncherVerb, destination: LauncherDestination?) -> [LauncherAction] {
        applicable(verb).compactMap { subject in
            switch (verb, subject) {
            case (.sendTo, .target):
                return LauncherAction(subject: subject, verb: .sendTo, destination: destination)
            case (.sendTo, _):
                switch destination?.kind {
                case .stage?, .newStage?: return LauncherAction(subject: subject, verb: .openIn, destination: destination)
                default: return nil
                }
            default:
                return LauncherAction(subject: subject, verb: verb, destination: destination)
            }
        }
    }
}

extension LauncherActionList {
    /// Verbes d'un lot, chacun avec son nombre ; destinations : celles d'une fenêtre si le lot en
    /// contient une, sinon celles d'une ouverture (stages). O(v + d).
    static func batch(_ selection: LauncherSelection, query: String) -> LauncherActionList {
        var list = LauncherActionList()
        list.appendHeader(tr("\(selection.count) choisi\(selection.count > 1 ? "s" : "") ›", "\(selection.count) selected ›"))
        let folded = LauncherMatch.fold(query)
        for verb in LauncherSelection.verbs {
            let count = selection.applicable(verb).count
            guard count > 0, folded.isEmpty || LauncherMatch.score(query, in: LauncherSelection.title(verb, count: count)) != nil
                || verb.matches(query, app: "") else { continue }
            list.appendVerb(verb)
        }
        return list
    }

    /// Verbe de destination du lot : `sendTo` (toutes destinations) avec une fenêtre, sinon `openIn` ; un verbe de
    /// fichier (session 131) garde le sien. O(1).
    static func batchDestinationVerb(_ selection: LauncherSelection, chosen: LauncherVerb = .sendTo) -> LauncherVerb {
        chosen != .sendTo ? chosen : selection.hasWindows ? .sendTo : .openIn
    }
}
