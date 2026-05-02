import Foundation
import CoreGraphics
import RoadieCore
import RoadieStagePlugin
import RoadieDesktops

// MARK: - DesktopBackedStagePersistence

/// Implémentation V2 de StagePersistence : source de vérité = DesktopRegistry.
///
/// Principe :
/// - `loadStages()` / `loadActiveStage()` : lit le `RoadieDesktop` courant depuis le
///   DesktopRegistry et reconstitue les `Stage` en mémoire (cgwids → StageMember).
/// - `saveStage()` / `saveActiveStage()` / `deleteStage()` : écrit dans le DesktopRegistry
///   (qui persiste atomiquement dans `state.toml`). Ne touche PAS aux fichiers V1.
///
/// Contrainte de concurrence :
/// DesktopRegistry est un `actor` (async). Cette classe est appelée depuis @MainActor
/// (StageManager). On utilise un cache en mémoire rechargé lors du `loadStages()`
/// (appelé une fois par `reload(forDesktop:)`). Les mutations sont propagées en
/// fire-and-forget Task vers l'actor.
/// Box thread-safe pour passer un résultat hors d'un Task.detached.
/// `@unchecked Sendable` car la synchronisation est garantie par DispatchSemaphore.
final class ResultBox<T>: @unchecked Sendable {
    var value: T!
}

final class DesktopBackedStagePersistence: StagePersistence, @unchecked Sendable {
    private let registry: DesktopRegistry
    /// ID du desktop courant. Mis à jour par `setCurrentDesktopID` avant `loadStages()`.
    private(set) var currentDesktopID: Int

    /// Cache en mémoire du desktop courant, rechargé par `loadStages()`.
    /// Utilisé pour les mutations synchrones qui ne peuvent pas `await` l'actor.
    private var cachedDesktop: RoadieDesktop?

    init(registry: DesktopRegistry, desktopID: Int) {
        self.registry = registry
        self.currentDesktopID = desktopID
    }

    /// Met à jour l'ID courant avant `loadStages()` (appelé par StageManager via le protocol).
    func setCurrentDesktopID(_ id: Int) {
        currentDesktopID = id
        cachedDesktop = nil
    }

    func setDesktopID(_ id: Int) {
        setCurrentDesktopID(id)
    }

    /// Faux : DesktopRegistry est la source de vérité, pas le système de fichiers V1.
    var requiresPhysicalDirSwap: Bool { false }

    // MARK: - StagePersistence

    /// Charge les stages depuis DesktopRegistry.
    /// Bloque sur l'actor via DispatchSemaphore — acceptable car appelé une fois
    /// par transition desktop, pas dans une hot loop.
    func loadStages() -> [Stage] {
        let desktop = fetchDesktopSync()
        cachedDesktop = desktop
        guard let desktop else { return [] }
        return buildStages(from: desktop)
    }

    func loadActiveStage() -> StageID? {
        let desktop = cachedDesktop ?? fetchDesktopSync()
        guard let desktop else { return nil }
        return StageID(String(desktop.activeStageID))
    }

    func saveStage(_ stage: Stage) {
        guard var desktop = cachedDesktop else { return }
        let stageIntID = Int(stage.id.value) ?? 1
        let cgwids = stage.memberWindows.map { UInt32($0.cgWindowID) }

        // Mettre à jour le DesktopStage correspondant.
        if let idx = desktop.stages.firstIndex(where: { $0.id == stageIntID }) {
            desktop.stages[idx].windows = cgwids
        } else {
            desktop.stages.append(DesktopStage(id: stageIntID,
                                               label: stage.displayName,
                                               windows: cgwids))
        }
        // Synchroniser windows[] : chaque cgwid du stage doit exister dans
        // desktop.windows avec le bon stageID.
        for member in stage.memberWindows {
            let cgwid = UInt32(member.cgWindowID)
            if let idx = desktop.windows.firstIndex(where: { $0.cgwid == cgwid }) {
                desktop.windows[idx].stageID = stageIntID
            } else {
                desktop.windows.append(WindowEntry(
                    cgwid: cgwid,
                    bundleID: member.bundleID,
                    title: member.titleHint,
                    expectedFrame: member.savedFrame?.cgRect ?? .zero,
                    stageID: stageIntID
                ))
            }
        }
        cachedDesktop = desktop
        persist(desktop)
    }

    func deleteStage(_ id: StageID) {
        guard var desktop = cachedDesktop else { return }
        let stageIntID = Int(id.value) ?? 1
        desktop.stages.removeAll { $0.id == stageIntID }
        // Réassigner les fenêtres orphelines au stage 1.
        for i in desktop.windows.indices where desktop.windows[i].stageID == stageIntID {
            desktop.windows[i].stageID = 1
        }
        cachedDesktop = desktop
        persist(desktop)
    }

    func saveActiveStage(_ stageID: StageID?) {
        guard var desktop = cachedDesktop else { return }
        desktop.activeStageID = stageID.flatMap { Int($0.value) } ?? 1
        cachedDesktop = desktop
        persist(desktop)
    }

    // MARK: - Helpers privés

    private func fetchDesktopSync() -> RoadieDesktop? {
        // CRITICAL : `Task { ... }` peut être planifié sur le main thread, qui
        // est bloqué par `semaphore.wait()` → deadlock. Forcer l'exécution
        // sur une queue background avec `Task.detached`.
        let semaphore = DispatchSemaphore(value: 0)
        let result = ResultBox<RoadieDesktop?>()
        let id = currentDesktopID
        let reg = registry
        Task.detached(priority: .userInitiated) {
            let r = await reg.desktop(id: id)
            result.value = r
            semaphore.signal()
        }
        semaphore.wait()
        return result.value
    }

    private func persist(_ desktop: RoadieDesktop) {
        Task {
            do {
                try await registry.save(desktop)
            } catch {
                logWarn("DesktopBackedStagePersistence: save failed",
                        ["desktop": String(desktop.id), "error": "\(error)"])
            }
        }
    }

    /// Reconstitue les `Stage` (RoadieStagePlugin) depuis un `RoadieDesktop`.
    private func buildStages(from desktop: RoadieDesktop) -> [Stage] {
        var result: [Stage] = []
        for ds in desktop.stages {
            let members: [StageMember] = ds.windows.map { cgwid in
                if let entry = desktop.windows.first(where: { $0.cgwid == cgwid }) {
                    return StageMember(
                        cgWindowID: WindowID(cgwid),
                        bundleID: entry.bundleID,
                        titleHint: entry.title,
                        savedFrame: entry.expectedFrame == .zero
                            ? nil
                            : SavedRect(entry.expectedFrame)
                    )
                }
                // Fenêtre présente dans le stage mais sans WindowEntry complet.
                return StageMember(cgWindowID: WindowID(cgwid),
                                   bundleID: "", titleHint: "", savedFrame: nil)
            }
            result.append(Stage(
                id: StageID(String(ds.id)),
                displayName: ds.label ?? String(ds.id),
                memberWindows: members
            ))
        }
        // Invariant : stage 1 toujours présent.
        if !result.contains(where: { $0.id == StageID("1") }) {
            result.append(Stage(id: StageID("1"), displayName: "1"))
        }
        return result
    }
}
