import AppKit
import SwiftUI

/// Fenêtre unique « Réglages Roadie » (SPEC-023, research R7). Le daemon reste `.accessory` :
/// la fenêtre active le processus à l'ouverture et rend le focus à l'application précédente à la fermeture.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private let model = SettingsViewModel(service: SettingsService())
    private var window: NSWindow?
    private var watcher: RailFileWatcher?
    /// Application au premier plan avant l'ouverture, réactivée à la fermeture.
    private var previousApplication: NSRunningApplication?

    /// Ouvre la fenêtre, ou la ramène devant. `nil` : dernière catégorie vue (Général à la première ouverture).
    public func show(category: SettingCategory?) {
        model.prepareForShow(category: category)
        let window = self.window ?? makeWindow()
        self.window = window
        if let front = NSWorkspace.shared.frontmostApplication, front != .current {
            previousApplication = front
        }
        // Le watcher ne démarre pas si le fichier est absent : on le relance à chaque ouverture.
        if watcher == nil {
            let path = model.service.configPath
            watcher = RailFileWatcher(path: { path }, onChange: { [weak self] in self?.model.refresh() })
        }
        watcher?.start()
        // Fenêtre déjà au premier plan : `windowDidBecomeKey` ne viendra pas, on relit ici.
        if window.isKeyWindow { model.refresh() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        // La taille vient de la fenêtre, pas de la taille idéale de la vue.
        hosting.sizingOptions = []
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Réglages Roadie"
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 860, height: 600))
        window.contentMinSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        window.center()
        return window
    }

    // MARK: - NSWindowDelegate

    public func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }

    public func windowWillClose(_ notification: Notification) {
        watcher?.stop()
        if let previous = previousApplication, !previous.isTerminated {
            _ = previous.activate(from: .current, options: [])
        }
        previousApplication = nil
    }
}

/// Sans menu principal dans le daemon, la fenêtre gère elle-même Cmd + W, Échap et les raccourcis d'édition.
private final class SettingsWindow: NSWindow {
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
