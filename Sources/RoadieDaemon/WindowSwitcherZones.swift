import Foundation
import RoadieAX
import RoadieCore

/// Zone montrée par le sélecteur (session 136) : la zone et l'entrée de sa fenêtre réelle.
struct SwitcherZone: Equatable {
    let record: ZoneRecord
    let window: WindowSwitcherEntry
}

/// Profils `zones` du sélecteur (session 136) : chaque zone devient une entrée comme une fenêtre (même regroupement par
/// bureau et stage, même navigation), avec un identifiant propre, puisqu'une fenêtre peut porter plusieurs zones. Le
/// texte de la zone tient lieu de titre ; l'ordre de l'historique tient lieu de récence.
enum WindowSwitcherZones {
    /// Identifiants des entrées de zones, hors de la plage des fenêtres de macOS.
    static let firstID: UInt32 = 0xF000_0000

    struct Built: Equatable {
        var entries: [WindowSwitcherEntry] = []
        var zones: [WindowID: SwitcherZone] = [:]
        /// Plus récente d'abord : l'ordre de l'historique.
        var recentIDs: [WindowID] = []
    }

    /// Une entrée par zone dont la fenêtre existe encore. O(z + w).
    static func build(records: [ZoneRecord], windows: [WindowSwitcherEntry]) -> Built {
        let byID = Dictionary(windows.map { ($0.id.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
        var built = Built()
        for (offset, record) in records.enumerated() {
            guard let window = byID[record.windowID] else { continue }
            var snapshot = window.window
            snapshot.id = WindowID(rawValue: firstID + UInt32(offset))
            snapshot.title = record.title
            let entry = WindowSwitcherEntry(window: snapshot, scope: window.scope, displayName: window.displayName,
                                            desktopName: window.desktopName, stageName: window.stageName,
                                            isMinimized: window.isMinimized, isHidden: window.isHidden,
                                            isFullscreen: window.isFullscreen, isAvailable: window.isAvailable,
                                            visibilityKnown: window.visibilityKnown)
            built.entries.append(entry)
            built.zones[entry.id] = SwitcherZone(record: record, window: window)
            built.recentIDs.append(entry.id)
        }
        return built
    }

    /// Fenêtre au premier plan vue comme la zone la plus récente qu'elle porte : la sélection initiale passe alors à
    /// la zone d'avant, comme ⌘Tab passe à la fenêtre d'avant. O(z).
    static func context(_ context: WindowSwitcherContext, built: Built) -> WindowSwitcherContext {
        var mapped = context
        mapped.focusedWindowID = built.recentIDs.first { built.zones[$0]?.window.id == context.focusedWindowID }
        return mapped
    }
}
