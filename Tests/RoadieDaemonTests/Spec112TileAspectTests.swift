import AppKit
import Foundation
import Testing
@testable import RoadieDaemon

/// Forme des tuiles d'une grille de workflow (`imageaspect`, session 112).
struct Spec112TileAspectTests {
    @Test func alfredMenuOrderGivesSquarePortraitLandscape() {
        #expect(AlfredGridView.imageAspect(nil) == 1)
        #expect(AlfredGridView.imageAspect(0) == 1)
        #expect(AlfredGridView.imageAspect(1) == 2.0 / 3)
        #expect(AlfredGridView.imageAspect(2) == 3.0 / 2)
        #expect(AlfredGridView.imageAspect(7) == 1)
    }

    @Test func tileWidthStaysAndImageHeightFollowsTheAspect() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 900)
        func tile(_ aspect: CGFloat) throws -> CGRect {
            try #require(SearchBarLayout.makeGrid(bounds: bounds, count: 6, columns: 3, selected: 0, label: 20, footer: false,
                                                  aspect: aspect).suggestionRows.first)
        }
        let square = try tile(1), portrait = try tile(2.0 / 3), landscape = try tile(3.0 / 2)
        #expect(square.width == portrait.width && square.width == landscape.width)
        #expect(square.height - 20 == square.width)
        #expect(abs((portrait.height - 20) - square.width * 1.5) <= 1)
        #expect(abs((landscape.height - 20) - square.width / 1.5) <= 1)
    }
}
