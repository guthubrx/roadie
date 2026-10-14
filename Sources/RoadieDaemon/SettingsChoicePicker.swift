import AppKit
import SwiftUI

/// Le Picker SwiftUI macOS impose 13 points : ce contrôle natif garde une police lisible.
struct SettingsChoicePicker: NSViewRepresentable {
    let descriptor: SettingDescriptor
    let fontSize: Double
    @Binding var selection: String
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .large
        button.font = .systemFont(ofSize: fontSize)
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        let values = descriptor.choiceValues(includingCurrent: selection)
        let selectable: Set<String>
        if case .choice(let choices) = descriptor.kind { selectable = Set(choices) } else { selectable = [] }
        // Garder le menu natif stable pendant les mises à jour de la vue. O(c), c < 10.
        if button.itemArray.compactMap({ $0.representedObject as? String }) != values {
            button.removeAllItems()
            for value in values {
                button.addItem(withTitle: descriptor.choiceLabel(value))
                button.lastItem?.representedObject = value
                if !selectable.contains(value) {
                    button.lastItem?.title = "\(value) (valeur actuelle non proposée)"
                    button.lastItem?.isEnabled = false
                }
            }
        }
        button.menu?.autoenablesItems = false
        button.font = .systemFont(ofSize: fontSize)
        button.menu?.font = .systemFont(ofSize: fontSize)
        button.select(button.itemArray.first { $0.representedObject as? String == selection })
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(descriptor.label)
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: max(30, fontSize + 12))
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }

        @objc func select(_ sender: NSPopUpButton) {
            guard let item = sender.selectedItem, item.isEnabled,
                  let value = item.representedObject as? String else { return }
            selection.wrappedValue = value
        }
    }
}
