import Foundation
func rss() -> Int { var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
  _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
  return Int(info.resident_size) / 1024 }
let before = rss()
let folder = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")
func plist(_ n: String) -> Any? { (try? Data(contentsOf: folder.appendingPathComponent(n))).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } }
struct Symbol { let name: String; let categories: [String]; let keywords: [String]; let release: String }
let start = Date()
let years = (plist("name_availability.plist") as? [String: Any])?["symbols"] as? [String: String] ?? [:]
let cats = plist("symbol_categories.plist") as? [String: [String]] ?? [:]
let search = plist("symbol_search.plist") as? [String: [String]] ?? [:]
let order = plist("symbol_order.plist") as? [String] ?? []
let symbols = order.filter { years[$0] != nil }.map { Symbol(name: $0, categories: cats[$0] ?? [], keywords: search[$0] ?? [], release: years[$0] ?? "") }
print("symboles \(symbols.count), lecture \(Int(Date().timeIntervalSince(start) * 1000)) ms, mémoire +\((rss() - before) / 1024) Mio")
