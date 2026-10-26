import AppKit
import Foundation
import Testing
@testable import RoadieDaemon

/// Audit V15 des sessions 087 à 091.
struct AuditV15LanceurTests {
    /// F1 : la copie simulée de la sélection remet tout le presse-papiers, image comprise.
    @Test func pasteboardSnapshotRestoresEveryRepresentation() {
        let board = NSPasteboard(name: NSPasteboard.Name("roadie-audit-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let image = Data([0x89, 0x50, 0x4E, 0x47])
        let item = NSPasteboardItem()
        item.setData(image, forType: .png)
        item.setString("légende", forType: .string)
        board.clearContents()
        board.writeObjects([item])
        let snapshot = PasteboardSnapshot(board)
        board.clearContents()
        board.setString("texte copié par ⌘C", forType: .string)
        snapshot.restore(to: board)
        #expect(board.data(forType: .png) == image)
        #expect(board.string(forType: .string) == "légende")
        // Presse-papiers vide au départ : il reste vide.
        board.clearContents()
        let empty = PasteboardSnapshot(board)
        board.setString("x", forType: .string)
        empty.restore(to: board)
        #expect(board.pasteboardItems?.isEmpty ?? true)
    }
}
