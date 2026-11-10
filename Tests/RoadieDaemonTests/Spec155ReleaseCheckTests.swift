import Foundation
import Testing
@testable import RoadieDaemon

/// `roadie update check` (spec 155, US10). Aucun test n'utilise le réseau.
@Suite(.serialized) struct Spec155ReleaseCheckTests {
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
    @Test func transportChecksHeadersAndAcceptsHTTP200() throws {
        ReleaseProtocol.state.configure(.http(200))
        let session = session()
        defer { session.invalidateAndCancel() }
        #expect(try ReleaseCheck.fetchLatestRelease(session: session).get() == Data("ok".utf8))
        let request = try #require(ReleaseProtocol.state.request())
        #expect(request.url?.host == "api.github.com")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "roadie-update-check")
        #expect(request.timeoutInterval == 5)
    }

    @Test func transportRejectsHTTP403AndReportsNetworkFailure() {
        for mode in [ReleaseProtocol.Mode.http(403), .offline] {
            ReleaseProtocol.state.configure(mode)
            let session = session()
            defer { session.invalidateAndCancel() }
            switch ReleaseCheck.fetchLatestRelease(session: session) {
            case .success: Issue.record("Une erreur réseau/HTTP ne doit pas être acceptée")
            case .failure(let error):
                if case .http = mode { #expect(String(describing: error) == "HTTP 403") }
                else { #expect((error as? URLError)?.code == .notConnectedToInternet) }
            }
        }
    }

    @Test func stalledTransportIsCancelledAtTheDeadline() {
        ReleaseProtocol.state.configure(.stalled)
        let session = session()
        defer { session.invalidateAndCancel() }
        let start = Date()
        let result = ReleaseCheck.fetchLatestRelease(timeout: 0.02, session: session)
        #expect(Date().timeIntervalSince(start) < 1.5)
        if case .failure(let error) = result {
            // URLSession peut expirer avant la garde externe ; les deux issues libèrent le transport.
            #expect(String(describing: error) == "timeout" || (error as? URLError)?.code == .timedOut)
        } else { Issue.record("Le transport bloqué doit expirer") }
        #expect(ReleaseProtocol.state.stopped.wait(timeout: .now() + 0.5) == .success)
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseProtocol.self]
        return URLSession(configuration: config)
    }

}

// Le protocole exerce la vraie dataTask URLSession ; aucun appel réseau ni état sans verrou.
private final class ReleaseProtocol: URLProtocol, @unchecked Sendable {
    enum Mode: Sendable { case http(Int), offline, stalled }
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var mode: Mode = .http(200)
        private var lastRequest: URLRequest?
        let stopped = DispatchSemaphore(value: 0)
        func configure(_ value: Mode) { lock.withLock { mode = value; lastRequest = nil } }
        func receive(_ request: URLRequest) -> Mode { lock.withLock { lastRequest = request; return mode } }
        func request() -> URLRequest? { lock.withLock { lastRequest } }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        switch Self.state.receive(request) {
        case .http(let code):
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("ok".utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .offline: client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .stalled: break
        }
    }
    override func stopLoading() { if request.timeoutInterval < 1 { Self.state.stopped.signal() } }
}
