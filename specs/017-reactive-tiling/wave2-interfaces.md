# Interfaces disponibles pour la vague 2 (état réel après la vague 1, commit 7c4189e)

Source de vérité : le code. Ce fichier résume ce que la vague 1 a livré.

## RoadieTiler/BSPTree.swift (L4)

```swift
public enum BSPOrientation { case vertical, horizontal }
public enum BSPInsertionSide { case right, left }
public enum BSPEdge: String { case left, right, up, down }   // BSPEdge(rawValue: direction.rawValue)
public indirect enum BSPTree {   // cas et JSON inchangés, pas d'identifiant de nœud persistant
  func place(in rect: CGRect, innerGap: CGFloat) -> [WindowID: CGRect]
  func inserting(_ window: WindowID, at anchor: WindowID?, side: BSPInsertionSide, in container: CGRect, innerGap: CGFloat = 0, excluding absent: Set<WindowID> = []) -> BSPTree   // coupe selon la feuille
  func projected(excluding absent: Set<WindowID>) -> BSPTree
  func balanced() -> BSPTree
  func togglingSplit(of: WindowID, excluding: Set<WindowID> = []) -> BSPTree
  func settingSplit(of: WindowID, to: BSPOrientation, excluding: Set<WindowID> = []) -> BSPTree
  func adjustingFence(of: WindowID, edge: BSPEdge, to frame: CGRect, in container: CGRect, innerGap: CGFloat = 0, excluding: Set<WindowID> = []) -> BSPTree  // arbre égal si pas de frontière
  func correctingForMinimumSize(of: WindowID, minimum: CGSize, in container: CGRect, innerGap: CGFloat = 0, excluding: Set<WindowID> = [], knownMinimums: [WindowID: CGSize] = [:]) -> BSPTree?  // nil = infaisable
  static func inferred(from ordered: [(WindowID, CGRect?)], in container: CGRect, innerGap: CGFloat = 0) -> BSPTree
  // Anciennes API conservées jusqu'à la vague 3 : inserting(_:nextTo:side:containerIsWide:), removing(_:), swapping(_:_:),
  // warping(_:nextTo:side:containerIsWide:), resizing(window:orientation:delta:), reconciled(liveWindowIDs:focus:side:containerIsWide:)
  // Équivalent de warping avec coupe selon la feuille : removing(w).inserting(w, at: voisine, side:, in:, excluding:)
}
// RoadieCore : WindowManagementMode.usesTreeEngine (spatialBsp, mutableBsp). Config : mutableBsp/yabai -> spatialBsp.
// CLICommandRouter.swift:1728 (`roadie mode mutableBsp`) ne traduit pas encore l'alias : à faire par L9.
```

## RoadieAX (L3)

```swift
public struct WrittenFrame { requested; readBack?; accepted?; writtenAt; generation: UInt64; writesInGeneration: Int; refusalConfirmedAt: Date?; var hasRefusal: Bool }
public final class WrittenFrameRegistry {
  static let shared
  func record(windowID: UInt32, requested: CGRect, readBack: CGRect?, generation: UInt64, at: Date)
  func accept(windowID: UInt32, frame: CGRect)
  func entry(for: UInt32) -> WrittenFrame?
  func forget(windowID: UInt32)
  @discardableResult func confirmRefusal(windowID: UInt32, observed: CGRect, at: Date) -> Bool
  func pendingRefusals() -> [UInt32]
  enum Classification { case echo, appResponse, external }      // la frame acceptée compte comme écho
  func classify(windowID: UInt32, observed: CGRect, now: Date) -> Classification
}
public final class PlacementGeneration { static let shared; func next() -> UInt64; var current: UInt64 }
public struct AXWindowEvent { name: String; pid: pid_t; windowID: UInt32? }
// AXWindowEventObserver : init(onWindowEvent: (String) -> Void) (ancien, sans moved/resized) ; convenience init(onEvent: (AXWindowEvent) -> Void) (nouveau, avec moved/resized, échos absorbés après confirmation de refus)
public enum SpaceProbe { static func isUserSpaceActive(displayUUID: String) -> Bool? }   // nil = indisponible
// WindowFrameWriting : + setFrames(_ updates: [WindowFrameUpdate], generation: UInt64) -> [WindowID: CGRect?] (défaut : ignore la génération)
//                      + readFrame(of window: WindowSnapshot) -> CGRect?  (lecture AX fraîche ; défaut nil)
```

## RoadieDaemon (L1, L2, jonction)

```swift
EpisodeContext.shared.begin(cause:) -> String ; current ; currentCause ; continue()   // fermeture après 1 s sans begin/continue
StageStore.migrateLegacyTreeModes(infer: ([(WindowID, CGRect?)], CGRect) -> BSPTree, container: (StageScope) -> CGRect?) throws -> Int
//   appel : try store.migrateLegacyTreeModes(infer: { BSPTree.inferred(from: $0, in: $1) }, container: { scope in <visibleFrame> })
JSONPersistence : cache par signature (fstat), mutate sans écriture si valeur égale (types Equatable)
// Stubs à remplir :
LayoutMaintainer.tick(cause:) -> MaintenanceTick ; nextDeadline(now:) -> Date? ; spaceDidChange(displayUUID:)      // L7
SnapshotService.applyTreeScope(_ scope: StageScope, cause: String, generation: UInt64) -> MaintenanceTick            // L8
GestureSession { windowID: UInt32?; startFrame: CGRect?; startedAt: Date; endedAt: Date? }
UserInputActivity.currentGesture: GestureSession? ; takeGesture() -> GestureSession?                                 // L6
```

## RoadieCore/LayoutTolerance.swift

`frameMatch` (2 pt), `echoWindow` (1 s), `burstWindow` (0,3 s), `burstQuiet` (0,1 s), `burstCap` (1 s), `spaceGuardPoll` (0,05 s), `spaceGuardCap` (1,5 s), `refusalConfirmDelay` (0,1 s), `writeBudgetPerGeneration` (2). Les `TickDuration` existent encore : L7 les supprime (T070).

## Événements (catalogue, L1)

`layout_echo_ignored`, `layout_app_response_accepted`, `layout_external_change_reverted`, `layout_manual_gesture`, `layout_stable`, `space_transition_guard`, `space_did_change`, `state_migrated`. `layout_apply` : `durationMs`, `cause`, `pass`, `scans`, `axWrites`, `windowWrites` (`"wid:n,wid:n"`), `layoutVersion` → mettre la génération.
