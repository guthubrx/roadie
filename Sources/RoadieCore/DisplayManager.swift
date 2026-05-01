import Foundation
import Cocoa

/// V1 : single-monitor strict (NSScreen.main).
/// L'API permet l'extension multi-monitor V2 sans casser le code appelant.
@MainActor
public final class DisplayManager {
    public init() {}

    public var mainScreen: NSScreen? { NSScreen.main }

    /// Rect de la zone utile (sous la barre de menu, sans le Dock).
    public var workArea: CGRect {
        guard let screen = mainScreen else { return .zero }
        return convertedToTopLeft(screen.visibleFrame, fullScreen: screen.frame)
    }

    /// Convertit un rect de NSScreen (origine bottom-left) vers AX (origine top-left).
    private func convertedToTopLeft(_ rect: CGRect, fullScreen: CGRect) -> CGRect {
        let y = fullScreen.height - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: y, width: rect.width, height: rect.height)
    }

    /// Workspace courant (V1 = singleton "main").
    public func currentWorkspaceID() -> WorkspaceID { .main }
}
