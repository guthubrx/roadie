import Foundation
import TOMLKit

/// Configuration pour le framework FX, parsée depuis section `[fx]` de `roadies.toml`.
public struct FXConfig: Codable, Sendable {
    public var dylibDir: String
    public var osaxSocketPath: String
    public var checksumFile: String?
    public var disableLoading: Bool

    public init(dylibDir: String = "~/.local/lib/roadie/",
                osaxSocketPath: String = "/var/tmp/roadied-osax.sock",
                checksumFile: String? = nil,
                disableLoading: Bool = false) {
        self.dylibDir = dylibDir
        self.osaxSocketPath = osaxSocketPath
        self.checksumFile = checksumFile
        self.disableLoading = disableLoading
    }

    enum CodingKeys: String, CodingKey {
        case dylibDir = "dylib_dir"
        case osaxSocketPath = "osax_socket_path"
        case checksumFile = "checksum_file"
        case disableLoading = "disable_loading"
    }

    /// Charge la sous-section `[fx]` depuis un TOML complet, retourne défaut si absent.
    /// Lecture directe (pas de re-encode TOML) pour rester robuste face aux limitations TOMLKit.
    public static func load(fromTOML data: String) -> FXConfig {
        guard let root = try? TOMLTable(string: data) else { return FXConfig() }
        guard let fxValue = root["fx"], let fxSection = fxValue.table else {
            return FXConfig()
        }
        var cfg = FXConfig()
        if let v = fxSection["dylib_dir"]?.string { cfg.dylibDir = v }
        if let v = fxSection["osax_socket_path"]?.string { cfg.osaxSocketPath = v }
        if let v = fxSection["checksum_file"]?.string { cfg.checksumFile = v }
        if let v = fxSection["disable_loading"]?.bool { cfg.disableLoading = v }
        return cfg
    }

    /// Expand `~` → home directory.
    public var expandedDylibDir: String {
        (dylibDir as NSString).expandingTildeInPath
    }
}
