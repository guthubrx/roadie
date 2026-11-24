import Foundation
import RoadieCore

/// Élément du sélecteur hors ligne d'émojis et symboles typographiques (Spec 161).
struct LauncherEmojiItem: Equatable, Hashable, Sendable {
    let id: String
    let glyph: String
    let name: String
    let keywords: [String]
    let category: String

    var foldedSearch: String {
        LauncherMatch.fold(([name] + keywords).joined(separator: " "))
    }
}

/// Catalogue bilingue FR/EN 100 % hors ligne d'émojis courants, touches macOS et symboles typographiques (Spec 161).
enum LauncherEmojiCatalog {
    static let all: [LauncherEmojiItem] = [
        // Touches macOS & raccourcis
        .init(id: "cmd", glyph: "⌘", name: tr("Commande (⌘)", "Command (⌘)"), keywords: ["cmd", "command", "commande", "mac", "apple", "touche"], category: "macOS"),
        .init(id: "opt", glyph: "⌥", name: tr("Option / Alt (⌥)", "Option / Alt (⌥)"), keywords: ["opt", "option", "alt", "mac", "touche"], category: "macOS"),
        .init(id: "shift", glyph: "⇧", name: tr("Majuscule / Shift (⇧)", "Shift (⇧)"), keywords: ["shift", "maj", "majuscule", "touche"], category: "macOS"),
        .init(id: "ctrl", glyph: "⌃", name: tr("Contrôle / Ctrl (⌃)", "Control / Ctrl (⌃)"), keywords: ["ctrl", "control", "controle", "touche"], category: "macOS"),
        .init(id: "ret", glyph: "⏎", name: tr("Retour / Entrée (⏎)", "Return / Enter (⏎)"), keywords: ["return", "enter", "retour", "entree", "touche"], category: "macOS"),
        .init(id: "del", glyph: "⌫", name: tr("Effacer / Backspace (⌫)", "Delete / Backspace (⌫)"), keywords: ["backspace", "delete", "effacer", "suppr"], category: "macOS"),
        .init(id: "esc", glyph: "⎋", name: tr("Échap / Escape (⎋)", "Escape (⎋)"), keywords: ["esc", "escape", "echap", "touche"], category: "macOS"),
        .init(id: "tab", glyph: "⇥", name: tr("Tabulation (⇥)", "Tab (⇥)"), keywords: ["tab", "tabulation", "touche"], category: "macOS"),
        .init(id: "caps", glyph: "⇪", name: tr("Verr. Maj (⇪)", "Caps Lock (⇪)"), keywords: ["caps", "capslock", "verr maj", "hyper"], category: "macOS"),
        // Flèches & typographie
        .init(id: "arrow-right", glyph: "→", name: tr("Flèche droite", "Right arrow"), keywords: ["fleche", "arrow", "droite", "right", "->"], category: tr("Typographie", "Typography")),
        .init(id: "arrow-left", glyph: "←", name: tr("Flèche gauche", "Left arrow"), keywords: ["fleche", "arrow", "gauche", "left", "<-"], category: tr("Typographie", "Typography")),
        .init(id: "arrow-up", glyph: "↑", name: tr("Flèche haut", "Up arrow"), keywords: ["fleche", "arrow", "haut", "up"], category: tr("Typographie", "Typography")),
        .init(id: "arrow-down", glyph: "↓", name: tr("Flèche bas", "Down arrow"), keywords: ["fleche", "arrow", "bas", "down"], category: tr("Typographie", "Typography")),
        .init(id: "arrow-lr", glyph: "↔", name: tr("Double flèche", "Left-right arrow"), keywords: ["fleche", "arrow", "swap", "echange", "both"], category: tr("Typographie", "Typography")),
        .init(id: "emdash", glyph: "—", name: tr("Tiret cadratin", "Em dash"), keywords: ["tiret", "dash", "emdash", "cadratin", "--"], category: tr("Typographie", "Typography")),
        .init(id: "endash", glyph: "–", name: tr("Tiret demi-cadratin", "En dash"), keywords: ["tiret", "dash", "endash"], category: tr("Typographie", "Typography")),
        .init(id: "ellipsis", glyph: "…", name: tr("Points de suspension", "Ellipsis"), keywords: ["points", "suspension", "ellipsis", "..."], category: tr("Typographie", "Typography")),
        .init(id: "bullet", glyph: "•", name: tr("Puce", "Bullet"), keywords: ["puce", "bullet", "point", "liste"], category: tr("Typographie", "Typography")),
        .init(id: "check-sym", glyph: "✓", name: tr("Coche typographique", "Check mark"), keywords: ["check", "coche", "ok", "valide", "oui"], category: tr("Typographie", "Typography")),
        .init(id: "cross-sym", glyph: "✗", name: tr("Croix typographique", "Cross mark"), keywords: ["cross", "croix", "non", "erreur", "ko"], category: tr("Typographie", "Typography")),
        .init(id: "euro", glyph: "€", name: tr("Euro", "Euro"), keywords: ["euro", "eur", "monnaie", "devise"], category: tr("Typographie", "Typography")),
        .init(id: "pound", glyph: "£", name: tr("Livre sterling", "Pound sterling"), keywords: ["pound", "gbp", "livre"], category: tr("Typographie", "Typography")),
        .init(id: "yen", glyph: "¥", name: tr("Yen", "Yen"), keywords: ["yen", "jpy"], category: tr("Typographie", "Typography")),
        .init(id: "copy", glyph: "©", name: "Copyright", keywords: ["copyright", "c", "droit"], category: tr("Typographie", "Typography")),
        .init(id: "reg", glyph: "®", name: tr("Marque déposée", "Registered"), keywords: ["registered", "marque", "r"], category: tr("Typographie", "Typography")),
        .init(id: "tm", glyph: "™", name: tr("Marque commerciale", "Trademark"), keywords: ["trademark", "tm", "marque"], category: tr("Typographie", "Typography")),
        .init(id: "pm", glyph: "±", name: tr("Plus ou moins", "Plus-minus"), keywords: ["plus", "moins", "pm", "math"], category: tr("Typographie", "Typography")),
        .init(id: "approx", glyph: "≈", name: tr("Environ égal", "Approximately equal"), keywords: ["approx", "environ", "math"], category: tr("Typographie", "Typography")),
        .init(id: "neq", glyph: "≠", name: tr("Différent", "Not equal"), keywords: ["neq", "different", "inegal", "math"], category: tr("Typographie", "Typography")),
        .init(id: "leq", glyph: "≤", name: tr("Inférieur ou égal", "Less than or equal"), keywords: ["leq", "inferieur", "math"], category: tr("Typographie", "Typography")),
        .init(id: "geq", glyph: "≥", name: tr("Supérieur ou égal", "Greater than or equal"), keywords: ["geq", "superieur", "math"], category: tr("Typographie", "Typography")),
        .init(id: "deg", glyph: "°", name: tr("Degré", "Degree"), keywords: ["degre", "degree", "temperature", "angle"], category: tr("Typographie", "Typography")),
        .init(id: "times", glyph: "×", name: tr("Multiplication", "Multiplication"), keywords: ["fois", "times", "mult", "math"], category: tr("Typographie", "Typography")),
        .init(id: "div", glyph: "÷", name: tr("Division", "Division"), keywords: ["div", "division", "math"], category: tr("Typographie", "Typography")),
        .init(id: "guil-l", glyph: "«", name: tr("Guillemet ouvrant", "Left guillemet"), keywords: ["guillemet", "quote", "francais"], category: tr("Typographie", "Typography")),
        .init(id: "guil-r", glyph: "»", name: tr("Guillemet fermant", "Right guillemet"), keywords: ["guillemet", "quote", "francais"], category: tr("Typographie", "Typography")),
        .init(id: "section", glyph: "§", name: tr("Paragraphe", "Section sign"), keywords: ["section", "paragraphe", "droit"], category: tr("Typographie", "Typography")),
        // Émojis : statuts, dev & productivité
        .init(id: "check", glyph: "✅", name: tr("Validé", "Check mark button"), keywords: ["ok", "done", "fait", "valide", "check", "vert", "yes", "oui"], category: "Emoji"),
        .init(id: "cross", glyph: "❌", name: tr("Erreur / Non", "Cross mark"), keywords: ["no", "non", "erreur", "error", "fail", "rouge", "x"], category: "Emoji"),
        .init(id: "warn", glyph: "⚠️", name: tr("Avertissement", "Warning"), keywords: ["warning", "attention", "alerte", "danger", "warn"], category: "Emoji"),
        .init(id: "fire", glyph: "🔥", name: tr("Feu", "Fire"), keywords: ["fire", "feu", "hot", "flamme", "top"], category: "Emoji"),
        .init(id: "rocket", glyph: "🚀", name: tr("Fusée", "Rocket"), keywords: ["rocket", "fusee", "launch", "deploy", "ship", "lancement"], category: "Emoji"),
        .init(id: "sparkles", glyph: "✨", name: tr("Étincelles", "Sparkles"), keywords: ["sparkles", "etincelles", "magie", "nouveau", "clean", "new"], category: "Emoji"),
        .init(id: "tada", glyph: "🎉", name: tr("Fête", "Party popper"), keywords: ["tada", "party", "fete", "bravo", "celebrate", "congrats"], category: "Emoji"),
        .init(id: "bulb", glyph: "💡", name: tr("Idée", "Light bulb"), keywords: ["idea", "idee", "ampoule", "tip", "astuce", "bulb"], category: "Emoji"),
        .init(id: "bug", glyph: "🐛", name: tr("Bug", "Bug"), keywords: ["bug", "insecte", "fix", "debug"], category: "Emoji"),
        .init(id: "wrench", glyph: "🔧", name: tr("Outil / Réglage", "Wrench"), keywords: ["wrench", "outil", "cle", "fix", "config", "reglage"], category: "Emoji"),
        .init(id: "gear", glyph: "⚙️", name: tr("Paramètres", "Gear"), keywords: ["gear", "settings", "parametres", "roue", "config"], category: "Emoji"),
        .init(id: "lock", glyph: "🔒", name: tr("Verrouillé", "Locked"), keywords: ["lock", "cadenas", "securite", "prive", "security"], category: "Emoji"),
        .init(id: "key", glyph: "🔑", name: tr("Clé", "Key"), keywords: ["key", "cle", "password", "secret", "auth"], category: "Emoji"),
        .init(id: "pin", glyph: "📌", name: tr("Épingle", "Pushpin"), keywords: ["pin", "epingle", "fixe", "important"], category: "Emoji"),
        .init(id: "memo", glyph: "📝", name: tr("Note", "Memo"), keywords: ["memo", "note", "ecrire", "doc", "texte"], category: "Emoji"),
        .init(id: "folder", glyph: "📁", name: tr("Dossier", "Folder"), keywords: ["folder", "dossier", "fichier", "dir"], category: "Emoji"),
        .init(id: "clip", glyph: "📎", name: tr("Pièce jointe", "Paperclip"), keywords: ["clip", "trombone", "piece jointe", "attach"], category: "Emoji"),
        .init(id: "link", glyph: "🔗", name: tr("Lien", "Link"), keywords: ["link", "lien", "url", "chaine"], category: "Emoji"),
        .init(id: "search", glyph: "🔍", name: tr("Recherche", "Magnifying glass"), keywords: ["search", "loupe", "chercher", "find"], category: "Emoji"),
        .init(id: "clock", glyph: "⏱️", name: tr("Chronomètre", "Stopwatch"), keywords: ["timer", "chrono", "temps", "clock", "heure", "perf"], category: "Emoji"),
        .init(id: "hourglass", glyph: "⏳", name: tr("Sablier", "Hourglass"), keywords: ["wait", "attente", "sablier", "loading", "en cours"], category: "Emoji"),
        .init(id: "calendar", glyph: "📅", name: tr("Calendrier", "Calendar"), keywords: ["calendar", "date", "agenda", "calendrier", "rdv"], category: "Emoji"),
        .init(id: "chart", glyph: "📊", name: tr("Graphique", "Bar chart"), keywords: ["chart", "stats", "graphique", "data", "metrics"], category: "Emoji"),
        .init(id: "zap", glyph: "⚡", name: tr("Éclair / Rapide", "High voltage"), keywords: ["zap", "fast", "rapide", "eclair", "perf", "vitesse"], category: "Emoji"),
        .init(id: "target", glyph: "🎯", name: tr("Cible / Objectif", "Direct hit"), keywords: ["target", "cible", "goal", "objectif", "focus"], category: "Emoji"),
        .init(id: "star", glyph: "⭐", name: tr("Étoile", "Star"), keywords: ["star", "etoile", "favori", "favorite"], category: "Emoji"),
        .init(id: "heart", glyph: "❤️", name: tr("Cœur", "Red heart"), keywords: ["heart", "coeur", "love", "amour", "merci"], category: "Emoji"),
        .init(id: "coffee", glyph: "☕", name: tr("Café", "Hot beverage"), keywords: ["coffee", "cafe", "pause", "break", "the"], category: "Emoji"),
        .init(id: "tomato", glyph: "🍅", name: "Pomodoro", keywords: ["pomodoro", "tomate", "tomato", "timer", "focus"], category: "Emoji"),
        .init(id: "laptop", glyph: "💻", name: tr("Ordinateur", "Laptop"), keywords: ["laptop", "mac", "code", "dev", "ordinateur"], category: "Emoji"),
        .init(id: "mail", glyph: "✉️", name: tr("Courriel", "Envelope"), keywords: ["mail", "email", "message", "enveloppe"], category: "Emoji"),
        .init(id: "bell", glyph: "🔔", name: tr("Notification", "Bell"), keywords: ["bell", "cloche", "notif", "alerte", "rappel"], category: "Emoji"),
        .init(id: "eyes", glyph: "👀", name: tr("Yeux / Revue", "Eyes"), keywords: ["eyes", "yeux", "look", "review", "voir", "regarder"], category: "Emoji"),
        // Visages & mains courants
        .init(id: "thumbsup", glyph: "👍", name: tr("Pouce levé", "Thumbs up"), keywords: ["thumbsup", "pouce", "ok", "super", "cool", "like", "+1"], category: "Emoji"),
        .init(id: "thumbsdown", glyph: "👎", name: tr("Pouce baissé", "Thumbs down"), keywords: ["thumbsdown", "pouce", "non", "-1"], category: "Emoji"),
        .init(id: "clap", glyph: "👏", name: tr("Applaudissements", "Clapping hands"), keywords: ["clap", "bravo", "applaudir"], category: "Emoji"),
        .init(id: "pray", glyph: "🙏", name: tr("Merci / S'il vous plaît", "Folded hands"), keywords: ["pray", "merci", "thanks", "svp", "please"], category: "Emoji"),
        .init(id: "wave", glyph: "👋", name: tr("Bonjour / Salut", "Waving hand"), keywords: ["wave", "bonjour", "salut", "hello", "hi", "coucou"], category: "Emoji"),
        .init(id: "okhand", glyph: "👌", name: tr("Parfait", "OK hand"), keywords: ["ok", "parfait", "perfect", "nickel"], category: "Emoji"),
        .init(id: "smile", glyph: "😊", name: tr("Sourire", "Smiling face"), keywords: ["smile", "sourire", "content", "happy", "heureux"], category: "Emoji"),
        .init(id: "joy", glyph: "😂", name: tr("Rire aux larmes", "Face with tears of joy"), keywords: ["joy", "lol", "mdr", "rire", "laugh"], category: "Emoji"),
        .init(id: "wink", glyph: "😉", name: tr("Clin d'œil", "Winking face"), keywords: ["wink", "clin", "oeil"], category: "Emoji"),
        .init(id: "thinking", glyph: "🤔", name: tr("Réflexion", "Thinking face"), keywords: ["think", "thinking", "hmm", "reflexion", "question"], category: "Emoji"),
        .init(id: "sunglasses", glyph: "😎", name: "Cool", keywords: ["cool", "lunettes", "sunglasses", "classe"], category: "Emoji"),
        .init(id: "shrug", glyph: "🤷", name: tr("Haussement d'épaules", "Shrug"), keywords: ["shrug", "bof", "jsp", "idk", "epaules"], category: "Emoji"),
        .init(id: "sweat", glyph: "😅", name: tr("Ouf / Sourire gêné", "Grinning face with sweat"), keywords: ["sweat", "ouf", "phew", "gene"], category: "Emoji"),
        .init(id: "mindblown", glyph: "🤯", name: tr("Époustouflant", "Exploding head"), keywords: ["mindblown", "wow", "dingue", "incroyable"], category: "Emoji"),
        .init(id: "partyface", glyph: "🥳", name: tr("Festif", "Partying face"), keywords: ["party", "fete", "anniversaire", "bravo"], category: "Emoji"),
        .init(id: "cry", glyph: "😢", name: tr("Triste", "Crying face"), keywords: ["cry", "sad", "triste", "pleure"], category: "Emoji"),
        .init(id: "angry", glyph: "😠", name: tr("Fâché", "Angry face"), keywords: ["angry", "colere", "fache", "enerve"], category: "Emoji"),
        .init(id: "green-dot", glyph: "🟢", name: tr("Point vert", "Green circle"), keywords: ["vert", "green", "ok", "en ligne", "online"], category: "Emoji"),
        .init(id: "orange-dot", glyph: "🟠", name: tr("Point orange", "Orange circle"), keywords: ["orange", "warn", "moyen"], category: "Emoji"),
        .init(id: "red-dot", glyph: "🔴", name: tr("Point rouge", "Red circle"), keywords: ["rouge", "red", "stop", "bloque", "offline"], category: "Emoji"),
        .init(id: "blue-dot", glyph: "🔵", name: tr("Point bleu", "Blue circle"), keywords: ["bleu", "blue", "info"], category: "Emoji"),
    ]

    /// Retourne les correspondances si la requête commence par `:`, `emoji` ou `symbole`.
    /// Retourne `nil` si la saisie ne vise pas le sélecteur d'émojis. O(n).
    static func matches(_ rawQuery: String, limit: Int = 8) -> [LauncherEmojiItem]? {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        let needle: String
        if lower.hasPrefix(":") {
            needle = String(lower.dropFirst()).trimmingCharacters(in: .whitespaces)
        } else if lower == "emoji" || lower == "emojis" || lower == "symbole" || lower == "symboles" {
            needle = ""
        } else if lower.hasPrefix("emoji ") {
            needle = String(lower.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if lower.hasPrefix("emojis ") {
            needle = String(lower.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        } else if lower.hasPrefix("symbole ") {
            needle = String(lower.dropFirst(8)).trimmingCharacters(in: .whitespaces)
        } else if lower.hasPrefix("symboles ") {
            needle = String(lower.dropFirst(9)).trimmingCharacters(in: .whitespaces)
        } else {
            return nil
        }

        if needle.isEmpty {
            return Array(all.prefix(limit))
        }
        let foldedNeedle = LauncherMatch.fold(needle)
        let tokens = foldedNeedle.split(separator: " ").map(String.init)
        let ranked = all.compactMap { item -> (LauncherEmojiItem, Int)? in
            let folded = item.foldedSearch
            guard tokens.allSatisfy({ folded.contains($0) }) else { return nil }
            let exactKeyword = item.keywords.contains { LauncherMatch.fold($0) == foldedNeedle }
            let prefixMatch = item.keywords.contains { LauncherMatch.fold($0).hasPrefix(foldedNeedle) }
                || LauncherMatch.fold(item.name).hasPrefix(foldedNeedle)
            let score = exactKeyword ? 3 : (prefixMatch ? 2 : 1)
            return (item, score)
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name.count < $1.0.name.count }
        return Array(ranked.prefix(limit).map(\.0))
    }
}
