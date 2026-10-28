import AppKit
import Foundation
import PDFKit

/// Fenêtre des vues Image et PDF d'un workflow (session 118), comme celle de la vue Texte : panneau qui n'active
/// pas Roadie mais reçoit le clavier. Échap ferme ; Retour (avec ou sans touche tenue) envoie le chemin du fichier
/// à la suite du schéma.
@MainActor
final class WorkflowMediaPanel: NSObject, NSWindowDelegate {
    typealias Proceed = @MainActor (_ path: String, _ modifiers: Int) -> Void

    private static var current: WorkflowMediaPanel?

    private let view: AlfredMediaView
    private let proceed: Proceed
    private let panel: NSPanel
    private var monitor: Any?

    static func show(_ view: AlfredMediaView, proceed: @escaping Proceed) {
        current?.close()
        let controller = WorkflowMediaPanel(view: view, proceed: proceed)
        current = controller
        controller.present()
    }

    private init(view: AlfredMediaView, proceed: @escaping Proceed) {
        self.view = view
        self.proceed = proceed
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                        styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        super.init()
    }

    private func present() {
        panel.title = "\(view.title) · \((view.path as NSString).lastPathComponent)"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.minSize = NSSize(width: 320, height: 240)
        panel.contentView = view.kind == .pdf ? pdfView() : imageView()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.keyCode == 53 { self.close(); return nil }
            guard event.keyCode == 36 || event.keyCode == 76 else { return event }
            let path = self.view.path, modifiers = WorkflowTextPanel.alfredModifiers(event.modifierFlags)
            self.close()
            self.proceed(path, modifiers)
            return nil
        }
    }

    /// Image : réduite à la fenêtre (automatique), agrandie aussi (ajustée), ou à ses pixels réels (sans tenir
    /// compte de la résolution d'écran), dans une vue défilante. O(1).
    private func imageView() -> NSView {
        let image = NSImage(contentsOfFile: view.path) ?? NSImage()
        if view.imageSize == .ignoreDPI, let rep = image.representations.first, rep.pixelsWide > 0 {
            image.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        let imageView = NSImageView(image: image)
        imageView.imageScaling = view.imageSize == .fit ? .scaleProportionallyUpOrDown : .scaleProportionallyDown
        guard view.imageSize == .ignoreDPI else { return imageView }
        imageView.frame = NSRect(origin: .zero, size: image.size)
        let scroll = NSScrollView()
        scroll.documentView = imageView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        return scroll
    }

    /// PDF : mode d'affichage de la brique ; automatique : une page continue. O(1).
    private func pdfView() -> NSView {
        let pdf = PDFView()
        pdf.document = PDFDocument(url: URL(fileURLWithPath: view.path))
        pdf.autoScales = true
        pdf.displayMode = switch view.pdfMode {
        case .singlePage: .singlePage
        case .twoPages: .twoUp
        case .twoPagesContinuous: .twoUpContinuous
        case .automatic, .singlePageContinuous: .singlePageContinuous
        }
        return pdf
    }

    func windowWillClose(_ notification: Notification) { teardown() }

    private func close() {
        teardown()
        panel.orderOut(nil)
    }

    private func teardown() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if Self.current === self { Self.current = nil }
    }
}
