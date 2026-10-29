import Foundation
import RoadieCore

/// Place d'une fenêtre après son placement, demandée par une phrase ou une abréviation (SPEC-079).
enum LauncherPosition: String, Codable, Sendable {
    case left, right, full, float

    var title: String {
        switch self {
        case .left: tr("à gauche", "on the left")
        case .right: tr("à droite", "on the right")
        case .full: tr("en plein écran", "full screen")
        case .float: tr("en flottant", "floating")
        }
    }
}

/// Phrase du lanceur (SPEC-079) : « fire perso gauche » = objet `fire`, stage Perso, à gauche. Les mots
/// sont reconnus en français et en anglais à la fois ; les noms restent ceux de l'utilisateur.
struct LauncherPhrase: Equatable, Sendable {
    enum Place: Equatable, Sendable {
        case none
        case here
        case destination(LauncherDestination)
    }

    let objectQuery: String
    let place: Place
    let position: LauncherPosition?

    private static let positions: [String: LauncherPosition] = [
        "gauche": .left, "left": .left, "droite": .right, "right": .right,
        "plein": .full, "full": .full, "max": .full, "flotte": .float, "flottant": .float, "float": .float,
    ]
    private static let here: Set<String> = ["ici", "here"]
    private static let fresh: Set<String> = ["nouvelle", "new"]
    private static let desktop: Set<String> = ["bureau", "desktop"]
    private static let screen: Set<String> = ["ecran", "screen"]

    /// Lecture de la fin vers le début : position, ici, nouvelle stage, bureau N, écran N, nom de stage
    /// (un ou deux mots, exact ou début unique de 3 lettres au moins) ; arrêt au premier mot inconnu.
    /// nil : pas de phrase (un seul mot, rien de reconnu, ou rien avant). O(m × d).
    static func parse(_ query: String, destinations: [LauncherDestination], newStageHome: (DisplayID, DesktopID)) -> LauncherPhrase? {
        let words = query.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return nil }
        var end = words.count
        var position: LauncherPosition?
        var place = Place.none
        while end > 1 {
            let word = LauncherMatch.fold(words[end - 1])
            if position == nil, let found = positions[word] {
                position = found
                end -= 1
                continue
            }
            guard place == .none else { break }
            if here.contains(word) {
                place = .here
                end -= 1
                continue
            }
            if fresh.contains(word) || (word == "stage" && end >= 3 && fresh.contains(LauncherMatch.fold(words[end - 2]))) {
                end -= word == "stage" ? 2 : 1
                place = .destination(LauncherDestination(kind: .newStage(name: nil, newStageHome.0, newStageHome.1),
                                                         title: tr("Nouvelle stage", "New stage"), detail: tr("bureau", "desktop") + " \(newStageHome.1.rawValue)"))
                continue
            }
            if let number = Int(word), end >= 3 {
                let keyword = LauncherMatch.fold(words[end - 2])
                if desktop.contains(keyword) {
                    let id = DesktopID(rawValue: number)
                    place = .destination(destinations.first { $0.kind == .desktop(newStageHome.0, id) }
                        ?? LauncherDestination(kind: .desktop(newStageHome.0, id), title: tr("Bureau", "Desktop") + " \(number)", detail: ""))
                    end -= 2
                    continue
                }
                if screen.contains(keyword) {
                    let screens = destinations.filter { if case .display = $0.kind { true } else { false } }
                    guard number >= 1, number <= screens.count else { break }
                    place = .destination(screens[number - 1])
                    end -= 2
                    continue
                }
            }
            if let (stage, span) = stageName(words, end: end, destinations: destinations) {
                place = .destination(stage)
                end -= span
                continue
            }
            break
        }
        guard end >= 1, end < words.count, place != .none || position != nil else { return nil }
        return LauncherPhrase(objectQuery: words[0..<end].joined(separator: " "), place: place, position: position)
    }

    /// Stage nommée par les deux ou le dernier mot : nom exact, sinon début unique d'au moins 3 lettres.
    private static func stageName(_ words: [String], end: Int, destinations: [LauncherDestination]) -> (LauncherDestination, Int)? {
        let stages = destinations.filter { if case .stage = $0.kind { true } else { false } }
        for span in [2, 1] where end - span >= 1 {
            let name = LauncherMatch.fold(words[(end - span)..<end].joined(separator: " "))
            if let exact = stages.first(where: { LauncherMatch.fold($0.title) == name }) { return (exact, span) }
            guard span == 1, name.count >= 3 else { continue }
            let starts = stages.filter { LauncherMatch.fold($0.title).hasPrefix(name) }
            if starts.count == 1 { return (starts[0], 1) }
        }
        return nil
    }

    /// Action de la phrase sur l'objet trouvé ; nil si elle ne s'y applique pas. O(1).
    func action(for subject: LauncherSubject, activeStage: StageScope?) -> LauncherAction? {
        let here = activeStage.map { LauncherDestination(kind: .stage($0), title: tr("ici", "here"), detail: "") }
        func make(_ verb: LauncherVerb, _ destination: LauncherDestination?) -> LauncherAction {
            var action = LauncherAction(subject: subject, verb: verb, destination: destination)
            action.position = position
            return action
        }
        switch subject {
        case .text, .openItem:
            return nil
        case .app, .file, .url:
            switch place {
            case .none: return make(.open, nil)
            case .here: return here.map { make(.bringHere, $0) }
            case .destination(let destination):
                switch destination.kind {
                case .stage, .newStage: return make(.openIn, destination)
                case .desktop, .display, .document, .folder, .application, .tag: return nil
                }
            }
        case .target(let target):
            switch (target.kind, place) {
            case (.window, .none): return make(.focus, nil)
            case (.window, .here): return here.map { make(.bringHere, $0) }
            case (.window, .destination(let destination)):
                return LauncherActionList.ownStage(of: subject).map({ .stage($0) }) == destination.kind ? nil : make(.sendTo, destination)
            case (.stage, .destination(let destination)), (.desktop, .destination(let destination)):
                guard position == nil, LauncherDestination.acceptsMove(destination, of: target.kind) else { return nil }
                return make(.moveTo, destination)
            default:
                return nil
            }
        case .project:
            return nil
        }
    }

    /// Ce que la ligne annonce : « Ouvrir Firefox dans Perso, à gauche ».
    static func title(_ action: LauncherAction) -> String {
        let name = action.subject.appName
        let target = action.destination?.title ?? ""
        let base: String = switch action.verb {
        case .open: tr("Ouvrir \(name)", "Open \(name)")
        case .openIn: tr("Ouvrir \(name) dans \(target)", "Open \(name) in \(target)")
        case .bringHere: tr("Amener \(name) ici", "Bring \(name) here")
        case .sendTo: tr("Envoyer \(name) vers \(target)", "Send \(name) to \(target)")
        case .focus: tr("Aller à \(name)", "Go to \(name)")
        case .moveTo: tr("Déplacer \(name) vers \(target)", "Move \(name) to \(target)")
        default: "\(action.verb.title) \(name)"
        }
        return action.position.map { "\(base), \($0.title)" } ?? base
    }
}
