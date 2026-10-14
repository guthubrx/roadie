import Foundation
import CoreGraphics
import RoadieCore
import RoadieAX
import RoadieTiler
@testable import RoadieDaemon

let root = URL(fileURLWithPath: CommandLine.arguments[1])
for (name, value) in [("bool", "true"), ("literal", "'30'")] {
    let file = root.appendingPathComponent("config-\(name).toml")
    try "[tiling]\ngaps_inner = \(value)\n".write(to: file, atomically: true, encoding: .utf8)
    let report = RoadieConfigLoader.validate(path: file.path)
    let config = try RoadieConfigLoader.load(from: file.path)
    print("bad_numeric_type=\(name) validation_has_errors=\(report.hasErrors) decoded_gap=\(config.tiling.gapsInner)")
}
let scope = StageScope(displayID: DisplayID(rawValue: "test"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
let request = LayoutRequest(scope: scope, mode: .masterStack, container: CGRect(x: 0, y: 0, width: 1000, height: 500), windowIDs: [1,2,3].map { WindowID(rawValue: UInt32($0)) }, innerGap: 600)
for (id, frame) in LayoutPlanner.plan(request).placements.sorted(by: { $0.key < $1.key }) {
    print("large_gap wid=\(id.rawValue) frame=\(frame) inside=\(request.container.contains(frame))")
}
let rect = Rect(x: -3840, y: 0, width: 3840, height: 2160)
let display = DisplaySnapshot(id: DisplayID(rawValue: "left"), index: 2, name: "Left", frame: rect, visibleFrame: rect, isMain: false)
let frame = CGRect(x: -3000, y: 100, width: 1000, height: 500)
print("visible_left_window=\(rect.cgRect.contains(frame)) classified_hidden=\(HiddenWindowPlacement.isHiddenOrLegacyOffscreen(frame, in: [display]))")
let corruptFile = root.appendingPathComponent("corrupt-rail.json")
try "INVALID JSON".write(to: corruptFile, atomically: true, encoding: .utf8)
let rail = RailRuntimeStateStore(path: corruptFile.path)
print("corrupt_persistence claimed_pin=\(rail.setPinned(true).isPinned) readback_pin=\(rail.load().isPinned)")
let reloadFile = root.appendingPathComponent("reload-alternate.toml")
try "[tiling]\ngaps_inner = 31\n".write(to: reloadFile, atomically: true, encoding: .utf8)
let initialPath = ConfigReloadService.shared.state.activePath
let response = MainActor.assumeIsolated { CLICommandRouter().run(["config", "reload", "--config", reloadFile.path]) }
print("config_reload exit=\(response.exitCode) stdout=\(response.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) shared_path_unchanged=\(initialPath == ConfigReloadService.shared.state.activePath)")
