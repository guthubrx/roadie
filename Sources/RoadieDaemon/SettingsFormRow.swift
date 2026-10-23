import AppKit
import SwiftUI
import RoadieCore

/// Colonnes identiques pour une largeur et une police données. O(1).
struct SettingsFormGeometry {
    let width: CGFloat
    let labelWidth: CGFloat
    let controlWidth: CGFloat
    let stacked: Bool
    let gap: CGFloat = 14
    let accessoryWidth: CGFloat = 26

    init(width: CGFloat, fontSize: Double) {
        self.width = max(1, width)
        let label = min(max(196, CGFloat(fontSize) * 18), self.width * 0.46)
        let control = self.width - label - 28 - 26
        stacked = control < max(168, CGFloat(fontSize) * 8)
        labelWidth = stacked ? max(1, self.width - 40) : label
        controlWidth = stacked ? self.width : max(1, control)
    }

    func frames(labelHeight: CGFloat, controlHeight: CGFloat) -> [CGRect] {
        let head = max(labelHeight, accessoryWidth)
        if stacked {
            return [
                CGRect(x: 0, y: 0, width: labelWidth, height: head),
                CGRect(x: 0, y: head + 8, width: controlWidth, height: controlHeight),
                CGRect(x: width - accessoryWidth, y: (head - accessoryWidth) / 2, width: accessoryWidth, height: accessoryWidth)
            ]
        }
        let height = max(head, controlHeight)
        return [
            CGRect(x: 0, y: (height - labelHeight) / 2, width: labelWidth, height: labelHeight),
            CGRect(x: labelWidth + gap, y: (height - controlHeight) / 2, width: controlWidth, height: controlHeight),
            CGRect(x: width - accessoryWidth, y: (height - accessoryWidth) / 2, width: accessoryWidth, height: accessoryWidth)
        ]
    }
}

/// Mesurer avant de placer préserve les libellés longs et le focus lors du redimensionnement.
private struct SettingsFormLayout: Layout {
    let fontSize: Double

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let geometry = SettingsFormGeometry(width: width, fontSize: fontSize)
        let label = subviews[0].sizeThatFits(.init(width: geometry.labelWidth, height: nil))
        let control = subviews[1].sizeThatFits(.init(width: geometry.controlWidth, height: nil))
        return geometry.frames(labelHeight: label.height, controlHeight: control.height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 640
        let rows = frames(width: max(1, width), subviews: subviews)
        return CGSize(width: max(1, width), height: ceil(rows.map(\.maxY).max() ?? 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                       proposal: .init(width: frame.width, height: frame.height))
        }
    }
}

struct SettingsFormRow<Content: View>: View {
    let title: String
    let help: String
    let fonts: InterfaceConfig
    let reset: (() -> Void)?
    let content: Content

    init(_ title: String, help: String = "", fonts: InterfaceConfig, reset: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.help = help
        self.fonts = fonts
        self.reset = reset
        self.content = content()
    }

    var body: some View {
        SettingsFormLayout(fontSize: fonts.settingsTextFontSize) {
            SettingsFieldLabel(title: title, help: help, fonts: fonts)
            content
                .frame(maxWidth: .infinity, minHeight: max(30, fonts.settingsTextFontSize + 10), alignment: .leading)
                .accessibilityLabel(title)
            ZStack {
                if let reset { SettingsResetButton(action: reset) }
                else { Color.clear.accessibilityHidden(true) }
            }.frame(width: 26, height: 26)
        }
        .padding(.vertical, 8)
    }
}

struct SettingsFieldLabel: View {
    let title: String
    var help = ""
    let fonts: InterfaceConfig
    var prominent = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title)
                .font(.system(size: fonts.settingsTextFontSize, weight: prominent ? .semibold : .regular))
                .fixedSize(horizontal: false, vertical: true)
            if !help.isEmpty { SettingsHelpButton(title: title, text: help, fontSize: fonts.settingsHelpFontSize).padding(.top, 2) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsResetButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "arrow.counterclockwise").font(.system(size: 14)) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .help("Rétablir la valeur par défaut")
            .accessibilityLabel("Rétablir la valeur par défaut")
    }
}

/// Le contenu ne reçoit pas d'indentation : ses champs restent dans la grille commune.
struct SettingsDisclosureSection<Content: View>: View {
    let title: String
    let content: Content
    @State private var expanded = false

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 11, weight: .semibold)).frame(width: 14)
                    Text(title).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Déplié" : "Replié")
            if expanded { content }
        }.padding(.vertical, 6)
    }
}

/// La hauteur borne le panneau, jamais le texte : le contenu reste défilable. O(t).
@MainActor
struct SettingsHelpGeometry {
    let width: CGFloat
    let height: CGFloat

    init(title: String, text: String, fontSize: Double, screen: CGSize) {
        width = max(180, min(420, screen.width - 48))
        let font = NSFont.systemFont(ofSize: fontSize)
        let measured = (title + "\n\n" + text as NSString).boundingRect(
            with: CGSize(width: width - 32, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        height = min(max(100, ceil(measured.height) + 52), max(100, min(480, screen.height - 100)))
    }
}

struct SettingsHelpContent: View {
    let title: String
    let text: String
    let fontSize: Double

    var body: some View {
        let size = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        let geometry = SettingsHelpGeometry(title: title, text: text, fontSize: fontSize, screen: size)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).fontWeight(.semibold)
                Text(text).textSelection(.enabled)
            }
            .font(.system(size: fontSize))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(width: geometry.width, height: geometry.height)
    }
}

struct SettingsHelpButton: View {
    let title: String
    let text: String
    let fontSize: Double
    @State private var opened = false

    var body: some View {
        Button { opened.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: min(18, max(13, fontSize)))).foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aide : " + title)
        .popover(isPresented: $opened) { SettingsHelpContent(title: title, text: text, fontSize: fontSize) }
    }
}

/// Le bezel arrondi AppKit est limité à 28 pt, même avec une police de 32 pt.
/// Garder le menu natif avec une surface dont la hauteur suit réellement la police.
final class SettingsPopUpButton: NSPopUpButton {
    override init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame, pullsDown: flag)
        isBordered = false
        updateSettingsSurface()
    }
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        let font = font ?? NSFont.systemFont(ofSize: 16)
        return NSSize(width: base.width, height: max(30, ceil(font.ascender - font.descender + font.leading) + 12))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSettingsSurface()
    }
}

extension NSButton {
    func updateSettingsSurface() {
        wantsLayer = true
        layer?.cornerRadius = 6
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
        layer?.borderWidth = 0.5
    }
}
