import AppKit
import Foundation
import Testing
@testable import RoadieDaemon

struct Spec087CalculatorTests {
    private let fr = Locale(identifier: "fr_FR")

    private func text(_ input: String) -> String? { LauncherCalculator.evaluate(input, locale: fr)?.text }

    @Test func priorityAssociativityAndSigns() {
        #expect(text("12*4,5") == "54")
        #expect(text("12*4.5") == "54")
        #expect(text("2+3*4") == "14")
        #expect(text("2^3^2") == "512")
        #expect(text("-(3+4)*2") == "-14")
        #expect(text("-2^2") == "-4")
        #expect(text("10-4-3") == "3")
        #expect(text("7 % 3") == "1")
        #expect(text("6 × 7") == "42")
        #expect(text("1 ÷ 4") == "0,25")
    }

    @Test func advancedFunctionsAfterEqualSign() {
        #expect(text("=sqrt(2)") == "1,41421356237")
        #expect(text("=2*pi") == "6,28318530718")
        #expect(text("=round(2,6)") == "3")
        #expect(text("sqrt(2)") == nil) // sans `=`, pas de fonction
        #expect(text("=foo(2)") == nil)
    }

    @Test func notACalculation() {
        for input in ["12", "-3", "12*", "1/0", "0/0", "1.2.3", "fire perso", "2 3", "(1+2", "=ln(-1)", "", "*", "e2"] {
            #expect(text(input) == nil, "\(input)")
        }
    }

    @Test func randomInputNeverCrashes() {
        var generator = SystemRandomNumberGenerator()
        let alphabet = Array("0123456789+-*/^%(),.=xsqrtpi ×÷e")
        for _ in 0..<10_000 {
            let length = Int.random(in: 0...14, using: &generator)
            let input = String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
            _ = LauncherCalculator.evaluate(input, locale: fr)
        }
    }

    @MainActor @Test func shiftDigitTypesInACalculation() throws {
        func key(_ code: UInt16) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0, windowNumber: 0,
                                          context: nil, characters: "1", charactersIgnoringModifiers: "&", isARepeat: false, keyCode: code))
        }
        let shift = LauncherPickModifier.shift.flags
        // Saisie vide ou de calcul : le chiffre s'écrit (AZERTY).
        #expect(SearchInputPanel.navigation(try key(18), pick: shift, text: "") == nil)
        #expect(SearchInputPanel.navigation(try key(18), pick: shift, text: "12*(4,5") == nil)
        // Calcul avancé : les lettres des fonctions n'empêchent pas d'écrire le chiffre.
        #expect(SearchInputPanel.navigation(try key(18), pick: shift, text: "=sqrt(") == nil)
        #expect(SearchInputPanel.navigation(try key(18), pick: shift, text: "=2*pi+") == nil)
        // Recherche ordinaire : Maj + 1 reste le raccourci de la première ligne.
        #expect(SearchInputPanel.navigation(try key(18), pick: shift, text: "fire")?.kind == .pick(1))
        // Commande pour les raccourcis : rien ne change.
        #expect(SearchInputPanel.navigation(try key(18), pick: .command, text: "") == nil)
    }
}
