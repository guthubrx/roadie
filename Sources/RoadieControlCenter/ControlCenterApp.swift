import AppKit
import RoadieCore
import RoadieDaemon

@MainActor
public final class ControlCenterAppController: NSObject {
    private let stateProvider: () -> ControlCenterState
    private let eventLog: EventLog
    private var statusItem: NSStatusItem?

    public init(
        stateProvider: @escaping () -> ControlCenterState = { ControlCenterStateService().state() },
        eventLog: EventLog = EventLog()
    ) {
        self.stateProvider = stateProvider
        self.eventLog = eventLog
    }

    public func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Roadie"
        item.menu = makeMenu()
        statusItem = item
        eventLog.append(RoadieEventEnvelope(
            id: "control_center_\(UUID().uuidString)",
            type: "control_center.opened",
            scope: .controlCenter,
            subject: AutomationSubject(kind: "control_center", id: "menu_bar"),
            cause: .controlCenter,
            payload: [:]
        ))
    }

    public func stop() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        self.statusItem = nil
    }

    public func makeMenuModel() -> ControlCenterMenuModel {
        ControlCenterMenuModel(state: stateProvider())
    }

    private func makeMenu() -> NSMenu {
        let model = makeMenuModel()
        let menu = NSMenu()
        for item in model.items {
            let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            menuItem.isEnabled = item.isEnabled
            menu.addItem(menuItem)
        }
        return menu
    }
}
