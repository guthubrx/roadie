import Foundation

// Même ordre d'opérations que l'ancien installateur, limité à un dossier synthétique.
let manager = FileManager.default
let sandbox = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).appendingPathComponent("repro-replacement-\(UUID().uuidString)")
defer { try? manager.removeItem(at: sandbox) }
let target = sandbox.appendingPathComponent("installed")
let missing = sandbox.appendingPathComponent("source-disparue")
try manager.createDirectory(at: target, withIntermediateDirectories: true)
let marker = target.appendingPathComponent("ancien")
try Data("conserver".utf8).write(to: marker)
try manager.removeItem(at: target)
do { try manager.moveItem(at: missing, to: target) }
catch { print("move_failed=true") }
print("old_preserved=\(manager.fileExists(atPath: marker.path))")
