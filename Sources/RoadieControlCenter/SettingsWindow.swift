import SwiftUI
import RoadieCore

public struct SettingsWindowModel: Equatable, Sendable {
    public var configPath: String
    public var controlCenterEnabled: Bool
    public var safeReloadEnabled: Bool
    public var restoreSafetyEnabled: Bool
    public var transientWindowsEnabled: Bool
    public var layoutPersistenceVersion: Int
    public var widthPresets: [Double]

    public init(config: RoadieConfig = RoadieConfig(), configPath: String = RoadieConfigLoader.defaultConfigPath()) {
        self.configPath = configPath
        self.controlCenterEnabled = config.controlCenter.enabled
        self.safeReloadEnabled = config.configReload.keepPreviousOnError
        self.restoreSafetyEnabled = config.restoreSafety.enabled
        self.transientWindowsEnabled = config.transientWindows.enabled
        self.layoutPersistenceVersion = config.layoutPersistence.version
        self.widthPresets = config.widthAdjustment.presets
    }
}

public struct SettingsWindowView: View {
    public let model: SettingsWindowModel

    public init(model: SettingsWindowModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Text("Config: \(model.configPath)")
            Toggle("Control Center", isOn: .constant(model.controlCenterEnabled))
            Toggle("Safe reload", isOn: .constant(model.safeReloadEnabled))
            Toggle("Restore safety", isOn: .constant(model.restoreSafetyEnabled))
            Toggle("Transient windows", isOn: .constant(model.transientWindowsEnabled))
            Text("Layout persistence v\(model.layoutPersistenceVersion)")
            Text("Width presets: \(model.widthPresets.map { String($0) }.joined(separator: ", "))")
        }
        .padding()
        .frame(minWidth: 420)
    }
}
