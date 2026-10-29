import Foundation
import RoadieCore

/// Chronométrage d'une ouverture de la barre (session 123) : attente de la touche, étapes faites avant
/// l'affichage, premier dessin, arrivée des listes lues en fond, plus long blocage du fil principal et
/// coût des dessins. Un seul événement `launcher.timing` à la fermeture, sans saisie ni titre.
@MainActor
final class LauncherOpenClock {
    static private(set) var current: LauncherOpenClock?
    /// Attente de la dernière touche Carbon avant son traitement, lue par la prochaine ouverture.
    static var pendingKeyLagMs: Double?

    private let start = DispatchTime.now().uptimeNanoseconds
    private let keyLagMs: Double?
    private var marks: [String: Double] = [:]
    private var lastTick: UInt64?
    private var maxStallMs = 0.0
    private var renders = 0
    private var renderTotalMs = 0.0
    private var renderMaxMs = 0.0
    private var parts: [String: (total: Double, max: Double)] = [:]
    private var draws = 0
    private var drawTotalMs = 0.0
    private var drawMaxMs = 0.0

    private init(keyLagMs: Double?) { self.keyLagMs = keyLagMs }

    static func begin() -> LauncherOpenClock {
        let clock = LauncherOpenClock(keyLagMs: pendingKeyLagMs)
        pendingKeyLagMs = nil
        current = clock
        return clock
    }

    private func elapsedMs(since origin: UInt64? = nil) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - (origin ?? start)) / 1_000_000
    }

    /// Instant d'une étape depuis l'ouverture ; seule la première occurrence compte. O(1).
    func mark(_ name: String) {
        if marks[name] == nil { marks[name] = elapsedMs() }
    }

    /// Battement du minuteur de la barre (50 ms) : un écart plus grand est un blocage du fil principal. O(1).
    func tick(interval: Double) {
        let now = DispatchTime.now().uptimeNanoseconds
        if let lastTick { maxStallMs = max(maxStallMs, Double(now - lastTick) / 1_000_000 - interval * 1000) }
        lastTick = now
    }

    /// Mesure un dessin de la liste. O(1) en plus du dessin.
    func measureRender(_ body: () -> Void) {
        let begin = DispatchTime.now().uptimeNanoseconds
        body()
        let ms = elapsedMs(since: begin)
        renders += 1
        renderTotalMs += ms
        renderMaxMs = max(renderMaxMs, ms)
    }

    /// Mesure une partie nommée du redessin (`rows`, `files`) quand une ouverture est chronométrée. O(1) en plus.
    static func measure<T>(_ name: String, _ body: () -> T) -> T {
        guard let clock = current else { return body() }
        let begin = DispatchTime.now().uptimeNanoseconds
        let result = body()
        let ms = clock.elapsedMs(since: begin)
        let part = clock.parts[name] ?? (0, 0)
        clock.parts[name] = (part.total + ms, max(part.max, ms))
        return result
    }

    /// Mesure un dessin à l'écran de la barre ; le premier marque `first_draw`. O(1) en plus du dessin.
    func measureDraw(_ body: () -> Void) {
        mark("first_draw")
        let begin = DispatchTime.now().uptimeNanoseconds
        body()
        let ms = elapsedMs(since: begin)
        draws += 1
        drawTotalMs += ms
        drawMaxMs = max(drawMaxMs, ms)
    }

    /// Détails de l'événement, en millisecondes arrondies. O(m log m).
    var details: [String: String] {
        var details = marks.mapValues { String(Int($0.rounded())) }
        if let keyLagMs { details["key_lag"] = String(Int(keyLagMs.rounded())) }
        details["max_stall"] = String(Int(maxStallMs.rounded()))
        details["renders"] = String(renders)
        details["render_total"] = String(Int(renderTotalMs.rounded()))
        details["render_max"] = String(Int(renderMaxMs.rounded()))
        for (name, part) in parts {
            details["\(name)_total"] = String(Int(part.total.rounded()))
            details["\(name)_max"] = String(Int(part.max.rounded()))
        }
        details["draws"] = String(draws)
        details["draw_total"] = String(Int(drawTotalMs.rounded()))
        details["draw_max"] = String(Int(drawMaxMs.rounded()))
        details["open_ms"] = String(Int(elapsedMs().rounded()))
        return details
    }

    func finish(events: EventLog) {
        guard Self.current === self else { return }
        Self.current = nil
        events.append(RoadieEvent(type: "launcher.timing", details: details))
    }
}
