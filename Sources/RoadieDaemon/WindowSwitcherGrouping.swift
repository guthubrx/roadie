import CoreGraphics
import RoadieCore

/// Les noms sont des libellés : seuls les identifiants distinguent deux homonymes.
struct SwitcherGroupID: Hashable {
    let display: DisplayID?
    let desktop: DesktopID?
    let stage: StageID?

    init(scope: StageScope?, desktopOnly: Bool = false) {
        display = scope?.displayID
        desktop = scope?.desktopID
        stage = desktopOnly ? nil : scope?.stageID
    }
}

struct SwitcherStageGroup {
    let id: SwitcherGroupID
    let desktopID: SwitcherGroupID
    let title: String
    let desktopTitle: String
    var entries: [WindowSwitcherEntry]
}

struct SwitcherDesktopGroup {
    let id: SwitcherGroupID
    let title: String
    var stages: [SwitcherStageGroup]
    var entries: [WindowSwitcherEntry] { stages.flatMap(\.entries) }
}

/// O(n) : ordre de première apparition, ordre des fenêtres conservé dans chaque stage.
struct WindowSwitcherGroups {
    let desktops: [SwitcherDesktopGroup]
    let stages: [SwitcherStageGroup]

    init(entries: [WindowSwitcherEntry]) {
        var stages: [SwitcherStageGroup] = []
        var stageIndices: [SwitcherGroupID: Int] = [:]
        for entry in entries {
            let id = SwitcherGroupID(scope: entry.scope)
            if let index = stageIndices[id] {
                stages[index].entries.append(entry)
            } else {
                stageIndices[id] = stages.count
                let stageTitle = entry.stageName.isEmpty
                    ? entry.scope.map { "Stage \($0.stageID.rawValue)" } ?? "Autres fenêtres" : entry.stageName
                let desktop = entry.desktopName.isEmpty
                    ? entry.scope.map { "Bureau \($0.desktopID.rawValue)" } ?? "Sans bureau" : entry.desktopName
                stages.append(SwitcherStageGroup(id: id, desktopID: SwitcherGroupID(scope: entry.scope, desktopOnly: true),
                    title: stageTitle, desktopTitle: [desktop, entry.displayName].filter { !$0.isEmpty }.joined(separator: " · "), entries: [entry]))
            }
        }
        self.stages = stages
        var desktops: [SwitcherDesktopGroup] = []
        var desktopIndices: [SwitcherGroupID: Int] = [:]
        for stage in stages {
            if let index = desktopIndices[stage.desktopID] { desktops[index].stages.append(stage) }
            else {
                desktopIndices[stage.desktopID] = desktops.count
                desktops.append(SwitcherDesktopGroup(id: stage.desktopID, title: stage.desktopTitle, stages: [stage]))
            }
        }
        self.desktops = desktops
    }
}

struct SwitcherBrowsingState {
    var desktop: SwitcherGroupID?
    var stage: SwitcherGroupID?

    mutating func reconcile(groups: WindowSwitcherGroups, selectedID: WindowID?) {
        let selected = groups.stages.first { group in group.entries.contains { $0.id == selectedID } }
        if let selected { desktop = selected.desktopID; stage = selected.id }
        else {
            if !groups.desktops.contains(where: { $0.id == desktop }) { desktop = groups.desktops.first?.id }
            if !groups.stages.contains(where: { $0.id == stage && $0.desktopID == desktop }) {
                stage = groups.desktops.first { $0.id == desktop }?.stages.first?.id
            }
        }
    }
}

struct SwitcherPlacedCard {
    let entry: WindowSwitcherEntry
    let frame: CGRect
}

struct SwitcherGroupHeading {
    let text: String
    let frame: CGRect
    let isDesktop: Bool
}

struct WindowSwitcherGroupedLayout {
    var cards: [SwitcherPlacedCard] = []
    var headings: [SwitcherGroupHeading] = []
    var surfaces: [CGRect] = []
    var size: CGSize = .zero
}

/// Géométrie commune des cinq présentations ; aucune acquisition, mutation ou vue.
enum WindowSwitcherGroupedGeometry {
    static func layout(entries: [WindowSwitcherEntry], appearance: WindowSwitcherAppearance,
                       width: CGFloat, browsing: SwitcherBrowsingState) -> WindowSwitcherGroupedLayout {
        let groups = WindowSwitcherGroups(entries: entries)
        let width = max(1, width)
        var result = WindowSwitcherGroupedLayout(size: CGSize(width: width, height: 0))
        let gap: CGFloat = 12
        let headingHeight = max(30, appearance.fontSize * 1.4 + 10)

        func grid(_ entries: [WindowSwitcherEntry], x: CGFloat, y: CGFloat, width: CGFloat,
                  spatial: Bool = false) -> CGFloat {
            if spatial, appearance.style == .thumbnails,
               let frames = spatialFrames(entries: entries, width: width, fontSize: appearance.fontSize) {
                result.cards += zip(entries, frames).map { SwitcherPlacedCard(entry: $0, frame: $1.offsetBy(dx: x, dy: y)) }
                return frames.map(\.maxY).max() ?? 0
            }
            let layout = WindowSwitcherGrid.layout(count: entries.count, appearance: appearance, available: width)
            result.cards += zip(entries, layout.frames).map { SwitcherPlacedCard(entry: $0, frame: $1.offsetBy(dx: x, dy: y)) }
            return layout.contentSize.height
        }

        func stage(_ group: SwitcherStageGroup, x: CGFloat, y: CGFloat, width: CGFloat,
                   spatial: Bool = false) -> CGFloat {
            let inset: CGFloat = 10
            result.headings.append(SwitcherGroupHeading(text: "\(group.title) · \(group.entries.count)",
                frame: CGRect(x: x + inset, y: y + 4, width: max(1, width - 2 * inset), height: headingHeight), isDesktop: false))
            let height = headingHeight + 10 + grid(group.entries, x: x + inset, y: y + headingHeight + 4,
                                                  width: max(1, width - 2 * inset), spatial: spatial)
            result.surfaces.append(CGRect(x: x, y: y, width: width, height: height))
            return height
        }

        func sections(_ stages: [SwitcherStageGroup], x: CGFloat = 0, y: CGFloat = 0, width: CGFloat,
                      spatial: Bool = false) -> CGFloat {
            var top = y
            for group in stages { top += stage(group, x: x, y: top, width: width, spatial: spatial) + gap }
            return max(0, top - y - (stages.isEmpty ? 0 : gap))
        }

        switch appearance.presentation {
        case .classic:
            result.size.height = grid(entries, x: 0, y: 0, width: width)
            let occupied = result.cards.map(\.frame.maxX).max() ?? width
            let inset = max(0, (width - occupied) / 2)
            result.cards = result.cards.map { SwitcherPlacedCard(entry: $0.entry, frame: $0.frame.offsetBy(dx: inset, dy: 0)) }
        case .hierarchy:
            let group = groups.stages.first { $0.id == browsing.stage } ?? groups.stages.first
            if let group { result.size.height = sections([group], width: width) }
        case .desktopTabs:
            let desktop = groups.desktops.first { $0.id == browsing.desktop } ?? groups.desktops.first
            result.size.height = sections(desktop?.stages ?? [], width: width)
        case .stageColumns:
            let stages = (groups.desktops.first { $0.id == browsing.desktop } ?? groups.desktops.first)?.stages ?? []
            let columns = max(1, min(stages.count, Int((width + gap) / max(220, appearance.fontSize * 10))))
            let columnWidth = (width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            var top: CGFloat = 0
            for start in stride(from: 0, to: stages.count, by: columns) {
                var rowHeight: CGFloat = 0
                for index in start..<min(stages.count, start + columns) {
                    rowHeight = max(rowHeight, stage(stages[index], x: CGFloat(index - start) * (columnWidth + gap),
                                                     y: top, width: columnWidth))
                }
                top += rowHeight + gap
            }
            result.size.height = max(0, top - (stages.isEmpty ? 0 : gap))
        case .sections:
            var top: CGFloat = 0
            for desktop in groups.desktops {
                result.headings.append(SwitcherGroupHeading(text: "\(desktop.title) · \(desktop.entries.count)",
                    frame: CGRect(x: 0, y: top, width: width, height: headingHeight), isDesktop: true))
                top += headingHeight + 4
                top += sections(desktop.stages, y: top, width: width) + gap
            }
            result.size.height = max(0, top - (groups.desktops.isEmpty ? 0 : gap))
        case .overview:
            let columns = max(1, min(groups.desktops.count, Int((width + gap) / max(330, appearance.fontSize * 13))))
            let columnWidth = (width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            var top: CGFloat = 0
            for start in stride(from: 0, to: groups.desktops.count, by: columns) {
                var rowHeight: CGFloat = 0
                for index in start..<min(groups.desktops.count, start + columns) {
                    let desktop = groups.desktops[index], x = CGFloat(index - start) * (columnWidth + gap)
                    result.headings.append(SwitcherGroupHeading(text: "\(desktop.title) · \(desktop.entries.count)",
                        frame: CGRect(x: x, y: top, width: columnWidth, height: headingHeight), isDesktop: true))
                    let height = headingHeight + 4 + sections(desktop.stages, x: x, y: top + headingHeight + 4,
                                                            width: columnWidth, spatial: true)
                    rowHeight = max(rowHeight, height)
                }
                top += rowHeight + gap
            }
            result.size.height = max(0, top - (groups.desktops.isEmpty ? 0 : gap))
        }
        return result
    }

    /// Réduit un plan de fenêtres, sans déformer les proportions. Une géométrie ambiguë
    /// ou trop petite revient à la grille : les titres et les cibles restent utilisables.
    static func spatialFrames(entries: [WindowSwitcherEntry], width: CGFloat, fontSize: CGFloat) -> [CGRect]? {
        // La recherche de chevauchement est bornée à 32 fenêtres par stage.
        guard !entries.isEmpty, entries.count <= 32 else { return nil }
        let frames = entries.map { CGRect(x: $0.window.frame.x, y: $0.window.frame.y,
                                         width: $0.window.frame.width, height: $0.window.frame.height) }
        guard frames.allSatisfy({ !$0.isNull && !$0.isInfinite && $0.width > 0 && $0.height > 0
            && $0.minX.isFinite && $0.minY.isFinite && $0.width.isFinite && $0.height.isFinite }) else { return nil }
        let extent = frames.reduce(CGRect.null) { $0.union($1) }
        let scale = min(width / extent.width, 240 / extent.height)
        let minimumHeight = WindowSwitcherGrid.labelsHeight(fontSize: fontSize) + 40
        let scaled = frames.map { frame in
            CGRect(x: (frame.minX - extent.minX) * scale, y: (frame.minY - extent.minY) * scale,
                   width: frame.width * scale, height: frame.height * scale).insetBy(dx: 3, dy: 3)
        }
        guard scaled.allSatisfy({ $0.width >= max(100, fontSize * 5) && $0.height >= minimumHeight }) else { return nil }
        // Les fenêtres flottantes superposées ne doivent pas créer des cartes inaccessibles.
        for i in scaled.indices {
            for j in scaled.indices where j > i {
                if scaled[i].intersects(scaled[j]) { return nil }
            }
        }
        return scaled
    }
}
