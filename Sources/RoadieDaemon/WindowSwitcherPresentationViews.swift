import AppKit
import RoadieCore

/// Recadre les vignettes sur le haut du contenu. Le grand aperçu reste intégral.
@MainActor
final class WindowSwitcherThumbnailView: NSImageView {
    var fillsThumbnail = false
    var isIcon = false

    static func sourceRect(image: CGSize, target: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, target.width > 0, target.height > 0 else { return .zero }
        let scale = max(target.width / image.width, target.height / image.height)
        let size = CGSize(width: target.width / scale, height: target.height / scale)
        return CGRect(x: (image.width - size.width) / 2, y: image.height - size.height,
                      width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isIcon, let image {
            let side = min(64, bounds.width, bounds.height)
            image.draw(in: CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        guard fillsThumbnail, let image, image.size.width > 0, image.size.height > 0 else {
            super.draw(dirtyRect)
            return
        }
        image.draw(in: bounds, from: Self.sourceRect(image: image.size, target: bounds.size),
                   operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
    }
}

/// Détail commun : chemin de la fenêtre, titre, capture intégrale et action explicite.
@MainActor
final class WindowSwitcherDetailView: NSView {
    var onOpen: (() -> Void)?
    private let breadcrumb = NSTextField(labelWithString: "")
    private let heading = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private let iconView = NSImageView()
    private let appLabel = NSTextField(labelWithString: "")
    private let contextLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton(title: "Ouvrir ↗", target: nil, action: nil)
    private var switcherAppearance = WindowSwitcherAppearance(config: WindowSwitcherConfig())

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for label in [breadcrumb, heading, appLabel, contextLabel] {
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        breadcrumb.textColor = .secondaryLabelColor
        contextLabel.textColor = .secondaryLabelColor
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 9
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 0.5
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
        imageView.setAccessibilityLabel("Aperçu intégral de la fenêtre sélectionnée")
        iconView.imageScaling = .scaleProportionallyUpOrDown
        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(openSelected)
        for view in [imageView, iconView, openButton] { addSubview(view) }
    }

    required init?(coder: NSCoder) { nil }

    func update(entry: WindowSwitcherEntry?, image: NSImage?, icon: NSImage?, appearance: WindowSwitcherAppearance) {
        self.switcherAppearance = appearance
        let context = [entry?.desktopName, entry?.stageName].compactMap { $0 }.filter { !$0.isEmpty }
        breadcrumb.stringValue = context.joined(separator: "  ›  ")
        heading.stringValue = entry.map { $0.window.title.isEmpty ? $0.window.appName : $0.window.title } ?? ""
        appLabel.stringValue = entry?.window.appName ?? ""
        contextLabel.stringValue = ([entry?.displayName ?? ""] + (entry?.stateBadges ?? [])).filter { !$0.isEmpty }.joined(separator: " · ")
        for label in [breadcrumb, heading, appLabel, contextLabel] { label.toolTip = label.stringValue }
        imageView.image = image ?? icon
        iconView.image = icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        openButton.isEnabled = entry != nil
        layoutContent()
    }

    func layoutContent() {
        let inset: CGFloat = 12
        let width = max(0, bounds.width - 2 * inset)
        let height = max(0, bounds.height - 2 * inset)
        let font = switcherAppearance.fontSize
        let line = ceil(font * 1.5)
        breadcrumb.font = switcherAppearance.font(size: max(11, font - 2), weight: .regular)
        heading.font = switcherAppearance.font(size: font + 3, weight: .semibold)
        appLabel.font = switcherAppearance.font(size: font, weight: .medium)
        contextLabel.font = breadcrumb.font
        openButton.font = breadcrumb.font
        let horizontal = bounds.width > bounds.height * 1.8 || bounds.height < 240
        let textX = horizontal ? inset + width * 0.43 + 16 : inset
        let textWidth = max(0, bounds.width - inset - textX)
        let crumbHeight = min(line, height)
        breadcrumb.frame = CGRect(x: textX, y: inset, width: textWidth, height: crumbHeight)
        let titleY = breadcrumb.frame.maxY + 6
        heading.frame = CGRect(x: textX, y: titleY, width: textWidth, height: min(line + 6, max(0, bounds.height - inset - titleY)))
        let metadataHeight = min(line * 2 + 12, max(0, height - heading.frame.maxY))
        let imageY = horizontal ? inset : heading.frame.maxY + 14
        let imageBottom = horizontal ? bounds.height - inset : max(imageY, bounds.height - inset - metadataHeight - 16)
        imageView.frame = CGRect(x: inset, y: imageY, width: horizontal ? width * 0.43 : width,
                                 height: max(0, imageBottom - imageY))
        let metadataY = horizontal ? heading.frame.maxY + 12 : imageView.frame.maxY + 14
        let fitsMetadata = metadataY + line * 2 + 8 <= bounds.height - inset
        for view in [iconView, appLabel, contextLabel, openButton] { view.isHidden = !fitsMetadata }
        if fitsMetadata {
            let iconSize = min(38, line * 2)
            iconView.frame = CGRect(x: textX, y: metadataY, width: iconSize, height: iconSize)
            let labelX = textX + iconSize + 10
            let buttonWidth = min(90, textWidth * 0.3)
            openButton.frame = CGRect(x: bounds.width - inset - buttonWidth, y: metadataY,
                                      width: buttonWidth, height: min(30, line + 6))
            appLabel.frame = CGRect(x: labelX, y: metadataY, width: max(0, openButton.frame.minX - labelX - 8), height: line)
            contextLabel.frame = CGRect(x: labelX, y: metadataY + line + 6,
                                        width: max(0, bounds.width - inset - labelX), height: line)
        }
    }

    @objc private func openSelected() { onOpen?() }
}
