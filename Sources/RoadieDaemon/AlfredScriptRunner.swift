import Darwin
import Foundation

/// Script d'un objet de workflow (Script Filter, Run Script) : langage d'Alfred, source ou fichier,
/// argument en `argv` ou dans `{query}`, bits d'échappement (SPEC-088, research R3, R4).
struct AlfredScript: Equatable, Sendable {
    let language: Int
    let source: String
    let file: String?
    let usesArgv: Bool
    let escaping: Int

    init(language: Int, source: String, file: String? = nil, usesArgv: Bool = true, escaping: Int = 0) {
        self.language = language
        self.source = source
        self.file = file
        self.usesArgv = usesArgv
        self.escaping = escaping
    }

    init?(object: AlfredObject) {
        let source = object.string("script") ?? ""
        let file = object.string("scriptfile").flatMap { $0.isEmpty ? nil : $0 }
        guard !source.isEmpty || file != nil else { return nil }
        self.init(language: object.int("type") ?? 0, source: source, file: file,
                  usesArgv: (object.int("scriptargtype") ?? 1) == 1, escaping: object.int("escaping") ?? 0)
    }
}

/// Issue d'un script : sortie (coupée au plafond), code, arrêt par délai ou par annulation.
struct AlfredScriptResult: Equatable, Sendable {
    var output = Data()
    var status: Int32 = 0
    var timedOut = false
    var cancelled = false
    var truncated = false
    /// Raison d'un lancement impossible (interpréteur absent, fichier non exécutable).
    var failure: String?

    var text: String { String(decoding: output, as: UTF8.self) }
    var succeeded: Bool { failure == nil && !timedOut && !cancelled && status == 0 }
}

/// Script lancé : seul moyen de l'arrêter avant sa fin (frappe suivante dans la barre).
final class AlfredProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var ended = false
    private(set) var cancelled = false

    /// Arrête le script et ses enfants (groupe de processus). Sans effet s'il est fini.
    func cancel() {
        lock.withLock {
            cancelled = true
            if pid > 0, !ended { killpg(pid, SIGTERM) }
        }
    }

    fileprivate func started(_ pid: pid_t) -> Bool {
        lock.withLock {
            self.pid = pid
            if cancelled { killpg(pid, SIGTERM) }
            return !cancelled
        }
    }

    fileprivate func signal(_ number: Int32) { lock.withLock { if pid > 0, !ended { killpg(pid, number) } } }
    fileprivate func finish() { lock.withLock { ended = true } }
}

/// Exécution des scripts des workflows (SPEC-088 FR-004) : interpréteur selon le type d'Alfred,
/// dossier du workflow, environnement, délai, plafond de sortie, groupe de processus propre.
enum AlfredScriptRunner {
    static let defaultTimeout: TimeInterval = 10
    static let maxOutput = 5 * 1024 * 1024

    /// Langages : 0 bash, 1 php, 2 ruby, 3 python 2, 4 perl, 5 zsh, 6 AppleScript, 7 JavaScript,
    /// 8 script externe, 9 python3, 11 zsh sans fichiers de démarrage (research R3).
    static func argv(for script: AlfredScript, arguments: [String], folder: URL) -> Result<[String], ScriptFailure> {
        let source = script.source
        func tool(_ name: String) -> Result<String, ScriptFailure> {
            find(name).map { .success($0) } ?? .failure(.missingInterpreter(name))
        }
        switch script.language {
        case 0: return .success(["/bin/bash", "-c", source, "bash"] + arguments)
        case 5: return .success(["/bin/zsh", "-c", source, "zsh"] + arguments)
        case 11: return .success(["/bin/zsh", "--no-rcs", "-c", source, "zsh"] + arguments)
        case 6: return .success(["/usr/bin/osascript", "-l", "AppleScript", "-e", source] + arguments)
        case 7: return .success(["/usr/bin/osascript", "-l", "JavaScript", "-e", source] + arguments)
        case 2: return tool("ruby").map { [$0, "-e", source, "--"] + arguments }
        case 4: return tool("perl").map { [$0, "-e", source, "--"] + arguments }
        case 1: return tool("php").map { [$0, "-r", source, "--"] + arguments }
        case 3: return tool("python2").map { [$0, "-c", source] + arguments }
        case 9:
            guard let python3 else { return .failure(.missingInterpreter("python3")) }
            return .success([python3, "-c", source] + arguments)
        case 8:
            guard let file = script.file else { return .failure(.missingFile("")) }
            let path = folder.appendingPathComponent(file).path
            guard FileManager.default.isExecutableFile(atPath: path) else { return .failure(.missingFile(file)) }
            return .success([path] + arguments)
        default: return .failure(.unknownLanguage(script.language))
        }
    }

    enum ScriptFailure: Error, Equatable {
        case missingInterpreter(String), missingFile(String), unknownLanguage(Int), spawn(Int32)

        var message: String {
            switch self {
            case .missingInterpreter(let name): "interpréteur absent : \(name)"
            case .missingFile(let file): "script introuvable ou non exécutable : \(file)"
            case .unknownLanguage(let type): "langage inconnu : \(type)"
            case .spawn(let code): "lancement impossible (\(code))"
            }
        }
    }

    /// Outil dans les dossiers habituels, Homebrew d'abord. O(d).
    static func find(_ name: String) -> String? {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// python3 d'Apple seulement si les outils de développement sont là : sinon `/usr/bin/python3`
    /// ouvre la fenêtre d'installation de macOS. Homebrew sinon.
    static let python3: String? = {
        let tools = ["/Library/Developer/CommandLineTools", "/Applications/Xcode.app/Contents/Developer"]
        if tools.contains(where: { FileManager.default.fileExists(atPath: $0) }) { return "/usr/bin/python3" }
        return ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Échappement de `{query}` : barre oblique inverse devant chaque caractère choisi. Bits : espaces 1,
    /// apostrophes inverses 2, guillemets 4, crochets 8, points-virgules 16, dollars 32, barres
    /// obliques inverses 64 (research R4). O(n).
    static func escape(_ text: String, bits: Int) -> String {
        var sets: [Int: Set<Character>] = [1: [" "], 2: ["`"], 4: ["\""], 8: ["(", ")", "[", "]", "{", "}"], 16: [";"], 32: ["$"], 64: ["\\"]]
        sets = sets.filter { bits & $0.key != 0 }
        let escaped = sets.values.reduce(into: Set<Character>()) { $0.formUnion($1) }
        guard !escaped.isEmpty else { return text }
        var out = ""
        for character in text {
            if escaped.contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }

    /// Variables d'Alfred (documentées), du workflow et de l'appel ; `PATH` complété. O(v).
    static func environment(workflow: AlfredWorkflow, variables: [String: String], keyword: String?,
                            base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        let path = env["PATH"] ?? ""
        env["PATH"] = ([path] + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).filter { !$0.isEmpty }.joined(separator: ":")
        for (key, value) in constants(workflow: workflow) { env[key] = value }
        if let keyword { env["alfred_workflow_keyword"] = keyword }
        for (key, value) in variables { env[key] = value }
        return env
    }

    /// Constantes `alfred_*` d'un workflow (research R9). Les dossiers de données d'un workflow d'Alfred
    /// sont ceux d'Alfred : même état que dans Alfred. O(1).
    static func constants(workflow: AlfredWorkflow, home: String = NSHomeDirectory()) -> [String: String] {
        let key = workflow.bundleID.isEmpty ? workflow.id : workflow.bundleID
        let data: String, cache: String
        switch workflow.source {
        case .alfred:
            data = "\(home)/Library/Application Support/Alfred/Workflow Data/\(key)"
            cache = "\(home)/Library/Caches/com.runningwithcrayons.Alfred/Workflow Data/\(key)"
        case .roadie:
            data = "\(home)/.roadies/workflows-data/\(key)"
            cache = "\(home)/Library/Caches/roadie/workflows/\(key)"
        }
        var result = [
            "alfred_workflow_bundleid": workflow.bundleID, "alfred_workflow_name": workflow.name,
            "alfred_workflow_description": workflow.description, "alfred_workflow_version": workflow.version,
            "alfred_workflow_uid": workflow.id, "alfred_workflow_data": data, "alfred_workflow_cache": cache,
            "alfred_version": alfredVersion, "alfred_version_build": alfredBuild, "alfred_debug": "0",
            "alfred_theme_subtext": "0", "roadie_version": RoadieVersion.current,
        ]
        if let preferences = AlfredWorkflowIndex.alfredPreferences() { result["alfred_preferences"] = preferences.path }
        return result
    }

    /// Version d'Alfred installée (certains scripts la testent), sinon 5.5.
    static let (alfredVersion, alfredBuild): (String, String) = {
        let info = ["/Applications/Alfred 5.app", "/Applications/Alfred 6.app"].lazy
            .compactMap { Bundle(path: $0)?.infoDictionary }.first
        return (info?["CFBundleShortVersionString"] as? String ?? "5.5", info?["CFBundleVersion"] as? String ?? "0")
    }()

    /// Lance le script hors du fil principal ; `done` reçoit l'issue (sur une file quelconque). O(sortie).
    @discardableResult
    static func start(_ script: AlfredScript, query: String, arguments: [String], workflow: AlfredWorkflow,
                      variables: [String: String], keyword: String? = nil, timeout: TimeInterval = defaultTimeout,
                      done: @escaping @Sendable (AlfredScriptResult) -> Void) -> AlfredProcess {
        let process = AlfredProcess()
        var script = script
        var arguments = arguments
        if !script.usesArgv {
            script = AlfredScript(language: script.language, source: script.source.replacingOccurrences(of: "{query}", with: escape(query, bits: script.escaping)),
                                  file: script.file, usesArgv: false, escaping: script.escaping)
            arguments = []
        }
        let argv = argv(for: script, arguments: arguments, folder: workflow.folder)
        let env = environment(workflow: workflow, variables: variables, keyword: keyword)
        DispatchQueue.global(qos: .userInitiated).async {
            switch argv {
            case .failure(let failure): done(AlfredScriptResult(failure: failure.message))
            case .success(let argv): done(spawn(argv, environment: env, directory: workflow.folder, timeout: timeout, process: process))
            }
        }
        return process
    }

    static func run(_ script: AlfredScript, query: String, arguments: [String], workflow: AlfredWorkflow,
                    variables: [String: String], keyword: String? = nil, timeout: TimeInterval = defaultTimeout) async -> AlfredScriptResult {
        await withCheckedContinuation { continuation in
            start(script, query: query, arguments: arguments, workflow: workflow, variables: variables, keyword: keyword,
                  timeout: timeout) { continuation.resume(returning: $0) }
        }
    }

    /// `posix_spawn` dans un nouveau groupe de processus : l'arrêt atteint aussi les enfants du script
    /// (research R5). Entrée vide, erreurs jetées, sortie lue jusqu'au plafond. Bloquant : hors fil principal.
    static func spawn(_ argv: [String], environment: [String: String], directory: URL, timeout: TimeInterval,
                      process: AlfredProcess) -> AlfredScriptResult {
        var result = AlfredScriptResult()
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { result.failure = ScriptFailure.spawn(errno).message; return result }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        // Signaux remis à leur effet par défaut et débloqués : le démon ignore SIGTERM pour le traiter
        // lui-même, et un enfant en hériterait (le script ne pourrait plus être arrêté).
        var all = sigset_t(), none = sigset_t()
        sigfillset(&all)
        sigemptyset(&none)
        posix_spawnattr_setsigdefault(&attributes, &all)
        posix_spawnattr_setsigmask(&attributes, &none)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
                                                     | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        posix_spawnattr_setpgroup(&attributes, 0)
        let cArgs = argv.map { strdup($0) } + [nil]
        let cEnv = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            cArgs.forEach { free($0) }
            cEnv.forEach { free($0) }
        }
        var pid: pid_t = 0
        let code = posix_spawn(&pid, argv[0], &actions, &attributes, cArgs, cEnv)
        close(fds[1])
        guard code == 0 else {
            close(fds[0])
            result.failure = ScriptFailure.spawn(code).message
            return result
        }
        guard process.started(pid) else {
            result.cancelled = true
            close(fds[0])
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            process.finish()
            return result
        }
        let timedOut = TimeoutFlag()
        let timer = DispatchWorkItem {
            timedOut.set()
            process.signal(SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { process.signal(SIGINT) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(fds[0], &buffer, buffer.count)
            if count <= 0 { break }
            if result.output.count + count > maxOutput {
                result.truncated = true
                process.signal(SIGTERM)
                break
            }
            result.output.append(buffer, count: count)
        }
        close(fds[0])
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        timer.cancel()
        process.finish()
        // Sortie normale : code dans l'octet haut ; arrêt par signal : 128 + numéro, comme un shell.
        result.status = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        result.timedOut = timedOut.value
        result.cancelled = process.cancelled
        return result
    }

    private final class TimeoutFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        func set() { lock.withLock { flag = true } }
        var value: Bool { lock.withLock { flag } }
    }
}
