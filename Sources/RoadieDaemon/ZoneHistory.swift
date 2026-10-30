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
    /// Zone née d'un clic ordinaire (session 136), plafonnée par fenêtre ; nil ou faux : recherche à l'écran.
    var fromClick: Bool?

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

/// Retour à une zone, sans écran. O(1).
enum ZoneNavigation {
    /// Écart de taille de fenêtre toléré pour retrouver une zone par sa position relative.
    static let sizeTolerance = 4.0

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

extension ZoneNavigation {
    /// Cadre de la zone à l'écran (accessibilité) d'après sa fenêtre affichée, ou nil si la fenêtre n'est pas à
    /// l'écran (réduite, cachée) ou si le centre de la zone tombe hors des écrans (fenêtre d'une autre stage, poussée
    /// dans un coin par Roadie). O(é).
    static func screenRect(of record: ZoneRecord, window: WindowSwitcherEntry, screens: [CGRect]) -> CGRect? {
        guard window.window.isOnScreen, !window.isMinimized, !window.isHidden else { return nil }
        let frame = window.window.frame
        let rect = record.relative.cgRect.offsetBy(dx: frame.x, dy: frame.y)
        return screens.contains { $0.contains(CGPoint(x: rect.midX, y: rect.midY)) } ? rect : nil
    }
}

/// Conservation des zones (session 136) : nombre, âge, zones des clics par fenêtre. Réglages de `[switcher]`.
struct ZonePolicy: Equatable, Sendable {
    var maxCount = 20
    var maxAge: TimeInterval = 24 * 3600
    var clicksPerWindow = 3

    /// Zones utiles seulement avec un profil `zones` actif (session 136) : sans lui, ni zone, ni photo. O(p).
    static func isUsed(_ config: WindowSwitcherConfig) -> Bool {
        config.enabled && config.shortcuts.contains { $0.enabled && $0.source == "zones" }
    }

    @MainActor static var current: ZonePolicy {
        let config = ConfigReloadService.shared.currentConfig().switcher
        return ZonePolicy(maxCount: config.zoneHistorySize, maxAge: TimeInterval(config.zoneHistoryHours) * 3600,
                          clicksPerWindow: config.zoneClicksPerWindow)
    }

    /// Zones gardées, dans l'ordre : assez récentes, au plus `clicksPerWindow` zones de clics par fenêtre (les plus
    /// récentes), puis `maxCount` au plus. O(n).
    func kept(_ records: [ZoneRecord], now: Date) -> [ZoneRecord] {
        var clicks: [UInt32: Int] = [:]
        let recent = records.filter { record in
            guard now.timeIntervalSince(record.date) <= maxAge else { return false }
            guard record.fromClick == true else { return true }
            clicks[record.windowID, default: 0] += 1
            return clicks[record.windowID, default: 0] <= clicksPerWindow
        }
        return Array(recent.prefix(maxCount))
    }
}

/// Historique des zones (sessions 135 et 136), le plus récent d'abord, dans `~/.roadies/zone-history.json`. Les
/// éléments d'accessibilité restent en mémoire : après un redémarrage, la position relative prend le relais.
@MainActor
final class ZoneHistory {
    static let shared = ZoneHistory()

    private let path: String
    private(set) var records: [ZoneRecord]
    private var elements: [String: AXUIElement] = [:]

    init(path: String = NSString(string: TestEnvironment.launcherFile("zone-history.json")).expandingTildeInPath) {
        self.path = path
        let data = FileManager.default.contents(atPath: path)
        records = data.flatMap { try? JSONDecoder().decode([ZoneRecord].self, from: $0) } ?? []
    }

    /// Zone en tête ; la même zone n'apparaît qu'une fois. Rend les zones sorties de l'historique (photos à
    /// effacer). O(n).
    @discardableResult
    func record(_ record: ZoneRecord, element: AXUIElement?, policy: ZonePolicy, now: Date = Date()) -> [String] {
        elements[record.key] = element
        return apply([record] + records.filter { $0.key != record.key }, policy: policy, now: now)
    }

    /// Zones encore valables (âge, nombre) ; rend celles qui sortent. O(n).
    @discardableResult
    func prune(policy: ZonePolicy, now: Date = Date()) -> [String] {
        apply(records, policy: policy, now: now)
    }

    private func apply(_ candidates: [ZoneRecord], policy: ZonePolicy, now: Date) -> [String] {
        let before = Set(records.map(\.key)).union(candidates.map(\.key))
        let kept = policy.kept(candidates, now: now)
        let keys = Set(kept.map(\.key))
        let changed = kept != records
        records = kept
        elements = elements.filter { keys.contains($0.key) }
        if changed { save() }
        return before.subtracting(keys).sorted()
    }

    /// Zone où l'on revient : elle remonte en tête, datée de maintenant, avec son élément et sa photo. Comme une
    /// fenêtre activée par ⌘Tab, elle devient la plus récente : un second appui ramène à la précédente (essai du 30
    /// octobre 2026 : l'ordre ne bougeait pas, ⌥Tab reproposait toujours la même zone). O(n).
    func touch(_ record: ZoneRecord, now: Date = Date()) {
        guard let index = records.firstIndex(where: { $0.key == record.key }) else { return }
        var moved = records.remove(at: index)
        moved.date = now
        records.insert(moved, at: 0)
        save()
    }

    /// Zones de clics d'une application, retirées (sens interdit, session 137) ; rend leurs clés. O(n).
    func forgetClicks(bundleID: String) -> [String] {
        let dropped = records.filter { $0.fromClick == true && $0.bundleID == bundleID }.map(\.key)
        guard !dropped.isEmpty else { return [] }
        records.removeAll { $0.fromClick == true && $0.bundleID == bundleID }
        save()
        return dropped
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

/// Enregistrement d'une zone, commun à la recherche à l'écran et aux clics (session 136) : historique, photos des
/// zones sorties effacées, photo de la nouvelle zone prise tout de suite.
@MainActor
enum ZoneRecorder {
    static func remember(_ record: ZoneRecord, element: AXUIElement?, events: EventLog) {
        guard ZonePolicy.isUsed(ConfigReloadService.shared.currentConfig().switcher) else { return }
        ZoneHistory.shared.record(record, element: element, policy: .current).forEach(ZoneThumbnails.shared.remove)
        events.append(RoadieEvent(type: "zone.recorded", details: [
            "app": record.appName, "source": record.fromClick == true ? "click" : "search",
            "count": String(ZoneHistory.shared.records.count)]))
        Task { @MainActor in
            let crop = await ZoneThumbnails.shared.capture(key: record.key, windowID: record.windowID, zone: record.relative.cgRect,
                                                           windowSize: CGSize(width: record.windowWidth, height: record.windowHeight)) { outcome in
                if outcome != "ok" { events.append(RoadieEvent(type: "zone.thumbnail", details: ["app": record.appName, "outcome": outcome])) }
            }
            if let crop { ZoneHistory.shared.setThumbnail(crop, for: record.key) }
        }
    }
}
