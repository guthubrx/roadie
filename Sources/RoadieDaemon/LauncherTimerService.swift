import AppKit
import Foundation
import os
import RoadieCore

/// Formatage pur d'une couleur sRGB capturée par `NSColorSampler` (Spec 161).
struct LauncherColorFormat: Equatable, Sendable {
    let hex: String
    let rgb: String
    let hsl: String

    /// Convertit des composantes sRGB dans `[0, 1]` en chaînes HEX (`#RRGGBB`), RGB et HSL.
    static func fromSRGB(red: Double, green: Double, blue: Double) -> LauncherColorFormat {
        let r = min(1, max(0, red))
        let g = min(1, max(0, green))
        let b = min(1, max(0, blue))
        let ri = Int((r * 255.0).rounded())
        let gi = Int((g * 255.0).rounded())
        let bi = Int((b * 255.0).rounded())
        let hex = String(format: "#%02X%02X%02X", ri, gi, bi)
        let rgb = "rgb(\(ri), \(gi), \(bi))"

        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let delta = maxC - minC
        let l = (maxC + minC) / 2.0
        let s: Double
        var h: Double = 0
        if delta == 0 {
            s = 0
        } else {
            s = delta / (1.0 - abs(2.0 * l - 1.0))
            if maxC == r {
                h = 60.0 * (((g - b) / delta).truncatingRemainder(dividingBy: 6.0))
            } else if maxC == g {
                h = 60.0 * (((b - r) / delta) + 2.0)
            } else {
                h = 60.0 * (((r - g) / delta) + 4.0)
            }
            if h < 0 { h += 360.0 }
        }
        let hsl = "hsl(\(Int(h.rounded())), \(Int((s * 100.0).rounded()))%, \(Int((l * 100.0).rounded()))%)"
        return LauncherColorFormat(hex: hex, rgb: rgb, hsl: hsl)
    }

    /// Déclenche la pipette système macOS (`NSColorSampler`), copie `#RRGGBB` et notifie l'utilisateur.
    @MainActor static func pickColor() {
        NSColorSampler().show { selected in
            guard let color = selected?.usingColorSpace(.sRGB) else { return }
            let formatted = fromSRGB(
                red: Double(color.redComponent),
                green: Double(color.greenComponent),
                blue: Double(color.blueComponent)
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(formatted.hex, forType: .string)
            LauncherTimerService.postLocalNotification(
                title: tr("Couleur copiée : \(formatted.hex)", "Color copied: \(formatted.hex)"),
                body: "\(formatted.rgb) · \(formatted.hsl)"
            )
        }
    }
}

/// Minuteur et Pomodoro locaux dans le daemon Roadie (Spec 161). Thread-safe (`OSAllocatedUnfairLock`).
final class LauncherTimerService: Sendable {
    struct ActiveTimer: Equatable, Sendable {
        let id: Int
        let label: String
        let totalSeconds: Int
        let startedAt: Date
        let endsAt: Date

        func remainingSeconds(at now: Date) -> Int {
            max(0, Int(ceil(endsAt.timeIntervalSince(now))))
        }
    }

    enum ParsedQuery: Equatable, Sendable {
        case start(seconds: Int, label: String)
        case status
        case cancelAll
    }

    private struct State {
        var nextID = 1
        var timers: [Int: ActiveTimer] = [:]
        var sources: [Int: DispatchSourceTimer] = [:]
    }

    static let shared = LauncherTimerService()

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let clock: @Sendable () -> Date
    private let notifier: @Sendable (ActiveTimer) -> Void
    private let scheduleRealTimers: Bool

    init(
        clock: @escaping @Sendable () -> Date = { Date() },
        notifier: @escaping @Sendable (ActiveTimer) -> Void = LauncherTimerService.defaultNotifier,
        scheduleRealTimers: Bool = true
    ) {
        self.clock = clock
        self.notifier = notifier
        self.scheduleRealTimers = scheduleRealTimers
    }

    /// Démarre un minuteur local et renvoie sa fiche active. Durée bornée entre 1 s et 24 h.
    @discardableResult
    func start(seconds: Int, label: String) -> ActiveTimer {
        let clamped = min(86_400, max(1, seconds))
        let now = clock()
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleanLabel.isEmpty ? tr("Minuteur", "Timer") : cleanLabel

        let timer: ActiveTimer = state.withLock { st in
            let id = st.nextID
            st.nextID += 1
            let entry = ActiveTimer(
                id: id,
                label: title,
                totalSeconds: clamped,
                startedAt: now,
                endsAt: now.addingTimeInterval(TimeInterval(clamped))
            )
            st.timers[id] = entry
            if scheduleRealTimers {
                let source = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                source.schedule(deadline: .now() + .seconds(clamped))
                source.setEventHandler { [weak self] in
                    self?.fire(id: id)
                }
                st.sources[id] = source
                source.resume()
            }
            return entry
        }
        return timer
    }

    /// Retourne les minuteurs encore en cours, triés par échéance croissante.
    func activeTimers() -> [ActiveTimer] {
        let now = clock()
        return state.withLock { st in
            st.timers.values
                .filter { $0.endsAt > now }
                .sorted { $0.endsAt < $1.endsAt }
        }
    }

    /// Annule un minuteur par identifiant ; retourne `true` s'il existait.
    @discardableResult
    func cancel(id: Int) -> Bool {
        state.withLock { st in
            st.sources.removeValue(forKey: id)?.cancel()
            return st.timers.removeValue(forKey: id) != nil
        }
    }

    /// Annule tous les minuteurs actifs et renvoie le nombre annulé.
    @discardableResult
    func cancelAll() -> Int {
        state.withLock { st in
            let count = st.timers.count
            st.sources.values.forEach { $0.cancel() }
            st.sources.removeAll()
            st.timers.removeAll()
            return count
        }
    }

    /// Déclenche l'expiration d'un minuteur (appelé par `DispatchSourceTimer` ou par les tests).
    func fire(id: Int) {
        let fired: ActiveTimer? = state.withLock { st in
            st.sources.removeValue(forKey: id)?.cancel()
            return st.timers.removeValue(forKey: id)
        }
        if let fired {
            notifier(fired)
        }
    }

    // MARK: - Analyseur de durée et de commande lanceur / CLI

    /// Parse une durée libre : `25m`, `1h30m`, `90s`, `45` (minutes par défaut), `1h15`, `2m30s`.
    static func parseDurationSeconds(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if let bareMinutes = Int(text), bareMinutes > 0 {
            return min(86_400, bareMinutes * 60)
        }
        var total = 0
        var number = ""
        var matchedUnit = false
        for char in text {
            if char.isNumber {
                number.append(char)
            } else if let n = Int(number), !number.isEmpty {
                switch char {
                case "h": total += n * 3600; matchedUnit = true
                case "m": total += n * 60; matchedUnit = true
                case "s": total += n; matchedUnit = true
                default: return nil
                }
                number = ""
            } else {
                return nil
            }
        }
        if !number.isEmpty {
            // Ex. `1h30` → les chiffres finaux après `h` sont des minutes.
            if matchedUnit, let trailing = Int(number), text.contains("h"), !text.contains("m"), !text.contains("s") {
                total += trailing * 60
            } else {
                return nil
            }
        }
        guard matchedUnit, total > 0 else { return nil }
        return min(86_400, total)
    }

    /// Formate une durée en `MM:SS` ou `HH:MM:SS`.
    static func formatDuration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let rem = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, rem)
        }
        return String(format: "%02d:%02d", m, rem)
    }

    /// Analyse une saisie du lanceur (`timer 15m pause`, `pomodoro`, `timer status`, `timer stop`).
    static func parseQuery(_ raw: String) -> ParsedQuery? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let head = parts.first?.lowercased() else { return nil }

        if head == "pomodoro" || head == "pomo" {
            if parts.count == 1 {
                return .start(seconds: 25 * 60, label: "Pomodoro")
            }
            if let dur = parseDurationSeconds(parts[1]) {
                let label = parts.dropFirst(2).joined(separator: " ")
                return .start(seconds: dur, label: label.isEmpty ? "Pomodoro" : label)
            }
            let label = parts.dropFirst().joined(separator: " ")
            return .start(seconds: 25 * 60, label: "Pomodoro · \(label)")
        }

        guard head == "timer" || head == "minuteur" || head == "chrono" else { return nil }
        if parts.count == 1 { return .status }
        let second = parts[1].lowercased()
        if second == "status" || second == "list" || second == "etat" || second == "état" {
            return .status
        }
        if second == "stop" || second == "cancel" || second == "annuler" || second == "clear" {
            return .cancelAll
        }
        if let dur = parseDurationSeconds(parts[1]) {
            let label = parts.dropFirst(2).joined(separator: " ")
            return .start(seconds: dur, label: label.isEmpty ? tr("Minuteur", "Timer") : label)
        }
        return nil
    }

    private static func defaultNotifier(_ timer: ActiveTimer) {
        postLocalNotification(
            title: tr("Minuteur terminé : \(timer.label)", "Timer finished: \(timer.label)"),
            body: tr("Durée écoulée : \(formatDuration(timer.totalSeconds))", "Elapsed: \(formatDuration(timer.totalSeconds))")
        )
    }

    /// Affiche une notification macOS locale via `osascript` (sans injection shell : arguments passés par `Process`).
    static func postLocalNotification(title: String, body: String) {
        let safeTitle = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let safeBody = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(safeBody)\" with title \"Roadie\" subtitle \"\(safeTitle)\" sound name \"Glass\""
        DispatchQueue.global(qos: .utility).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
        }
    }
}
