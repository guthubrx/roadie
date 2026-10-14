import Foundation
import CoreGraphics
import RoadieCore
import RoadieAX
@testable import RoadieDaemon

let labels = TargetHintService.labels(count: 9, alphabet: "aaaaaaaaa")
print("REL-045 labels=\(labels.count) unique=\(Set(labels).count)")
precondition(labels.count == 9 && Set(labels).count == 1)
let display = DisplaySnapshot(id: DisplayID(rawValue: "probe"), index: 1, name: "Probe", frame: Rect(x: 0, y: 0, width: 900, height: 900), visibleFrame: Rect(x: 0, y: 0, width: 900, height: 900), isMain: true)
let cells = TargetGridService.cells(display: display, parentPath: "AAA", rows: 3, columns: 3, maxDepth: 3, alphabet: "asdfghjkl")
let resolved = TargetGridService.cell(display: display, path: cells[0].path, rows: 3, columns: 3, maxDepth: 3, alphabet: "asdfghjkl")
print("REL-048 cells=\(cells.count) path=\(cells[0].path) resolvable=\(resolved != nil)")
precondition(cells.count == 9 && resolved == nil)
let raw = """
[fx.rail.stage_labels]
enabled = true
[[rules]]
id = "disabled-terminal"
enabled = false
[rules.match]
app = "Terminal"
[rules.action]
floating = true
"""
let rail = RailSettings.load(raw: raw)
print("REL-049 configured=true actual=\(rail.stageLabel.enabled)")
precondition(!rail.stageLabel.enabled)
let screens = [CGRect(x: 0, y: 0, width: 800, height: 600), CGRect(x: 0, y: 600, width: 800, height: 800)]
let point = CGPoint(x: 120, y: 700)
let result = RoadieScreenCoordinate.nsPointToAX(point, screenFrames: screens, primaryHeight: 600)
print("MIN-008 y=\(result.y) expected=\(600-point.y)")
precondition(result == CGPoint(x: point.x, y: 600-point.y))
print("4 pure probes passed; no system event posted")
