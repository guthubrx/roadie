import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

struct Spec110CalcCalculatorTests {
    @Test func returnOnlyCopiesByDefault() {
        #expect(!TargetModeConfig().calcOpensCalculator)
        #expect(LauncherCalculator.returnHint(opensCalculator: false) == "Retour copie")
    }

    @Test func fileTurnsTheCalculatorOn() throws {
        let path = tempPath("spec110") + ".toml"
        try """
        [experimental.target_mode]
        calc_opens_calculator = true
        """.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(try RoadieConfigLoader.load(from: path).experimental.targetMode.calcOpensCalculator)
        #expect(RoadieConfigLoader.validate(path: path).items.allSatisfy { !$0.path.contains("calc_") })
        #expect(LauncherCalculator.returnHint(opensCalculator: true) == "Retour copie et ouvre Calculette")
    }

    @Test func calculatorIsFoundByItsBundleIdentifier() {
        let calculator = LauncherApp(bundleID: "com.apple.calculator", path: "/System/Applications/Calculator.app",
                                     name: "Calculette", alternateNames: ["Calculator"])
        let notes = LauncherApp(bundleID: "com.apple.Notes", path: "/System/Applications/Notes.app", name: "Notes", alternateNames: [])
        #expect(LauncherCalculator.calculator(in: [notes, calculator]) == calculator)
        #expect(LauncherCalculator.calculator(in: [notes]) == nil)
    }

    @Test func settingSitsInSearchAndIsOffByDefault() throws {
        let entry = try #require(SettingsCatalog.all.first { $0.tablePath == "experimental.target_mode" && $0.key == "calc_opens_calculator" })
        #expect(entry.category == .recherche)
        #expect(entry.defaultValue == .bool(false))
    }
}
