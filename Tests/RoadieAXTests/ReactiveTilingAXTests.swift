import ApplicationServices
import Foundation
import RoadieCore
import Testing
@testable import RoadieAX

// SPEC-017 T035 : écrivain AX, registre des frames écrites, écho absorbé, sonde de bureau.

/// Écrivain espion : enregistre les appels AX et répond avec des valeurs scriptées.
private final class SpyAXFrameIO: AXFrameIO, @unchecked Sendable {
    var calls: [String] = []
    var enumerations = 0
    var windows: [pid_t: AXApplicationWindows] = [:]
    var enhancedUserInterface = false
    var minimized: Bool?
    var minimizedReadError: AXError?
    var nativeFullscreen: Bool?
    var nativeFullscreenReadError: AXError?
    var setErrors: [String: AXError] = [:]
    var actionError: AXError = .success
    var titles: [AXUIElement: String] = [:]
    var readBackError: AXError?
    var frameAfterWrite: CGRect?
    var afterFrameWrite: (@Sendable () -> Void)?
    var readBack = CGRect(x: 0, y: 0, width: 100, height: 100)
    var simulatesFrameAttributes = false
    var resizeOrigins: [CGPoint] = []

    func enumerateWindows(pid: pid_t) -> AXApplicationWindows? {
        enumerations += 1
        return windows[pid]
    }

    func value(of attribute: String, on element: AXUIElement) -> (AXError, CFTypeRef?) {
        calls.append("get \(attribute)")
        if attribute == kAXTitleAttribute { return (.success, (titles[element] ?? "") as CFString) }
        if attribute == kAXMinimizedAttribute {
            if let error = minimizedReadError { return (error, nil) }
            if let minimized { return (.success, minimized ? kCFBooleanTrue : kCFBooleanFalse) }
            return (.attributeUnsupported, nil)
        }
        if attribute == "AXFullScreen" {
            if let error = nativeFullscreenReadError { return (error, nil) }
            if let nativeFullscreen { return (.success, nativeFullscreen ? kCFBooleanTrue : kCFBooleanFalse) }
            return (.attributeUnsupported, nil)
        }
        return attribute == AXWindowFrameWriter.enhancedUserInterface
            ? (.success, enhancedUserInterface ? kCFBooleanTrue : kCFBooleanFalse)
            : (.attributeUnsupported, nil)
    }

    func values(of attributes: [String], on element: AXUIElement) -> (AXError, [AnyObject]) {
        calls.append("read \(attributes.joined(separator: ","))")
        if let error = readBackError { return (error, []) }
        var origin = readBack.origin
        var size = readBack.size
        return (.success, [AXValueCreate(.cgPoint, &origin)!, AXValueCreate(.cgSize, &size)!])
    }

    func setValue(_ value: CFTypeRef, of attribute: String, on element: AXUIElement) -> AXError {
        if attribute == AXWindowFrameWriter.enhancedUserInterface {
            calls.append("set \(attribute)=\((value as? Bool) == true)")
            return .success
        }
        calls.append("set \(attribute)")
        if simulatesFrameAttributes, setErrors[attribute] == nil {
            let ax = unsafeBitCast(value, to: AXValue.self)
            if attribute == kAXPositionAttribute {
                var point = CGPoint.zero
                if AXValueGetValue(ax, .cgPoint, &point) { readBack.origin = point }
            } else if attribute == kAXSizeAttribute {
                resizeOrigins.append(readBack.origin)
                var size = CGSize.zero
                if AXValueGetValue(ax, .cgSize, &size) { readBack.size = size }
            }
        }
        if let frameAfterWrite { readBack = frameAfterWrite }
        afterFrameWrite?()
        return setErrors[attribute] ?? .success
    }

    func performAction(_ action: String, on element: AXUIElement) -> AXError {
        calls.append("action \(action)")
        return actionError
    }

    var frameWrites: [String] { calls.filter { $0 == "set AXSize" || $0 == "set AXPosition" } }
}

private final class ManualClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

private func window(_ id: UInt32, pid: pid_t) -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: id), pid: pid, appName: "App", bundleID: "app", title: "w\(id)",
        frame: Rect(x: 0, y: 0, width: 400, height: 300), isOnScreen: true, isTileCandidate: true
    )
}

/// Index AX factice : un élément distinct par fenêtre (éléments application de pid factices).
private func index(pid: pid_t, ids: [UInt32]) -> AXApplicationWindows {
    AXApplicationWindows(pid: pid, entries: ids.map { (id: $0, element: AXUIElementCreateApplication(pid_t($0))) })
}

private struct WriterFixture {
    let io = SpyAXFrameIO()
    let cache = AXWindowIndexCache()
    let frames = WrittenFrameRegistry()
    let clock = ManualClock()
    let generations = PlacementGeneration()

    var writer: AXWindowFrameWriter {
        let clock = clock
        return AXWindowFrameWriter(
            io: io, windowIndex: cache, writtenFrames: frames, registry: AXUnresponsiveApps(),
            generations: generations, now: { clock.now }
        )
    }
}

@Suite
struct AXWindowFrameWriterTests {
    @Test func spec147NewWindowReachesDestinationBeforeAnyResize() {
        let f = WriterFixture()
        f.io.windows[50] = index(pid: 50, ids: [1])
        f.io.readBack = CGRect(x: 150, y: 40, width: 570, height: 436)
        f.io.simulatesFrameAttributes = true
        let target = CGRect(x: 4432, y: -759, width: 914, height: 1052)
        let result = f.writer.setFrames([WindowFrameUpdate(window: window(1, pid: 50), frame: target,
                                                         positionsBeforeResizing: true)], generation: 1)
        #expect(result[WindowID(rawValue: 1)] == target)
        #expect(!f.io.resizeOrigins.isEmpty)
        #expect(f.io.resizeOrigins.allSatisfy { $0 == target.origin })
        #expect(f.frames.entry(for: 1)?.writesInGeneration == 1)
    }
    @Test func spec142RevokedBatchDoesNotReachAX() {
        let fixture = WriterFixture()
        fixture.io.windows[50] = index(pid: 50, ids: [1])
        let result = fixture.writer.setFrames([WindowFrameUpdate(window: window(1, pid: 50), frame: .zero)],
                                             generation: 1, isCurrent: { false })
        #expect(result.isEmpty)
        #expect(fixture.io.calls.isEmpty)
        #expect(fixture.io.enumerations == 0)
    }

    @Test func spec142RevocationBetweenAttributesStopsWritesAndOldPublication() {
        let fixture = WriterFixture()
        fixture.io.windows[50] = index(pid: 50, ids: [1])
        let permit = NSLockPermit142()
        fixture.io.afterFrameWrite = { permit.invalidate() }
        _ = fixture.writer.setFrames([WindowFrameUpdate(window: window(1, pid: 50), frame: .zero)],
                                     generation: 1, isCurrent: { permit.isCurrent })
        #expect(fixture.io.frameWrites == ["set AXSize"])
        #expect(fixture.frames.entry(for: 1) == nil)
    }
    @Test
    func missingIDsReadEachFallbackCandidateOncePerBatch() {
        let fixture = WriterFixture()
        fixture.io.windows[50] = index(pid: 50, ids: [901, 902, 903])
        let updates = (1...4).map { WindowFrameUpdate(window: window(UInt32($0), pid: 50), frame: .zero) }
        let results = fixture.writer.setFrames(updates, generation: 1)
        #expect(results.values.allSatisfy { $0 == nil })
        #expect(fixture.io.calls.filter { $0.hasPrefix("read ") }.count == 3)
        #expect(fixture.io.calls.filter { $0 == "get AXTitle" }.count == 3)
        #expect(fixture.io.enumerations == 1)
        #expect(fixture.io.frameWrites.isEmpty)
    }

    @Test
    func fallbackFrameIsUpdatedAfterWritingAndTitlesStayCached() {
        let fixture = WriterFixture()
        let element = AXUIElementCreateApplication(901)
        fixture.io.windows[50] = AXApplicationWindows(pid: 50, entries: [(id: 901, element: element)])
        fixture.io.titles[element] = "w1"
        // La première fenêtre est trouvée par cadre. La seconde ne doit pas réutiliser ce cadre ancien.
        var first = window(1, pid: 50)
        first.frame = Rect(fixture.io.readBack)
        var second = window(2, pid: 50)
        second.frame = first.frame
        fixture.io.frameAfterWrite = CGRect(x: 500, y: 300, width: 400, height: 300)
        let result = fixture.writer.setFrames([
            WindowFrameUpdate(window: first, frame: fixture.io.frameAfterWrite!),
            WindowFrameUpdate(window: second, frame: .zero)
        ], generation: 1)
        #expect(result[first.id] != nil)
        #expect(result[second.id] == .some(nil))
        #expect(fixture.io.calls.filter { $0.hasPrefix("read ") }.count == 2) // observation + relecture d'écriture
        #expect(fixture.io.frameWrites.count == 3)
    }

    @Test
    func freshNativeFullscreenPreventsWritesWithoutConsumingTheBudget() {
        let fixture = WriterFixture()
        fixture.io.windows[50] = index(pid: 50, ids: [501])
        fixture.io.nativeFullscreen = true
        var snapshot = window(501, pid: 50)
        snapshot.furniture = WindowFurniture(isNativeFullscreen: false)
        let target = CGRect(x: 10, y: 20, width: 300, height: 200)
        fixture.io.readBack = target

        #expect(fixture.writer.setFrame(target, of: snapshot, generation: 7) == nil)
        #expect(fixture.io.calls == ["get AXFullScreen"])
        #expect(fixture.frames.entry(for: 501) == nil)

        // La sortie du plein écran rend le placement possible dans la même génération.
        fixture.io.nativeFullscreen = false
        #expect(fixture.writer.setFrame(target, of: snapshot, generation: 7) == target)
        #expect(fixture.frames.entry(for: 501)?.writesInGeneration == 1)
        #expect(fixture.frames.entry(for: 501)?.nativeFullscreenReading == false)
        #expect(fixture.frames.entry(for: 501)?.axResultCodes?["nativeFullscreen"] == AXError.success.rawValue)
        #expect(fixture.io.frameWrites == ["set AXSize", "set AXPosition", "set AXSize"])
    }

    @Test
    func hiddenOrdinaryWindowStillMovesWhenNativeFullscreenIsUnavailable() {
        let fixture = WriterFixture()
        fixture.io.windows[50] = index(pid: 50, ids: [501])
        var snapshot = window(501, pid: 50)
        snapshot.isOnScreen = false
        let target = CGRect(x: -2000, y: 20, width: 300, height: 200)
        fixture.io.readBack = target

        #expect(fixture.writer.setFrame(target, of: snapshot, generation: 7) == target)
        #expect(fixture.io.frameWrites == ["set AXSize", "set AXPosition", "set AXSize"])
        #expect(fixture.frames.entry(for: 501)?.writesInGeneration == 1)
        #expect(fixture.frames.entry(for: 501)?.nativeFullscreenReading == nil)
        #expect(fixture.frames.entry(for: 501)?.axResultCodes?["nativeFullscreen"] == AXError.attributeUnsupported.rawValue)
    }

    @Test
    func unresponsiveNativeFullscreenReadStopsBeforeWriting() {
        let fixture = WriterFixture()
        fixture.io.windows[50] = index(pid: 50, ids: [501])
        fixture.io.nativeFullscreenReadError = .cannotComplete

        #expect(fixture.writer.setFrame(CGRect(x: 10, y: 20, width: 300, height: 200), of: window(501, pid: 50), generation: 7) == nil)
        #expect(fixture.io.calls == ["get AXFullScreen"])
        #expect(fixture.frames.entry(for: 501) == nil)
    }

    @Test
    func writesSizeThenPositionThenSizeThenReadsBackOnce() {
        let fixture = WriterFixture()
        fixture.io.windows[50] = index(pid: 50, ids: [501])

        let target = CGRect(x: 10, y: 20, width: 300, height: 200)
        fixture.io.readBack = target
        let result = fixture.writer.setFrames([WindowFrameUpdate(window: window(501, pid: 50), frame: target)])

        #expect(result[WindowID(rawValue: 501)] == target)
        #expect(fixture.io.frameWrites == ["set AXSize", "set AXPosition", "set AXSize"])
        #expect(fixture.io.calls.filter { $0.hasPrefix("read") } == ["read AXPosition,AXSize"])
    }

    @Test
    func enhancedUserInterfaceIsDisabledOncePerAppAndRestoredEvenOnFailure() {
        let fixture = WriterFixture()
        fixture.io.windows[51] = index(pid: 51, ids: [511, 512])
        fixture.io.enhancedUserInterface = true
        fixture.io.setErrors[kAXPositionAttribute] = .cannotComplete

        let result = fixture.writer.setFrames([
            WindowFrameUpdate(window: window(511, pid: 51), frame: CGRect(x: 0, y: 0, width: 300, height: 200)),
            WindowFrameUpdate(window: window(512, pid: 51), frame: CGRect(x: 300, y: 0, width: 300, height: 200)),
        ])

        let euiCalls = fixture.io.calls.filter { $0.contains(AXWindowFrameWriter.enhancedUserInterface) }
        #expect(euiCalls == [
            "get AXEnhancedUserInterface", "set AXEnhancedUserInterface=false", "set AXEnhancedUserInterface=true",
        ])
        #expect(fixture.io.calls.last == "set AXEnhancedUserInterface=true")
        #expect(result[WindowID(rawValue: 511)] == .some(nil))
        // T213 : la tentative a atteint l'appel AX, elle est inscrite (sans relecture) et compte au budget.
        #expect(fixture.frames.entry(for: 511)?.readBack == nil)
        #expect(fixture.frames.entry(for: 511)?.writesInGeneration == 1)
    }

    @Test
    func inactiveEnhancedUserInterfaceIsLeftAlone() {
        let fixture = WriterFixture()
        fixture.io.windows[52] = index(pid: 52, ids: [521])
        _ = fixture.writer.setFrame(CGRect(x: 0, y: 0, width: 300, height: 200), of: window(521, pid: 52))
        #expect(!fixture.io.calls.contains { $0.hasPrefix("set AXEnhancedUserInterface") })
    }

    @Test
    func readFrameDoesAFreshReadWithoutWriting() {
        let fixture = WriterFixture()
        fixture.io.windows[56] = index(pid: 56, ids: [561])
        fixture.io.readBack = CGRect(x: 5, y: 5, width: 640, height: 480)
        let writer: any WindowFrameWriting = fixture.writer
        #expect(writer.readFrame(of: window(561, pid: 56)) == fixture.io.readBack)
        #expect(fixture.io.calls == ["read AXPosition,AXSize"])
    }

    @Test
    func refusedSizeStillMovesTheWindow() {
        let fixture = WriterFixture()
        fixture.io.windows[53] = index(pid: 53, ids: [531])
        fixture.io.nativeFullscreen = false
        fixture.io.setErrors[kAXSizeAttribute] = .attributeUnsupported
        let readBack = CGRect(x: 10, y: 10, width: 500, height: 400)
        fixture.io.readBack = readBack

        let applied = fixture.writer.setFrame(CGRect(x: 10, y: 10, width: 300, height: 200), of: window(531, pid: 53))
        #expect(applied == readBack)
        #expect(fixture.io.frameWrites == ["set AXSize", "set AXPosition", "set AXSize"])
        #expect(fixture.frames.entry(for: 531)?.writesInGeneration == 1)
        #expect(fixture.frames.entry(for: 531)?.nativeFullscreenReading == false)
        #expect(fixture.frames.entry(for: 531)?.axResultCodes == [
            "nativeFullscreen": AXError.success.rawValue,
            "sizeBefore": AXError.attributeUnsupported.rawValue,
            "position": AXError.success.rawValue,
            "sizeAfter": AXError.attributeUnsupported.rawValue,
            "readBack": AXError.success.rawValue,
        ])
    }

    @Test
    func failedReadBackRecordsItsAXCodeWithoutAnotherWrite() {
        let fixture = WriterFixture()
        fixture.io.windows[53] = index(pid: 53, ids: [531])
        fixture.io.nativeFullscreen = false
        fixture.io.readBackError = .failure
        let target = CGRect(x: 10, y: 10, width: 300, height: 200)

        #expect(fixture.writer.setFrame(target, of: window(531, pid: 53), generation: 7) == nil)
        #expect(fixture.frames.entry(for: 531)?.axResultCodes?["readBack"] == AXError.failure.rawValue)
        #expect(fixture.frames.entry(for: 531)?.nativeFullscreenReading == false)
        #expect(fixture.frames.entry(for: 531)?.writesInGeneration == 1)
        #expect(fixture.io.frameWrites == ["set AXSize", "set AXPosition", "set AXSize"])
        #expect(fixture.io.calls.filter { $0.hasPrefix("read") } == ["read AXPosition,AXSize"])
    }

    @Test
    func enumeratesOncePerPidAndBatchThenReusesSnapshotIndex() {
        let fixture = WriterFixture()
        fixture.io.windows[54] = index(pid: 54, ids: [541, 542])
        let updates = [541, 542].map {
            WindowFrameUpdate(window: window($0, pid: 54), frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        }

        // Une génération par lot : le budget A13 n'interfère pas avec la mesure des énumérations.
        _ = fixture.writer.setFrames(updates, generation: 1)
        #expect(fixture.io.enumerations == 1)

        // Index en cache (posé par le snapshot ou le lot précédent) : aucune énumération.
        _ = fixture.writer.setFrames(updates, generation: 2)
        #expect(fixture.io.enumerations == 1)

        // Fenêtre plus récente que l'index : une seule nouvelle énumération pour ce pid.
        fixture.io.windows[54] = index(pid: 54, ids: [541, 542, 543])
        _ = fixture.writer.setFrames(updates + [
            WindowFrameUpdate(window: window(543, pid: 54), frame: CGRect(x: 0, y: 0, width: 200, height: 200)),
        ], generation: 3)
        #expect(fixture.io.enumerations == 2)

        // Élément devenu invalide : l'index du pid est vidé.
        fixture.io.setErrors[kAXSizeAttribute] = .invalidUIElement
        _ = fixture.writer.setFrames(updates, generation: 4)
        #expect(fixture.cache.windows(for: 54) == nil)
    }

    @Test
    func eachWriteIsRecordedWithTheGenerationPassedThroughTheProtocol() {
        let fixture = WriterFixture()
        fixture.io.windows[55] = index(pid: 55, ids: [551])
        let target = CGRect(x: 0, y: 0, width: 300, height: 200)
        let readBack = CGRect(x: 0, y: 0, width: 300, height: 190)
        fixture.io.readBack = readBack

        let writer: any WindowFrameWriting = fixture.writer
        _ = writer.setFrames([WindowFrameUpdate(window: window(551, pid: 55), frame: target)], generation: 7)
        _ = writer.setFrames([WindowFrameUpdate(window: window(551, pid: 55), frame: target)], generation: 7)

        let entry = fixture.frames.entry(for: 551)
        #expect(entry?.requested == target)
        #expect(entry?.readBack == readBack)
        #expect(entry?.generation == 7)
        #expect(entry?.writesInGeneration == 2)
        #expect(entry?.writtenAt == fixture.clock.now)
    }

    // MARK: - T213 : génération des écritures directes et budget au point commun

    @Test
    func directWritesCarryTheirGenerationAndDefaultToTheCurrentOne() {
        let fixture = WriterFixture()
        fixture.io.windows[57] = index(pid: 57, ids: [571])
        let target = CGRect(x: 0, y: 0, width: 300, height: 200)
        fixture.io.readBack = target
        let writer: any WindowFrameWriting = fixture.writer

        _ = writer.setFrame(target, of: window(571, pid: 57), generation: 41)
        #expect(fixture.frames.entry(for: 571)?.generation == 41)

        // Sans génération : la génération en cours, plus jamais 0.
        fixture.generations.next()
        let current = fixture.generations.next()
        _ = writer.setFrame(target, of: window(571, pid: 57))
        #expect(fixture.frames.entry(for: 571)?.generation == current)
        _ = writer.setFrames([WindowFrameUpdate(window: window(571, pid: 57), frame: target)])
        #expect(fixture.frames.entry(for: 571)?.generation == current)
        #expect(fixture.frames.entry(for: 571)?.writesInGeneration == 2)
    }

    @Test
    func writeBudgetIsEnforcedAtTheCommonWritePoint() {
        let fixture = WriterFixture()
        fixture.io.windows[58] = index(pid: 58, ids: [581])
        let target = CGRect(x: 0, y: 0, width: 300, height: 200)
        fixture.io.readBack = target
        let writer: any WindowFrameWriting = fixture.writer

        _ = writer.setFrames([WindowFrameUpdate(window: window(581, pid: 58), frame: target)], generation: 7)
        _ = writer.setFrame(target, of: window(581, pid: 58), generation: 7)
        let callsAtBudget = fixture.io.calls.count

        // Troisième écriture de la génération 7 : refusée sans aucun appel AX, par les deux chemins.
        #expect(writer.setFrame(target, of: window(581, pid: 58), generation: 7) == nil)
        #expect(writer.setFrames([WindowFrameUpdate(window: window(581, pid: 58), frame: target)], generation: 7)[WindowID(rawValue: 581)] == .some(nil))
        #expect(fixture.io.calls.count == callsAtBudget)
        #expect(fixture.frames.entry(for: 581)?.writesInGeneration == 2)

        // Nouvelle génération : nouveau budget.
        #expect(writer.setFrame(target, of: window(581, pid: 58), generation: 8) == target)
        #expect(fixture.frames.entry(for: 581)?.writesInGeneration == 1)
    }

    /// T222, A3 : la réparation des modes sans arbre écrit hors budget ; aucune tentative n'est refusée.
    @Test
    func outsideBudgetGenerationIsNeverRefused() {
        let fixture = WriterFixture()
        fixture.io.windows[57] = index(pid: 57, ids: [571])
        let target = CGRect(x: 0, y: 0, width: 300, height: 200)
        fixture.io.readBack = target
        let writer: any WindowFrameWriting = fixture.writer

        for _ in 0..<4 {
            #expect(writer.setFrame(target, of: window(571, pid: 57), generation: PlacementGeneration.outsideBudget) == target)
        }
        #expect(fixture.frames.entry(for: 571)?.writesInGeneration == 4)
        #expect(!fixture.frames.isOverBudget(windowID: 571, generation: PlacementGeneration.outsideBudget))
    }

    @Test
    func failedAttemptsAfterTheAXCallCountTowardsTheBudget() {
        let fixture = WriterFixture()
        fixture.io.windows[59] = index(pid: 59, ids: [591])
        fixture.io.nativeFullscreen = false
        // Position refusée (pas un délai dépassé, qui mettrait l'application en quarantaine).
        fixture.io.setErrors[kAXPositionAttribute] = .failure
        let target = CGRect(x: 0, y: 0, width: 300, height: 200)
        let writer: any WindowFrameWriting = fixture.writer

        #expect(writer.setFrame(target, of: window(591, pid: 59), generation: 9) == nil)
        #expect(writer.setFrame(target, of: window(591, pid: 59), generation: 9) == nil)
        #expect(fixture.frames.entry(for: 591)?.writesInGeneration == 2)
        #expect(fixture.frames.entry(for: 591)?.readBack == nil)
        #expect(fixture.frames.entry(for: 591)?.axResultCodes == [
            "nativeFullscreen": AXError.success.rawValue,
            "sizeBefore": AXError.success.rawValue,
            "position": AXError.failure.rawValue,
        ])
        #expect(fixture.frames.isOverBudget(windowID: 591, generation: 9))

        let writesBefore = fixture.io.frameWrites.count
        #expect(writer.setFrame(target, of: window(591, pid: 59), generation: 9) == nil)
        #expect(fixture.io.frameWrites.count == writesBefore)
    }
}

@Suite("Spec062 écriture et sonde")
struct Spec062AXTests {
    /// Garer une fenêtre : une seule écriture, la position ; la taille n’est jamais touchée.
    @Test(arguments: [false, true])
    func preservesSizeWritesPositionOnly(positionFirst: Bool) {
        let fixture = WriterFixture()
        fixture.io.windows[62] = index(pid: 62, ids: [621])
        fixture.io.nativeFullscreen = false
        let update = WindowFrameUpdate(window: window(621, pid: 62), frame: CGRect(x: 5351, y: 100, width: 449, height: 258), preservesSize: true, positionsBeforeResizing: positionFirst)
        _ = fixture.writer.setFrames([update], generation: 1)
        #expect(fixture.io.frameWrites == ["set AXPosition"])
        #expect(fixture.frames.entry(for: 621)?.axResultCodes?["sizeBefore"] == nil)
    }

    /// Signature mesurée le 24 octobre 2026 : fenêtres du Dock de niveau 18 sur tout un écran.
    @Test
    func missionControlIsRecognisedFromDockWindows() {
        func dock(layer: Int, _ rect: CGRect, owner: String = "Dock") -> [String: Any] {
            [kCGWindowOwnerName as String: owner, kCGWindowLayer as String: layer,
             kCGWindowBounds as String: rect.dictionaryRepresentation as NSDictionary]
        }
        let wallpaper = dock(layer: -2_147_483_624, CGRect(x: 0, y: 0, width: 1512, height: 982))
        let dockBar = dock(layer: 20, CGRect(x: 400, y: 900, width: 700, height: 80))
        #expect(!MissionControlProbe.isActive(in: [wallpaper, dockBar]))
        #expect(MissionControlProbe.isActive(in: [wallpaper, dock(layer: 18, CGRect(x: 1512, y: -797, width: 3840, height: 2160))]))
        #expect(!MissionControlProbe.isActive(in: [dock(layer: 18, CGRect(x: 0, y: 0, width: 1512, height: 982), owner: "Finder")]))
    }
}

@Suite
struct WrittenFrameRegistryTests {
    private let requested = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let start = Date(timeIntervalSince1970: 2_000)

    @Test
    func diagnosticsBelongToTheirAttemptAndDoNotCarryIntoTheNextGeneration() {
        let registry = WrittenFrameRegistry()
        let codes = ["position": AXError.failure.rawValue]
        registry.record(
            windowID: 1, requested: requested, readBack: nil, generation: 1, at: start,
            axResultCodes: codes, nativeFullscreenReading: false
        )
        #expect(registry.entry(for: 1)?.axResultCodes == codes)
        #expect(registry.entry(for: 1)?.nativeFullscreenReading == false)
        #expect(registry.entry(for: 1)?.writesInGeneration == 1)

        registry.record(windowID: 1, requested: requested, readBack: requested, generation: 2, at: start)
        #expect(registry.entry(for: 1)?.axResultCodes == nil)
        #expect(registry.entry(for: 1)?.nativeFullscreenReading == nil)
        #expect(registry.entry(for: 1)?.writesInGeneration == 1)
    }

    /// SPEC-062 : une écriture sans relecture (iTerm2, −25204) n’a reçu aucune réponse de l’application ;
    /// l’ancienne frame encore observée est un écart à reprendre, pas une réponse à accepter.
    @Test
    func writeWithoutReadBackIsNotAnApplicationResponse() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 7, requested: requested, readBack: nil, generation: 1, at: start,
                        axResultCodes: ["sizeBefore": -25204], nativeFullscreenReading: false)
        let stale = CGRect(x: 5351, y: 943, width: 276, height: 158)
        #expect(registry.classify(windowID: 7, observed: stale, now: start.addingTimeInterval(0.2)) == .external)
        #expect(registry.classify(windowID: 7, observed: requested, now: start.addingTimeInterval(0.2)) == .echo)
    }

    @Test
    func classifiesEchoAppResponseAndExternalChange() {
        let registry = WrittenFrameRegistry()
        let readBack = CGRect(x: 0, y: 0, width: 800, height: 583)
        registry.record(windowID: 1, requested: requested, readBack: readBack, generation: 1, at: start)

        // Écho : frame demandée ou relue, à frameMatch près, sans limite de temps.
        #expect(registry.classify(windowID: 1, observed: requested.offsetBy(dx: 2, dy: -1), now: start) == .echo)
        #expect(registry.classify(windowID: 1, observed: readBack, now: start.addingTimeInterval(60)) == .echo)
        // Réponse de l'application : différente, moins de 1 s après l'écriture.
        let other = CGRect(x: 0, y: 0, width: 760, height: 600)
        #expect(registry.classify(windowID: 1, observed: other, now: start.addingTimeInterval(0.5)) == .appResponse)
        // Changement externe : au-delà, ou sans écriture connue.
        #expect(registry.classify(windowID: 1, observed: other, now: start.addingTimeInterval(1.5)) == .external)
        #expect(registry.classify(windowID: 2, observed: other, now: start) == .external)
    }

    @Test
    func expiredHistoryLeavesOnlyTheLastWriteAsAnEcho() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: requested, readBack: requested, generation: 1, at: start)
        let moved = requested.offsetBy(dx: 400, dy: 0)
        registry.record(windowID: 1, requested: moved, readBack: moved, generation: 2, at: start.addingTimeInterval(5))

        #expect(registry.classify(windowID: 1, observed: moved, now: start.addingTimeInterval(10)) == .echo)
        #expect(registry.classify(windowID: 1, observed: requested, now: start.addingTimeInterval(10)) == .external)
    }

    @Test
    func acceptedFrameIsTiedToTheGenerationAndDroppedByANewOne() {
        let registry = WrittenFrameRegistry()
        let accepted = CGRect(x: 0, y: 0, width: 900, height: 600)
        registry.record(windowID: 1, requested: requested, readBack: requested, generation: 1, at: start)
        registry.accept(windowID: 1, frame: accepted)
        registry.record(windowID: 1, requested: requested, readBack: requested, generation: 1, at: start)

        #expect(registry.entry(for: 1)?.accepted == accepted)
        #expect(registry.entry(for: 1)?.writesInGeneration == 2)
        #expect(registry.classify(windowID: 1, observed: accepted, now: start.addingTimeInterval(30)) == .echo)

        registry.record(windowID: 1, requested: requested, readBack: requested, generation: 2, at: start)
        #expect(registry.entry(for: 1)?.accepted == nil)
        #expect(registry.entry(for: 1)?.writesInGeneration == 1)
        #expect(registry.classify(windowID: 1, observed: accepted, now: start.addingTimeInterval(30)) == .external)
    }

    @Test
    func echoOfTheReadBackConfirmsAPendingRefusal() {
        let registry = WrittenFrameRegistry()
        let clamped = CGRect(x: 0, y: 0, width: 800, height: 650)
        registry.record(windowID: 1, requested: requested, readBack: clamped, generation: 3, at: start)
        registry.record(windowID: 2, requested: requested, readBack: requested, generation: 3, at: start)
        #expect(registry.pendingRefusals() == [1])

        // Une observation différente de la relecture ne confirme rien.
        #expect(!registry.confirmRefusal(windowID: 1, observed: requested.insetBy(dx: 50, dy: 50), at: start))
        let confirmedAt = start.addingTimeInterval(0.1)
        #expect(registry.confirmRefusal(windowID: 1, observed: clamped, at: confirmedAt))
        #expect(registry.entry(for: 1)?.refusalConfirmedAt == confirmedAt)
        #expect(registry.pendingRefusals().isEmpty)

        // Une nouvelle écriture attend sa propre confirmation.
        registry.record(windowID: 1, requested: requested, readBack: clamped, generation: 3, at: start)
        #expect(registry.pendingRefusals() == [1])
        // L'application finit par accepter la frame demandée : plus de refus en attente.
        #expect(!registry.confirmRefusal(windowID: 1, observed: requested, at: confirmedAt))
        #expect(registry.pendingRefusals().isEmpty)
    }

    @Test
    func forgetDropsTheWindow() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: requested, readBack: nil, generation: 0, at: start)
        registry.forget(windowID: 1)
        #expect(registry.entry(for: 1) == nil)
    }
}

@Suite
@MainActor
struct AXWindowEventObserverDispatchTests {
    @Test
    func echoMoveIsAbsorbedButExternalMoveAndOtherEventsAreForwarded() {
        let registry = WrittenFrameRegistry()
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let now = Date()
        registry.record(windowID: 7, requested: frame, readBack: frame, generation: 1, at: now.addingTimeInterval(-5))
        var received: [AXWindowEvent] = []
        let observer = AXWindowEventObserver(writtenFrames: registry, mouseButtonsPressed: { false }) { received.append($0) }

        let moved = AXWindowEvent(name: kAXWindowMovedNotification as String, pid: 3, windowID: 7)
        let resized = AXWindowEvent(name: kAXWindowResizedNotification as String, pid: 3, windowID: 7)
        observer.dispatch(moved, observedFrame: frame.offsetBy(dx: 1, dy: 0), now: now)
        observer.dispatch(resized, observedFrame: frame, now: now)
        #expect(received.isEmpty)

        observer.dispatch(moved, observedFrame: frame.offsetBy(dx: 300, dy: 0), now: now)
        observer.dispatch(moved, observedFrame: nil, now: now)
        let created = AXWindowEvent(name: kAXWindowCreatedNotification as String, pid: 3, windowID: 7)
        observer.dispatch(created, observedFrame: frame, now: now)
        #expect(received.count == 3)
        #expect(received.last == created)
    }

    @Test
    func absorbedEchoOfTheReadBackConfirmsTheRefusal() {
        let registry = WrittenFrameRegistry()
        let requested = CGRect(x: 0, y: 0, width: 800, height: 600)
        let clamped = CGRect(x: 0, y: 0, width: 800, height: 650)
        let now = Date()
        registry.record(windowID: 8, requested: requested, readBack: clamped, generation: 1, at: now)
        var received: [AXWindowEvent] = []
        let observer = AXWindowEventObserver(writtenFrames: registry, mouseButtonsPressed: { false }) { received.append($0) }

        let resized = AXWindowEvent(name: kAXWindowResizedNotification as String, pid: 3, windowID: 8)
        observer.dispatch(resized, observedFrame: clamped, now: now.addingTimeInterval(0.05))
        #expect(received.isEmpty)
        #expect(registry.entry(for: 8)?.refusalConfirmedAt != nil)
    }

    @Test
    func legacyCallbackReceivesNamesOnly() {
        var names: [String] = []
        let observer = AXWindowEventObserver(onWindowEvent: { names.append($0) })
        observer.dispatch(AXWindowEvent(name: "AXWindowCreated", pid: 1, windowID: nil), observedFrame: nil, now: Date())
        #expect(names == ["AXWindowCreated"])
    }
}

@Suite
struct AXCacheInvalidationTests {
    @Test
    func attributeCacheIsInvalidatedPerPid() {
        let clock = ManualClock()
        let cache = AXAttributeCache(now: { clock.now })
        let attributes = AXWindowAttributes(
            stable: AXStableWindowAttributes(role: "AXWindow", subrole: "AXStandardWindow"),
            volatile: AXVolatileWindowAttributes()
        )
        for _ in 0..<2 {
            cache.record(attributes, for: 1, pid: 10, stableIsFresh: true)
            cache.record(attributes, for: 2, pid: 11, stableIsFresh: true)
            clock.advance(1)
        }
        cache.invalidate(pid: 10)
        #expect(cache.stableAttributes(for: 1, ttl: 600) == nil)
        #expect(cache.stableAttributes(for: 2, ttl: 600) != nil)
    }

    @Test
    func windowIndexReplaceAllDropsAbsentApplications() {
        let cache = AXWindowIndexCache()
        cache.store(index(pid: 60, ids: [601]))
        cache.replaceAll(with: [index(pid: 61, ids: [611])])
        #expect(cache.windows(for: 60) == nil)
        #expect(cache.windows(for: 61)?.element(id: 611) != nil)
        cache.invalidate(pid: 61)
        #expect(cache.windows(for: 61) == nil)
    }
}

@Suite
struct SpaceProbeTests {
    private let uuid = "AAAAAAAA-0000-4000-8000-000000000001"

    @Test
    func parsesCurrentSpaceOfEachDisplay() {
        let other = "11111111-2222-3333-4444-555555555555"
        let twoDisplays: [[String: Any]] = [
            ["Display Identifier": other, "Current Space": ["type": 0, "ManagedSpaceID": 3]],
            ["Display Identifier": uuid, "Current Space": ["type": 4, "ManagedSpaceID": 9]],
        ]
        // Deux écrans : bureau utilisateur sur l'un, plein écran sur l'autre.
        #expect(SpaceProbe.parse(twoDisplays, displayUUID: other, mainDisplayUUID: nil) == true)
        #expect(SpaceProbe.parse(twoDisplays, displayUUID: uuid, mainDisplayUUID: nil) == false)
        #expect(SpaceProbe.parse(twoDisplays, displayUUID: uuid.lowercased(), mainDisplayUUID: nil) == false)
        // Écran introuvable.
        #expect(SpaceProbe.parse(twoDisplays, displayUUID: "MISSING", mainDisplayUUID: nil) == nil)
    }

    @Test
    func mainIdentifierDesignatesOnlyTheMainDisplay() {
        let main: [[String: Any]] = [["Display Identifier": "Main", "Current Space": ["type": 0]]]
        #expect(SpaceProbe.parse(main, displayUUID: uuid, mainDisplayUUID: uuid) == true)
        #expect(SpaceProbe.parse(main, displayUUID: uuid, mainDisplayUUID: "OTHER") == nil)
        #expect(SpaceProbe.parse(main, displayUUID: uuid, mainDisplayUUID: nil) == nil)
    }

    @Test
    func incompleteDataGivesNil() {
        let cases: [[[String: Any]]] = [
            [],
            [["Display Identifier": uuid]],
            [["Display Identifier": uuid, "Current Space": "not a dictionary"]],
            [["Display Identifier": uuid, "Current Space": ["ManagedSpaceID": 3]]],
            [["Display Identifier": uuid, "Current Space": ["type": "0"]]],
            [["Current Space": ["type": 0]]],
        ]
        for displays in cases {
            #expect(SpaceProbe.parse(displays, displayUUID: uuid, mainDisplayUUID: uuid) == nil)
        }
    }

    @Test
    func liveProbeAnswersOrReturnsNilWithoutCrashing() {
        // Écran principal réel : une valeur si SkyLight expose le symbole, nil sinon.
        let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID()).map {
            CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
        } ?? uuid
        let answer = SpaceProbe.isUserSpaceActive(displayUUID: uuid)
        #expect(answer == true || answer == false || answer == nil)
    }
}

@Suite struct MinimizedFocus040Tests {
    @Test func restoresMinimizedWindowBeforeRaisingIt() {
        let fixture = WriterFixture()
        let pid: pid_t = 9_999_999
        fixture.io.windows[pid] = index(pid: pid, ids: [501])
        fixture.io.minimized = true
        #expect(fixture.writer.focus(window(501, pid: pid)))
        let writes = fixture.io.calls.filter { $0.hasPrefix("set ") || $0.hasPrefix("action ") }
        #expect(writes == ["set AXMinimized", "set AXFrontmost", "set AXFocusedWindow", "action AXRaise"])
    }
}

extension MinimizedFocus040Tests {
    @Test(arguments: [false, true])
    func visibleOrUnsupportedWindowsAreNotRestored(unsupported: Bool) {
        let fixture = WriterFixture()
        let pid: pid_t = 9_999_999
        fixture.io.windows[pid] = index(pid: pid, ids: [501])
        fixture.io.minimized = unsupported ? nil : false
        #expect(fixture.writer.focus(window(501, pid: pid)))
        #expect(!fixture.io.calls.contains("set AXMinimized"))
        #expect(fixture.io.calls.contains("action AXRaise"))
    }

    @Test(arguments: [true, false])
    func failedRestorationDoesNotClaimFocusOrActivateApplication(readFailure: Bool) {
        let fixture = WriterFixture()
        let pid: pid_t = 9_999_999
        fixture.io.windows[pid] = index(pid: pid, ids: [501])
        fixture.io.minimized = true
        if readFailure { fixture.io.minimizedReadError = .cannotComplete }
        else { fixture.io.setErrors[kAXMinimizedAttribute] = .cannotComplete }
        let writer = fixture.writer
        #expect(!writer.focus(window(501, pid: pid)))
        #expect(!fixture.io.calls.contains("set AXFrontmost"))
        #expect(!fixture.io.calls.contains("action AXRaise"))
        let count = fixture.io.calls.count
        #expect(!writer.focus(window(501, pid: pid)))
        #expect(fixture.io.calls.count == count, "une application en délai dépassé reste en quarantaine")
    }
}

extension MinimizedFocus040Tests {
    @Test(arguments: [AXError.failure, .notImplemented, .actionUnsupported, .illegalArgument])
    func optionalMinimizedReadFailurePreservesExistingFocus(error: AXError) {
        let fixture = WriterFixture()
        let pid: pid_t = 9_999_999
        fixture.io.windows[pid] = index(pid: pid, ids: [501])
        fixture.io.minimizedReadError = error
        #expect(fixture.writer.focus(window(501, pid: pid)))
        #expect(!fixture.io.calls.contains("set AXMinimized"))
        #expect(fixture.io.calls.contains("action AXRaise"))
    }

    @Test func raiseTimeoutStopsBeforeFocusConfirmationRead() {
        let fixture = WriterFixture()
        let pid: pid_t = 9_999_999
        fixture.io.windows[pid] = index(pid: pid, ids: [501])
        fixture.io.setErrors[kAXFocusedWindowAttribute] = .failure
        fixture.io.actionError = .cannotComplete
        #expect(!fixture.writer.focus(window(501, pid: pid)))
        #expect(fixture.io.calls.last == "action AXRaise")
        #expect(!fixture.io.calls.contains("get AXFocusedWindow"))
    }
}

private final class NSLockPermit142: @unchecked Sendable {
    private let lock = NSLock()
    private var current = true
    var isCurrent: Bool { lock.withLock { current } }
    func invalidate() { lock.withLock { current = false } }
}

extension AXWindowFrameWriterTests {
    @Test func spec147RejectedEarlyPositionKeepsLegacyFallbackAndBudget() {
        let f = WriterFixture()
        f.io.windows[50] = index(pid: 50, ids: [1])
        f.io.setErrors[kAXPositionAttribute] = .failure
        let target = CGRect(x: 4432, y: -759, width: 914, height: 1052)
        let result = f.writer.setFrames([WindowFrameUpdate(window: window(1, pid: 50), frame: target,
                                                         positionsBeforeResizing: true)], generation: 1)
        #expect(result[WindowID(rawValue: 1)]! == nil)
        #expect(f.io.frameWrites == ["set AXPosition", "set AXSize", "set AXPosition"])
        #expect(f.frames.entry(for: 1)?.writesInGeneration == 1)
        #expect(f.frames.entry(for: 1)?.axResultCodes?["positionBefore"] == AXError.failure.rawValue)
    }
    @Test func spec147RevocationAfterTheFirstMoveNeverReachesResize() {
        let f = WriterFixture()
        f.io.windows[50] = index(pid: 50, ids: [1])
        let generations = f.generations, expected = generations.current
        f.io.afterFrameWrite = { _ = generations.next() }
        _ = f.writer.setFrames([WindowFrameUpdate(window: window(1, pid: 50),
                frame: CGRect(x: 4432, y: -759, width: 914, height: 1052), positionsBeforeResizing: true)],
            generation: expected, isCurrent: { generations.current == expected })
        #expect(f.io.frameWrites == ["set AXPosition"])
    }
}
