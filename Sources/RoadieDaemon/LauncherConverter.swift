import Foundation
import RoadieCore

/// Convertisseur hors ligne du lanceur (Spec 161) : unités physiques/informatiques, bases numériques
/// (hex/bin/oct/dec) et fuseaux horaires. Pur, déterministe et sans aucun appel réseau.
enum LauncherConverter {
    /// Évalue une conversion d'unité, de base numérique ou d'horaire. Retourne `nil` si la saisie ne correspond pas.
    static func evaluate(
        _ raw: String,
        locale: Locale = .current,
        grouping: Bool = false,
        now: Date = Date(),
        localTimeZone: TimeZone = .current
    ) -> LauncherCalculation? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let base = evaluateBase(trimmed) { return base }
        if let tz = evaluateTimeZone(trimmed, now: now, localTimeZone: localTimeZone) { return tz }
        if let unit = evaluateUnit(trimmed, locale: locale, grouping: grouping) { return unit }
        return nil
    }

    // MARK: - Bases numériques (hex / bin / oct / dec)

    private static func evaluateBase(_ text: String) -> LauncherCalculation? {
        let lower = text.lowercased()

        // 1) Littéral préfixé seul : `0xff`, `0b101010`, `0o755`.
        if !lower.contains(" "), let parsed = parseIntegerLiteral(lower, requirePrefix: true) {
            let dec = String(parsed.value)
            let hex = "0x" + String(parsed.value, radix: 16, uppercase: false)
            let bin = "0b" + String(parsed.value, radix: 2)
            let oct = "0o" + String(parsed.value, radix: 8)
            let extras: [String] = switch parsed.sourceBase {
            case 16: ["bin \(bin)", "oct \(oct)"]
            case 2: ["hex \(hex)", "oct \(oct)"]
            case 8: ["hex \(hex)", "bin \(bin)"]
            default: ["hex \(hex)", "bin \(bin)"]
            }
            return LauncherCalculation(
                expression: text,
                value: Double(parsed.value),
                text: dec,
                detail: "\(text) = \(dec) · \(extras.joined(separator: " · "))",
                isConversion: true
            )
        }

        // 2) Conversion explicite : `255 in hex`, `0xff to dec`, `42 en bin`, `493 -> oct`.
        let parts = splitConversion(lower)
        guard let (lhs, rhs) = parts,
              let target = parseBaseTarget(rhs),
              let parsed = parseIntegerLiteral(lhs, requirePrefix: false)
        else { return nil }

        let magnitude = parsed.value.magnitude
        let formatted: String
        let label: String
        switch target {
        case 16:
            formatted = (parsed.value < 0 ? "-0x" : "0x") + String(magnitude, radix: 16)
            label = "HEX"
        case 2:
            formatted = (parsed.value < 0 ? "-0b" : "0b") + String(magnitude, radix: 2)
            label = "BIN"
        case 8:
            formatted = (parsed.value < 0 ? "-0o" : "0o") + String(magnitude, radix: 8)
            label = "OCT"
        default:
            formatted = String(parsed.value)
            label = "DEC"
        }
        return LauncherCalculation(
            expression: text,
            value: Double(parsed.value),
            text: formatted,
            detail: "\(lhs) → \(label) · " + tr("Retour copie", "Return copies"),
            isConversion: true
        )
    }

    private static func parseIntegerLiteral(_ token: String, requirePrefix: Bool) -> (value: Int64, sourceBase: Int)? {
        let clean = token.replacingOccurrences(of: "_", with: "")
        if clean.hasPrefix("0x") {
            let digits = String(clean.dropFirst(2))
            guard !digits.isEmpty, let v = Int64(digits, radix: 16) else { return nil }
            return (v, 16)
        }
        if clean.hasPrefix("0b") {
            let digits = String(clean.dropFirst(2))
            guard !digits.isEmpty, let v = Int64(digits, radix: 2) else { return nil }
            return (v, 2)
        }
        if clean.hasPrefix("0o") {
            let digits = String(clean.dropFirst(2))
            guard !digits.isEmpty, let v = Int64(digits, radix: 8) else { return nil }
            return (v, 8)
        }
        guard !requirePrefix, let v = Int64(clean, radix: 10) else { return nil }
        return (v, 10)
    }

    private static func parseBaseTarget(_ token: String) -> Int? {
        switch token {
        case "hex", "hexa", "hexadecimal", "hexadécimal", "base16", "16": return 16
        case "bin", "binary", "binaire", "base2", "2": return 2
        case "oct", "octal", "base8", "8": return 8
        case "dec", "decimal", "décimal", "base10", "10": return 10
        default: return nil
        }
    }

    // MARK: - Unités physiques et informatiques

    private enum UnitDimension: Equatable {
        case length, mass, temperature, data, time, speed
    }

    private struct UnitDef {
        let dimension: UnitDimension
        let symbol: String
        /// Facteur vers l'unité de base (m, g, B, s, m/s). Ignoré pour la température.
        let toBase: Double
        let tempKind: TempKind?

        enum TempKind { case celsius, fahrenheit, kelvin }
    }

    private static let unitTable: [String: UnitDef] = {
        var t: [String: UnitDef] = [:]
        func add(_ aliases: [String], _ dim: UnitDimension, _ symbol: String, _ factor: Double) {
            let def = UnitDef(dimension: dim, symbol: symbol, toBase: factor, tempKind: nil)
            for a in aliases { t[a] = def }
        }
        // Longueur (base: mètre)
        add(["mm", "millimeter", "millimeters", "millimetre", "millimetres", "millimètre", "millimètres"], .length, "mm", 0.001)
        add(["cm", "centimeter", "centimeters", "centimetre", "centimetres", "centimètre", "centimètres"], .length, "cm", 0.01)
        add(["m", "meter", "meters", "metre", "metres", "mètre", "mètres"], .length, "m", 1.0)
        add(["km", "kilometer", "kilometers", "kilometre", "kilometres", "kilomètre", "kilomètres"], .length, "km", 1_000.0)
        add(["in", "inch", "inches", "pouce", "pouces"], .length, "in", 0.0254)
        add(["ft", "foot", "feet", "pied", "pieds"], .length, "ft", 0.3048)
        add(["yd", "yard", "yards"], .length, "yd", 0.9144)
        add(["mi", "mile", "miles"], .length, "mi", 1_609.344)

        // Masse (base: gramme)
        add(["mg", "milligram", "milligrams", "milligramme", "milligrammes"], .mass, "mg", 0.001)
        add(["g", "gram", "grams", "gramme", "grammes"], .mass, "g", 1.0)
        add(["kg", "kilogram", "kilograms", "kilogramme", "kilogrammes", "kilo", "kilos"], .mass, "kg", 1_000.0)
        add(["oz", "ounce", "ounces", "once", "onces"], .mass, "oz", 28.349523125)
        add(["lb", "lbs", "pound", "pounds", "livre", "livres"], .mass, "lb", 453.59237)

        // Température
        let cDef = UnitDef(dimension: .temperature, symbol: "°C", toBase: 1, tempKind: .celsius)
        let fDef = UnitDef(dimension: .temperature, symbol: "°F", toBase: 1, tempKind: .fahrenheit)
        let kDef = UnitDef(dimension: .temperature, symbol: "K", toBase: 1, tempKind: .kelvin)
        for a in ["c", "°c", "celsius", "degc"] { t[a] = cDef }
        for a in ["f", "°f", "fahrenheit", "degf"] { t[a] = fDef }
        for a in ["k", "kelvin"] { t[a] = kDef }

        // Données (base: octet / byte)
        add(["b", "byte", "bytes", "o", "octet", "octets"], .data, "B", 1.0)
        add(["kb", "ko"], .data, "KB", 1_000.0)
        add(["mb", "mo"], .data, "MB", 1_000_000.0)
        add(["gb", "go"], .data, "GB", 1_000_000_000.0)
        add(["tb", "to"], .data, "TB", 1_000_000_000_000.0)
        add(["kib", "kio"], .data, "KiB", 1_024.0)
        add(["mib", "mio"], .data, "MiB", 1_048_576.0)
        add(["gib", "gio"], .data, "GiB", 1_073_741_824.0)
        add(["tib", "tio"], .data, "TiB", 1_099_511_627_776.0)

        // Temps (base: seconde)
        add(["ms", "millisecond", "milliseconds", "milliseconde", "millisecondes"], .time, "ms", 0.001)
        add(["s", "sec", "secs", "second", "seconds", "seconde", "secondes"], .time, "s", 1.0)
        add(["min", "mins", "minute", "minutes"], .time, "min", 60.0)
        add(["h", "hr", "hrs", "hour", "hours", "heure", "heures"], .time, "h", 3_600.0)
        add(["d", "day", "days", "j", "jour", "jours"], .time, "d", 86_400.0)
        add(["wk", "week", "weeks", "sem", "semaine", "semaines"], .time, "wk", 604_800.0)

        // Vitesse (base: m/s)
        add(["m/s", "mps"], .speed, "m/s", 1.0)
        add(["km/h", "kmh", "kph"], .speed, "km/h", 1.0 / 3.6)
        add(["mph"], .speed, "mph", 0.44704)
        add(["kn", "kt", "kts", "knot", "knots", "noeud", "noeuds", "nœud", "nœuds"], .speed, "kn", 1852.0 / 3600.0)
        return t
    }()

    private static func evaluateUnit(_ text: String, locale: Locale, grouping: Bool) -> LauncherCalculation? {
        guard let (lhs, rhs) = splitConversion(text.lowercased()) else { return nil }
        guard let (rawValue, fromToken) = parseAmountAndUnit(lhs),
              let fromUnit = unitTable[fromToken],
              let toUnit = unitTable[rhs],
              fromUnit.dimension == toUnit.dimension
        else { return nil }

        let converted: Double
        if fromUnit.dimension == .temperature, let fromTemp = fromUnit.tempKind, let toTemp = toUnit.tempKind {
            let celsius: Double = switch fromTemp {
            case .celsius: rawValue
            case .fahrenheit: (rawValue - 32.0) * 5.0 / 9.0
            case .kelvin: rawValue - 273.15
            }
            converted = switch toTemp {
            case .celsius: celsius
            case .fahrenheit: celsius * 9.0 / 5.0 + 32.0
            case .kelvin: celsius + 273.15
            }
        } else {
            converted = (rawValue * fromUnit.toBase) / toUnit.toBase
        }
        guard converted.isFinite else { return nil }
        let formattedNumber = LauncherCalculator.format(converted, locale: locale, grouping: grouping)
        let formattedSource = LauncherCalculator.format(rawValue, locale: locale, grouping: grouping)
        let output = "\(formattedNumber) \(toUnit.symbol)"
        return LauncherCalculation(
            expression: text,
            value: converted,
            text: output,
            detail: "\(formattedSource) \(fromUnit.symbol) → \(output) · " + tr("Retour copie", "Return copies"),
            isConversion: true
        )
    }

    /// Sépare `<nombre><unité>` ou `<nombre> <unité>` (ex. `100km`, `72.5 f`, `-10°c`).
    private static func parseAmountAndUnit(_ lhs: String) -> (Double, String)? {
        let trimmed = lhs.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var index = trimmed.startIndex
        if trimmed[index] == "-" || trimmed[index] == "+" {
            index = trimmed.index(after: index)
        }
        var digits = trimmed[..<index].description
        var separators = 0
        while index < trimmed.endIndex {
            let c = trimmed[index]
            if c.isNumber {
                digits.append(c)
            } else if c == "." || c == "," {
                separators += 1
                digits.append(".")
            } else {
                break
            }
            index = trimmed.index(after: index)
        }
        guard separators <= 1, !digits.isEmpty, digits != "-", digits != "+", digits != ".",
              let value = Double(digits) else { return nil }
        let unit = trimmed[index...].trimmingCharacters(in: .whitespaces)
        guard !unit.isEmpty else { return nil }
        return (value, unit)
    }

    // MARK: - Fuseaux horaires hors ligne

    private struct ZoneAlias {
        let label: String
        let identifier: String
    }

    private static let timeZoneAliases: [String: ZoneAlias] = [
        "utc": ZoneAlias(label: "UTC", identifier: "UTC"),
        "gmt": ZoneAlias(label: "GMT", identifier: "GMT"),
        "paris": ZoneAlias(label: "Paris", identifier: "Europe/Paris"),
        "cet": ZoneAlias(label: "CET (Paris)", identifier: "Europe/Paris"),
        "cest": ZoneAlias(label: "CEST (Paris)", identifier: "Europe/Paris"),
        "france": ZoneAlias(label: "Paris", identifier: "Europe/Paris"),
        "lyon": ZoneAlias(label: "Paris", identifier: "Europe/Paris"),
        "london": ZoneAlias(label: "London", identifier: "Europe/London"),
        "londres": ZoneAlias(label: "Londres", identifier: "Europe/London"),
        "uk": ZoneAlias(label: "London", identifier: "Europe/London"),
        "bst": ZoneAlias(label: "London", identifier: "Europe/London"),
        "berlin": ZoneAlias(label: "Berlin", identifier: "Europe/Berlin"),
        "zurich": ZoneAlias(label: "Zurich", identifier: "Europe/Zurich"),
        "geneva": ZoneAlias(label: "Genève", identifier: "Europe/Zurich"),
        "geneve": ZoneAlias(label: "Genève", identifier: "Europe/Zurich"),
        "genève": ZoneAlias(label: "Genève", identifier: "Europe/Zurich"),
        "bruxelles": ZoneAlias(label: "Bruxelles", identifier: "Europe/Brussels"),
        "brussels": ZoneAlias(label: "Brussels", identifier: "Europe/Brussels"),
        "amsterdam": ZoneAlias(label: "Amsterdam", identifier: "Europe/Amsterdam"),
        "madrid": ZoneAlias(label: "Madrid", identifier: "Europe/Madrid"),
        "rome": ZoneAlias(label: "Rome", identifier: "Europe/Rome"),
        "lisbon": ZoneAlias(label: "Lisbon", identifier: "Europe/Lisbon"),
        "lisbonne": ZoneAlias(label: "Lisbonne", identifier: "Europe/Lisbon"),
        "dublin": ZoneAlias(label: "Dublin", identifier: "Europe/Dublin"),
        "new york": ZoneAlias(label: "New York", identifier: "America/New_York"),
        "nyc": ZoneAlias(label: "New York", identifier: "America/New_York"),
        "est": ZoneAlias(label: "EST (New York)", identifier: "America/New_York"),
        "edt": ZoneAlias(label: "EDT (New York)", identifier: "America/New_York"),
        "boston": ZoneAlias(label: "Boston", identifier: "America/New_York"),
        "montreal": ZoneAlias(label: "Montréal", identifier: "America/Toronto"),
        "montréal": ZoneAlias(label: "Montréal", identifier: "America/Toronto"),
        "toronto": ZoneAlias(label: "Toronto", identifier: "America/Toronto"),
        "chicago": ZoneAlias(label: "Chicago", identifier: "America/Chicago"),
        "cst": ZoneAlias(label: "CST (Chicago)", identifier: "America/Chicago"),
        "denver": ZoneAlias(label: "Denver", identifier: "America/Denver"),
        "mst": ZoneAlias(label: "MST (Denver)", identifier: "America/Denver"),
        "san francisco": ZoneAlias(label: "San Francisco", identifier: "America/Los_Angeles"),
        "sf": ZoneAlias(label: "San Francisco", identifier: "America/Los_Angeles"),
        "los angeles": ZoneAlias(label: "Los Angeles", identifier: "America/Los_Angeles"),
        "la": ZoneAlias(label: "Los Angeles", identifier: "America/Los_Angeles"),
        "seattle": ZoneAlias(label: "Seattle", identifier: "America/Los_Angeles"),
        "pst": ZoneAlias(label: "PST (Los Angeles)", identifier: "America/Los_Angeles"),
        "pdt": ZoneAlias(label: "PDT (Los Angeles)", identifier: "America/Los_Angeles"),
        "tokyo": ZoneAlias(label: "Tokyo", identifier: "Asia/Tokyo"),
        "jst": ZoneAlias(label: "Tokyo (JST)", identifier: "Asia/Tokyo"),
        "seoul": ZoneAlias(label: "Séoul", identifier: "Asia/Seoul"),
        "séoul": ZoneAlias(label: "Séoul", identifier: "Asia/Seoul"),
        "singapore": ZoneAlias(label: "Singapore", identifier: "Asia/Singapore"),
        "singapour": ZoneAlias(label: "Singapour", identifier: "Asia/Singapore"),
        "hong kong": ZoneAlias(label: "Hong Kong", identifier: "Asia/Hong_Kong"),
        "shanghai": ZoneAlias(label: "Shanghai", identifier: "Asia/Shanghai"),
        "dubai": ZoneAlias(label: "Dubai", identifier: "Asia/Dubai"),
        "dubaï": ZoneAlias(label: "Dubaï", identifier: "Asia/Dubai"),
        "mumbai": ZoneAlias(label: "Mumbai", identifier: "Asia/Kolkata"),
        "ist": ZoneAlias(label: "India (IST)", identifier: "Asia/Kolkata"),
        "sydney": ZoneAlias(label: "Sydney", identifier: "Australia/Sydney"),
        "melbourne": ZoneAlias(label: "Melbourne", identifier: "Australia/Melbourne"),
        "auckland": ZoneAlias(label: "Auckland", identifier: "Pacific/Auckland"),
        "sao paulo": ZoneAlias(label: "São Paulo", identifier: "America/Sao_Paulo"),
    ]

    private static func resolveTimeZone(_ raw: String) -> (label: String, tz: TimeZone)? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let alias = timeZoneAliases[key], let tz = TimeZone(identifier: alias.identifier) {
            return (alias.label, tz)
        }
        if let abbr = TimeZone(abbreviation: key.uppercased()) {
            return (key.uppercased(), abbr)
        }
        if let exact = TimeZone(identifier: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return (exact.identifier, exact)
        }
        return nil
    }

    private static func evaluateTimeZone(_ text: String, now: Date, localTimeZone: TimeZone) -> LauncherCalculation? {
        let lower = text.lowercased()

        // 1) `time Tokyo` / `heure Paris` / `tz nyc`.
        for prefix in ["time ", "heure ", "tz "] where lower.hasPrefix(prefix) {
            let zoneQuery = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard let resolved = resolveTimeZone(zoneQuery) else { return nil }
            let formatted = formatTime(now, in: resolved.tz)
            let delta = formatOffsetDelta(from: localTimeZone, to: resolved.tz, at: now)
            return LauncherCalculation(
                expression: text,
                value: Double(resolved.tz.secondsFromGMT(for: now)) / 3600.0,
                text: "\(formatted) (\(resolved.label))",
                detail: "\(resolved.tz.identifier) · \(delta) · " + tr("Retour copie", "Return copies"),
                isConversion: true
            )
        }

        // 2) `14:00 EST in Paris` / `9h30 UTC en Tokyo` / `18:30 Paris -> NYC`.
        guard let (lhs, rhs) = splitConversion(lower),
              let target = resolveTimeZone(rhs),
              let (hour, minute, sourceZoneQuery) = parseClockAndZone(lhs)
        else { return nil }

        let sourceTZ: TimeZone
        let sourceLabel: String
        if sourceZoneQuery.isEmpty {
            sourceTZ = localTimeZone
            sourceLabel = localTimeZone.abbreviation(for: now) ?? localTimeZone.identifier
        } else if let resolved = resolveTimeZone(sourceZoneQuery) {
            sourceTZ = resolved.tz
            sourceLabel = resolved.label
        } else {
            return nil
        }

        var sourceCal = Calendar(identifier: .gregorian)
        sourceCal.timeZone = sourceTZ
        var components = sourceCal.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let instant = sourceCal.date(from: components) else { return nil }

        var targetCal = Calendar(identifier: .gregorian)
        targetCal.timeZone = target.tz
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let sourceDayDate = utcCal.date(from: sourceCal.dateComponents([.year, .month, .day], from: instant))
        let targetDayDate = utcCal.date(from: targetCal.dateComponents([.year, .month, .day], from: instant))
        let dayDiff: Int
        if let sourceDayDate, let targetDayDate {
            dayDiff = utcCal.dateComponents([.day], from: sourceDayDate, to: targetDayDate).day ?? 0
        } else {
            dayDiff = 0
        }
        let daySuffix: String
        if dayDiff > 0 { daySuffix = " +\(dayDiff)" + tr("j", "d") }
        else if dayDiff < 0 { daySuffix = " \(dayDiff)" + tr("j", "d") }
        else { daySuffix = "" }

        let convertedTime = formatTime(instant, in: target.tz)
        let sourceTime = String(format: "%02d:%02d", hour, minute)
        return LauncherCalculation(
            expression: text,
            value: Double(hour * 60 + minute),
            text: "\(convertedTime)\(daySuffix) (\(target.label))",
            detail: "\(sourceTime) \(sourceLabel) → \(convertedTime)\(daySuffix) \(target.label) · " + tr("Retour copie", "Return copies"),
            isConversion: true
        )
    }

    /// Analyse `14:00 est`, `9h30 utc`, `9h paris`, `18:30`.
    private static func parseClockAndZone(_ lhs: String) -> (hour: Int, minute: Int, zone: String)? {
        let trimmed = lhs.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let timeToken = parts.first.map(String.init) else { return nil }
        let zone = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

        let separator: Character
        if timeToken.contains(":") { separator = ":" }
        else if timeToken.contains("h") { separator = "h" }
        else { return nil }

        let pieces = timeToken.split(separator: separator, omittingEmptySubsequences: false)
        guard pieces.count == 2,
              let hour = Int(pieces[0]), (0...23).contains(hour) else { return nil }
        let minute: Int
        if pieces[1].isEmpty {
            minute = 0
        } else if let m = Int(pieces[1]), (0...59).contains(m) {
            minute = m
        } else {
            return nil
        }
        return (hour, minute, zone)
    }

    private static func formatTime(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func formatOffsetDelta(from local: TimeZone, to target: TimeZone, at date: Date) -> String {
        let diffMinutes = (target.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)) / 60
        if diffMinutes == 0 { return tr("même fuseau", "same time zone") }
        let sign = diffMinutes > 0 ? "+" : "-"
        let absMin = abs(diffMinutes)
        let hours = absMin / 60
        let mins = absMin % 60
        if mins == 0 {
            return "\(sign)\(hours)h " + tr("vs local", "vs local")
        }
        return "\(sign)\(hours)h\(String(format: "%02d", mins)) " + tr("vs local", "vs local")
    }

    // MARK: - Découpage commun `<source> in|to|en|-> <cible>`

    private static func splitConversion(_ lower: String) -> (String, String)? {
        for sep in [" -> ", " to ", " in ", " en ", "->"] {
            if let range = lower.range(of: sep) {
                let lhs = String(lower[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let rhs = String(lower[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !lhs.isEmpty, !rhs.isEmpty {
                    return (lhs, rhs)
                }
            }
        }
        return nil
    }
}
