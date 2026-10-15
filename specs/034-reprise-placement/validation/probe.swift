import AppKit

final class PlacementProbeApplication: NSApplication {
    var exposesWindow = false
    override func accessibilityWindows() -> [Any]? { exposesWindow ? super.accessibilityWindows() : [] }
}

let app = PlacementProbeApplication.shared as! PlacementProbeApplication
app.setActivationPolicy(.regular)
let initialScreen = NSScreen.screens.first { !$0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.screens[0]
let visible = initialScreen.visibleFrame
let window = NSWindow(contentRect: NSRect(x: visible.minX + 200, y: visible.minY + 150, width: 570, height: 436),
    styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
window.title = "Roadie placement check"
window.isReleasedWhenClosed = false
window.contentView = NSTextField(labelWithString: "Vérification temporaire du placement Roadie")
window.setFrameOrigin(NSPoint(x: visible.minX + 200, y: visible.minY + 150))
let metadata = "mouse=\(NSEvent.mouseLocation) chosen=\(initialScreen.frame) actual=\(window.frame)"
try! metadata.write(toFile: "/private/tmp/roadie034-probe-coordinates.txt", atomically: true, encoding: .utf8)
window.orderFrontRegardless()
DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
    app.exposesWindow = true
    NSAccessibility.post(element: window, notification: .windowCreated)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 12) { app.terminate(nil) }
app.run()
