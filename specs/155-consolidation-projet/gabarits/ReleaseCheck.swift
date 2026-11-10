import Foundation
import RoadieCore

/// Dernière version publiée de Roadie (`roadie update check`, ADR 031).
/// Seul appel réseau du produit : à la demande, dans le processus `roadie`, jamais dans le daemon.
enum ReleaseCheck {
    struct Outcome: Equatable {
        let exitCode: Int32
        let stdout: String?
        let stderr: String?
    }

    struct LatestRelease: Decodable {
        let tag_name: String
        let html_url: String
    }

    struct FetchError: Error, CustomStringConvertible {
        let description: String
    }

    /// Réponse partagée entre le fil de `URLSession` et le fil appelant, protégée par un verrou.
    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result<Data, Error>?

        func set(_ newValue: Result<Data, Error>) {
            lock.lock()
            value = newValue
            lock.unlock()
        }

        func get() -> Result<Data, Error>? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    /// Message et code de retour de la commande. Fonction sans effet : `fetch` fournit la réponse.
    static func evaluate(current: String, fetch: () -> Result<Data, Error>) -> Outcome {
        switch fetch() {
        case .failure(let error):
            let reason = (error as? FetchError)?.description ?? error.localizedDescription
            return failure(reason)
        case .success(let data):
            guard let release = try? JSONDecoder().decode(LatestRelease.self, from: data) else {
                return failure(tr("réponse illisible", "unreadable response"))
            }
            if isNewer(release.tag_name, than: current) {
                let text = tr(
                    "Nouvelle version disponible : \(release.tag_name) (installée : \(current))",
                    "New version available: \(release.tag_name) (installed: \(current))"
                )
                return Outcome(exitCode: 0, stdout: "\(text)\n\(release.html_url)", stderr: nil)
            }
            return Outcome(
                exitCode: 0,
                stdout: tr("Roadie est à jour (\(current)).", "Roadie is up to date (\(current))."),
                stderr: nil
            )
        }
    }

    private static func failure(_ reason: String) -> Outcome {
        Outcome(
            exitCode: 1,
            stdout: nil,
            stderr: tr("roadie: vérification impossible : \(reason)", "roadie: update check failed: \(reason)")
        )
    }

    /// Vrai si `candidate` est une version plus récente que `current`. Le préfixe `v` est ignoré ;
    /// une partie absente ou non numérique vaut 0. O(k), k = nombre de parties (3 en pratique).
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ text: String) -> [Int] {
            let digits = text.hasPrefix("v") || text.hasPrefix("V") ? text.dropFirst() : Substring(text)
            return digits.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(candidate)
        let b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Lit la dernière release sur GitHub. Bloque le fil appelant `timeout + 1` secondes au plus.
    static func fetchLatestRelease(timeout: TimeInterval = 5) -> Result<Data, Error> {
        guard let url = URL(string: "https://api.github.com/repos/guthubrx/roadie/releases/latest") else {
            return .failure(FetchError(description: "invalid url"))
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("roadie-update-check", forHTTPHeaderField: "User-Agent")
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        let task = URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
            if let error {
                box.set(.failure(error))
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                box.set(.failure(FetchError(description: "HTTP \(http.statusCode)")))
            } else {
                box.set(.success(data ?? Data()))
            }
            done.signal()
        }
        task.resume()
        if done.wait(timeout: .now() + timeout + 1) == .timedOut {
            task.cancel()
            return .failure(FetchError(description: "timeout"))
        }
        return box.get() ?? .failure(FetchError(description: "no result"))
    }
}
