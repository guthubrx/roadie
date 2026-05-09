import Foundation

public struct FileAdminPolicy: Equatable, Sendable {
    public var maxEventLogBytes: Int
    public var maxLogBytes: Int
    public var retainedBackups: Int
    public var retainedLegacyArchiveDirectories: Int

    public init(
        maxEventLogBytes: Int = 10 * 1024 * 1024,
        maxLogBytes: Int = 10 * 1024 * 1024,
        retainedBackups: Int = 2,
        retainedLegacyArchiveDirectories: Int = 3
    ) {
        self.maxEventLogBytes = max(1, maxEventLogBytes)
        self.maxLogBytes = max(1, maxLogBytes)
        self.retainedBackups = max(0, retainedBackups)
        self.retainedLegacyArchiveDirectories = max(0, retainedLegacyArchiveDirectories)
    }
}

public struct FileAdminAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case delete
        case rotate
        case keep
    }

    public var kind: Kind
    public var path: String
    public var reason: String
    public var sizeBytes: Int64
    public var applied: Bool

    public init(kind: Kind, path: String, reason: String, sizeBytes: Int64 = 0, applied: Bool = false) {
        self.kind = kind
        self.path = path
        self.reason = reason
        self.sizeBytes = sizeBytes
        self.applied = applied
    }
}

public struct FileAdminReport: Codable, Equatable, Sendable {
    public var dryRun: Bool
    public var actions: [FileAdminAction]

    public var candidateCount: Int { actions.filter { $0.kind != .keep }.count }
    public var reclaimedBytes: Int64 {
        actions.filter { $0.kind != .keep }.reduce(0) { $0 + $1.sizeBytes }
    }

    public init(dryRun: Bool, actions: [FileAdminAction]) {
        self.dryRun = dryRun
        self.actions = actions
    }
}

public struct FileAdministrationService: @unchecked Sendable {
    private let manager: FileManager
    private let roadiesURL: URL
    private let localStateURL: URL
    private let configURL: URL
    private let policy: FileAdminPolicy

    public init(
        roadiesPath: String = "~/.roadies",
        localStatePath: String = "~/.local/state/roadies",
        configPath: String = "~/.config/roadies",
        policy: FileAdminPolicy = FileAdminPolicy(),
        manager: FileManager = .default
    ) {
        self.roadiesURL = URL(fileURLWithPath: NSString(string: roadiesPath).expandingTildeInPath)
        self.localStateURL = URL(fileURLWithPath: NSString(string: localStatePath).expandingTildeInPath)
        self.configURL = URL(fileURLWithPath: NSString(string: configPath).expandingTildeInPath)
        self.policy = policy
        self.manager = manager
    }

    public func run(dryRun: Bool = true) -> FileAdminReport {
        var actions: [FileAdminAction] = []
        actions.append(contentsOf: eventLogActions(dryRun: dryRun))
        actions.append(contentsOf: daemonLogActions(dryRun: dryRun))
        actions.append(contentsOf: configBackupActions(dryRun: dryRun))
        actions.append(contentsOf: legacyArchiveActions(dryRun: dryRun))
        actions.append(contentsOf: dsStoreActions(dryRun: dryRun))
        return FileAdminReport(dryRun: dryRun, actions: actions)
    }

    private func eventLogActions(dryRun: Bool) -> [FileAdminAction] {
        let url = roadiesURL.appendingPathComponent("events.jsonl")
        var actions: [FileAdminAction] = []
        if fileSize(url) > Int64(policy.maxEventLogBytes) {
            var action = FileAdminAction(
                kind: .rotate,
                path: url.path,
                reason: "events log exceeds \(policy.maxEventLogBytes) bytes",
                sizeBytes: fileSize(url)
            )
            if !dryRun {
                EventLog(path: url.path).rotateIfNeeded(
                    maxBytes: policy.maxEventLogBytes,
                    retainedBackups: policy.retainedBackups
                )
                action.applied = true
            }
            actions.append(action)
        }
        for index in 1...max(policy.retainedBackups + 3, 3) {
            let backup = URL(fileURLWithPath: "\(url.path).\(index)")
            guard manager.fileExists(atPath: backup.path) else { continue }
            let oversized = fileSize(backup) > Int64(policy.maxEventLogBytes)
            guard index > policy.retainedBackups || oversized else { continue }
            var action = FileAdminAction(
                kind: .delete,
                path: backup.path,
                reason: oversized ? "events backup exceeds \(policy.maxEventLogBytes) bytes" : "old events backup",
                sizeBytes: fileSize(backup)
            )
            if !dryRun {
                try? manager.removeItem(at: backup)
                action.applied = true
            }
            actions.append(action)
        }
        return actions
    }

    private func daemonLogActions(dryRun: Bool) -> [FileAdminAction] {
        ["daemon.log", "daemon.log.1"].compactMap { name in
            let url = localStateURL.appendingPathComponent(name)
            guard fileSize(url) > Int64(policy.maxLogBytes) else { return nil }
            var action = FileAdminAction(
                kind: .delete,
                path: url.path,
                reason: "daemon log exceeds \(policy.maxLogBytes) bytes",
                sizeBytes: fileSize(url)
            )
            if !dryRun {
                try? manager.removeItem(at: url)
                action.applied = true
            }
            return action
        }
    }

    private func configBackupActions(dryRun: Bool) -> [FileAdminAction] {
        let urls = directChildren(of: configURL)
            .filter { $0.lastPathComponent.hasPrefix("roadies.toml.b") }
            .sorted(by: newerFirst)
        return deleteOlder(urls, keeping: max(3, policy.retainedBackups), reason: "old roadies.toml backup", dryRun: dryRun)
    }

    private func legacyArchiveActions(dryRun: Bool) -> [FileAdminAction] {
        let directories = directChildren(of: configURL).filter { url in
            guard isDirectory(url) else { return false }
            let name = url.lastPathComponent
            return name.hasPrefix("desktops.legacy.archived-")
                || (name.hasPrefix("stages.") && (name.contains("backup") || name.contains("bak")))
        }
        let grouped = Dictionary(grouping: directories) { url in
            url.lastPathComponent.hasPrefix("stages.") ? "stages" : "desktops"
        }
        return grouped.values.flatMap { urls in
            deleteOlder(
                urls.sorted(by: newerFirst),
                keeping: policy.retainedLegacyArchiveDirectories,
                reason: "old legacy archive directory",
                dryRun: dryRun
            )
        }
    }

    private func dsStoreActions(dryRun: Bool) -> [FileAdminAction] {
        guard let enumerator = manager.enumerator(
            at: configURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else { return [] }
        return enumerator.compactMap { item -> FileAdminAction? in
            guard let url = item as? URL, url.lastPathComponent == ".DS_Store" else { return nil }
            var action = FileAdminAction(
                kind: .delete,
                path: url.path,
                reason: "Finder metadata",
                sizeBytes: fileSize(url)
            )
            if !dryRun {
                try? manager.removeItem(at: url)
                action.applied = true
            }
            return action
        }
    }

    private func deleteOlder(_ urls: [URL], keeping retainedCount: Int, reason: String, dryRun: Bool) -> [FileAdminAction] {
        guard urls.count > retainedCount else { return [] }
        return urls.dropFirst(retainedCount).map { url in
            var action = FileAdminAction(
                kind: .delete,
                path: url.path,
                reason: reason,
                sizeBytes: recursiveSize(url)
            )
            if !dryRun {
                try? manager.removeItem(at: url)
                action.applied = true
            }
            return action
        }
    }

    private func directChildren(of url: URL) -> [URL] {
        (try? manager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .fileSizeKey],
            options: []
        )) ?? []
    }

    private func newerFirst(_ lhs: URL, _ rhs: URL) -> Bool {
        modificationDate(lhs) > modificationDate(rhs)
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else { return 0 }
        return Int64(size)
    }

    private func recursiveSize(_ url: URL) -> Int64 {
        if !isDirectory(url) {
            return fileSize(url)
        }
        guard let enumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: []
        ) else { return 0 }
        return enumerator.reduce(Int64(0)) { total, item in
            guard let child = item as? URL, !isDirectory(child) else { return total }
            return total + fileSize(child)
        }
    }
}
