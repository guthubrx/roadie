import Foundation
import RoadieAX
import RoadieCore

/// Résultat du rappel de fenêtres absentes d'un relevé (Spec 159 — extrait de `StageCommands.swift`).
struct MissingWindowRecall: Equatable, Sendable {
    var attempted: [WindowID] = []
    var focusedWindowID: WindowID?
    var activatedApplication = false
}

/// Service dédié au focus et au rappel des fenêtres absentes lors des bascules et réconciliations de stage.
/// Centralise la logique auparavant dupliquée dans les trois branches de `StageCommands.switchDisplay`.
struct StageFocusRecallService {
    private let service: SnapshotService

    init(service: SnapshotService) {
        self.service = service
    }

    /// Classe les membres éligibles au rappel (fenêtre demandée en tête, puis dernière apparition décroissante).
    static func missingFocusCandidates(
        in stage: PersistentStage?,
        preferredWindowID: WindowID? = nil,
        includeMaximized: Bool = false
    ) -> [PersistentStageMember] {
        guard let stage else { return [] }
        let preferred = preferredWindowID ?? stage.focusedWindowID
        return stage.members.filter {
            !$0.bundleID.isEmpty && $0.confirmedClosedAt == nil && (includeMaximized || $0.presentationState != .maximized)
        }.sorted { lhs, rhs in
            if lhs.windowID == preferred { return rhs.windowID != preferred }
            if rhs.windowID == preferred { return false }
            let left = lhs.lastSeenAt ?? .distantPast
            let right = rhs.lastSeenAt ?? .distantPast
            return left == right ? lhs.windowID.rawValue < rhs.windowID.rawValue : left > right
        }
    }

    /// Chaque membre éligible est essayé au plus une fois ; arrêt au premier focus réussi.
    /// Si `onlyPreferred` est vrai, seule la fenêtre demandée explicitement est sollicitée (clic sur
    /// une icône précise du rail), sans jamais dévier le focus vers une autre application de la stage.
    func recallMissingWindows(
        in stage: PersistentStage?,
        preferredWindowID: WindowID? = nil,
        includeMaximized: Bool = false,
        onlyPreferred: Bool = false
    ) -> MissingWindowRecall {
        var candidates = Self.missingFocusCandidates(
            in: stage,
            preferredWindowID: preferredWindowID,
            includeMaximized: includeMaximized
        )
        if onlyPreferred, let preferredWindowID {
            candidates = candidates.filter { $0.windowID == preferredWindowID }
        }
        var result = MissingWindowRecall()
        for member in candidates {
            result.attempted.append(member.windowID)
            if service.focusApplicationWindow(
                bundleID: member.bundleID,
                windowID: member.windowID,
                title: member.title,
                frame: member.frame
            ) {
                result.focusedWindowID = member.windowID
                return result
            }
        }
        if let member = candidates.first {
            result.activatedApplication = service.activateApplication(bundleID: member.bundleID)
        }
        return result
    }

    /// Focalise une fenêtre explicitement ciblée (ex. clic icône NavRail), ou la rappelle si elle est
    /// absente du relevé courant, avec repli optionnel sur l'activation de son `bundleID`.
    @discardableResult
    func focusOrRecallPreferred(
        windowID: WindowID,
        bundleID: String?,
        in stage: PersistentStage?,
        windowsByID: [WindowID: WindowSnapshot]
    ) -> Bool {
        if let window = windowsByID[windowID] {
            return service.focus(window)
        }
        let recall = recallMissingWindows(
            in: stage,
            preferredWindowID: windowID,
            includeMaximized: true,
            onlyPreferred: true
        )
        if recall.focusedWindowID != nil || recall.activatedApplication {
            return true
        }
        if let bundleID, !bundleID.isEmpty {
            return service.activateApplication(bundleID: bundleID)
        }
        return false
    }

    /// Focalise la fenêtre cible vivante, sinon rappelle les fenêtres absentes de la stage.
    func focusOrRecallTarget(
        windowID: WindowID?,
        in stage: PersistentStage?,
        windowsByID: [WindowID: WindowSnapshot],
        includeMaximized: Bool = true
    ) -> (focusedWindow: Bool, recall: MissingWindowRecall) {
        var focusedWindow = false
        if let windowID, let window = windowsByID[windowID] {
            focusedWindow = service.focus(window)
        }
        let recall = !focusedWindow
            ? recallMissingWindows(in: stage, preferredWindowID: windowID, includeMaximized: includeMaximized)
            : MissingWindowRecall()
        return (focusedWindow, recall)
    }
}
