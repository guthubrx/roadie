import AppKit
import Foundation

// SPEC-014 T020 — State holder observable pour le rail.
// @Observable (macOS 14+) : pas besoin de @Published, SwiftUI observe automatiquement.

/// Raison de la perte de connexion vers le daemon.
public enum ConnectionState: Equatable {
    case connected
    case disconnected
    case offline(reason: String)
    case reconnecting(attempt: Int)
}

/// Disposition du rail : un panel par écran ou un panel global.
public enum DisplayMode: String {
    case perDisplay = "per_display"
    case global
}

/// Informations sur un écran physique.
public struct ScreenInfo: Identifiable, Equatable {
    public let id: CGDirectDisplayID
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let isMain: Bool
    public let displayUUID: String

    public init(id: CGDirectDisplayID, frame: CGRect, visibleFrame: CGRect,
                isMain: Bool, displayUUID: String) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
        self.displayUUID = displayUUID
    }
}

/// Vignette capturée pour une fenêtre.
public struct ThumbnailVM: Equatable {
    public let wid: CGWindowID
    public let pngData: Data
    public let size: CGSize
    public let degraded: Bool
    public let capturedAt: Date

    public init(wid: CGWindowID, pngData: Data, size: CGSize,
                degraded: Bool, capturedAt: Date = Date()) {
        self.wid = wid
        self.pngData = pngData
        self.size = size
        self.degraded = degraded
        self.capturedAt = capturedAt
    }
}

/// State holder global du rail. Observé par SwiftUI via @Observable.
@MainActor
@Observable
public final class RailState {
    public var currentDesktopID: Int = 1
    /// Liste plate des stages — TOUS displays confondus. Conservé pour compat
    /// (tests, IPC fallback), mais le rail utilise désormais `stagesByDisplay` pour
    /// que chaque panel affiche STRICTEMENT les stages de son écran.
    public var stages: [StageVM] = []
    /// SPEC-019 — stages indexées par UUID de display. Chaque panel rail lit
    /// `stagesByDisplay[panelDisplayUUID]` pour ne montrer que ses stages.
    public var stagesByDisplay: [String: [StageVM]] = [:]
    public var activeStageID: String = "1"
    public var thumbnails: [CGWindowID: ThumbnailVM] = [:]
    /// SPEC-014 : map wid → métadonnées (pid, bundle, app_name) pour résolution
    /// d'icône via NSRunningApplication. Peuplée via IPC `windows.list`.
    public var windows: [CGWindowID: WindowVM] = [:]
    public var connectionState: ConnectionState = .disconnected
    public var displayMode: DisplayMode = .perDisplay
    public var screens: [ScreenInfo] = []

    public init() {}
}
