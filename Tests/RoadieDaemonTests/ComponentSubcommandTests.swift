import Foundation
import Testing
import RoadieDaemon

/// Tests du verrou PID par composant (ComponentLockFile) avec les noms de composants
/// utilises par les sous-commandes `roadied <composant>` (SPEC-011).
///
/// La liste ci-dessous est un jeu de noms de test. Elle n'est pas lue depuis le
/// code de production : les noms reels sont dans Sources/roadied/main.swift, qui est
/// un executable et ne peut pas etre importe par les tests.
@Suite
struct ComponentSubcommandTests {
    static let canonicalComponentNames: [String] = [
        "tiler",
        "rail",
        "border",
        "focus-mouse",
        "titlebar-menu",
        "target-mode",
        "restore-safety"
    ]

    @Test
    func lockFilePathFollowsPattern() {
        for name in Self.canonicalComponentNames {
            let path = ComponentLockFile.pidFilePath(for: name)
            #expect(path.hasSuffix("/\(name).pid"), "expected suffix /\(name).pid, got \(path)")
        }
    }

    @Test
    func lockAcquireReleaseRoundTripsForEachComponent() throws {
        // Suffixe UUID pour isoler chaque run de test et eviter une collision si
        // un veritable daemon tourne dans la session de dev (en mode test, le
        // pidDirectory est dans NSTemporaryDirectory, donc isole de toute facon).
        for name in Self.canonicalComponentNames {
            let isolated = "\(name)-test-\(UUID().uuidString.prefix(8))"
            let lock = ComponentLockFile(component: isolated)
            try lock.acquire()
            lock.release()
        }
    }
}
