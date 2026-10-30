import AppKit
import RoadieCore

/// Fiche « Informations » d'un fichier (session 131), à la manière du « Lire les informations » du Finder : icône,
/// nom et type en tête, puis libellés et valeurs alignés, copiables. Hauteur ajustée au contenu ; Échap ferme.
/// Le fond suit le style des fenêtres de workflow (`workflow_view_style`).
@MainActor
final class FileInfoPanel: NSObject, NSWindowDelegate {
    private(set) static var current: FileInfoPanel?

    let panel: NSPanel
    private var monitor: Any?

    private static let width: CGFloat = 480
    private static let labelWidth: CGFloat = 84

    static func show(path: String, info: LauncherFileOperations.Info?) {
        current?.close()
        let controller = FileInfoPanel(path: path, info: info)
        current = controller
        controller.present()
    }

    private init(path: String, info: LauncherFileOperations.Info?) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 300),
                        styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        super.init()
        let style = WorkflowViewStyle.current
        let content = NSVisualEffectView()
        style.prepare(panel, effect: content)
        let root = NSStackView(views: [header(path: path, info: info), separator(), grid(path: path, info: info)])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: style == .system ? 16 : 34, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        panel.contentView = content
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor), root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor), root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: Self.width),
        ])
        panel.setContentSize(NSSize(width: Self.width, height: root.fittingSize.height))
    }

    /// Icône, nom (gras, sur deux lignes au plus) et type. O(1).
    private func header(path: String, info: LauncherFileOperations.Info?) -> NSView {
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: path))
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 56), icon.heightAnchor.constraint(equalToConstant: 56)])
        let name = value((path as NSString).lastPathComponent, font: .systemFont(ofSize: 15, weight: .semibold), width: Self.width - 112)
        name.maximumNumberOfLines = 2
        let kind = NSTextField(labelWithString: info?.kind ?? tr("Informations illisibles", "Information unavailable"))
        kind.font = .systemFont(ofSize: 12)
        kind.textColor = .secondaryLabelColor
        let titles = NSStackView(views: [name, kind])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 3
        let row = NSStackView(views: [icon, titles])
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: Self.width - 40).isActive = true
        return line
    }

    /// Emplacement puis lignes de la fiche ; les identifiants techniques en police fixe, plus petite. O(l).
    private func grid(path: String, info: LauncherFileOperations.Info?) -> NSView {
        var rows = [(tr("Emplacement", "Where"), ((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)]
        rows += info?.lines ?? []
        let technical: Set<String> = ["UTI", "MIME", "SHA-256"]
        let valueWidth = Self.width - 40 - Self.labelWidth - 12
        let grid = NSGridView(views: rows.map { label, text in
            let title = NSTextField(labelWithString: label)
            title.font = .systemFont(ofSize: 12)
            title.textColor = .secondaryLabelColor
            title.alignment = .right
            let font: NSFont = technical.contains(label) ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 12)
            return [title, value(text, font: font, width: valueWidth)]
        })
        grid.rowSpacing = 7
        grid.columnSpacing = 12
        grid.column(at: 0).width = Self.labelWidth
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        return grid
    }

    /// Valeur sélectionnable (copiable), repliée à la largeur donnée. O(1).
    private func value(_ text: String, font: NSFont, width: CGFloat) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.isSelectable = true
        field.lineBreakMode = .byCharWrapping
        field.preferredMaxLayoutWidth = width
        return field
    }

    private func present() {
        panel.title = ""
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, event.keyCode == 53 else { return event }
            self.close()
            return nil
        }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel.orderOut(nil)
        if Self.current === self { Self.current = nil }
    }

    func windowWillClose(_ notification: Notification) { close() }
}
