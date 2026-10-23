import AppKit
import Carbon
import SwiftUI

/// Conversion de l'appui réel ; aucune saisie du nom des touches. O(128) pour la disposition.
enum ShortcutCapture {
    static func value(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, layout: [UInt32: String]) -> String? {
        var names: [String] = []
        if modifiers.contains(.control) { names.append("control") }
        if modifiers.contains(.option) { names.append("alt") }
        if modifiers.contains(.shift) { names.append("shift") }
        if modifiers.contains(.command) { names.append("command") }
        guard modifiers.contains(.control) || modifiers.contains(.option) || modifiers.contains(.command) else { return nil }
        let named = ["space", "return", "tab", "escape", "backspace", "left", "right", "up", "down"] + (1...12).map { "f\($0)" }
        let key = named.first { TargetSearchHotkey.namedKeyCode($0) == keyCode }
            ?? layout[keyCode].flatMap { $0.count == 1 && !$0.contains("+") && !$0.contains(where: \.isWhitespace) ? $0 : nil }
            ?? "keycode-\(keyCode)"
        return (names + [key]).joined(separator: "+")
    }

    static func label(_ raw: String) -> String {
        guard !raw.isEmpty else { return "Enregistrer…" }
        let symbols = ["command": "⌘", "cmd": "⌘", "control": "⌃", "ctrl": "⌃",
                       "alt": "⌥", "option": "⌥", "shift": "⇧", "tab": "⇥", "space": "Espace",
                       "return": "↩", "escape": "⎋", "left": "←", "right": "→", "up": "↑", "down": "↓"]
        return raw.split(separator: "+").map { symbols[String($0)] ?? $0.uppercased() }.joined(separator: " ")
    }
}

struct ShortcutRecorderControl: View {
    let value: String
    let fontSize: Double
    let onChange: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            RecorderButton(value: value, fontSize: fontSize, onChange: onChange)
                .frame(minWidth: 120, idealWidth: 230, maxWidth: .infinity, minHeight: 34)
            if !value.isEmpty {
                Button("Effacer", systemImage: "xmark.circle") { onChange("") }
                    .labelStyle(.iconOnly).accessibilityLabel("Effacer le raccourci")
            }
        }
    }
}

private struct RecorderButton: NSViewRepresentable {
    let value: String
    let fontSize: Double
    let onChange: (String) -> Void
    @Environment(\.isEnabled) private var enabled

    func makeNSView(context: Context) -> ShortcutRecorderButton { ShortcutRecorderButton() }
    func updateNSView(_ view: ShortcutRecorderButton, context: Context) {
        view.onChange = onChange
        view.raw = value
        view.font = .systemFont(ofSize: fontSize)
        view.isEnabled = enabled
        if !view.recording { view.title = ShortcutCapture.label(value) }
        view.setAccessibilityLabel("Enregistrer le raccourci : " + ShortcutCapture.label(value))
    }
    static func dismantleNSView(_ view: ShortcutRecorderButton, coordinator: ()) { view.finish() }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ShortcutRecorderButton, context: Context) -> CGSize? {
        let font = nsView.font ?? NSFont.systemFont(ofSize: fontSize)
        return CGSize(width: proposal.width ?? 230, height: max(34, ceil(font.ascender - font.descender + font.leading) + 12))
    }
}

@MainActor
private final class ShortcutRecorderButton: NSButton {
    var raw = ""
    var onChange: ((String) -> Void)?
    private(set) var recording = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timeout: Timer?
    private var focusObserver: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        isBordered = false
        updateSettingsSurface()
        cell?.lineBreakMode = .byTruncatingTail
        target = self
        action = #selector(begin)
    }
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSettingsSurface()
    }

    @objc private func begin() {
        guard !recording else { finish(); return }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let recorder = Unmanaged<ShortcutRecorderButton>.fromOpaque(context).takeUnretainedValue()
            let consumed = MainActor.assumeIsolated {
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    recorder.finish()
                    return false
                }
                guard recorder.recording, recorder.window?.isKeyWindow == true, type == .keyDown else {
                    return false
                }
                let code = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
                if code == 53 { recorder.finish(); return true }
                let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                if let value = ShortcutCapture.value(keyCode: code, modifiers: flags, layout: TargetSearchHotkey.currentLayoutTable()) {
                    let change = recorder.onChange
                    recorder.finish()
                    change?(value)
                } else { recorder.title = "Ajoutez ⌘, ⌃ ou ⌥" }
                return true
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            title = "Capture indisponible : vérifiez l’accès de Roadie"
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        recording = true
        title = "Vos touches…"
        toolTip = "Appuyez sur la combinaison. Échap annule."
        timeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        if let window {
            focusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            }
        }
    }

    func finish() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        recording = false
        timeout?.invalidate()
        timeout = nil
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        focusObserver = nil
        title = ShortcutCapture.label(raw)
    }
}

