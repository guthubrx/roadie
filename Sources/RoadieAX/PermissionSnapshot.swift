import ApplicationServices

public struct PermissionSnapshot: Equatable, Codable, Sendable {
    public var accessibilityTrusted: Bool

    public init(accessibilityTrusted: Bool) {
        self.accessibilityTrusted = accessibilityTrusted
    }
}

public enum AXPermissions {
    public static func snapshot(prompt: Bool = false) -> PermissionSnapshot {
        let options = [
            "AXTrustedCheckOptionPrompt": prompt
        ] as CFDictionary
        return PermissionSnapshot(
            accessibilityTrusted: AXIsProcessTrustedWithOptions(options)
        )
    }
}
