import Foundation

public struct RailSettings: Equatable, Sendable {
    public var renderer: String
    public var width: Double
    public var backgroundColor: String
    public var backgroundOpacity: Double
    public var autoHide: Bool
    public var edgeHitWidth: Double
    public var edgeMagnetismWidth: Double
    public var animationMS: Double
    public var hideDelayMS: Double
    public var layoutMode: String
    public var emptyClickHideActive: Bool
    public var emptyClickSafetyMargin: Double
    public var preview: Preview
    public var stacked: Stacked
    public var parallax: Parallax
    public var header: Header
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

    public struct Header: Equatable, Sendable {
        public var enabled: Bool
        public var placement: String
        public var alignment: String
        public var topPadding: Double
        public var bottomPadding: Double
        public var height: Double
        public var width: Double
        public var titleColor: String
        public var subtitleColor: String
        public var titleFontSize: Double
        public var subtitleFontSize: Double
        public var fontFamily: String
        public var titleWeight: String
        public var subtitleWeight: String
        public var titleTemplate: String
        public var subtitleTemplate: String
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
        let header = sections["fx.rail.header"] ?? [:]
        return RailSettings(
            renderer: rail["renderer"] ?? renderer(from: raw),
            width: number(rail["width"], default: 150, min: 90, max: 320),
            backgroundColor: rail["background_color"] ?? "#000000",
            backgroundOpacity: number(rail["background_opacity"], default: 0, min: 0, max: 1),
            autoHide: bool(rail["auto_hide"], default: false),
            edgeHitWidth: number(rail["edge_hit_width"], default: 8, min: 1, max: 40),
            edgeMagnetismWidth: number(rail["edge_magnetism_width"], default: 24, min: 0, max: 160),
            animationMS: number(rail["animation_ms"], default: 160, min: 0, max: 1000),
            hideDelayMS: number(rail["hide_delay_ms"], default: 350, min: 0, max: 5000),
            layoutMode: normalizedLayoutMode(rail["layout_mode"]),
            emptyClickHideActive: bool(rail["empty_click_hide_active"], default: true),
            emptyClickSafetyMargin: number(rail["empty_click_safety_margin"], default: 12, min: 0, max: 80),
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
            header: Header(
                enabled: bool(header["enabled"], default: true),
                placement: normalizedChoice(header["placement"], allowed: ["top", "center"], default: "top"),
                alignment: normalizedChoice(header["alignment"], allowed: ["left", "center", "right"], default: "center"),
                topPadding: number(header["top_padding"], default: 26, min: 0, max: 240),
                bottomPadding: number(header["bottom_padding"], default: 16, min: 0, max: 240),
                height: number(header["height"], default: 42, min: 0, max: 120),
                width: number(header["width"], default: 0, min: 0, max: 320),
                titleColor: header["title_color"] ?? "#FFFFFFDB",
                subtitleColor: header["subtitle_color"] ?? "#FFFFFF6B",
                titleFontSize: number(header["title_font_size"], default: 13, min: 6, max: 40),
                subtitleFontSize: number(header["subtitle_font_size"], default: 10, min: 6, max: 32),
                fontFamily: header["font_family"] ?? "system",
                titleWeight: normalizedChoice(header["title_weight"], allowed: ["regular", "medium", "semibold", "bold"], default: "bold"),
                subtitleWeight: normalizedChoice(header["subtitle_weight"], allowed: ["regular", "medium", "semibold", "bold"], default: "medium"),
                titleTemplate: header["title_template"] ?? "{display}",
                subtitleTemplate: header["subtitle_template"] ?? "Desktop {desktop}"
            ),
            stageAccents: stageAccents(from: raw)
        )
    }

    public var statusLines: [String] {
        [
            "renderer=\(renderer)",
            "width=\(width)",
            "background_color=\(backgroundColor)",
            "background_opacity=\(backgroundOpacity)",
            "auto_hide=\(autoHide)",
            "edge_hit_width=\(edgeHitWidth)",
            "edge_magnetism_width=\(edgeMagnetismWidth)",
            "animation_ms=\(animationMS)",
            "hide_delay_ms=\(hideDelayMS)",
            "layout_mode=\(layoutMode)",
            "empty_click_hide_active=\(emptyClickHideActive)",
            "empty_click_safety_margin=\(emptyClickSafetyMargin)",
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
            "header.enabled=\(header.enabled)",
            "header.placement=\(header.placement)",
            "header.alignment=\(header.alignment)",
            "header.top_padding=\(header.topPadding)",
            "header.bottom_padding=\(header.bottomPadding)",
            "header.height=\(header.height)",
            "header.width=\(header.width)",
            "header.title_color=\(header.titleColor)",
            "header.subtitle_color=\(header.subtitleColor)",
            "header.title_font_size=\(header.titleFontSize)",
            "header.subtitle_font_size=\(header.subtitleFontSize)",
            "header.font_family=\(header.fontFamily)",
            "header.title_weight=\(header.titleWeight)",
            "header.subtitle_weight=\(header.subtitleWeight)",
            "header.title_template=\(header.titleTemplate)",
            "header.subtitle_template=\(header.subtitleTemplate)",
        ]
    }

    private static let defaults = RailSettings(
        renderer: "stacked-previews",
        width: 150,
        backgroundColor: "#000000",
        backgroundOpacity: 0,
        autoHide: false,
        edgeHitWidth: 8,
        edgeMagnetismWidth: 24,
        animationMS: 160,
        hideDelayMS: 350,
        layoutMode: "overlay",
        emptyClickHideActive: true,
        emptyClickSafetyMargin: 12,
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
        header: Header(
            enabled: true,
            placement: "top",
            alignment: "center",
            topPadding: 26,
            bottomPadding: 16,
            height: 42,
            width: 0,
            titleColor: "#FFFFFFDB",
            subtitleColor: "#FFFFFF6B",
            titleFontSize: 13,
            subtitleFontSize: 10,
            fontFamily: "system",
            titleWeight: "bold",
            subtitleWeight: "medium",
            titleTemplate: "{display}",
            subtitleTemplate: "Desktop {desktop}"
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
            let trimmed = stripComment(from: line).trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func stripComment(from line: String) -> String {
        var inQuotes = false
        var result = ""
        for character in line {
            if character == "\"" {
                inQuotes.toggle()
                result.append(character)
                continue
            }
            if character == "#", !inQuotes {
                break
            }
            result.append(character)
        }
        return result
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

    private static func bool(_ raw: String?, default fallback: Bool) -> Bool {
        guard let raw else { return fallback }
        switch raw.lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return fallback
        }
    }

    private static func normalizedLayoutMode(_ raw: String?) -> String {
        switch raw?.lowercased() {
        case "resize", "reserve", "push":
            return "resize"
        default:
            return "overlay"
        }
    }

    private static func normalizedChoice(_ raw: String?, allowed: Set<String>, default fallback: String) -> String {
        guard let raw else { return fallback }
        let normalized = raw.lowercased()
        return allowed.contains(normalized) ? normalized : fallback
    }
}
