import ApplicationServices
import CoreGraphics

public struct PermissionSnapshot: Equatable, Codable, Sendable {
    public var accessibilityTrusted: Bool
    /// Permission Screen Recording du processus (vignettes du rail). Absente des anciens
    /// fichiers JSON : décodée à false.
    public var screenRecordingGranted: Bool

    public init(accessibilityTrusted: Bool, screenRecordingGranted: Bool = false) {
        self.accessibilityTrusted = accessibilityTrusted
        self.screenRecordingGranted = screenRecordingGranted
    }

    enum CodingKeys: String, CodingKey {
        case accessibilityTrusted, screenRecordingGranted
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.accessibilityTrusted = try c.decode(Bool.self, forKey: .accessibilityTrusted)
        self.screenRecordingGranted = try c.decodeIfPresent(Bool.self, forKey: .screenRecordingGranted) ?? false
    }
}

public enum AXPermissions {
    public static func snapshot(prompt: Bool = false) -> PermissionSnapshot {
        let options = [
            "AXTrustedCheckOptionPrompt": prompt
        ] as CFDictionary
        return PermissionSnapshot(
            accessibilityTrusted: AXIsProcessTrustedWithOptions(options),
            // Preflight : lecture seule, n'ouvre jamais la demande système.
            screenRecordingGranted: CGPreflightScreenCaptureAccess()
        )
    }
}
