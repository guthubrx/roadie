import AppKit
import SwiftUI
import RoadieCore
import RoadieDaemon

@MainActor
public final class ControlCenterAppController: NSObject, NSMenuDelegate {
    private let stateProvider: () -> ControlCenterState
    private let eventLog: EventLog
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    public init(
        stateProvider: @escaping () -> ControlCenterState = { ControlCenterStateService().state() },
        eventLog: EventLog = EventLog()
    ) {
        self.stateProvider = stateProvider
        self.eventLog = eventLog
    }

    public func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Roadie") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "Roadie"
        }
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

    public func menuWillOpen(_ menu: NSMenu) {
        populate(menu)
    }

    public func makeMenuModel() -> ControlCenterMenuModel {
        ControlCenterMenuModel(state: stateProvider())
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        populate(menu)
        return menu
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        let model = makeMenuModel()
        for item in model.items {
            let selector = item.action == nil ? nil : #selector(handleMenuItem(_:))
            let menuItem = NSMenuItem(title: item.title, action: selector, keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item.action?.rawValue
            menuItem.isEnabled = item.isEnabled
            menu.addItem(menuItem)
        }
    }

    @objc private func handleMenuItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = ControlCenterMenuAction(rawValue: raw)
        else {
            return
        }
        perform(action)
        statusItem?.menu.map(populate)
    }

    private func perform(_ action: ControlCenterMenuAction) {
        switch action {
        case .openSettings:
            openSettings()
        case .reloadConfig:
            reloadConfig()
        case .reapplyLayout:
            reapplyLayout()
        case .revealConfig:
            reveal(path: RoadieConfigLoader.defaultConfigPath(), fallbackDirectory: true)
        case .revealState:
            reveal(path: stateDirectoryPath(), fallbackDirectory: true)
        case .openLogs:
            reveal(path: EventLog.defaultPath(), fallbackDirectory: true)
        case .runDoctor:
            runDoctor()
        case .quitSafely:
            NSApplication.shared.terminate(nil)
        }
    }

    private func openSettings() {
        let config = (try? RoadieConfigLoader.load()) ?? RoadieConfig()
        let view = SettingsWindowView(model: SettingsWindowModel(config: config))
        let window = settingsWindow ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Roadie"
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    private func reloadConfig() {
        let result = ConfigReloadService(eventLog: eventLog).reload()
        switch result.status {
        case .applied:
            showMessage("Config rechargee", detail: result.path)
        case .failedKeepingPrevious:
            showMessage("Config refusee", detail: result.error ?? "ancienne config conservee")
        case .idle, .validating:
            break
        }
    }

    private func reapplyLayout() {
        let config = (try? RoadieConfigLoader.load()) ?? RoadieConfig()
        let tick = LayoutMaintainer(events: eventLog, config: config).tick()
        showMessage("Layout reapplique", detail: "applied=\(tick.applied) failed=\(tick.failed)")
    }

    private func runDoctor() {
        let report = DaemonHealthService().run()
        let summary = report.checks.map { "\($0.name): \($0.level.rawValue) (\($0.message))" }.joined(separator: "\n")
        showMessage(report.failed ? "Doctor: probleme detecte" : "Doctor: OK", detail: summary)
    }

    private func reveal(path: String, fallbackDirectory: Bool) {
        let expanded = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if fallbackDirectory {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func stateDirectoryPath() -> String {
        URL(fileURLWithPath: NSString(string: RestoreSafetyService.defaultPath()).expandingTildeInPath)
            .deletingLastPathComponent()
            .path
    }

    private func showMessage(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .informational
        alert.runModal()
    }
}
