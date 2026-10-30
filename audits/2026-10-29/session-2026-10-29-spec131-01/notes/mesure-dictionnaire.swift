import AppKit
import CoreServices
let words = ["chat", "chaton", "chatte", "chateau", "chatier", "chatouille", "chaud", "chauffe", "chaussure", "chauve"]
var times: [Double] = []
for round in 0..<3 {
    let start = Date()
    for word in words { _ = DCSCopyTextDefinition(nil, word as CFString, CFRange(location: 0, length: (word as NSString).length)) }
    let t1 = Date()
    _ = NSSpellChecker.shared.completions(forPartialWordRange: NSRange(location: 0, length: 4), in: "chat", language: nil, inSpellDocumentWithTag: 0)
    times.append(Date().timeIntervalSince(start) * 1000)
    print("round \(round): 10 definitions \(Int(t1.timeIntervalSince(start) * 1000)) ms, total \(Int(times.last!)) ms")
}
