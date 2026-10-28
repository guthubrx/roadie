import Testing
@testable import RoadieAX

struct Spec098WindowKeyFocusTests {
    @Test func recordCarriesKindAndWindowNumber() {
        let record = WindowKeyFocus.record(0x02, windowID: 0x0102_0304)
        #expect(record.count == 0xf8 && record[0x04] == 0xf8 && record[0x08] == 0x02 && record[0x3a] == 0x10)
        #expect(Array(record[0x3c..<0x40]) == [0x04, 0x03, 0x02, 0x01])
        #expect(record[0x20..<0x30].allSatisfy { $0 == 0xff })
        #expect(record[0x30..<0x3a].allSatisfy { $0 == 0 })
    }
}
