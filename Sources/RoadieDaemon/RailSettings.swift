import Foundation

public struct RailSettings: Equatable, Sendable {
    public var renderer: String
    public var width: Double
    public var preview: Preview
    public var stacked: Stacked
    public var parallax: Parallax
    public var stageAccents: [String: String]

    public struct Preview: Equatable, Sendable {
        public var width: Double
        public var height: Double
        public var leadingPadding: Double
        public var trailingPadding: Double
        public var verticalPadding: Double
    }

    public struct Stacked: Equatable, Sendable {
        public var offsetX: Double
        public var offsetY: Double
        public var scalePerLayer: Double
        public var opacityPerLayer: Double
    }

    public struct Parallax: Equatable, Sendable {
        public var rotation: Double
        public var offsetX: Double
        public var offsetY: Double
        public var scalePerLayer: Double
        public var opacityPerLayer: Double
        public var darkenPerLayer: Double
        public var width: Double
        public var height: Double
        public var leadingPadding: Double
        public var trailingPadding: Double
        public var verticalPadding: Double
    }

    public static func load(path: String = "~/.config/roadies/roadies.toml") -> RailSettings {
        let expanded = NSString(string: path).expandingTildeInPath
        guard let raw = try? String(contentsOfFile: expanded, encoding: .utf8) else {
            return defaults
        }
        return load(raw: raw)
    }

    public static func load(raw: String) -> RailSettings {
        let sections = sections(from: raw)
        let rail = sections["fx.rail"] ?? [:]
        let preview = sections["fx.rail.preview"] ?? [:]
        let stacked = sections["fx.rail.stacked"] ?? [:]
        let parallax = sections["fx.rail.parallax"] ?? [:]
        return RailSettings(
            renderer: rail["renderer"] ?? renderer(from: raw),
            width: number(rail["width"], default: 150, min: 90, max: 320),
            preview: Preview(
                width: number(preview["width"], default: 160, min: 60, max: 240),
                height: number(preview["height"], default: 104, min: 40, max: 180),
                leadingPadding: number(preview["leading_padding"], default: 8, min: 0, max: 80),
                trailingPadding: number(preview["trailing_padding"], default: 16, min: 0, max: 80),
                verticalPadding: number(preview["vertical_padding"], default: 20, min: 0, max: 80)
            ),
            stacked: Stacked(
                offsetX: number(stacked["offset_x"], default: 60, min: 0, max: 120),
                offsetY: number(stacked["offset_y"], default: 80, min: 0, max: 120),
                scalePerLayer: number(stacked["scale_per_layer"], default: 0.05, min: 0, max: 0.30),
                opacityPerLayer: number(stacked["opacity_per_layer"], default: 0.08, min: 0, max: 0.50)
            ),
            parallax: Parallax(
                rotation: number(parallax["rotation"], default: 35, min: 0, max: 75),
                offsetX: number(parallax["offset_x"], default: 25, min: 0, max: 80),
                offsetY: number(parallax["offset_y"], default: 18, min: 0, max: 80),
                scalePerLayer: number(parallax["scale_per_layer"], default: 0.08, min: 0, max: 0.30),
                opacityPerLayer: number(parallax["opacity_per_layer"], default: 0.20, min: 0, max: 0.50),
                darkenPerLayer: number(parallax["darken_per_layer"], default: 0.15, min: 0, max: 1),
                width: number(parallax["width"] ?? preview["width"], default: 160, min: 60, max: 240),
                height: number(parallax["height"] ?? preview["height"], default: 104, min: 40, max: 180),
                leadingPadding: number(parallax["leading_padding"] ?? preview["leading_padding"], default: 8, min: 0, max: 80),
                trailingPadding: number(parallax["trailing_padding"] ?? preview["trailing_padding"], default: 16, min: 0, max: 80),
                verticalPadding: number(parallax["vertical_padding"] ?? preview["vertical_padding"], default: 20, min: 0, max: 80)
            ),
            stageAccents: stageAccents(from: raw)
        )
    }

    public var statusLines: [String] {
        [
            "renderer=\(renderer)",
            "width=\(width)",
            "preview.width=\(preview.width)",
            "preview.height=\(preview.height)",
            "preview.leading_padding=\(preview.leadingPadding)",
            "preview.trailing_padding=\(preview.trailingPadding)",
            "preview.vertical_padding=\(preview.verticalPadding)",
            "stacked.offset_x=\(stacked.offsetX)",
            "stacked.offset_y=\(stacked.offsetY)",
            "stacked.scale_per_layer=\(stacked.scalePerLayer)",
            "stacked.opacity_per_layer=\(stacked.opacityPerLayer)",
            "parallax.rotation=\(parallax.rotation)",
            "parallax.offset_x=\(parallax.offsetX)",
            "parallax.offset_y=\(parallax.offsetY)",
            "parallax.scale_per_layer=\(parallax.scalePerLayer)",
            "parallax.opacity_per_layer=\(parallax.opacityPerLayer)",
            "parallax.darken_per_layer=\(parallax.darkenPerLayer)",
            "parallax.width=\(parallax.width)",
            "parallax.height=\(parallax.height)",
            "parallax.leading_padding=\(parallax.leadingPadding)",
            "parallax.trailing_padding=\(parallax.trailingPadding)",
            "parallax.vertical_padding=\(parallax.verticalPadding)",
        ]
    }

    private static let defaults = RailSettings(
        renderer: "stacked-previews",
        width: 150,
        preview: Preview(width: 160, height: 104, leadingPadding: 8, trailingPadding: 16, verticalPadding: 20),
        stacked: Stacked(offsetX: 60, offsetY: 80, scalePerLayer: 0.05, opacityPerLayer: 0.08),
        parallax: Parallax(
            rotation: 35,
            offsetX: 25,
            offsetY: 18,
            scalePerLayer: 0.08,
            opacityPerLayer: 0.20,
            darkenPerLayer: 0.15,
            width: 160,
            height: 104,
            leadingPadding: 8,
            trailingPadding: 16,
            verticalPadding: 20
        ),
        stageAccents: [:]
    )

    private static func renderer(from raw: String) -> String {
        if raw.contains("renderer = \"mosaic\"") { return "mosaic" }
        if raw.contains("renderer = \"parallax-45\"") || raw.contains("renderer = \"parallax\"") { return "parallax-45" }
        if raw.contains("renderer = \"icons-only\"") || raw.contains("renderer = \"icons\"") { return "icons-only" }
        return "stacked-previews"
    }

    private static func sections(from raw: String) -> [String: [String: String]] {
        var sections: [String: [String: String]] = [:]
        var current: String?
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.split(separator: "#", maxSplits: 1).first.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]"), !trimmed.hasPrefix("[[") {
                current = String(trimmed.dropFirst().dropLast())
                continue
            }
            guard let current, let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            sections[current, default: [:]][key] = value
        }
        return sections
    }

    private static func stageAccents(from raw: String) -> [String: String] {
        var accents: [String: String] = [:]
        var currentStageID: String?
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[[fx.rail.preview.stage_overrides]]" {
                currentStageID = nil
                continue
            }
            if trimmed.hasPrefix("[") {
                currentStageID = nil
            }
            if let value = quotedValue(in: trimmed, key: "stage_id") {
                currentStageID = value
            }
            if let value = quotedValue(in: trimmed, key: "active_color"),
               let currentStageID {
                accents[currentStageID] = value
            }
        }
        return accents
    }

    private static func quotedValue(in line: String, key: String) -> String? {
        guard line.hasPrefix("\(key)"),
              let first = line.firstIndex(of: "\""),
              let last = line[line.index(after: first)...].firstIndex(of: "\"")
        else { return nil }
        return String(line[line.index(after: first)..<last])
    }

    private static func number(_ raw: String?, default fallback: Double, min: Double, max: Double) -> Double {
        guard let raw, let value = Double(raw) else { return fallback }
        return Swift.max(min, Swift.min(max, value))
    }
}
