import Foundation
import CoreGraphics
import UniformTypeIdentifiers

// SPEC-014 T050 (US3) — Payload de drag-drop pour les chips de fenêtre.
// Codable + Transferable : SwiftUI macOS 14 gère sérialisation pasteboard.
// Le sourceStageID permet à la cible (StageCard) d'ignorer les drops same-stage (FR-020).

import SwiftUI

struct WindowDragData: Codable, Transferable, Equatable {
    let wid: CGWindowID
    let sourceStageID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .windowDragRoadie)
    }
}

extension UTType {
    /// UTType custom pour le drag de chip — évite de polluer le pasteboard global.
    static let windowDragRoadie = UTType(exportedAs: "com.roadie.window-drag")
}
