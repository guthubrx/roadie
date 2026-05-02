import Foundation
import CoreGraphics
import RoadieCore

// MARK: - DesktopRegistryError

public enum DesktopRegistryError: Error {
    case saveFailure(String)
    case invalidID(Int)
    /// M2 : desktop introuvable pour un ID donné (updateExpectedFrame, assignWindow).
    case unknownDesktop(Int)
}

// MARK: - DesktopRegistry

/// Actor central de l'état des desktops virtuels (SPEC-011, data-model.md).
/// Source de vérité in-memory ; persistance write-then-rename par desktop (FR-011).
public actor DesktopRegistry {
    private var desktops: [Int: RoadieDesktop] = [:]
    public private(set) var currentID: Int = 1
    public private(set) var recentID: Int? = nil
    public private(set) var count: Int

    private let configDir: URL

    public init(configDir: URL, count: Int = 10) {
        self.configDir = configDir
        self.count = count
        // H2 : créer le répertoire desktops/ dès l'init pour éviter les échecs
        // de saveCurrentID() si appelé avant tout save(_:).
        let desktopsDir = configDir.appendingPathComponent("desktops")
        try? FileManager.default.createDirectory(
            at: desktopsDir, withIntermediateDirectories: true)
    }

    // MARK: - Chargement (FR-012)

    /// Charge tous les desktops depuis `<configDir>/desktops/<id>/state.toml`.
    /// Les desktops absents ou corrompus sont initialisés vierges (FR-013).
    public func load() async {
        let fm = FileManager.default
        for id in 1...count {
            let url = desktopURL(id: id)
            if fm.fileExists(atPath: url.path) {
                do {
                    let toml = try String(contentsOf: url, encoding: .utf8)
                    let desktop = try parseDesktop(from: toml)
                    desktops[id] = desktop
                } catch {
                    // FR-013 : corruption → log + état vierge
                    logWarn("desktop state corrupted, using blank",
                            ["id": String(id), "error": "\(error)"])
                    desktops[id] = .blank(id: id)
                }
            } else {
                desktops[id] = .blank(id: id)
            }
        }
        // Charger le currentID persisté
        let curURL = configDir.appendingPathComponent("desktops/current.txt")
        if let raw = try? String(contentsOf: curURL, encoding: .utf8),
           let savedID = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           (1...count).contains(savedID) {
            currentID = savedID
        }
    }

    // MARK: - Persistance (FR-011)

    /// Persiste un desktop en write-then-rename atomique.
    public func save(_ desktop: RoadieDesktop) throws {
        let dir = configDir.appendingPathComponent("desktops/\(desktop.id)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw DesktopRegistryError.saveFailure("mkdir failed: \(error)")
        }
        let toml = serialize(desktop)
        let target = dir.appendingPathComponent("state.toml")
        let tmp = dir.appendingPathComponent("state.toml.tmp")
        do {
            try toml.write(to: tmp, atomically: false, encoding: .utf8)
            // rename(2) POSIX : atomique + overwrite si cible existe.
            // FileManager.moveItem échoue si la cible existe (code 516), d'où l'appel direct.
            guard Darwin.rename(tmp.path, target.path) == 0 else {
                let err = String(cString: strerror(errno))
                throw DesktopRegistryError.saveFailure("rename failed: \(err)")
            }
        } catch let e as DesktopRegistryError {
            throw e
        } catch {
            throw DesktopRegistryError.saveFailure("write failed: \(error)")
        }
        desktops[desktop.id] = desktop
    }

    /// Persiste tous les desktops modifiés (T035 — utilisé au boot propre ou shutdown).
    public func saveAll() async throws {
        for desktop in desktops.values {
            try save(desktop)
        }
        try saveCurrentID()
    }

    /// Persiste le currentID sur disque pour restauration au prochain boot.
    public func saveCurrentID() throws {
        let dir = configDir.appendingPathComponent("desktops")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = configDir.appendingPathComponent("desktops/current.txt")
        try String(currentID).write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Accès et mutations

    public func desktop(id: Int) -> RoadieDesktop? { desktops[id] }

    public func allDesktops() -> [RoadieDesktop] {
        (1...count).compactMap { desktops[$0] }
    }

    /// Met à jour currentID et recentID.
    public func setCurrent(id: Int) {
        guard id != currentID else { return }
        recentID = currentID
        currentID = id
    }

    /// Retourne les CGWindowIDs des fenêtres d'un desktop.
    /// Les wids disparus côté macOS sont ignorés silencieusement à la restauration (FR-024).
    public func windows(of desktopID: Int) -> [CGWindowID] {
        desktops[desktopID]?.windows.map { CGWindowID($0.cgwid) } ?? []
    }

    // MARK: - Label (T042, US4)

    /// Valide et pose un label sur le desktop courant. Persiste immédiatement.
    /// - Parameter label: chaîne vide = retrait du label.
    /// - Throws: `DesktopRegistryError.saveFailure` si persistance échoue ;
    ///           `DesktopRegistryError.invalidID` si label invalide ou réservé.
    public func setLabel(_ label: String?, for id: Int) throws {
        let normalised = label.flatMap { $0.isEmpty ? nil : $0 }
        if let l = normalised {
            guard isValidDesktopLabel(l) else {
                throw DesktopRegistryError.saveFailure(
                    "invalid label \"\(l)\": alphanumeric + '-_' only, max 32 chars")
            }
            guard !isReservedDesktopLabel(l) else {
                throw DesktopRegistryError.saveFailure("label \"\(l)\" is reserved")
            }
        }
        guard var desktop = desktops[id] else {
            throw DesktopRegistryError.invalidID(id)
        }
        desktop.label = normalised
        try save(desktop)
    }

    /// Met à jour la expectedFrame d'une fenêtre dans un desktop (R-002).
    /// - Throws: `DesktopRegistryError.unknownDesktop` si le desktop n'existe pas (M2).
    public func updateExpectedFrame(cgwid: UInt32, desktopID: Int, frame: CGRect) throws {
        guard var desktop = desktops[desktopID] else {
            throw DesktopRegistryError.unknownDesktop(desktopID)
        }
        guard let idx = desktop.windows.firstIndex(where: { $0.cgwid == cgwid }) else { return }
        desktop.windows[idx].expectedFrame = frame
        try save(desktop)
    }

    /// Retourne la expectedFrame d'une fenêtre, ou nil si inconnue.
    public func expectedFrame(cgwid: UInt32, desktopID: Int) -> CGRect? {
        desktops[desktopID]?.windows.first(where: { $0.cgwid == cgwid })?.expectedFrame
    }

    /// Assigne une fenêtre à un desktop et un stage (pour future US window assign).
    /// - Throws: `DesktopRegistryError.unknownDesktop` si le desktop n'existe pas (M2).
    public func assignWindow(_ entry: WindowEntry, to desktopID: Int) throws {
        guard var desktop = desktops[desktopID] else {
            throw DesktopRegistryError.unknownDesktop(desktopID)
        }
        // Éviter les doublons par cgwid
        desktop.windows.removeAll { $0.cgwid == entry.cgwid }
        desktop.windows.append(entry)
        // Enregistrer dans le stage par défaut (id == entry.stageID)
        let stageID = entry.stageID
        if let idx = desktop.stages.firstIndex(where: { $0.id == stageID }) {
            if !desktop.stages[idx].windows.contains(entry.cgwid) {
                desktop.stages[idx].windows.append(entry.cgwid)
            }
        } else if var firstStage = desktop.stages.first {
            if !firstStage.windows.contains(entry.cgwid) {
                firstStage.windows.append(entry.cgwid)
                desktop.stages[0] = firstStage
            }
        }
        try save(desktop)
    }

    /// Retire une fenêtre de tous les desktops (appelé à la destruction de la fenêtre).
    /// Best-effort : ignore les erreurs de persistance (log uniquement).
    public func removeWindow(cgwid: UInt32) {
        var modified: [RoadieDesktop] = []
        for var desktop in desktops.values {
            let beforeCount = desktop.windows.count
            desktop.windows.removeAll { $0.cgwid == cgwid }
            for i in desktop.stages.indices {
                desktop.stages[i].windows.removeAll { $0 == cgwid }
            }
            if desktop.windows.count != beforeCount {
                modified.append(desktop)
            }
        }
        for desktop in modified {
            do {
                try save(desktop)
            } catch {
                logWarn("removeWindow save failed",
                        ["cgwid": String(cgwid), "desktop": String(desktop.id), "error": "\(error)"])
            }
        }
    }

    // MARK: - Helpers internes

    private func desktopURL(id: Int) -> URL {
        configDir.appendingPathComponent("desktops/\(id)/state.toml")
    }
}
