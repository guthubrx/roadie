import CoreGraphics
import Foundation
import Testing
import RoadieAX

struct Spec068LastingRefusalTests {
    private let wide = CGRect(x: 150, y: 30, width: 1650, height: 1087)
    private let phone = CGRect(x: 150, y: 30, width: 471, height: 1086)

    private func refuse(_ registry: WrittenFrameRegistry, generation: UInt64, target: CGRect? = nil) {
        let requested = target ?? wide
        registry.record(windowID: 7, requested: requested, readBack: phone, generation: generation, at: Date())
        registry.accept(windowID: 7, frame: phone)
    }

    @Test func aRefusalRepeatedOverTwoGenerationsStopsTheRewrite() {
        let registry = WrittenFrameRegistry()
        refuse(registry, generation: 1)
        #expect(!registry.refusesLastingly(windowID: 7, target: wide, observed: phone))
        refuse(registry, generation: 1)
        #expect(!registry.refusesLastingly(windowID: 7, target: wide, observed: phone))
        refuse(registry, generation: 2)
        #expect(registry.refusesLastingly(windowID: 7, target: wide, observed: phone))
        // Autre cible ou autre cadre observé : on réessaie.
        #expect(!registry.refusesLastingly(windowID: 7, target: wide.insetBy(dx: 100, dy: 0), observed: phone))
        #expect(!registry.refusesLastingly(windowID: 7, target: wide, observed: phone.insetBy(dx: 50, dy: 0)))
    }

    @Test func anAcceptedWriteClearsTheLastingRefusal() {
        let registry = WrittenFrameRegistry()
        refuse(registry, generation: 1)
        refuse(registry, generation: 2)
        registry.record(windowID: 7, requested: wide, readBack: wide, generation: 3, at: Date())
        #expect(!registry.refusesLastingly(windowID: 7, target: wide, observed: phone))
        #expect(registry.entry(for: 7)?.lastingRefusal == nil)
    }

    @Test func aDifferentAnswerRestartsTheCount() {
        let registry = WrittenFrameRegistry()
        refuse(registry, generation: 1)
        registry.record(windowID: 7, requested: wide, readBack: phone, generation: 2, at: Date())
        registry.accept(windowID: 7, frame: phone.insetBy(dx: 20, dy: 0))
        #expect(registry.entry(for: 7)?.lastingRefusal?.generations == 1)
    }
}
