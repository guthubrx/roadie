import CoreGraphics

// SPEC-014 T021 — View models immuables pour stages et fenêtres.

/// Représentation d'un stage pour SwiftUI.
public struct StageVM: Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let isActive: Bool
    public let windowIDs: [CGWindowID]
    public let desktopID: Int

    public init(id: String, displayName: String, isActive: Bool,
                windowIDs: [CGWindowID], desktopID: Int) {
        self.id = id
        self.displayName = displayName
        self.isActive = isActive
        self.windowIDs = windowIDs
        self.desktopID = desktopID
    }
}

/// Représentation d'une fenêtre pour SwiftUI.
public struct WindowVM: Identifiable, Equatable {
    public let id: CGWindowID
    public let pid: Int32
    public let bundleID: String
    public let title: String
    public let appName: String
    public let isFloating: Bool
    public let isFocused: Bool

    public init(id: CGWindowID, pid: Int32, bundleID: String, title: String,
                appName: String, isFloating: Bool, isFocused: Bool = false) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.title = title
        self.appName = appName
        self.isFloating = isFloating
        self.isFocused = isFocused
    }
}
