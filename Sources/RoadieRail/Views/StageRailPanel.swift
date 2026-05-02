import AppKit
import SwiftUI

// SPEC-014 T027 — Panel NSPanel non-activating pour le rail.
// Niveau statusBar, sans bordure, fond transparent, ne vole pas le focus.

final class StageRailPanel: NSPanel {
    private var hostingView: NSHostingView<AnyView>?

    init(rootView: some View) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure()
        setRootView(rootView)
    }

    // MARK: - NSWindow overrides

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Public

    /// Place le panel sur l'edge gauche de l'écran donné.
    func position(on screen: NSScreen, width: CGFloat = 408, edgeWidth: CGFloat = 8) {
        let f = screen.frame
        setFrame(NSRect(x: f.minX, y: f.minY, width: width, height: f.height), display: false)
    }

    func setRootView(_ view: some View) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        hostingView = hosting
    }

    // MARK: - Private

    private func configure() {
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        hasShadow = false  // pas d'ombre sur le panel lui-même (fond transparent)
        backgroundColor = .clear
        isOpaque = false
        alphaValue = 0
    }
}
