import ApplicationServices
import CoreGraphics
import Foundation
import RoadieCore

/// Zone trouvée et cliquée par la recherche à l'écran (session 135) : de quoi y revenir par ⌥Tab, même depuis une
/// autre stage ou un autre bureau.
struct ZoneRecord: Codable, Equatable, Sendable {
    var appName: String
    var bundleID: String
    var pid: Int32
    var windowID: UInt32
    var windowTitle: String
    /// Texte de la zone (bouton, cellule, lien).
    var title: String
    /// Cadre de la zone par rapport au coin de sa fenêtre, et taille de la fenêtre à ce moment.
    var relative: Rect
    var windowWidth: Double
    var windowHeight: Double
    var date: Date
    /// Rectangle de la vignette par rapport à la fenêtre (`ZoneThumbnails`), nil sans capture.
    var thumbnailCrop: Rect?

    /// Une zone par fenêtre et par place (8 points près) : deux éléments distincts au même texte restent deux zones
    /// (lignes « AXButton » de T3 Code, essai du 30 octobre 2026) ; recliquer la même zone la remonte en tête.
    var key: String { "\(windowID)|\(Int((relative.x / 8).rounded()))|\(Int((relative.y / 8).rounded()))" }

    /// Texte montré pour une zone : son titre, sauf s'il n'est qu'un nom de rôle (« AXButton ») ; alors le premier
    /// texte visible de l'élément, puis son sous-titre. O(t).
    static func label(title: String, searchText: String?, subtitle: String) -> String {
        let named = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !named.isEmpty, !(named.hasPrefix("AX") && !named.contains(" ")) { return named }
        let visible = (searchText ?? "").split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let text = visible ?? subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return named }
        return text.count > 80 ? String(text.prefix(79)) + "…" : text
    }
}

/// Décisions de ⌥Tab, sans écran. O(1).
public enum ZoneNavigation {
    /// Écart de taille de fenêtre toléré pour retrouver une zone par sa position relative.
    static let sizeTolerance = 4.0

    /// Raccourci réglé, ou le même avec Maj pour reculer (déjà avec Maj : rien à reculer). O(1).
    public static func hotkey(_ setting: String, reverse: Bool) -> String {
        guard reverse, !setting.isEmpty else { return setting }
        return setting.contains("shift") ? "" : "shift+" + setting
    }

    /// Premier choix : la zone la plus récente, sauf si sa fenêtre est déjà au premier plan (on y est déjà) ; à
    /// rebours (⌥⇧Tab), la plus ancienne. O(1).
    static func firstIndex(count: Int, mostRecentWindow: UInt32?, frontWindow: UInt32?, reverse: Bool) -> Int {
        guard count > 0 else { return 0 }
        if reverse { return count - 1 }
        return count > 1 && mostRecentWindow != nil && mostRecentWindow == frontWindow ? 1 : 0
    }

    /// Point à cliquer, une fois la fenêtre revenue : le centre de l'élément mémorisé s'il se lit encore dans la
    /// fenêtre ; sinon la position relative, si la fenêtre a gardé sa taille ; sinon nil (la fenêtre revient,
    /// rien n'est cliqué). Coordonnées de l'accessibilité. O(1).
    static func point(for record: ZoneRecord, elementFrame: Rect?, windowFrame: Rect?) -> CGPoint? {
        guard let window = windowFrame?.cgRect else { return nil }
        if let element = elementFrame?.cgRect, window.contains(CGPoint(x: element.midX, y: element.midY)) {
            return CGPoint(x: element.midX, y: element.midY)
        }
        guard abs(window.width - record.windowWidth) <= sizeTolerance, abs(window.height - record.windowHeight) <= sizeTolerance else {
            return nil
        }
        let zone = record.relative.cgRect
        return CGPoint(x: window.minX + zone.midX, y: window.minY + zone.midY)
    }
}

/// Historique des zones (session 135), le plus récent d'abord, 20 au plus, dans `~/.roadies/zone-history.json`.
/// Les éléments d'accessibilité restent en mémoire : après un redémarrage, la position relative prend le relais.
@MainActor
final class ZoneHistory {
    static let shared = ZoneHistory()
    static let limit = 20

    private let path: String
    private(set) var records: [ZoneRecord]
    private var elements: [String: AXUIElement] = [:]

    init(path: String = NSString(string: TestEnvironment.launcherFile("zone-history.json")).expandingTildeInPath) {
        self.path = path
        let data = FileManager.default.contents(atPath: path)
        records = data.flatMap { try? JSONDecoder().decode([ZoneRecord].self, from: $0) } ?? []
    }

    /// Zone en tête ; la même zone n'apparaît qu'une fois. O(n).
    static func inserting(_ record: ZoneRecord, into records: [ZoneRecord], limit: Int = ZoneHistory.limit) -> [ZoneRecord] {
        Array(([record] + records.filter { $0.key != record.key }).prefix(limit))
    }

    /// `dropped` : zones sorties de l'historique (vignettes à effacer). O(n).
    @discardableResult
    func record(_ record: ZoneRecord, element: AXUIElement?) -> [String] {
        let before = Set(records.map(\.key))
        records = Self.inserting(record, into: records)
        let kept = Set(records.map(\.key))
        elements = elements.filter { kept.contains($0.key) }
        elements[record.key] = element
        save()
        return before.subtracting(kept).sorted()
    }

    /// Vignette capturée pour cette zone. O(n).
    func setThumbnail(_ crop: CGRect, for key: String) {
        guard let index = records.firstIndex(where: { $0.key == key }) else { return }
        records[index].thumbnailCrop = Rect(crop)
        save()
    }

    func element(for record: ZoneRecord) -> AXUIElement? { elements[record.key] }

    /// Zone dont la fenêtre a disparu. O(n).
    func forget(_ record: ZoneRecord) {
        records.removeAll { $0.key == record.key }
        elements[record.key] = nil
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? JSONEncoder().encode(records).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
