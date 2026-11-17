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
    /// Nombre propre à une application (session 140), par identifiant ou nom en minuscules.
    var clicksPerApp: [String: Int] = [:]

    /// Zones de clics par fenêtre pour cette application : la sienne, sinon la valeur globale. O(1).
    func clicksPerWindow(bundleID: String, appName: String) -> Int {
        clicksPerApp[bundleID.lowercased()] ?? clicksPerApp[appName.lowercased()] ?? clicksPerWindow
    }

    /// Table par application, les lignes sans nom écartées. O(a).
    static func perApp(_ rows: [ZoneClicksAppConfig]) -> [String: Int] {
        Dictionary(rows.compactMap { row in
            let app = row.app.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return app.isEmpty ? nil : (app, row.count)
        }, uniquingKeysWith: { _, last in last })
    }

    /// Zones utiles seulement avec un profil `zones` actif (session 136) : sans lui, ni zone, ni photo. O(p).
    static func isUsed(_ config: WindowSwitcherConfig) -> Bool {
        config.enabled && config.shortcuts.contains { $0.enabled && $0.source == "zones" }
    }

    @MainActor static var current: ZonePolicy {
        let config = ConfigReloadService.shared.currentConfig().switcher
        return ZonePolicy(maxCount: config.zoneHistorySize, maxAge: TimeInterval(config.zoneHistoryHours) * 3600,
                          clicksPerWindow: config.zoneClicksPerWindow, clicksPerApp: perApp(config.zoneClicksPerApp))
    }

    /// Zones gardées, dans l'ordre : assez récentes, au plus `clicksPerWindow` zones de clics par fenêtre (les plus
    /// récentes), puis `maxCount` au plus. O(n).
    func kept(_ records: [ZoneRecord], now: Date) -> [ZoneRecord] {
        var clicks: [UInt32: Int] = [:]
        let recent = records.filter { record in
            guard now.timeIntervalSince(record.date) <= maxAge else { return false }
            guard record.fromClick == true else { return true }
            clicks[record.windowID, default: 0] += 1
            return clicks[record.windowID, default: 0] <= clicksPerWindow(bundleID: record.bundleID, appName: record.appName)
        }
        return Array(recent.prefix(maxCount))
    }
}

/// Historique des zones (sessions 135 et 136), le plus récent d'abord, dans `~/.roadies/zone-history.json`. Les
/// éléments d'accessibilité restent en mémoire : après un redémarrage, la position relative prend le relais.
@MainActor
final class ZoneHistory {
    static let shared = ZoneHistory()

    private let url: URL
    private var elements: [String: AXUIElement] = [:]
    var records: [ZoneRecord] {
        JSONPersistence.load([ZoneRecord].self, from: url, default: [])
    }

    init(path: String = NSString(string: TestEnvironment.launcherFile("zone-history.json")).expandingTildeInPath) {
        url = URL(fileURLWithPath: path)
    }

    /// Les photos et les éléments ne sont retirés qu'après une écriture réussie.
    private func update(_ edit: (inout [ZoneRecord]) -> Void) -> [String]? {
        if case .corrupt = JSONPersistence.loadResult([ZoneRecord].self, from: url) { return nil }
        do {
            let removed = try JSONPersistence.mutateChecked([ZoneRecord].self, at: url, default: [], label: "zone-history") { saved in
                let before = Set(saved.map(\.key))
                edit(&saved)
                return before.subtracting(saved.map(\.key)).sorted()
            }
            for key in removed { elements[key] = nil }
            return removed
        } catch {
            fputs("roadie: \(error)\n", stderr)
            return nil
        }
    }

    @discardableResult
    func record(_ record: ZoneRecord, element: AXUIElement?, policy: ZonePolicy, now: Date = Date()) -> [String]? {
        var retained = false
        guard var removed = update({ saved in
            saved = policy.kept([record] + saved.filter { $0.key != record.key }, now: now)
            retained = saved.first?.key == record.key
        }) else { return nil }
        if retained {
            elements[record.key] = element
        } else if !removed.contains(record.key) {
            removed.append(record.key)
            removed.sort()
        }
        return removed
    }

    @discardableResult
    func prune(policy: ZonePolicy, now: Date = Date()) -> [String] {
        let current = records
        guard policy.kept(current, now: now) != current else { return [] }
        return update { $0 = policy.kept($0, now: now) } ?? []
    }

    func touch(_ record: ZoneRecord, now: Date = Date()) {
        _ = update { saved in
            guard let index = saved.firstIndex(where: { $0.key == record.key }) else { return }
            var moved = saved.remove(at: index)
            moved.date = now
            saved.insert(moved, at: 0)
        }
    }

    func forgetClicks(bundleID: String) -> [String] {
        update { $0.removeAll { $0.fromClick == true && $0.bundleID == bundleID } } ?? []
    }

    func setThumbnail(_ crop: CGRect, for key: String) {
        _ = update { saved in
            guard let index = saved.firstIndex(where: { $0.key == key }) else { return }
            saved[index].thumbnailCrop = Rect(crop)
        }
    }

    func element(for record: ZoneRecord) -> AXUIElement? { elements[record.key] }

    @discardableResult
    func forget(_ record: ZoneRecord) -> Bool {
        update { $0.removeAll { $0.key == record.key } }?.contains(record.key) == true
    }
}

/// Enregistrement d'une zone, commun à la recherche à l'écran et aux clics (session 136) : historique, photos des
/// zones sorties effacées, photo de la nouvelle zone prise tout de suite.
@MainActor
enum ZoneRecorder {
    static func remember(_ record: ZoneRecord, element: AXUIElement?, events: EventLog) {
        guard ZonePolicy.isUsed(ConfigReloadService.shared.currentConfig().switcher) else { return }
        guard let removed = ZoneHistory.shared.record(record, element: element, policy: .current) else { return }
        removed.forEach(ZoneThumbnails.shared.remove)
        guard !removed.contains(record.key) else { return }
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
