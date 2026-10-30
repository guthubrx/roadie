import AppKit
import ApplicationServices
import Foundation
import RoadieAX
import RoadieCore

/// Zones des clics ordinaires (session 136) : un clic gauche dans la fenêtre d'une autre application devient une zone
/// des profils `zones`, photo comprise. Les clics envoyés par Roadie lui-même (recherche à l'écran, retour à une zone)
/// portent une marque et sont ignorés. Lecture d'accessibilité hors du fil principal.
@MainActor
public final class ZoneClickRecorder {
    /// Marque des clics envoyés par Roadie (`eventSourceUserData`).
    nonisolated static let roadieClickTag: Int64 = 0x524F_4144
    /// Au-delà, l'élément cliqué est trop grand pour être une zone (page web, tableur) : un rectangle autour du clic.
    nonisolated static let largestElement = CGSize(width: 600, height: 200)
    nonisolated static let clickBox = CGSize(width: 160, height: 44)

    private let events: EventLog
    private var monitor: Any?

    public init(events: EventLog = EventLog()) {
        self.events = events
    }

    public func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.clicked(event) }
        }
    }

    public func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func clicked(_ event: NSEvent) {
        let switcher = ConfigReloadService.shared.currentConfig().switcher
        // Une application peut avoir ses zones de clics même si la valeur globale est à 0 (session 140).
        guard switcher.zoneClicksPerWindow > 0 || switcher.zoneClicksPerApp.contains(where: { $0.count > 0 }), ZonePolicy.isUsed(switcher),
              let cgEvent = event.cgEvent, cgEvent.getIntegerValueField(.eventSourceUserData) != Self.roadieClickTag else { return }
        let point = cgEvent.location
        let events = events
        Task { @MainActor in
            guard let read = await Task.detached(priority: .utility, operation: { Self.read(at: point) }).value,
                  read.pid != ProcessInfo.processInfo.processIdentifier else { return }
            let app = NSRunningApplication(processIdentifier: read.pid)
            // Application interdite par le sens interdit d'une carte de zone (session 137).
            if let bundle = app?.bundleIdentifier,
               ConfigReloadService.shared.currentConfig().switcher.zoneClickExcludedBundles.contains(bundle) { return }
            // Nombre propre à l'application (session 140) : 0, aucune zone de clic pour elle.
            guard ZonePolicy.current.clicksPerWindow(bundleID: app?.bundleIdentifier ?? "", appName: app?.localizedName ?? "") > 0 else { return }
            let zone = Self.zone(click: point, element: read.elementFrame, window: read.windowFrame)
            let record = ZoneRecord(
                appName: app?.localizedName ?? "", bundleID: app?.bundleIdentifier ?? "", pid: read.pid, windowID: read.windowID,
                windowTitle: read.windowTitle,
                title: Self.title(read, appName: app?.localizedName ?? ""),
                relative: Rect(zone.offsetBy(dx: -read.windowFrame.minX, dy: -read.windowFrame.minY)),
                windowWidth: read.windowFrame.width, windowHeight: read.windowFrame.height, date: Date(), fromClick: true)
            ZoneRecorder.remember(record, element: zone == read.elementFrame ? read.element : nil, events: events)
        }
    }

    /// Zone d'un clic : l'élément cliqué s'il est assez petit et contient le clic, sinon un rectangle de
    /// `clickBox` autour du clic, gardé dans la fenêtre. Coordonnées de l'accessibilité. O(1).
    nonisolated static func zone(click: CGPoint, element: CGRect?, window: CGRect) -> CGRect {
        if let element, element.contains(click), element.width <= largestElement.width, element.height <= largestElement.height {
            return element
        }
        let box = CGRect(x: click.x - clickBox.width / 2, y: click.y - clickBox.height / 2, width: clickBox.width, height: clickBox.height)
        let x = min(max(box.minX, window.minX), max(window.minX, window.maxX - box.width))
        let y = min(max(box.minY, window.minY), max(window.minY, window.maxY - box.height))
        return CGRect(x: x, y: y, width: min(box.width, window.width), height: min(box.height, window.height))
    }

    /// Texte de la zone : celui de l'élément (titre, description, valeur), sinon « Clic dans <application> ». O(t).
    nonisolated static func title(_ read: ClickRead, appName: String) -> String {
        let label = ZoneRecord.label(title: read.title, searchText: [read.text, read.value].joined(separator: "\n"), subtitle: "")
        return label.isEmpty || (label.hasPrefix("AX") && !label.contains(" ")) ? tr("Clic dans \(appName)", "Click in \(appName)") : label
    }

    struct ClickRead: @unchecked Sendable {
        let element: AXUIElement
        let pid: pid_t
        let windowID: UInt32
        let windowTitle: String
        let windowFrame: CGRect
        let elementFrame: CGRect?
        let title: String
        let text: String
        let value: String
    }

    /// Élément sous le clic, sa fenêtre et ses textes ; nil hors d'une fenêtre connue. 0,3 s par appel au plus.
    nonisolated static func read(at point: CGPoint) -> ClickRead? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let element = hit else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let windowValue = attribute(element, kAXWindowAttribute), CFGetTypeID(windowValue) == AXUIElementGetTypeID(),
              case let window = windowValue as! AXUIElement,
              let windowID = axWindowElements(pid: pid).first(where: { CFEqual($0.value, window) })?.key,
              let windowFrame = frame(window) else { return nil }
        return ClickRead(element: element, pid: pid, windowID: windowID, windowTitle: string(window, kAXTitleAttribute),
                         windowFrame: windowFrame, elementFrame: frame(element), title: string(element, kAXTitleAttribute),
                         text: string(element, kAXDescriptionAttribute), value: string(element, kAXValueAttribute))
    }

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    nonisolated private static func string(_ element: AXUIElement, _ name: String) -> String {
        (attribute(element, name) as? String).map { $0.count > 200 ? String($0.prefix(200)) : $0 } ?? ""
    }

    nonisolated private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent),
              extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
