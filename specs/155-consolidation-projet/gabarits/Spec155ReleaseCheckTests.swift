import Foundation
import Testing
@testable import RoadieDaemon

/// `roadie update check` (spec 155, US10). Aucun test n'utilise le réseau.
@Suite struct Spec155ReleaseCheckTests {
    private func release(_ tag: String) -> Data {
        Data(#"{"tag_name":"\#(tag)","html_url":"https://example.invalid/\#(tag)","draft":false}"#.utf8)
    }

    @Test func versionsAreComparedAsNumbers() {
        #expect(ReleaseCheck.isNewer("v0.14.0", than: "0.13.0"))
        #expect(ReleaseCheck.isNewer("v1.0", than: "0.13.9"))
        #expect(!ReleaseCheck.isNewer("v0.13.0", than: "0.13.0"))
        #expect(!ReleaseCheck.isNewer("0.9.0", than: "0.13.0"))
        #expect(!ReleaseCheck.isNewer("0.14", than: "0.14.0"))
        // Seul le préfixe « v » est ignoré : « 5v » n'est pas un nombre et vaut 0.
        #expect(!ReleaseCheck.isNewer("0.13.5v", than: "0.13.0"))
    }

    @Test func aNewerReleaseIsAnnouncedWithItsAddress() {
        let outcome = ReleaseCheck.evaluate(current: "0.13.0") { .success(release("v0.14.0")) }
        #expect(outcome == ReleaseCheck.Outcome(
            exitCode: 0,
            stdout: "Nouvelle version disponible : v0.14.0 (installée : 0.13.0)\nhttps://example.invalid/v0.14.0",
            stderr: nil
        ))
    }

    @Test func theSameReleaseMeansUpToDate() {
        let outcome = ReleaseCheck.evaluate(current: "0.13.0") { .success(release("v0.13.0")) }
        #expect(outcome == ReleaseCheck.Outcome(exitCode: 0, stdout: "Roadie est à jour (0.13.0).", stderr: nil))
    }

    @Test func aNetworkFailureGivesCodeOneAndTheReason() {
        let outcome = ReleaseCheck.evaluate(current: "0.13.0") { .failure(ReleaseCheck.FetchError(description: "timeout")) }
        #expect(outcome == ReleaseCheck.Outcome(exitCode: 1, stdout: nil, stderr: "roadie: vérification impossible : timeout"))
    }

    @Test func anUnreadableAnswerGivesCodeOne() {
        let outcome = ReleaseCheck.evaluate(current: "0.13.0") { .success(Data("oops".utf8)) }
        #expect(outcome == ReleaseCheck.Outcome(exitCode: 1, stdout: nil, stderr: "roadie: vérification impossible : réponse illisible"))
    }
}
