import AppKit
import SwiftUI

/// Segments égaux, sans couper les mots. Repli en deux rangées puis une colonne.
/// O(n), n = nombre d'onglets (quatre dans les profils).
struct SettingsTabsGeometry {
    let columns: Int
    let cellHeight: CGFloat
    let width: CGFloat
    let count: Int
    let spacing: CGFloat = 2

    init(width: CGFloat, titles: [String], fontSize: Double) {
        let available = max(1, width)
        self.width = available
        count = titles.count
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let minimum = titles.map { ($0 as NSString).size(withAttributes: [.font: font]).width + 20 }.max() ?? 1
        columns = [max(1, count), 2, 1].first { CGFloat($0) * minimum + CGFloat($0 - 1) * 2 <= available } ?? 1
        cellHeight = max(34, ceil(font.ascender - font.descender + font.leading) + 14)
    }

    var height: CGFloat { CGFloat((count + columns - 1) / columns) * (cellHeight + spacing) - spacing }

    func frame(at index: Int) -> CGRect {
        let cellWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        return CGRect(x: CGFloat(index % columns) * (cellWidth + spacing),
                      y: CGFloat(index / columns) * (cellHeight + spacing), width: cellWidth, height: cellHeight)
    }
}

private struct SettingsTabsLayout: Layout {
    let titles: [String]
    let fontSize: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let geometry = SettingsTabsGeometry(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 640,
                                            titles: titles, fontSize: fontSize)
        return CGSize(width: geometry.width, height: geometry.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let geometry = SettingsTabsGeometry(width: bounds.width, titles: titles, fontSize: fontSize)
        for (index, view) in subviews.enumerated() {
            let frame = geometry.frame(at: index)
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       anchor: .topLeading, proposal: .init(width: frame.width, height: frame.height))
        }
    }
}

struct SettingsTabs: View {
    let values: [String]
    @Binding var selection: String
    let fontSize: Double

    var body: some View {
        SettingsTabsLayout(titles: values, fontSize: fontSize) {
            ForEach(values, id: \.self) { value in
                Button { selection = value } label: {
                    Text(value)
                        .font(.system(size: fontSize, weight: selection == value ? .semibold : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(selection == value ? Color.white : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 5).fill(selection == value ? Color.accentColor : Color(nsColor: .windowBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
                .help("Afficher les réglages : " + value)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}
