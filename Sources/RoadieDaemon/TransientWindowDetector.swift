import Foundation
import RoadieAX
import RoadieCore

public struct TransientWindowDetector {
    private let service: SnapshotService
    private let frameWriter: any WindowFrameWriting
    private let events: EventLog
    private let now: () -> Date

    public init(
        service: SnapshotService = SnapshotService(),
        frameWriter: any WindowFrameWriting = AXWindowFrameWriter(),
        events: EventLog = EventLog(),
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.frameWriter = frameWriter
        self.events = events
        self.now = now
    }

    public func status() -> TransientWindowState {
        status(in: service.snapshot())
    }

    public func status(in snapshot: DaemonSnapshot) -> TransientWindowState {
        for entry in snapshot.windows {
            guard let reason = reason(for: entry.window) else { continue }
            return TransientWindowState(
                isActive: true,
                reason: reason,
                ownerBundleID: entry.window.bundleID,
                recoverable: !isVisible(entry.window.frame, in: snapshot.displays),
                frame: entry.window.frame,
                detectedAt: now()
            )
        }
        return TransientWindowState(isActive: false)
    }

    @discardableResult
    public func recoverIfNeeded() -> Bool {
        let snapshot = service.snapshot()
        guard let entry = snapshot.windows.first(where: { reason(for: $0.window) != nil && !isVisible($0.window.frame, in: snapshot.displays) }),
              let target = snapshot.displays.first?.visibleFrame
        else { return false }
        let recovered = frameWriter.setFrame(target.cgRect, of: entry.window) != nil
        events.append(envelope(
            recovered ? "transient.recovery_attempted" : "transient.recovery_failed",
            window: entry.window,
            payload: ["recovered": .bool(recovered)]
        ))
        return recovered
    }

    public func emitStatus(_ state: TransientWindowState) {
        guard state.isActive else {
            events.append(RoadieEventEnvelope(
                id: "transient_\(UUID().uuidString)",
                type: "transient.cleared",
                scope: .transient,
                subject: AutomationSubject(kind: "transient", id: "active"),
                cause: .transient
            ))
            return
        }
        events.append(RoadieEventEnvelope(
            id: "transient_\(UUID().uuidString)",
            type: "transient.detected",
            scope: .transient,
            subject: AutomationSubject(kind: "bundle", id: state.ownerBundleID ?? "unknown"),
            cause: .transient,
            payload: [
                "reason": .string(state.reason?.rawValue ?? "unknown"),
                "recoverable": .bool(state.recoverable)
            ]
        ))
    }

    private func reason(for window: WindowSnapshot) -> TransientWindowReason? {
        let role = (window.role ?? "").lowercased()
        let subrole = (window.subrole ?? "").lowercased()
        let text = "\(window.bundleID) \(window.appName) \(window.title)".lowercased()
        if subrole.contains("sheet") { return .sheet }
        if subrole.contains("dialog") || role.contains("dialog") { return .dialog }
        if subrole.contains("popover") || role.contains("popover") { return .popover }
        if role.contains("menu") || subrole.contains("menu") { return .menu }
        if text.contains("open") && text.contains("save") { return .openSavePanel }
        if text.contains("com.apple.appkit.xpc.openandsavepanelservice") { return .openSavePanel }
        if !role.isEmpty && role != "axwindow" { return .unknownTransient }
        return nil
    }

    private func envelope(_ type: String, window: WindowSnapshot, payload: [String: AutomationPayload]) -> RoadieEventEnvelope {
        RoadieEventEnvelope(
            id: "transient_\(UUID().uuidString)",
            type: type,
            scope: .transient,
            subject: AutomationSubject(kind: "window", id: String(window.id.rawValue)),
            cause: .transient,
            payload: payload
        )
    }

    private func isVisible(_ frame: Rect, in displays: [DisplaySnapshot]) -> Bool {
        displays.contains { $0.visibleFrame.cgRect.intersects(frame.cgRect) }
    }
}
