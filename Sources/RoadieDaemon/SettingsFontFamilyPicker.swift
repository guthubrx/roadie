import AppKit
import RoadieCore
import SwiftUI

/// Le menu natif respecte la taille des paramètres et garde la valeur brute d'une famille absente.
struct SettingsFontFamilyPicker: NSViewRepresentable {
    let fontSize: Double
    @Binding var selection: String
    var inheritedLabel: String? = nil
    var label: String = tr("Famille de police", "Font family")
    @Environment(\.isEnabled) private var isEnabled

    // Énumération AppKit une fois au démarrage de ce menu ; tri O(f log f), f = familles installées.
    private static let installedFamilies = NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }

    func makeNSView(context: Context) -> SettingsPopUpButton {
        let button = SettingsPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .large
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        return button
    }

    func updateNSView(_ button: SettingsPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        var values = (inheritedLabel == nil ? ["system"] : ["", "system"]) + Self.installedFamilies
        let isMissing = !values.contains(selection)
        if isMissing { values.append(selection) }
        // O(f) : ne pas reconstruire le menu à chaque frappe dans un autre réglage.
        if button.itemArray.compactMap({ $0.representedObject as? String }) != values {
            button.removeAllItems()
            for value in values {
                let title = value.isEmpty ? (inheritedLabel ?? value) : (value == "system" ? tr("Police système", "System font") : value)
                button.addItem(withTitle: title)
                button.lastItem?.representedObject = value
            }
            if isMissing {
                button.lastItem?.title = (selection.isEmpty ? tr("Famille vide", "Empty family") : selection) + tr(" — absente, secours système", " — missing, system fallback")
                button.lastItem?.isEnabled = false
            }
        }
        button.menu?.autoenablesItems = false
        button.font = .systemFont(ofSize: fontSize)
        button.menu?.font = .systemFont(ofSize: fontSize)
        button.select(button.itemArray.first { $0.representedObject as? String == selection })
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(label)
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SettingsPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }

        @objc func select(_ sender: NSPopUpButton) {
            guard let item = sender.selectedItem, item.isEnabled,
                  let family = item.representedObject as? String else { return }
            selection.wrappedValue = family
        }
    }
}
