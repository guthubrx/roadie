import Foundation

// Reproduction confinée dans la session d'audit. Aucun chemin personnel n'est utilisé.
let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let parent = base.appendingPathComponent("sandbox-parent", isDirectory: true)
let workflows = parent.appendingPathComponent("workflows", isDirectory: true)
let marker = parent.appendingPathComponent("donnees-a-preserver")
let manager = FileManager.default
try manager.createDirectory(at: workflows, withIntermediateDirectories: true)
try Data("temoin".utf8).write(to: marker)
let name = "..".replacingOccurrences(of: "/", with: "-")
let target = workflows.appendingPathComponent(name)
print("target=\(target.path)")
print("target_exists=\(manager.fileExists(atPath: target.path))")
do {
    try manager.removeItem(at: target)
    print("remove=success")
} catch {
    print("remove=error \(error)")
}
print("parent_exists=\(manager.fileExists(atPath: parent.path))")
print("marker_exists=\(manager.fileExists(atPath: marker.path))")
