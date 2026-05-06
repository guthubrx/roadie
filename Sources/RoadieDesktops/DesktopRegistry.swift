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
    /// Current desktop global (legacy, mode `global` ou fallback initial). En mode
    /// `perDisplay`, `currentByDisplay` est la source de vérité ; `currentID` reflète
    /// la valeur du primary par convention pour les call-sites legacy non-migrés.
    public private(set) var currentID: Int = 1
    public private(set) var recentID: Int?
    public private(set) var count: Int

    /// SPEC-013 FR-004 : current desktop par display physique.
    /// En mode `global`, toutes les entries sont synchronisées (FR-005).
    /// En mode `perDisplay`, chaque entry est mutée indépendamment (FR-006).
    public private(set) var currentByDisplay: [CGDirectDisplayID: Int] = [:]

    /// SPEC-013 fix : recent desktop par display. En mode per_display, le
    /// back-and-forth utilise cette map au lieu du `recentID` global, sinon
    /// le back d'un display tape sur le recent d'un autre.
    public private(set) var recentByDisplay: [CGDirectDisplayID: Int] = [:]

    /// SPEC-013 FR-001 : mode runtime (settable via setMode).
    public private(set) var mode: DesktopMode = .global

    private let configDir: URL
    private let displayUUID: String

    public init(configDir: URL, displayUUID: String, count: Int = 10, mode: DesktopMode = .global) {
        self.configDir = configDir
        self.displayUUID = displayUUID
        self.count = count
        self.mode = mode
        // SPEC-013 : créer le dossier displays/ au boot (V3 path).
        let displaysDir = configDir.appendingPathComponent("displays")
        try? FileManager.default.createDirectory(
            at: displaysDir, withIntermediateDirectories: true)
    }

    // MARK: - Chargement (FR-012)

    /// Charge tous les desktops depuis `<configDir>/displays/<uuid>/desktops/<id>/state.toml`.
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
                    // FR-013 : corruption → archive le fichier corrompu pour
                    // post-mortem puis état vierge. Sans archivage, le warning
                    // ré-apparaît à chaque boot car le blank en mémoire n'est
                    // persisté que sur la prochaine mutation. Avec archivage +
                    // save synchrone du blank, le boot suivant trouve un fichier
                    // valide → silence.
                    let corruptPath = url.path + ".corrupt-"
                        + String(Int(Date().timeIntervalSince1970))
                    try? fm.moveItem(atPath: url.path, toPath: corruptPath)
                    logWarn("desktop state corrupted, using blank",
                            ["id": String(id), "error": "\(error)",
                             "archived_to": corruptPath])
                    let blank = RoadieDesktop.blank(id: id)
                    desktops[id] = blank
                    do {
                        try save(blank)
                    } catch {
                        logWarn("desktop blank save failed",
                                ["id": String(id), "error": "\(error)"])
                    }
                }
            } else {
                desktops[id] = .blank(id: id)
            }
        }
        // Charger le currentID persisté (V3 : current.toml dans le dossier display)
        let curURL = configDir
            .appendingPathComponent("displays/\(displayUUID)/current.toml")
        if let raw = try? String(contentsOf: curURL, encoding: .utf8),
           let savedID = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           (1...count).contains(savedID) {
            currentID = savedID
        }
    }

    // MARK: - Persistance (FR-011)

    /// Persiste un desktop en write-then-rename atomique (V3 : displays/<uuid>/desktops/<id>/).
    public func save(_ desktop: RoadieDesktop) throws {
        let dir = configDir
            .appendingPathComponent("displays/\(displayUUID)/desktops/\(desktop.id)")
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

    /// Persiste le currentID sur disque pour restauration au prochain boot (V3 : current.toml).
    public func saveCurrentID() throws {
        let dir = configDir.appendingPathComponent("displays/\(displayUUID)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("current.toml")
        try String(currentID).write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Accès et mutations

    public func desktop(id: Int) -> RoadieDesktop? { desktops[id] }

    public func allDesktops() -> [RoadieDesktop] {
        (1...count).compactMap { desktops[$0] }
    }

    /// Met à jour currentID et recentID.
    /// En mode `global`, propage la même valeur à toutes les entries
    /// `currentByDisplay` connues (FR-005). En mode `perDisplay`, ne touche que
    /// le primary par défaut — utiliser `setCurrent(_:on:)` pour cibler un display.
    public func setCurrent(id: Int) {
        guard id != currentID else { return }
        let previous = currentID
        recentID = previous
        currentID = id
        if mode == .global {
            // FR-005 : sync toutes les entries (current ET recent : sinon un appel
            // mixte legacy + setCurrent(_:on:) produit des recents incohérents).
            for k in currentByDisplay.keys {
                if let old = currentByDisplay[k] { recentByDisplay[k] = old }
                currentByDisplay[k] = id
            }
        } else {
            let primaryID = CGMainDisplayID()
            if let old = currentByDisplay[primaryID], old != id {
                recentByDisplay[primaryID] = old
            }
            currentByDisplay[primaryID] = id
        }
    }

    // MARK: - SPEC-013 (per-display mode)

    /// SPEC-013 FR-007/FR-008 : mute le current d'un display spécifique.
    /// En mode global, la mutation se propage à TOUTES les entries (et currentID).
    /// En mode perDisplay, seule la cible est mutée.
    public func setCurrent(_ desktopID: Int, on displayID: CGDirectDisplayID) {
        let oldGlobalID = currentID
        switch mode {
        case .global:
            recentID = currentID
            currentID = desktopID
            for k in currentByDisplay.keys {
                if let old = currentByDisplay[k] { recentByDisplay[k] = old }
                currentByDisplay[k] = desktopID
            }
            currentByDisplay[displayID] = desktopID
        case .perDisplay:
            // Recent par display (utile pour `desktop back` scopé).
            if let old = currentByDisplay[displayID], old != desktopID {
                recentByDisplay[displayID] = old
                recentID = old   // pour les call-sites legacy
            }
            currentByDisplay[displayID] = desktopID
            // Maintenir currentID en cohérence avec primary pour les legacy callers.
            let primaryID = CGMainDisplayID()
            if displayID == primaryID {
                currentID = desktopID
            }
        }
        _ = oldGlobalID
    }

    /// SPEC-013 : recent desktop d'un display. Fallback sur `recentID` global
    /// si pas encore d'historique pour ce display.
    public func recentID(for displayID: CGDirectDisplayID?) -> Int? {
        if let did = displayID, let v = recentByDisplay[did] { return v }
        return recentID
    }

    /// SPEC-013 FR-009 : retourne le current d'un display, fallback primary, fallback 1.
    public func currentID(for displayID: CGDirectDisplayID?) -> Int {
        if let did = displayID, let v = currentByDisplay[did] { return v }
        let primaryID = CGMainDisplayID()
        return currentByDisplay[primaryID] ?? currentID
    }

    /// Switch de mode à chaud (FR-003). Synchronise `currentByDisplay` selon les
    /// transitions documentées dans data-model.md (R6).
    public func setMode(_ newMode: DesktopMode) {
        guard newMode != mode else { return }
        let primaryID = CGMainDisplayID()
        switch (mode, newMode) {
        case (.global, .perDisplay):
            // Chaque display garde son current actuel (déjà tous égaux). Aucune action.
            break
        case (.perDisplay, .global):
            // Synchroniser tout sur la valeur du primary.
            let primaryCurrent = currentByDisplay[primaryID] ?? currentID
            for k in currentByDisplay.keys { currentByDisplay[k] = primaryCurrent }
            currentID = primaryCurrent
        case (.global, .global), (.perDisplay, .perDisplay):
            break
        }
        mode = newMode
    }

    /// Initialise/synchronise `currentByDisplay` pour la liste de displays présents.
    /// Appelé au boot et à chaque `displays_changed`. Les displays nouveaux héritent
    /// du `currentID` global (mode global) ou de la valeur 1 par défaut (perDisplay).
    public func syncCurrentByDisplay(presentIDs: [CGDirectDisplayID]) {
        // Retirer les entries des displays absents (current ET recent : sinon
        // recentByDisplay garde des entries d'écrans débranchés indéfiniment,
        // ce qui peut faire que `recentID(for:)` retourne un desktopID stale
        // si le CGDirectDisplayID est réattribué à un nouvel écran physique).
        for k in currentByDisplay.keys where !presentIDs.contains(k) {
            currentByDisplay.removeValue(forKey: k)
        }
        for k in recentByDisplay.keys where !presentIDs.contains(k) {
            recentByDisplay.removeValue(forKey: k)
        }
        // Ajouter les entries manquantes pour les displays présents.
        for id in presentIDs where currentByDisplay[id] == nil {
            currentByDisplay[id] = mode == .global ? currentID : 1
        }
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

    /// Retourne l'ID du desktop contenant la fenêtre, ou nil si inconnue (FR-005).
    public func desktopID(for cgwid: UInt32) -> Int? {
        for (id, desktop) in desktops {
            if desktop.windows.contains(where: { $0.cgwid == cgwid }) { return id }
        }
        return nil
    }

    /// Assigne une fenêtre à un desktop et un stage (pour future US window assign).
    /// - Throws: `DesktopRegistryError.unknownDesktop` si le desktop n'existe pas (M2).
    public func assignWindow(_ entry: WindowEntry, to desktopID: Int) throws {
        guard var desktop = desktops[desktopID] else {
            throw DesktopRegistryError.unknownDesktop(desktopID)
        }
        // Une fenêtre appartient à exactement un desktop : retirer des autres
        // d'abord pour éviter qu'elle apparaisse simultanément dans plusieurs.
        // Sans cette étape : à chaque ré-enregistrement (boot, focus changed,
        // etc.) le cgwid s'accumulait dans tous les desktops visités → fenêtres
        // fantômes qui surgissent au mauvais endroit lors de la bascule.
        for otherID in desktops.keys where otherID != desktopID {
            guard var other = desktops[otherID] else { continue }
            let before = other.windows.count
            other.windows.removeAll { $0.cgwid == entry.cgwid }
            for i in other.stages.indices {
                other.stages[i].windows.removeAll { $0 == entry.cgwid }
            }
            if other.windows.count != before {
                desktops[otherID] = other
                try? save(other)
            }
        }
        // Éviter les doublons par cgwid sur le desktop target.
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

    // MARK: - SPEC-012 T022 : mise à jour displayUUID d'une fenêtre

    /// Met à jour le `displayUUID` d'une fenêtre dans un desktop donné (T022, FR-020).
    /// - Throws: `DesktopRegistryError.unknownDesktop` si le desktop n'existe pas.
    public func updateWindowDisplayUUID(cgwid: UInt32,
                                        desktopID: Int,
                                        displayUUID: String) throws {
        guard var desktop = desktops[desktopID] else {
            throw DesktopRegistryError.unknownDesktop(desktopID)
        }
        guard let idx = desktop.windows.firstIndex(where: { $0.cgwid == cgwid }) else { return }
        desktop.windows[idx].displayUUID = displayUUID
        try save(desktop)
    }

    // MARK: - SPEC-021 : cache spaceID → scope (US2, T043-T045)

    /// Index RAM-only : space_id SkyLight → (displayUUID, desktopID roadie).
    /// Rebuilt à chaque appel à `rebuildSpaceIDCache(from:)`. Jamais persisté.
    private var spaceIDToScopeCache: [UInt64: (displayUUID: String, desktopID: Int)] = [:]

    /// SPEC-021 T043 — résout un space_id SkyLight vers un scope roadie.
    /// Retourne nil si le space_id est inconnu (desktop nouvellement créé, fullscreen).
    public func scopeForSpaceID(_ spaceID: UInt64) -> (displayUUID: String, desktopID: Int)? {
        spaceIDToScopeCache[spaceID]
    }

    /// SPEC-021 T045 — reconstruit le cache depuis les données SkyLight pré-calculées.
    /// Appelant (MainActor) doit avoir appelé `SkyLightBridge.managedDisplaySpaces()`
    /// et passer le résultat ici. Mapping : ordre SkyLight → desktopID 1, 2, 3, ...
    public func rebuildSpaceIDCache(
        from displaySpaces: [(displayUUID: String, spaceIDs: [UInt64])]
    ) {
        spaceIDToScopeCache.removeAll(keepingCapacity: true)
        for entry in displaySpaces {
            for (index, spaceID) in entry.spaceIDs.enumerated() {
                spaceIDToScopeCache[spaceID] = (entry.displayUUID, index + 1)
            }
        }
        logInfo("space_id_cache_rebuilt", ["entries": String(spaceIDToScopeCache.count)])
    }

    // MARK: - Helpers internes

    private func desktopURL(id: Int) -> URL {
        configDir
            .appendingPathComponent("displays/\(displayUUID)/desktops/\(id)/state.toml")
    }
}
