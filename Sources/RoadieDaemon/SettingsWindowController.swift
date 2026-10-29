import AppKit
import RoadieCore
import SwiftUI

/// Fenêtre unique « Réglages Roadie » (SPEC-023, research R7). Le daemon reste `.accessory` et ne s'active jamais :
/// depuis macOS 14, un processus d'arrière-plan ne peut pas prendre le premier plan (`NSApp.activate()` est refusé), et une
/// `NSWindow` ordinaire restait alors derrière les fenêtres de l'application active, invisible. La fenêtre est donc un panneau
/// qui n'active pas l'application (`.nonactivatingPanel`), placé devant toutes les fenêtres et sur l'écran du pointeur ; il
/// reçoit quand même le clavier, et l'application de l'utilisateur garde son rôle d'application active.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private let model = SettingsViewModel(service: .shared)
    private var window: NSWindow?
    private var watcher: RailFileWatcher?
    /// Surveille le dossier du fichier tant que celui-ci est absent ; arrêtée dès sa création.
    private var directoryWatcher: RailFileWatcher?

    /// Ouvre la fenêtre, ou la ramène devant. `nil` : dernière catégorie vue (Général à la première ouverture).
    /// `query` : recherche déjà tapée, pour montrer un réglage trouvé par la barre (session 115).
    public func show(category: SettingCategory?, query: String? = nil) {
        WindowSwitcherHotkeyRegistry.observePeerStatus()
        model.prepareForShow(category: category)
        if let query { model.query = query }
        let window = self.window ?? makeWindow()
        self.window = window
        armWatchers()
        // Fenêtre déjà au premier plan : `windowDidBecomeKey` ne viendra pas, on relit ici.
        if window.isKeyWindow { model.refresh() }
        if !window.isVisible {
            let screens = NSScreen.screens.map(\.visibleFrame)
            window.setFrame(Self.centeredFrame(size: window.frame.size, screens: screens, pointer: NSEvent.mouseLocation), display: false)
        }
        // `orderFrontRegardless` : devant toutes les fenêtres sans activer l'application ; `makeKey` : clavier au panneau.
        window.orderFrontRegardless()
        window.makeKey()
    }

    /// Cadre de la fenêtre, centré dans l'écran qui contient le pointeur (le premier écran à défaut). Pur : testable sans écran.
    /// Complexité : O(s), s = nombre d'écrans.
    nonisolated static func centeredFrame(size: NSSize, screens: [CGRect], pointer: CGPoint) -> CGRect {
        guard let area = screens.first(where: { $0.contains(pointer) }) ?? screens.first else {
            return CGRect(origin: .zero, size: size)
        }
        let width = min(size.width, area.width), height = min(size.height, area.height)
        return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }

    /// Le watcher du fichier ne démarre pas si le fichier est absent : dans ce cas, le dossier parent est surveillé
    /// jusqu'à la création du fichier. Limite : si le dossier n'existe pas non plus, rien n'est surveillé
    /// (la prise de focus relit tout de même). Appelé à chaque ouverture et quand le fichier disparaît.
    private func armWatchers() {
        let path = model.service.configPath
        if watcher == nil {
            watcher = RailFileWatcher(path: { path }, onChange: { [weak self] in
                self?.model.refresh()
                // Fichier supprimé : le réarmement du watcher échoue, le dossier prend le relais.
                if let self, !FileManager.default.fileExists(atPath: path) { self.armWatchers() }
            })
        }
        if FileManager.default.fileExists(atPath: path) {
            directoryWatcher?.stop()
            directoryWatcher = nil
            watcher?.start()
        } else if directoryWatcher == nil {
            let directory = (path as NSString).deletingLastPathComponent
            directoryWatcher = RailFileWatcher(path: { directory }, onChange: { [weak self] in
                guard let self else { return }
                self.model.refresh()
                if FileManager.default.fileExists(atPath: path) { self.armWatchers() }
            })
            directoryWatcher?.start()
        }
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        // La taille vient de la fenêtre, pas de la taille idéale de la vue.
        hosting.sizingOptions = []
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = tr("Réglages Roadie", "Roadie Settings")
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 1040, height: 760))
        window.contentMinSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.delegate = self
        return window
    }

    // MARK: - NSWindowDelegate

    public func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }

    public func windowWillClose(_ notification: Notification) {
        watcher?.stop()
        directoryWatcher?.stop()
        directoryWatcher = nil
    }
}

/// Sans menu principal dans le daemon, la fenêtre gère elle-même Cmd + W, Échap et les raccourcis d'édition.
private final class SettingsWindow: NSPanel {
    /// Un panneau ne devient « key » que s'il le dit : sans cela, ses champs ne recevraient pas le clavier.
    override var canBecomeKey: Bool { true }

    /// Raccourcis du menu Édition, absents du daemon : sans eux, coller dans un champ est impossible.
    private static let editActions: [String: Selector] = [
        "x": #selector(NSText.cut(_:)),
        "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)),
        "a": #selector(NSText.selectAll(_:)),
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }
        if key == "w" {
            performClose(nil)
            return true
        }
        if let action = Self.editActions[key], NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Échap ferme la fenêtre, sauf pendant l'édition d'un champ : il termine alors seulement l'édition
    /// (la perte du focus valide le champ).
    override func cancelOperation(_ sender: Any?) {
        if let editor = firstResponder as? NSTextView, editor.isFieldEditor {
            makeFirstResponder(nil)
            return
        }
        performClose(nil)
    }
}
