import Foundation

/// Détection unique « le code tourne sous XCTest / swift test » (SPEC-016 T222).
/// Sert à isoler les chemins d'état et à couper les observateurs système pendant les tests.
enum TestEnvironment {
    static let isRunningTests: Bool = {
        let name = ProcessInfo.processInfo.processName.lowercased()
        return name.contains("test")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || Bundle.main.bundlePath.contains(".xctest")
            || CommandLine.arguments.contains { $0.contains(".xctest") || $0.contains("PackageTests") }
    }()
}
