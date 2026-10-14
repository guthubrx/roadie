import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import RoadieAX
import RoadieCore

public enum TargetMacroEventKind: String, Codable, Equatable, Sendable {
    case mouseDown = "mouse-down"
    case mouseUp = "mouse-up"
    case mouseMove = "mouse-move"
    case keyDown = "key-down"
    case keyUp = "key-up"
    case scroll
}

/// Bouton de souris d'un événement de macro (REL-025).
public enum TargetMacroMouseButton: String, Codable, Equatable, Sendable {
    case left
    case right
}

public struct TargetMacroEvent: Codable, Equatable, Sendable {
    public var t: Double
    public var kind: TargetMacroEventKind
    public var point: CGPointCodable?
    public var keyCode: Int?
    public var characters: String?
    public var modifiers: UInt64
    public var scrollDeltaY: Int32?
    public var target: RoadieTarget?
    public var gridPath: String?
    /// Absent des fichiers antérieurs à REL-025 : clic gauche.
    public var button: TargetMacroMouseButton?

    public init(
        t: Double,
        kind: TargetMacroEventKind,
        point: CGPointCodable? = nil,
        keyCode: Int? = nil,
        characters: String? = nil,
        modifiers: UInt64 = 0,
        scrollDeltaY: Int32? = nil,
        target: RoadieTarget? = nil,
        gridPath: String? = nil,
        button: TargetMacroMouseButton? = nil
    ) {
        self.t = t
        self.kind = kind
        self.point = point
        self.keyCode = keyCode
        self.characters = characters
        self.modifiers = modifiers
        self.scrollDeltaY = scrollDeltaY
        self.target = target
        self.gridPath = gridPath
        self.button = button
    }

    public var mouseButton: TargetMacroMouseButton {
        button ?? .left
    }
}

public struct TargetMacroRecording: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var name: String
    public var createdAt: Date
    public var durationSeconds: Double
    public var events: [TargetMacroEvent]

    public init(
        schemaVersion: Int = 1,
        name: String,
        createdAt: Date = Date(),
        durationSeconds: Double,
        events: [TargetMacroEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.events = events
    }
}

public struct TargetMacroListReport: Codable, Equatable, Sendable {
    public var directory: String
    public var names: [String]
}

public struct TargetRecordingStatus: Codable, Equatable, Sendable {
    public var name: String
    public var startedAt: Date
    public var pid: Int32
    public var outputPath: String

    public init(name: String, startedAt: Date, pid: Int32, outputPath: String) {
        self.name = name
        self.startedAt = startedAt
        self.pid = pid
        self.outputPath = outputPath
    }
}

public struct TargetRecordingStatusStore {
    public static let defaultURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".local/state/roadies/recording.json")

    private let url: URL
    private let manager: FileManager

    public init(url: URL = TargetRecordingStatusStore.defaultURL, manager: FileManager = .default) {
        self.url = url
        self.manager = manager
    }

    public static var directoryURL: URL {
        defaultURL.deletingLastPathComponent()
    }

    public func write(_ status: TargetRecordingStatus) throws {
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.roadie.encode(status)
        try data.write(to: url, options: .atomic)
    }

    public func activeStatus() -> TargetRecordingStatus? {
        guard let data = try? Data(contentsOf: url),
              let status = try? JSONDecoder.roadie.decode(TargetRecordingStatus.self, from: data)
        else { return nil }
        guard ProcessLiveness.isAlive(status.pid) else {
            try? manager.removeItem(at: url)
            return nil
        }
        return status
    }

    public func clear(pid: Int32? = nil) {
        if let pid,
           let data = try? Data(contentsOf: url),
           let status = try? JSONDecoder.roadie.decode(TargetRecordingStatus.self, from: data),
           status.pid != pid {
            return
        }
        try? manager.removeItem(at: url)
    }
}

public struct TargetMacroService {
    private let service: SnapshotService
    private let config: TargetRecordConfig
    private let gridConfig: TargetGridConfig
    private let manager = FileManager.default
    /// Points d'injection des tests (REL-024, REL-025, TEST-002) : émission des événements et clic
    /// sémantique d'une cible, sans CGEvent ni AX réels.
    private let postEvent: (CGEvent) -> Void
    private let activateTarget: (RoadieTarget, TargetActionVerb) -> TargetActionResult

    public init(
        service: SnapshotService = SnapshotService(),
        config: TargetRecordConfig? = nil,
        gridConfig: TargetGridConfig? = nil
    ) {
        self.init(service: service, config: config, gridConfig: gridConfig, postEvent: { $0.post(tap: .cghidEventTap) })
    }

    init(
        service: SnapshotService,
        config: TargetRecordConfig? = nil,
        gridConfig: TargetGridConfig? = nil,
        postEvent: @escaping (CGEvent) -> Void,
        activateTarget: ((RoadieTarget, TargetActionVerb) -> TargetActionResult)? = nil
    ) {
        self.service = service
        self.config = config ?? service.effectiveConfig.experimental.targetRecord
        self.gridConfig = gridConfig ?? service.effectiveConfig.experimental.targetGrid
        self.postEvent = postEvent
        self.activateTarget = activateTarget ?? { target, action in
            TargetHintService(service: service).activate(target.id, action: action)
        }
    }

    public func list() -> TargetMacroListReport {
        let directory = recordsDirectory()
        let names = ((try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
        return TargetMacroListReport(directory: directory.path, names: names)
    }

    public func inspect(_ name: String) throws -> TargetMacroRecording {
        let data = try Data(contentsOf: recordingURL(name))
        return try JSONDecoder.roadie.decode(TargetMacroRecording.self, from: data)
    }

    public func delete(_ name: String) throws -> TargetActionResult {
        try manager.removeItem(at: recordingURL(name))
        return TargetActionResult(changed: true, message: "record delete \(name)")
    }

    public func record(name: String, duration: Double? = nil, stopFilePath: String? = nil) -> TargetActionResult {
        guard config.enabled else {
            return TargetActionResult(changed: false, message: "target_record_disabled", error: "target_record_disabled")
        }
        guard AXIsProcessTrusted() else {
            return TargetActionResult(changed: false, message: "accessibility_denied", error: "accessibility_denied")
        }
        let safeName = sanitizedName(name)
        let durationSeconds = min(config.maxDurationSeconds, max(0.5, duration ?? config.defaultDurationSeconds))
        let capture = MacroCaptureBox(
            startedAt: Date(),
            maxEvents: config.maxEvents,
            includeMouseMoves: config.includeMouseMoves,
            includeKeyEvents: config.includeKeyEvents,
            includeAXContext: config.includeAXContext,
            recordTextInput: config.recordTextInput,
            targetContext: TargetMacroContext(service: service, gridConfig: gridConfig)
        )
        let mask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (config.includeMouseMoves ? (1 << CGEventType.mouseMoved.rawValue) : 0)
        let retainedCapture = Unmanaged.passRetained(capture)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: macroTapCallback,
            userInfo: retainedCapture.toOpaque()
        ) else {
            retainedCapture.release()
            return TargetActionResult(changed: false, message: "event_tap_failed", error: "event_tap_failed")
        }
        capture.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let outputURL = recordingURL(safeName)
        let statusStore = TargetRecordingStatusStore()
        try? manager.createDirectory(at: recordsDirectory(), withIntermediateDirectories: true)
        try? statusStore.write(TargetRecordingStatus(
            name: safeName,
            startedAt: capture.startedAt,
            pid: getpid(),
            outputPath: outputURL.path
        ))
        notifyRecording("Enregistrement macro demarre: \(safeName)")
        var finalNotification = "Enregistrement macro arrete: \(safeName)"
        defer {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            retainedCapture.release()
            if let stopFilePath {
                try? manager.removeItem(atPath: stopFilePath)
            }
            statusStore.clear(pid: getpid())
            notifyRecording(finalNotification)
        }
        let deadline = Date().addingTimeInterval(durationSeconds)
        while Date() < deadline {
            if let stopFilePath, manager.fileExists(atPath: stopFilePath) {
                break
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        let recording = TargetMacroRecording(name: safeName, durationSeconds: durationSeconds, events: capture.events)
        do {
            let data = try JSONEncoder.roadie.encode(recording)
            try data.write(to: outputURL, options: .atomic)
            finalNotification = "Enregistrement macro termine: \(safeName) (\(capture.events.count) events)"
            return TargetActionResult(changed: true, message: "recorded \(safeName) events=\(capture.events.count)")
        } catch {
            finalNotification = "Echec enregistrement macro: \(safeName)"
            return TargetActionResult(changed: false, message: "record write failed: \(error.localizedDescription)", error: "record_write_failed")
        }
    }

    public func replay(_ name: String) -> TargetActionResult {
        guard config.replayEnabled else {
            return TargetActionResult(changed: false, message: "target_replay_disabled", error: "target_replay_disabled")
        }
        do {
            let recording = try inspect(name)
            let fallbacks = replay(events: recording.events)
            let suffix = fallbacks > 0 ? " semantic_fallbacks=\(fallbacks)" : ""
            return TargetActionResult(changed: true, message: "replayed \(name) events=\(recording.events.count)\(suffix)")
        } catch {
            return TargetActionResult(changed: false, message: "replay failed: \(error.localizedDescription)", error: "replay_failed")
        }
    }

    public static func nearestTarget(at point: CGPoint, targets: [RoadieTarget]) -> RoadieTarget? {
        targets
            .filter { $0.frame?.cgRect.contains(point) == true }
            .sorted {
                let lhsArea = ($0.frame?.width ?? .greatestFiniteMagnitude) * ($0.frame?.height ?? .greatestFiniteMagnitude)
                let rhsArea = ($1.frame?.width ?? .greatestFiniteMagnitude) * ($1.frame?.height ?? .greatestFiniteMagnitude)
                return lhsArea < rhsArea
            }
            .first
    }

    /// Rejoue les événements à leur instant enregistré. Renvoie le nombre de clics sémantiques rejoués
    /// aux coordonnées faute de cible résolue. O(n * h), n = nombre d'événements, h = appuis bruts
    /// encore tenus (quelques-uns au plus).
    func replay(events: [TargetMacroEvent]) -> Int {
        let startedAt = Date()
        var fallbacks = 0
        // REL-038 : appuis bruts émis sans leur relâchement. Une capture tronquée (max_events, durée
        // écoulée) peut finir sur un appui ; il est relâché en fin de replay, du dernier au premier.
        var held: [TargetMacroEvent] = []
        defer {
            for var press in held.reversed() {
                press.kind = press.kind == .mouseDown ? .mouseUp : .keyUp
                replay(press)
            }
        }
        var index = 0
        while index < events.count {
            let event = events[index]
            let targetTime = startedAt.addingTimeInterval(event.t)
            if targetTime > Date() {
                Thread.sleep(forTimeInterval: targetTime.timeIntervalSinceNow)
            }
            // REL-024 : un clic complet sur une cible applicative est une unité, résolue avant toute
            // émission. Clic sémantique réussi : ni down ni up bruts. Échec : paire down/up aux
            // coordonnées enregistrées, le relâchement n'est jamais perdu. REL-025 : un geste sans
            // action sémantique fidèle (Maj-clic, Cmd-clic droit…) est rejoué en brut, drapeaux complets.
            if index + 1 < events.count, let target = Self.semanticClickTarget(down: event, up: events[index + 1]),
               let action = Self.semanticAction(for: event) {
                let result = activateTarget(target, action)
                if result.changed, result.error == nil {
                    index += 2
                    continue
                }
                fallbacks += 1
            }
            replay(event)
            Self.track(event, held: &held)
            index += 1
        }
        return fallbacks
    }

    /// Même bouton ou même touche : un relâchement libère l'appui correspondant (REL-038). O(h).
    private static func track(_ event: TargetMacroEvent, held: inout [TargetMacroEvent]) {
        let pairs: (TargetMacroEvent) -> Bool = { press in
            switch (press.kind, event.kind) {
            case (.mouseDown, .mouseDown), (.mouseDown, .mouseUp): press.mouseButton == event.mouseButton
            case (.keyDown, .keyDown), (.keyDown, .keyUp): press.keyCode == event.keyCode
            default: false
            }
        }
        switch event.kind {
        case .mouseDown where event.point != nil, .keyDown where event.keyCode != nil:
            held.removeAll(where: pairs)
            held.append(event)
        case .mouseUp where event.point != nil, .keyUp where event.keyCode != nil:
            held.removeAll(where: pairs)
        default:
            break
        }
    }

    /// Cible d'un clic complet : down puis up immédiat, même bouton, même cible applicative.
    static func semanticClickTarget(down: TargetMacroEvent, up: TargetMacroEvent) -> RoadieTarget? {
        guard down.kind == .mouseDown, up.kind == .mouseUp,
              down.mouseButton == up.mouseButton,
              let target = down.target, target.kind == .appElement,
              up.target?.id == target.id
        else { return nil }
        return target
    }

    /// Action sémantique fidèle au clic enregistré (REL-025) : clic, clic droit ou Commande-clic, sans
    /// autre modificateur. Nil pour toute autre combinaison (Maj, Option, Contrôle, Cmd-clic droit) :
    /// aucune action ne la représente, le replay la rejoue en brut. Les bits sans effet sur un clic
    /// (verrouillage majuscule, événement non fusionné) sont ignorés.
    static func semanticAction(for event: TargetMacroEvent) -> TargetActionVerb? {
        let modifiers = CGEventFlags(rawValue: event.modifiers)
            .intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
        switch (event.mouseButton, modifiers) {
        case (.left, []): return .click
        case (.right, []): return .rightClick
        case (.left, .maskCommand): return .commandClick
        default: return nil
        }
    }

    private func replay(_ event: TargetMacroEvent) {
        switch event.kind {
        case .mouseDown, .mouseUp:
            guard let point = event.point?.cgPoint else { return }
            postMouse(event, at: point)
        case .mouseMove:
            guard let point = event.point?.cgPoint else { return }
            CGDisplayMoveCursorToPoint(CGMainDisplayID(), point)
        case .keyDown:
            guard let code = event.keyCode else { return }
            postKey(type: .keyDown, keyCode: CGKeyCode(code), modifiers: CGEventFlags(rawValue: event.modifiers))
        case .keyUp:
            guard let code = event.keyCode else { return }
            postKey(type: .keyUp, keyCode: CGKeyCode(code), modifiers: CGEventFlags(rawValue: event.modifiers))
        case .scroll:
            guard let delta = event.scrollDeltaY else { return }
            if let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) {
                postEvent(scroll)
            }
        }
    }

    /// REL-025 : bouton et modificateurs enregistrés.
    private func postMouse(_ recorded: TargetMacroEvent, at point: CGPoint) {
        let isDown = recorded.kind == .mouseDown
        let type: CGEventType
        let button: CGMouseButton
        switch recorded.mouseButton {
        case .left:
            type = isDown ? .leftMouseDown : .leftMouseUp
            button = .left
        case .right:
            type = isDown ? .rightMouseDown : .rightMouseUp
            button = .right
        }
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { return }
        event.flags = CGEventFlags(rawValue: recorded.modifiers)
        postEvent(event)
    }

    private func postKey(type: CGEventType, keyCode: CGKeyCode, modifiers: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: type == .keyDown) else { return }
        event.flags = modifiers
        postEvent(event)
    }

    private func recordsDirectory() -> URL {
        let path = config.directory.replacingOccurrences(of: "~", with: NSHomeDirectory())
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func recordingURL(_ name: String) -> URL {
        recordsDirectory().appendingPathComponent(sanitizedName(name)).appendingPathExtension("json")
    }

    private func sanitizedName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return value.isEmpty ? "recording" : value
    }

    private func notifyRecording(_ message: String) {
        guard config.indicator.showsNotification else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \"\(message.applescriptEscaped)\" with title \"Roadie record\""]
        try? process.run()
    }
}

private extension String {
    var applescriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private final class MacroCaptureBox: @unchecked Sendable {
    let startedAt: Date
    let maxEvents: Int
    let includeMouseMoves: Bool
    let includeKeyEvents: Bool
    let includeAXContext: Bool
    let recordTextInput: Bool
    let targetContext: TargetMacroContext
    /// Tap à réactiver si macOS le désactive (timeout ou saisie utilisateur), SPEC-016.
    var tap: CFMachPort?
    var events: [TargetMacroEvent] = []

    init(
        startedAt: Date,
        maxEvents: Int,
        includeMouseMoves: Bool,
        includeKeyEvents: Bool,
        includeAXContext: Bool,
        recordTextInput: Bool,
        targetContext: TargetMacroContext
    ) {
        self.startedAt = startedAt
        self.maxEvents = maxEvents
        self.includeMouseMoves = includeMouseMoves
        self.includeKeyEvents = includeKeyEvents
        self.includeAXContext = includeAXContext
        self.recordTextInput = recordTextInput
        self.targetContext = targetContext
    }

    func append(_ event: TargetMacroEvent) {
        guard events.count < maxEvents else { return }
        events.append(event)
    }
}

private struct TargetMacroContext {
    let service: SnapshotService
    let gridConfig: TargetGridConfig

    func context(for point: CGPoint, includeAXContext: Bool) -> (RoadieTarget?, String?) {
        let snapshot = service.snapshot(followFocus: false)
        let display = snapshot.displays.first { $0.visibleFrame.cgRect.contains(point) }
        let target: RoadieTarget?
        if includeAXContext {
            target = TargetMacroService.nearestTarget(
                at: point,
                targets: TargetHintService(service: service).list(TargetQueryOptions(source: .all, includeAppTargets: true)).targets
            )
        } else {
            target = nil
        }
        let path = display.flatMap {
            TargetGridService.path(
                for: point,
                display: $0,
                rows: gridConfig.rows,
                columns: gridConfig.columns,
                maxDepth: gridConfig.maxDepth,
                alphabet: gridConfig.hintCharacters
            )
        }
        return (target, path)
    }
}

private func macroTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let box = Unmanaged<MacroCaptureBox>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = box.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    let elapsed = Date().timeIntervalSince(box.startedAt)
    let point = event.location
    let modifiers = event.flags.rawValue
    switch type {
    case .leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp:
        // REL-025 : le bouton est conservé avec le geste.
        let kind: TargetMacroEventKind = type == .leftMouseDown || type == .rightMouseDown ? .mouseDown : .mouseUp
        let button: TargetMacroMouseButton = type == .rightMouseDown || type == .rightMouseUp ? .right : .left
        let context = box.targetContext.context(for: point, includeAXContext: box.includeAXContext)
        box.append(TargetMacroEvent(t: elapsed, kind: kind, point: CGPointCodable(point), modifiers: modifiers, target: context.0, gridPath: context.1, button: button))
    case .mouseMoved:
        guard box.includeMouseMoves else { break }
        box.append(TargetMacroEvent(t: elapsed, kind: .mouseMove, point: CGPointCodable(point), modifiers: modifiers))
    case .keyDown, .keyUp:
        guard box.includeKeyEvents else { break }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let chars = box.recordTextInput ? event.keyboardString : nil
        box.append(TargetMacroEvent(t: elapsed, kind: type == .keyDown ? .keyDown : .keyUp, keyCode: keyCode, characters: chars, modifiers: modifiers))
    case .scrollWheel:
        let delta = Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        box.append(TargetMacroEvent(t: elapsed, kind: .scroll, point: CGPointCodable(point), modifiers: modifiers, scrollDeltaY: delta))
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

private extension CGEvent {
    var keyboardString: String? {
        var length = 0
        keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return nil }
        var chars = [UniChar](repeating: 0, count: length)
        keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: length)
    }
}

private extension JSONEncoder {
    static var roadie: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var roadie: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
