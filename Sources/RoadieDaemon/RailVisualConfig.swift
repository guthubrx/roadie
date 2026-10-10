import AppKit
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages

@MainActor
struct RailVisualConfig {
    var mode: RailRenderMode = .stacked
    var stageAccents: [StageID: NSColor] = [:]
    var railWidth: CGFloat = 150
    var backgroundColor: NSColor = .black
    var backgroundOpacity: CGFloat = 0
    var autoHide: Bool = false
    var edgeHitWidth: CGFloat = 8
    var edgeMagnetismWidth: CGFloat = 24
    var animationDuration: TimeInterval = 0.16
    var hideDelay: TimeInterval = 0.35
    var emptyClickHideActive: Bool = true
    var emptyClickSafetyMargin: CGFloat = 12
    var hideOnMaximized: Bool = false
    var previewWidth: CGFloat = 160
    var previewHeight: CGFloat = 104
    var leadingPadding: CGFloat = 8
    var trailingPadding: CGFloat = 16
    var verticalPadding: CGFloat = 20
    var stackedOffsetX: CGFloat = 60
    var stackedOffsetY: CGFloat = 80
    var stackedScale: CGFloat = 0.05
    var stackedOpacity: CGFloat = 0.08
    var parallaxRotation: CGFloat = 35
    var parallaxOffsetX: CGFloat = 25
    var parallaxOffsetY: CGFloat = 18
    var parallaxScale: CGFloat = 0.08
    var parallaxOpacity: CGFloat = 0.20
    var parallaxDarken: CGFloat = 0.15
    var headerPosition: RailHeaderPosition = .top
    var stagesPosition: RailStagesPosition = .center
    var layoutSpacing: CGFloat = 13
    var layoutTopPadding: CGFloat = 26
    var layoutBottomPadding: CGFloat = 16
    var headerHeight: CGFloat = 42
    var headerWidth: CGFloat = 0
    var displayLabel: RailLabelConfig = .displayDefault
    var desktopLabel: RailLabelConfig = .desktopDefault
    var stageLabel: RailStageLabelConfig = .default

    var headerVisible: Bool {
        headerPosition != .hidden && (displayLabel.enabled || desktopLabel.enabled)
    }

    func accent(for stageID: StageID) -> NSColor {
        stageAccents[stageID] ?? NSColor.systemGreen
    }

    static func load(settings: RailSettings = RailSettings.load()) -> RailVisualConfig {
        let mode = RailRenderMode.load(renderer: settings.renderer)
        let accents = settings.stageAccents.reduce(into: [StageID: NSColor]()) { result, item in
            guard let color = NSColor(hex: item.value) else { return }
            result[StageID(rawValue: item.key)] = color
        }
        let preview = settings.preview
        let parallax = settings.parallax
        let displayLabel = settings.displayLabel
        let desktopLabel = settings.desktopLabel
        let stageLabel = settings.stageLabel
        let useParallaxGeometry = mode == .parallax
        return RailVisualConfig(
            mode: mode,
            stageAccents: accents,
            railWidth: CGFloat(settings.width),
            backgroundColor: NSColor(hex: settings.backgroundColor) ?? .black,
            backgroundOpacity: CGFloat(settings.backgroundOpacity),
            autoHide: settings.autoHide,
            edgeHitWidth: CGFloat(settings.edgeHitWidth),
            edgeMagnetismWidth: CGFloat(settings.edgeMagnetismWidth),
            animationDuration: settings.animationMS / 1000,
            hideDelay: settings.hideDelayMS / 1000,
            emptyClickHideActive: settings.emptyClickHideActive,
            emptyClickSafetyMargin: CGFloat(settings.emptyClickSafetyMargin),
            hideOnMaximized: settings.hideOnMaximized,
            previewWidth: CGFloat(useParallaxGeometry ? parallax.width : preview.width),
            previewHeight: CGFloat(useParallaxGeometry ? parallax.height : preview.height),
            leadingPadding: CGFloat(useParallaxGeometry ? parallax.leadingPadding : preview.leadingPadding),
            trailingPadding: CGFloat(useParallaxGeometry ? parallax.trailingPadding : preview.trailingPadding),
            verticalPadding: CGFloat(useParallaxGeometry ? parallax.verticalPadding : preview.verticalPadding),
            stackedOffsetX: CGFloat(settings.stacked.offsetX),
            stackedOffsetY: CGFloat(settings.stacked.offsetY),
            stackedScale: CGFloat(settings.stacked.scalePerLayer),
            stackedOpacity: CGFloat(settings.stacked.opacityPerLayer),
            parallaxRotation: CGFloat(parallax.rotation),
            parallaxOffsetX: CGFloat(parallax.offsetX),
            parallaxOffsetY: CGFloat(parallax.offsetY),
            parallaxScale: CGFloat(parallax.scalePerLayer),
            parallaxOpacity: CGFloat(parallax.opacityPerLayer),
            parallaxDarken: CGFloat(parallax.darkenPerLayer),
            headerPosition: RailHeaderPosition(rawValue: settings.layout.headerPosition) ?? .top,
            stagesPosition: RailStagesPosition(rawValue: settings.stages.position) ?? RailStagesPosition(rawValue: settings.layout.stagesPosition) ?? .center,
            layoutSpacing: CGFloat(settings.stages.gap > 0 ? settings.stages.gap : settings.layout.spacing),
            layoutTopPadding: CGFloat(settings.layout.topPadding),
            layoutBottomPadding: CGFloat(settings.layout.bottomPadding),
            headerHeight: max(CGFloat(displayLabel.fontSize + desktopLabel.fontSize + 12), 1),
            headerWidth: 0,
            displayLabel: RailLabelConfig(settings: displayLabel, fallbackColor: .white.withAlphaComponent(0.86)),
            desktopLabel: RailLabelConfig(settings: desktopLabel, fallbackColor: .white.withAlphaComponent(0.42)),
            stageLabel: RailStageLabelConfig(settings: stageLabel)
        )
    }
}

@MainActor
enum RailHeaderPosition: String {
    case top
    case bottom
    case hidden
}

@MainActor
enum RailStagesPosition: String {
    case top
    case center
    case bottom
}

@MainActor
enum RailTextAlignment: String {
    case left
    case center
    case right

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left:
            return .left
        case .center:
            return .center
        case .right:
            return .right
        }
    }
}

@MainActor
enum RailStageLabelPlacement: String {
    case above
    case below
}

@MainActor
enum RailStageLabelZOrder: String {
    case below
    case above
}

@MainActor
struct RailLabelConfig {
    var enabled: Bool
    var template: String
    var color: NSColor
    var fontSize: CGFloat
    var fontFamily: String
    var weight: NSFont.Weight
    var alignment: RailTextAlignment
    var offsetX: CGFloat
    var offsetY: CGFloat

    static let displayDefault = RailLabelConfig(
        enabled: true,
        template: "{display}",
        color: .white.withAlphaComponent(0.86),
        fontSize: 13,
        fontFamily: "system",
        weight: .bold,
        alignment: .center,
        offsetX: 0,
        offsetY: 0
    )

    static let desktopDefault = RailLabelConfig(
        enabled: true,
        template: "Desktop {desktop}",
        color: .white.withAlphaComponent(0.42),
        fontSize: 10,
        fontFamily: "system",
        weight: .medium,
        alignment: .center,
        offsetX: 0,
        offsetY: 0
    )

    init(
        enabled: Bool,
        template: String,
        color: NSColor,
        fontSize: CGFloat,
        fontFamily: String,
        weight: NSFont.Weight,
        alignment: RailTextAlignment,
        offsetX: CGFloat,
        offsetY: CGFloat
    ) {
        self.enabled = enabled
        self.template = template
        self.color = color
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.weight = weight
        self.alignment = alignment
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    init(settings: RailSettings.Label, fallbackColor: NSColor) {
        self.init(
            enabled: settings.enabled,
            template: settings.template,
            color: (NSColor(hex: settings.color) ?? fallbackColor).withAlphaComponent(CGFloat(settings.opacity)),
            fontSize: CGFloat(settings.fontSize),
            fontFamily: settings.fontFamily,
            weight: NSFont.Weight.toml(settings.weight),
            alignment: RailTextAlignment(rawValue: settings.alignment) ?? .center,
            offsetX: CGFloat(settings.offsetX),
            offsetY: CGFloat(settings.offsetY)
        )
    }
}

@MainActor
struct RailStageLabelConfig {
    var enabled: Bool
    var color: NSColor?
    var useStageAccent: Bool
    var fontSize: CGFloat
    var fontFamily: String
    var weight: NSFont.Weight
    var alignment: RailTextAlignment
    var opacity: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
    var placement: RailStageLabelPlacement
    var zOrder: RailStageLabelZOrder
    var visibilitySeconds: TimeInterval
    var fadeSeconds: TimeInterval
    var visibleUntil: TimeInterval?

    static let `default` = RailStageLabelConfig(
        enabled: true,
        color: nil,
        useStageAccent: true,
        fontSize: 11,
        fontFamily: "system",
        weight: .semibold,
        alignment: .center,
        opacity: 0.72,
        offsetX: 0,
        offsetY: 0,
        placement: .below,
        zOrder: .below,
        visibilitySeconds: 0,
        fadeSeconds: 0.35,
        visibleUntil: nil
    )

    init(
        enabled: Bool,
        color: NSColor?,
        useStageAccent: Bool,
        fontSize: CGFloat,
        fontFamily: String,
        weight: NSFont.Weight,
        alignment: RailTextAlignment,
        opacity: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat,
        placement: RailStageLabelPlacement,
        zOrder: RailStageLabelZOrder,
        visibilitySeconds: TimeInterval,
        fadeSeconds: TimeInterval,
        visibleUntil: TimeInterval? = nil
    ) {
        self.enabled = enabled
        self.color = color
        self.useStageAccent = useStageAccent
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.weight = weight
        self.alignment = alignment
        self.opacity = opacity
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.placement = placement
        self.zOrder = zOrder
        self.visibilitySeconds = visibilitySeconds
        self.fadeSeconds = fadeSeconds
        self.visibleUntil = visibleUntil
    }

    init(settings: RailSettings.StageLabel) {
        let trimmedColor = settings.color.trimmingCharacters(in: .whitespacesAndNewlines)
        let useStageAccent = trimmedColor.isEmpty || trimmedColor.lowercased() == "stage"
        self.init(
            enabled: settings.enabled,
            color: useStageAccent ? nil : NSColor(hex: trimmedColor),
            useStageAccent: useStageAccent,
            fontSize: CGFloat(settings.fontSize),
            fontFamily: settings.fontFamily,
            weight: NSFont.Weight.toml(settings.weight),
            alignment: RailTextAlignment(rawValue: settings.alignment) ?? .center,
            opacity: CGFloat(settings.opacity),
            offsetX: CGFloat(settings.offsetX),
            offsetY: CGFloat(settings.offsetY),
            placement: RailStageLabelPlacement(rawValue: settings.placement) ?? .below,
            zOrder: RailStageLabelZOrder(rawValue: settings.zOrder) ?? .below,
            visibilitySeconds: settings.visibilitySeconds,
            fadeSeconds: settings.fadeSeconds
        )
    }

    func opacityMultiplier(now: Date = Date()) -> CGFloat {
        guard visibilitySeconds > 0 else { return 1 }
        guard let visibleUntil else { return 0 }
        let current = now.timeIntervalSince1970
        guard current >= 0 else { return 0 }
        if current <= visibleUntil {
            return 1
        }
        guard fadeSeconds > 0 else { return 0 }
        let fadeProgress = (current - visibleUntil) / fadeSeconds
        return CGFloat(max(0, min(1, 1 - fadeProgress)))
    }

    func resolvedColor(stageAccent: NSColor, now: Date = Date()) -> NSColor {
        (useStageAccent ? stageAccent : (color ?? stageAccent)).withAlphaComponent(opacity * opacityMultiplier(now: now))
    }
}

@MainActor
enum RailRenderMode: String {
    case stacked = "stacked-previews"
    case mosaic
    case parallax = "parallax-45"
    case icons = "icons-only"

    static func load(renderer: String) -> RailRenderMode {
        switch renderer {
        case "mosaic":
            return .mosaic
        case "parallax-45", "parallax":
            return .parallax
        case "icons-only", "icons":
            return .icons
        default:
            return .stacked
        }
    }
}

private extension NSFont.Weight {
    static func toml(_ value: String) -> NSFont.Weight {
        switch value.lowercased() {
        case "regular":
            return .regular
        case "semibold":
            return .semibold
        case "bold":
            return .bold
        default:
            return .medium
        }
    }
}
