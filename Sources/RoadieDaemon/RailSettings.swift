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
    public var dynamicLeftGap: Bool
    public var emptyClickHideActive: Bool
    public var emptyClickSafetyMargin: Double
    public var preview: Preview
    public var stacked: Stacked
    public var parallax: Parallax
    public var layout: Layout
    public var displayLabel: Label
    public var desktopLabel: Label
    public var stages: Stages
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

    public struct Layout: Equatable, Sendable {
        public var headerPosition: String
        public var stagesPosition: String
        public var spacing: Double
        public var topPadding: Double
        public var bottomPadding: Double
    }

    public struct Label: Equatable, Sendable {
        public var enabled: Bool
        public var template: String
        public var color: String
        public var fontSize: Double
        public var fontFamily: String
        public var weight: String
        public var alignment: String
        public var opacity: Double
        public var offsetX: Double
        public var offsetY: Double
    }

    public struct Stages: Equatable, Sendable {
        public var position: String
        public var alignment: String
        public var gap: Double
    }

    private struct LegacyHeader: Equatable {
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
        let layout = sections["fx.rail.layout"] ?? [:]
        let legacyHeader = legacyHeader(from: sections["fx.rail.header"] ?? [:])
        let displayLabel = sections["fx.rail.header.display"] ?? [:]
        let desktopLabel = sections["fx.rail.header.desktop"] ?? [:]
        let stages = sections["fx.rail.stages"] ?? [:]
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
            dynamicLeftGap: bool(rail["dynamic_left_gap"], default: false),
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
            layout: Layout(
                headerPosition: normalizedChoice(layout["header_position"], allowed: ["top", "bottom", "hidden"], default: legacyHeader.enabled ? normalizedHeaderPosition(legacyHeader.placement) : "hidden"),
                stagesPosition: normalizedChoice(layout["stages_position"], allowed: ["top", "center", "bottom"], default: "center"),
                spacing: number(layout["spacing"], default: 13, min: 0, max: 80),
                topPadding: number(layout["top_padding"], default: legacyHeader.topPadding, min: 0, max: 240),
                bottomPadding: number(layout["bottom_padding"], default: legacyHeader.bottomPadding, min: 0, max: 240)
            ),
            displayLabel: Label(
                enabled: bool(displayLabel["enabled"], default: legacyHeader.enabled),
                template: displayLabel["template"] ?? legacyHeader.titleTemplate,
                color: displayLabel["color"] ?? legacyHeader.titleColor,
                fontSize: number(displayLabel["font_size"], default: legacyHeader.titleFontSize, min: 6, max: 40),
                fontFamily: displayLabel["font_family"] ?? legacyHeader.fontFamily,
                weight: normalizedChoice(displayLabel["weight"], allowed: ["regular", "medium", "semibold", "bold"], default: legacyHeader.titleWeight),
                alignment: normalizedChoice(displayLabel["alignment"], allowed: ["left", "center", "right"], default: legacyHeader.alignment),
                opacity: number(displayLabel["opacity"], default: 1, min: 0, max: 1),
                offsetX: number(displayLabel["offset_x"], default: 0, min: -120, max: 120),
                offsetY: number(displayLabel["offset_y"], default: 0, min: -120, max: 120)
            ),
            desktopLabel: Label(
                enabled: bool(desktopLabel["enabled"], default: legacyHeader.enabled),
                template: desktopLabel["template"] ?? legacyHeader.subtitleTemplate,
                color: desktopLabel["color"] ?? legacyHeader.subtitleColor,
                fontSize: number(desktopLabel["font_size"], default: legacyHeader.subtitleFontSize, min: 6, max: 32),
                fontFamily: desktopLabel["font_family"] ?? legacyHeader.fontFamily,
                weight: normalizedChoice(desktopLabel["weight"], allowed: ["regular", "medium", "semibold", "bold"], default: legacyHeader.subtitleWeight),
                alignment: normalizedChoice(desktopLabel["alignment"], allowed: ["left", "center", "right"], default: legacyHeader.alignment),
                opacity: number(desktopLabel["opacity"], default: 1, min: 0, max: 1),
                offsetX: number(desktopLabel["offset_x"], default: 0, min: -120, max: 120),
                offsetY: number(desktopLabel["offset_y"], default: 0, min: -120, max: 120)
            ),
            stages: Stages(
                position: normalizedChoice(stages["position"], allowed: ["top", "center", "bottom"], default: normalizedChoice(layout["stages_position"], allowed: ["top", "center", "bottom"], default: "center")),
                alignment: normalizedChoice(stages["alignment"], allowed: ["left", "center", "right"], default: "center"),
                gap: number(stages["gap"], default: 13, min: 0, max: 80)
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
            "dynamic_left_gap=\(dynamicLeftGap)",
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
            "layout.header_position=\(layout.headerPosition)",
            "layout.stages_position=\(layout.stagesPosition)",
            "layout.spacing=\(layout.spacing)",
            "layout.top_padding=\(layout.topPadding)",
            "layout.bottom_padding=\(layout.bottomPadding)",
            "header.display.enabled=\(displayLabel.enabled)",
            "header.display.template=\(displayLabel.template)",
            "header.display.color=\(displayLabel.color)",
            "header.display.font_size=\(displayLabel.fontSize)",
            "header.display.font_family=\(displayLabel.fontFamily)",
            "header.display.weight=\(displayLabel.weight)",
            "header.display.alignment=\(displayLabel.alignment)",
            "header.display.opacity=\(displayLabel.opacity)",
            "header.display.offset_x=\(displayLabel.offsetX)",
            "header.display.offset_y=\(displayLabel.offsetY)",
            "header.desktop.enabled=\(desktopLabel.enabled)",
            "header.desktop.template=\(desktopLabel.template)",
            "header.desktop.color=\(desktopLabel.color)",
            "header.desktop.font_size=\(desktopLabel.fontSize)",
            "header.desktop.font_family=\(desktopLabel.fontFamily)",
            "header.desktop.weight=\(desktopLabel.weight)",
            "header.desktop.alignment=\(desktopLabel.alignment)",
            "header.desktop.opacity=\(desktopLabel.opacity)",
            "header.desktop.offset_x=\(desktopLabel.offsetX)",
            "header.desktop.offset_y=\(desktopLabel.offsetY)",
            "stages.position=\(stages.position)",
            "stages.alignment=\(stages.alignment)",
            "stages.gap=\(stages.gap)",
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
        dynamicLeftGap: false,
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
        layout: Layout(headerPosition: "top", stagesPosition: "center", spacing: 13, topPadding: 26, bottomPadding: 16),
        displayLabel: Label(enabled: true, template: "{display}", color: "#FFFFFFDB", fontSize: 13, fontFamily: "system", weight: "bold", alignment: "center", opacity: 1, offsetX: 0, offsetY: 0),
        desktopLabel: Label(enabled: true, template: "Desktop {desktop}", color: "#FFFFFF6B", fontSize: 10, fontFamily: "system", weight: "medium", alignment: "center", opacity: 1, offsetX: 0, offsetY: 0),
        stages: Stages(position: "center", alignment: "center", gap: 13),
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

    private static func legacyHeader(from header: [String: String]) -> LegacyHeader {
        LegacyHeader(
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
        )
    }

    private static func normalizedLayoutMode(_ raw: String?) -> String {
        switch raw?.lowercased() {
        case "resize", "reserve", "push":
            return "resize"
        default:
            return "overlay"
        }
    }

    private static func normalizedHeaderPosition(_ raw: String) -> String {
        raw == "hidden" ? "hidden" : "top"
    }

    private static func normalizedChoice(_ raw: String?, allowed: Set<String>, default fallback: String) -> String {
        guard let raw else { return fallback }
        let normalized = raw.lowercased()
        return allowed.contains(normalized) ? normalized : fallback
    }
}
