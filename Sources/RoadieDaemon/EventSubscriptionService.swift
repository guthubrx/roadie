import Foundation
import RoadieCore

public struct EventSubscriptionOptions: Equatable, Sendable {
    public var fromNow: Bool
    public var initialState: Bool
    public var types: Set<String>
    public var scopes: Set<AutomationScope>

    public init(fromNow: Bool = false, initialState: Bool = false, types: Set<String> = [], scopes: Set<AutomationScope> = []) {
        self.fromNow = fromNow
        self.initialState = initialState
        self.types = types
        self.scopes = scopes
    }
}

public struct EventSubscriptionCursor: Equatable, Sendable {
    public var offset: UInt64
    /// Inode du fichier auquel `offset` se rapporte (REL-018). `nil` : curseur construit à la main,
    /// rattaché au fichier courant à la première lecture.
    public var inode: UInt64?

    public init(offset: UInt64 = 0, inode: UInt64? = nil) {
        self.offset = offset
        self.inode = inode
    }
}

public struct EventSubscriptionService: Sendable {
    private let url: URL

    public var path: String { url.path }

    public init(path: String = EventLog.defaultPath()) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    public func start(options: EventSubscriptionOptions = EventSubscriptionOptions()) -> EventSubscriptionCursor {
        let inode = Self.inode(atPath: url.path)
        guard options.fromNow,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else {
            return EventSubscriptionCursor(offset: 0, inode: inode)
        }
        return EventSubscriptionCursor(offset: size.uint64Value, inode: inode)
    }

    public func initialEvents(snapshot: RoadieStateSnapshot, options: EventSubscriptionOptions) -> [RoadieEventEnvelope] {
        guard options.initialState else { return [] }
        return [
            RoadieEventEnvelope(
                id: "state_snapshot_\(Int(snapshot.generatedAt.timeIntervalSince1970 * 1000))",
                timestamp: snapshot.generatedAt,
                type: "state.snapshot",
                scope: .system,
                subject: AutomationSubject(kind: "system", id: "roadie"),
                correlationId: nil,
                cause: .system,
                payload: [
                    "activeDisplayId": snapshot.activeDisplayId.map(AutomationPayload.string) ?? .null,
                    "activeDesktopId": snapshot.activeDesktopId.map(AutomationPayload.string) ?? .null,
                    "activeStageId": snapshot.activeStageId.map(AutomationPayload.string) ?? .null,
                    "focusedWindowId": snapshot.focusedWindowId.map(AutomationPayload.string) ?? .null,
                    "displayCount": .int(snapshot.displays.count),
                    "windowCount": .int(snapshot.windows.count)
                ]
            )
        ]
    }

    /// Lit les événements complets écrits depuis `cursor`. Le curseur désigne un fichier (inode) et
    /// un décalage : si le journal a tourné entre deux lectures, la fin de l'ancienne génération
    /// (`.1`, `.2`...) est lue d'abord, puis les générations suivantes depuis 0, chaque événement
    /// une seule fois (REL-018). Si des événements ont pu être perdus (ancienne génération déjà
    /// supprimée par la rétention, fichier tronqué sur place), un événement `events.gap` est émis
    /// en tête, quels que soient les filtres, puis la lecture reprend au début du fichier courant.
    /// Les générations sont ouvertes une fois et identifiées par l'inode de leur descripteur
    /// (`fstat`) : une rotation entre l'identification et la lecture ne fait pas lire un autre
    /// fichier. Une génération qui désigne déjà le fichier ouvert comme courant arrête la remontée :
    /// son contenu est lu une seule fois, comme fichier courant.
    // O(octets nouveaux) ; la recherche de l'ancienne génération coûte au plus `maxBackupsScanned` ouvertures.
    public func readAvailable(from cursor: EventSubscriptionCursor, options: EventSubscriptionOptions = EventSubscriptionOptions()) -> (events: [RoadieEventEnvelope], cursor: EventSubscriptionCursor) {
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url),
              let currentInode = Self.inode(of: handle)
        else {
            return ([], cursor)
        }
        defer { try? handle.close() }
        var events: [RoadieEventEnvelope] = []
        var gap: [RoadieEventEnvelope] = []
        var offset = cursor.offset
        if let known = cursor.inode, known != currentInode {
            // Rotation : finir l'ancienne génération, puis les intermédiaires, puis le fichier courant depuis 0.
            let generations = Self.openGenerations(of: url.path, upTo: known)
            defer { generations.forEach { try? $0.handle.close() } }
            if let first = generations.lastIndex(where: { $0.inode == known }) {
                for index in stride(from: first, through: 0, by: -1) {
                    guard generations[index].inode != currentInode else { break }
                    let from = index == first ? cursor.offset : 0
                    events += Self.completeLines(of: generations[index].handle, from: from).compactMap { decodeEnvelope($0) }
                }
            } else {
                gap = [Self.gapEvent(reason: "rotated_generation_missing", lostAfterOffset: cursor.offset)]
            }
            offset = 0
        }
        do {
            // Même fichier mais plus court que le curseur : remplacé sur place, on relit depuis 0.
            let size = try handle.seekToEnd()
            if size < offset {
                gap = [Self.gapEvent(reason: "file_truncated", lostAfterOffset: offset)]
                offset = 0
            }
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            // On n'avance que jusqu'au dernier saut de ligne : une ligne en cours d'écriture
            // sera lue entière au prochain appel.
            guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else {
                return (gap + filtered(events, options), EventSubscriptionCursor(offset: offset, inode: currentInode))
            }
            let complete = data[data.startIndex..<lastNewline]
            let newOffset = offset + UInt64(complete.count + 1)
            if let raw = String(data: complete, encoding: .utf8) {
                events += raw.split(separator: "\n").compactMap { decodeEnvelope(String($0)) }
            }
            return (gap + filtered(events, options), EventSubscriptionCursor(offset: newOffset, inode: currentInode))
        } catch {
            return ([], cursor)
        }
    }

    public func readAll(options: EventSubscriptionOptions = EventSubscriptionOptions()) -> [RoadieEventEnvelope] {
        readAvailable(from: EventSubscriptionCursor(offset: 0), options: options).events
    }

    /// Nombre maximal de générations `.N` examinées pour retrouver l'ancien fichier d'un curseur.
    private static let maxBackupsScanned = 10

    /// Type de l'événement émis quand des événements ont pu être perdus entre deux lectures.
    public static let gapEventType = "events.gap"

    /// Générations `.1`, `.2`... ouvertes (indice 0 = `.1`) jusqu'à celle d'inode `known`.
    /// Une génération absente est sautée : pendant une rotation, `.1` manque un court instant.
    private static func openGenerations(of path: String, upTo known: UInt64) -> [(handle: FileHandle, inode: UInt64)] {
        var generations: [(handle: FileHandle, inode: UInt64)] = []
        for index in 1...maxBackupsScanned {
            guard let handle = FileHandle(forReadingAtPath: "\(path).\(index)") else { continue }
            guard let inode = inode(of: handle) else {
                try? handle.close()
                continue
            }
            generations.append((handle, inode))
            if inode == known { break }
        }
        return generations
    }

    private static func gapEvent(reason: String, lostAfterOffset: UInt64) -> RoadieEventEnvelope {
        let now = Date()
        return RoadieEventEnvelope(
            id: "events_gap_\(Int(now.timeIntervalSince1970 * 1000))",
            timestamp: now,
            type: gapEventType,
            scope: .system,
            subject: AutomationSubject(kind: "system", id: "roadie"),
            correlationId: nil,
            cause: .system,
            payload: [
                "reason": .string(reason),
                "lostAfterOffset": .int(Int(clamping: lostAfterOffset))
            ]
        )
    }

    private func filtered(_ events: [RoadieEventEnvelope], _ options: EventSubscriptionOptions) -> [RoadieEventEnvelope] {
        events.filter { event in
            (options.types.isEmpty || options.types.contains(event.type)) &&
            (options.scopes.isEmpty || event.scope.map { options.scopes.contains($0) } == true)
        }
    }

    private static func inode(atPath path: String) -> UInt64? {
        var info = stat()
        return stat(path, &info) == 0 ? UInt64(info.st_ino) : nil
    }

    /// Inode du fichier effectivement ouvert, insensible à un renommage ultérieur.
    private static func inode(of handle: FileHandle) -> UInt64? {
        var info = stat()
        return fstat(handle.fileDescriptor, &info) == 0 ? UInt64(info.st_ino) : nil
    }

    /// Lignes complètes (terminées par un saut de ligne) de `handle` à partir de `offset`.
    private static func completeLines(of handle: FileHandle, from offset: UInt64) -> [String] {
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(),
              let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")),
              let raw = String(data: data[data.startIndex..<lastNewline], encoding: .utf8)
        else { return [] }
        return raw.split(separator: "\n").map(String.init)
    }

    /// Decoder partage : evite ~30us d'allocation par event (5Hz polling, peut traiter
    /// des dizaines d'events par tick si bursty).
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func decodeEnvelope(_ line: String) -> RoadieEventEnvelope? {
        guard let data = line.data(using: .utf8) else { return nil }
        let decoder = Self.decoder
        if let envelope = try? decoder.decode(RoadieEventEnvelope.self, from: data) {
            return envelope
        }
        if let legacy = try? decoder.decode(RoadieEvent.self, from: data) {
            return RoadieEventEnvelope(legacy: legacy)
        }
        return nil
    }
}
