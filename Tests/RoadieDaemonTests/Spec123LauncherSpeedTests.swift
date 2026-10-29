import Foundation
import Testing
@testable import RoadieDaemon

/// Session 123 : la comparaison accélérée (textes pliés une fois, empreinte des lettres, lecture d'écartement)
/// donne exactement les scores d'avant.
struct Spec123LauncherSpeedTests {
    /// Algorithme d'avant la session 123, gardé comme référence.
    private func reference(_ query: String, in text: String) -> Int? {
        let wanted = Array(LauncherMatch.fold(query).filter { !$0.isWhitespace })
        guard !wanted.isEmpty else { return nil }
        if String(LauncherMatch.fold(text).filter { !$0.isWhitespace }) == String(wanted) { return Int.max }
        let original = Array(text)
        let folded = original.map { LauncherMatch.fold(String($0)).first ?? $0 }
        let starts = original.indices.map { index -> Bool in
            guard index > 0 else { return true }
            let previous = original[index - 1], current = original[index]
            if previous.isWhitespace || "-._/()[]".contains(previous) { return current.isLetter || current.isNumber }
            if current.isUppercase, previous.isLowercase { return true }
            return current.isLetter && previous.isNumber
        }
        let none = Int.min
        var best = [Int](repeating: none, count: folded.count)
        for (i, letter) in wanted.enumerated() {
            var next = [Int](repeating: none, count: folded.count)
            var farthest = none
            for j in folded.indices {
                if j >= 2 { farthest = max(farthest, best[j - 2]) }
                guard folded[j] == letter else { continue }
                let points = j == 0 ? 4 : starts[j] ? 3 : 2
                if i == 0 { next[j] = points; continue }
                if j > 0, best[j - 1] != none { next[j] = best[j - 1] + points }
                if farthest != none { next[j] = max(next[j], farthest + points - 2) }
            }
            best = next
        }
        guard let found = best.max(), found != none, found >= max(3, 2 * wanted.count - 1) else { return nil }
        return found
    }

    private let texts = [
        "Visual Studio Code", "Adobe Photoshop 2026", "Firefox", "OrbStack", "1Password 8", "Réglages Système",
        "Straße und Fluß", "Ｆｕｌｌｗｉｄｔｈ Ｔｅｘｔ", "Éditeur de thème", "chat.openai.com/c/1234", "  Espaces  autour  ",
        "Calculette", "Ghostty", "T3 Code (Beta)", "Microsoft Word", "naïve café crème", "ÇA VA ?", "x", "",
        "Notes — Courses de la semaine", "github.com/guthubrx/roadie/pull/123", "日本語のタイトル",
    ]
    private let queries = [
        "v", "vsc", "code", "ps", "fire", "feox", "orb", "1p", "pass", "reglages", "systeme", "strasse", "fluss",
        "full", "text", "edit", "theme", "chat", "1234", "espaces", "calc", "g", "t3", "word", "naive", "creme",
        "ca va", "x", "courses", "roadie", "pull 123", "日本", "  ", "ß", "ss", "é",
    ]

    @Test func acceleratedScoreEqualsTheReference() {
        for text in texts {
            for query in queries {
                #expect(LauncherMatch.score(query, in: text) == reference(query, in: text), "« \(query) » dans « \(text) »")
            }
        }
    }

    @Test func lettersFingerprintNeverRejectsAMatch() {
        for text in texts {
            let prepared = LauncherMatch.Prepared(text)
            for query in queries {
                guard let query = LauncherMatch.Query(query), reference(String(query.wanted), in: text) != nil else { continue }
                #expect(query.letters & ~prepared.letters == 0 || prepared.compact == query.compact, "« \(query.compact) » dans « \(text) »")
            }
        }
    }

    @Test func indexFindsTheSameBookmarksAsTheList() {
        let pages = texts.enumerated().map { index, title in
            var page = LauncherBookmark(title: title, url: "https://site\(index).example/\(title.prefix(4))", folder: "Historique",
                                        browser: "firefox", profile: "")
            page.tags = index.isMultiple(of: 3) ? ["travail", "Équipe"] : []
            page.visits = index
            return page
        }
        // Règle d'avant la session 123 : titre, puis étiquettes, puis adresse (3 lettres au moins).
        func referenceScore(_ page: LauncherBookmark, _ query: String) -> Int? {
            if let score = reference(query, in: page.title) { return score }
            let needle = LauncherMatch.fold(query)
            if page.tags.contains(where: { LauncherMatch.fold($0).hasPrefix(needle) }) { return 3 }
            guard needle.count >= 3, LauncherMatch.fold(page.url).contains(needle) else { return nil }
            return 1
        }
        let index = LauncherBookmarkIndex(pages)
        for query in queries + ["site", "example", "trav", "equipe", "site1"] {
            for (page, entry) in zip(pages, index.entries) {
                #expect(entry.score(LauncherMatch.Query(query), needle: LauncherMatch.fold(query)) == referenceScore(page, query),
                        "« \(query) » dans « \(page.title) »")
            }
            #expect(LauncherBookmark.matches(query, in: index) == LauncherBookmark.matches(query, in: pages))
        }
    }
}

/// Session 123 : la requête Spotlight lancée hors du fil principal reprend les règles de `predicate`.
struct Spec123SpotlightQueryTests {
    @Test func queryStringsAreValidSpotlightQueriesWithTheSameRules() throws {
        let name = LauncherFileRules.queryString(LauncherFileQuery.parse("rap\"port*"), extraTypes: ["public.movie"])
        #expect(name.hasPrefix("kMDItemDisplayName == \"*rap\\\"port\\**\"cd && ("))
        #expect(name.contains("kMDItemContentTypeTree == \"public.folder\""))
        #expect(name.contains("kMDItemContentTypeTree == \"public.movie\""))
        let content = LauncherFileRules.queryString(LauncherFileQuery.parse("in facture mars"))
        #expect(content.hasPrefix("kMDItemTextContent == \"facture*\"cdw && kMDItemTextContent == \"mars*\"cdw && ("))
        let tag = LauncherFileRules.queryString(LauncherFileQuery.parse("tags rouge"))
        #expect(tag == "kMDItemUserTags == \"rouge*\"cd || kMDItemUserTags == \"Red*\"cd")
        for text in [name, content, tag, LauncherFileRules.recentQueryString(days: LauncherRecentFiles.days)] {
            #expect(NSPredicate(fromMetadataQueryString: text) != nil, "\(text)")
        }
    }
}

/// Session 123 : un fichier déjà ouvert reste devant les fichiers jamais ouverts que Spotlight ajoute ensuite.
struct Spec123FileOrderTests {
    @Test func openedFileStaysAboveNeverOpenedBetterNames() {
        let opened = LauncherFile(path: "/Users/u/Documents/Suivi commandé Maya.xlsx", name: "Suivi commandé Maya.xlsx", isFolder: false,
                                  lastUsed: Date(timeIntervalSince1970: 1_800_000_000))
        let never = ["Commande", "commande-parent.json", "commande-monde.js"].map {
            LauncherFile(path: "/Users/u/Projets/\($0)", name: $0, isFolder: false, lastUsed: nil)
        }
        func files(_ list: [LauncherFile]) -> [String] {
            LauncherList(query: "commande", apps: [], details: [:], targets: [], ranking: LauncherRanking(), now: Date(), files: list)
                .rows.compactMap { if case .file(let file) = $0 { file.name } else { nil } }
        }
        // Avant Spotlight : le fichier ouvert seul ; après : toujours en tête.
        #expect(files([opened]).first == opened.name)
        #expect(files([opened] + never).first == opened.name)
        #expect(files(never + [opened]).first == opened.name)
        // Entre fichiers jamais ouverts, l'appariement du nom décide toujours.
        #expect(files(never).first == "Commande")
    }
}
