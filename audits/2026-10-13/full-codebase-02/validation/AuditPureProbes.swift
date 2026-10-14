import Foundation
import CoreGraphics
import RoadieCore
import RoadieTiler
@testable import RoadieDaemon

for message in ["stage create failed: already exists", "stage create demo: already exists", "stage create not visible: already exists"] {
    print("exit-code", CLICommandRouter.actionExitCode(changed: false, message: message), message)
}
let scope = StageScope(displayID: DisplayID(rawValue: "audit"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
let bounds = CGRect(x: 0, y: 0, width: 1000, height: 500)
let plan = LayoutPlanner.plan(LayoutRequest(scope: scope, mode: .bsp, container: bounds, windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)], innerGap: 1500))
for (id, frame) in plan.placements.sorted(by: { $0.key < $1.key }) {
    print("bsp-excessive-gap", id.rawValue, frame, "origin-outside", frame.minX > bounds.maxX || frame.minY > bounds.maxY)
}
let accepted = StageID(rawValue: String(Int.max))
print("stage-max-accepted", accepted.rawValue, "next-overflows", Int(accepted.rawValue)!.addingReportingOverflow(1).overflow)

let probeRoot = URL(fileURLWithPath: CommandLine.arguments[1])
let dragPath = probeRoot.appendingPathComponent("drag-activity").path
let writer = WindowDragActivity(path: dragPath)
let reader = WindowDragActivity(path: dragPath)
let instant = Date(timeIntervalSince1970: 1000)
writer.markActive(windowID: WindowID(rawValue: 1), now: instant, holdSeconds: 1.5)
print("drag-before-release", reader.isActive(now: instant.addingTimeInterval(0.1)))
writer.release(now: instant.addingTimeInterval(0.2))
print("drag-after-release", reader.isActive(now: instant.addingTimeInterval(0.3)))
let eventPath = probeRoot.appendingPathComponent("utf8-events.jsonl")
// La dernière tranche commence sur le deuxième octet de é; elle contient deux lignes finales valides.
let ending = "\nok1\nok2\n"
let payload = "prefix-é" + String(repeating: "x", count: 65536 - 1 - ending.utf8.count) + ending
try payload.write(to: eventPath, atomically: true, encoding: .utf8)
print("events-tail-utf8", EventLog(path: eventPath.path).tail(limit: 1))
