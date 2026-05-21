import Foundation
import Testing
import RoadieDaemon

/// Invariants sur la liste des composants SPEC-011. Le but est de detecter
/// toute regression : si quelqu'un ajoute un composant a roadied/main.swift,
/// il doit aussi l'ajouter ici, ce qui force la mise a jour de :
/// - Scripts/start-modular (qui liste les composants a lancer)
/// - Quickstart documentation
/// - ComponentLockFile.registry() (qui scanne ~/.roadies/*.pid)
@Suite
struct ComponentSubcommandTests {
    /// Liste des noms de composants stables au sens du PID file et de la
    /// sous-commande `roadied <name>`. Source de verite SPEC-011.
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
    func canonicalNamesAreLowerKebabAndUnique() {
        let names = Self.canonicalComponentNames
        let set = Set(names)
        #expect(names.count == set.count, "duplicate name in canonical list")
        for name in names {
            #expect(!name.isEmpty)
            #expect(name == name.lowercased(), "expected lowercase kebab-case, got \(name)")
            #expect(!name.contains("_"), "use kebab-case (-), not snake_case (_)")
            #expect(!name.contains(" "), "no spaces allowed in component name")
        }
    }

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
