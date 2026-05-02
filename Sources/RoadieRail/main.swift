import AppKit

// SPEC-014 T034 — Entry point roadie-rail.
// Politique .accessory : pas d'icône dans le Dock, pas de menu bar.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
