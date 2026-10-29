import Foundation
import RoadieCore

/// Texte comme objet de la barre (session 131), comme les actions universelles d'Alfred sur un texte : copier,
/// chercher sur le web, extraire les adresses, envoyer par e-mail, afficher en grand. Logique pure.
enum LauncherText {
    /// Titre d'un texte sur une ligne : espaces réduits, 80 caractères au plus. O(t).
    static func preview(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count > 80 ? String(flat.prefix(79)) + "…" : flat
    }

    /// Adresse trouvée dans un texte : web ou e-mail.
    struct Address: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case web, email }
        let kind: Kind
        /// Adresse à ouvrir (`https://…` ou `mailto:…`).
        let url: URL
        /// Forme affichée : l'adresse telle qu'écrite, sans `mailto:`.
        let text: String
    }

    /// Adresses web et e-mail du texte, dans l'ordre, sans doublon. O(t).
    static func addresses(in text: String) -> [Address] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen = Set<String>()
        var found: [Address] = []
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, seen.insert(url.absoluteString).inserted else { continue }
            if url.scheme == "mailto" {
                found.append(Address(kind: .email, url: url, text: String(url.absoluteString.dropFirst("mailto:".count))))
            } else if let range = Range(match.range, in: text) {
                found.append(Address(kind: .web, url: url, text: String(text[range])))
            }
        }
        return found
    }

    /// Objet de Capslock + Maj + F : le texte sélectionné s'il n'est pas vide, sinon la fenêtre active. Une sélection
    /// qui n'est qu'une adresse web devient une adresse, avec ses verbes (ouvrir, ouvrir dans une stage…). O(t).
    static func initialSubject(selection: String?, window: LauncherSubject?) -> LauncherSubject? {
        guard let selection else { return window }
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return window }
        if let address = addresses(in: trimmed).first, address.kind == .web, address.text == trimmed { return .url(address.url) }
        return .text(selection)
    }

    /// Nouveau message contenant le texte, par le client de messagerie par défaut. O(t).
    static func mailURL(body: String, subject: String = "") -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
            .filter { !($0.value ?? "").isEmpty }
        return components.url
    }
}
