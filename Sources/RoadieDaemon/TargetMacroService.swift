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

    public init(
        t: Double,
        kind: TargetMacroEventKind,
        point: CGPointCodable? = nil,
        keyCode: Int? = nil,
        characters: String? = nil,
        modifiers: UInt64 = 0,
        scrollDeltaY: Int32? = nil,
        target: RoadieTarget? = nil,
        gridPath: String? = nil
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
        guard kill(status.pid, 0) == 0 else {
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

    public init(
        service: SnapshotService = SnapshotService(),
        config: TargetRecordConfig? = nil,
        gridConfig: TargetGridConfig? = nil
    ) {
        self.service = service
        self.config = config ?? service.effectiveConfig.experimental.targetRecord
        self.gridConfig = gridConfig ?? service.effectiveConfig.experimental.targetGrid
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
            let startedAt = Date()
            for event in recording.events {
                let targetTime = startedAt.addingTimeInterval(event.t)
                if targetTime > Date() {
                    Thread.sleep(forTimeInterval: targetTime.timeIntervalSinceNow)
                }
                replay(event)
            }
            return TargetActionResult(changed: true, message: "replayed \(name) events=\(recording.events.count)")
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

    private func replay(_ event: TargetMacroEvent) {
        if let target = event.target,
           target.kind == .appElement,
           event.kind == .mouseUp {
            _ = TargetHintService(service: service).activate(target.id, action: .click)
            return
        }
        switch event.kind {
        case .mouseDown:
            guard let point = event.point?.cgPoint else { return }
            postMouse(type: .leftMouseDown, point: point)
        case .mouseUp:
            guard let point = event.point?.cgPoint else { return }
            postMouse(type: .leftMouseUp, point: point)
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
            let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)
            scroll?.post(tap: .cghidEventTap)
        }
    }

    private func postMouse(type: CGEventType, point: CGPoint) {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        event?.post(tap: .cghidEventTap)
    }

    private func postKey(type: CGEventType, keyCode: CGKeyCode, modifiers: CGEventFlags) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: type == .keyDown)
        event?.flags = modifiers
        event?.post(tap: .cghidEventTap)
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
    let elapsed = Date().timeIntervalSince(box.startedAt)
    let point = event.location
    let modifiers = event.flags.rawValue
    switch type {
    case .leftMouseDown, .rightMouseDown:
        let context = box.targetContext.context(for: point, includeAXContext: box.includeAXContext)
        box.append(TargetMacroEvent(t: elapsed, kind: .mouseDown, point: CGPointCodable(point), modifiers: modifiers, target: context.0, gridPath: context.1))
    case .leftMouseUp, .rightMouseUp:
        let context = box.targetContext.context(for: point, includeAXContext: box.includeAXContext)
        box.append(TargetMacroEvent(t: elapsed, kind: .mouseUp, point: CGPointCodable(point), modifiers: modifiers, target: context.0, gridPath: context.1))
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
