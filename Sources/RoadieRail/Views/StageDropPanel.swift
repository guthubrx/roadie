import AppKit
import RoadieCore

/// SPEC-028 — overlay panel transparent couvrant la frame d'un écran (sauf le
/// rail). Reçoit les drops de `WindowDragData` (UTI `com.roadie.window-drag`)
/// initiés depuis n'importe quelle vignette du rail, et déclenche un callback
/// `onSummon(wid)` qui re-assigne la fenêtre à la stage active du display.
///
/// Le panel utilise `ignoresMouseEvents = true` pour rester transparent aux
/// clics normaux (ne pas casser l'interaction avec les apps utilisateur),
/// mais reste réceptif aux drags via `registerForDraggedTypes` sur le NSView
/// interne. macOS dispatch les drags hors du chemin hitTest standard.
///
/// Niveau `.floating - 1` : sous le rail (qui doit garder priorité hit-test
/// pour les drops on-stage), au-dessus du desktop standard. Les drops qui
/// atterrissent sur le rail vont au rail (renderer.dropDestination), ceux
/// qui tombent ailleurs sur le display tombent sur ce panel.
final class StageDropPanel: NSPanel {
    /// Callback invoqué quand un drop valide est reçu. Param : la `wid` payload.
    var onSummon: ((CGWindowID) -> Void)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = StageDropView()
        view.frame = screen.frame
        view.autoresizingMask = [.width, .height]
        view.onSummon = { [weak self] wid in self?.onSummon?(wid) }
        contentView = view
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// NSView interne qui s'enregistre pour le UTI custom `com.roadie.window-drag`
/// (cf. `WindowDragData.swift`) et décode le payload pour appeler `onSummon`.
final class StageDropView: NSView {
    var onSummon: ((CGWindowID) -> Void)?

    private static let draggedType = NSPasteboard.PasteboardType("com.roadie.window-drag")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([Self.draggedType])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // .move = curseur affiche flèche+icône standard de move ; ne fait rien
        // au stockage du payload, l'action effective est dans performDragOperation.
        return .move
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        guard let data = pb.data(forType: Self.draggedType),
              let payload = try? JSONDecoder().decode(WindowDragPayload.self, from: data)
        else { return false }
        onSummon?(payload.wid)
        return true
    }
}

/// Mirror minimal de `WindowDragData` (qui est `internal` au target rail) pour
/// permettre le décodage côté drop receiver. Apple's CodableRepresentation
/// sérialise via `JSONEncoder` par défaut → format JSON `{"wid":N,"sourceStageID":"..."}`.
private struct WindowDragPayload: Decodable {
    let wid: CGWindowID
    let sourceStageID: String
}
