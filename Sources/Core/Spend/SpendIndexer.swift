import Foundation

public actor SpendIndexer {
    private let store: Store
    private let home: URL
    private let environment: [String: String]
    private var isRunning = false

    public init(
        store: Store,
        home: URL = TranscriptHome.resolve(),
        environment: [String: String] = TranscriptHome.environment()
    ) {
        self.store = store
        self.home = home
        self.environment = environment
    }

    public func refresh(
        batch: Int = TranscriptReader.defaultBudget,
        calendar: Calendar = .current,
        at now: Date = Date()
    ) async throws -> SpendIndexOutcome {
        guard !isRunning else { return SpendIndexOutcome(finished: false) }
        isRunning = true
        defer { isRunning = false }

        var outcome = SpendIndexOutcome()
        outcome.rebuilt = try await rebuildIfRepriced()
        try await store.pruneSpend(before: SpendRetention.oldestKept(from: now, calendar: calendar))

        var census = SpendCensus()
        let sources = TranscriptSources.sources(accounts: try await SpendRoster.homes(
            store: store, defaults: SpendAccounts.defaultHomes(home: home, environment: environment)
        ))

        for kind in AgentKind.allCases where !sources.contains(where: { $0.provider == kind }) {
            census[kind] = SpendProviderCensus(keepsTranscripts: false, files: 0, pending: 0)
        }

        for source in sources {
            let files = TranscriptSources.files(in: source)
            var pending = 0
            var visited = 0
            pages: for page in TranscriptCursorSweep.pages(of: files) {
                let cursors = try await store.transcriptCursors(forPaths: page.map(\.url.path))
                for file in page {
                    if Task.isCancelled {
                        outcome.finished = false
                        break pages
                    }
                    visited += 1
                    let work = TranscriptWork.decide(for: file, cursor: cursors[file.url.path])
                    guard work != .unchanged else { continue }
                    guard let read = try await consume(file, work: work, batch: batch, calendar: calendar)
                    else {
                        outcome.unreadable += 1
                        pending += 1
                        outcome.finished = false
                        continue
                    }
                    outcome.filesRead += 1
                    outcome.bytesRead += read.bytesRead
                    outcome.turns += read.turns
                    outcome.abandonedLines += read.abandonedLines
                    if !read.finished {
                        pending += 1
                        outcome.finished = false
                    }
                    await Task.yield()
                }
            }
            census.add(source.provider, files: files.count, pending: pending + (files.count - visited))
        }

        try await save(census)
        if !Task.isCancelled { try await forgetVanishedCursors() }
        return outcome
    }

    public func read(account home: AgentAccountHome, calendar: Calendar = .current) async throws -> [String] {
        var unread: [String] = []
        for source in TranscriptSources.sources(accounts: [home]) {
            for page in TranscriptCursorSweep.pages(of: TranscriptSources.files(in: source)) {
                let cursors = try await store.transcriptCursors(forPaths: page.map(\.url.path))
                for file in page {
                    try Task.checkCancellation()
                    let work = TranscriptWork.decide(for: file, cursor: cursors[file.url.path])
                    guard work != .unchanged else { continue }
                    let read = try await consume(file, work: work, batch: TranscriptReader.lineCeiling, calendar: calendar)
                    if read?.finished != true { unread.append(file.url.path) }
                }
            }
        }
        return unread
    }

    private func forgetVanishedCursors() async throws {
        let position = try await store.setting(TranscriptCursorSweep.positionKey) ?? ""
        let paths = try await store.transcriptCursorPaths(after: position, limit: TranscriptCursorSweep.sweepBatch)
        let vanished = TranscriptCursorSweep.vanished(in: paths) { FileManager.default.fileExists(atPath: $0) }
        try await store.forgetTranscriptCursors(paths: vanished)
        try await store.setSetting(TranscriptCursorSweep.positionKey, TranscriptCursorSweep.nextPosition(after: paths))
    }

    private func consume(
        _ file: TranscriptFile,
        work: TranscriptWork,
        batch: Int,
        calendar: Calendar
    ) async throws -> (bytesRead: Int, turns: Int, abandonedLines: Int, finished: Bool)? {
        var offset = work.offset
        var carry = work.carry
        var replacing = work.startsOver ? file.url.path : nil
        var bytesRead = 0
        var turns = 0
        var abandoned = 0

        while true {
            let result: TranscriptReadResult
            do {
                result = try TranscriptReader.read(file, from: offset, carry: carry, budget: batch)
            } catch {
                return nil
            }
            bytesRead += result.bytesRead
            turns += result.records.count
            abandoned += result.abandonedLines
            let moved = result.offset > offset
            offset = result.offset
            carry = result.carry

            try await store.record(
                SpendTurns.turns(for: result.records, in: file, calendar: calendar),
                reaching: TranscriptCursor(
                    path: file.url.path,
                    provider: file.provider,
                    size: file.size,
                    modifiedAt: file.modifiedAt,
                    offset: offset,
                    carry: carry
                ),
                replacing: replacing
            )
            replacing = nil

            if result.reachedEnd { return (bytesRead, turns, abandoned, true) }
            if !moved { return (bytesRead, turns, abandoned, false) }
            if Task.isCancelled { return (bytesRead, turns, abandoned, false) }
        }
    }

    private func rebuildIfRepriced() async throws -> Bool {
        let stored = try await store.setting(SpendRetention.pricedOnKey)
        guard SpendRetention.mustRebuild(storedPricedOn: stored, table: ModelPrices.measuredOn) else {
            return false
        }
        if stored != nil { try await store.forgetEverySpendTurn() }
        try await store.setSetting(
            SpendRetention.pricedOnKey, SpendRetention.stamp(of: ModelPrices.measuredOn)
        )
        return stored != nil
    }

    private func save(_ census: SpendCensus) async throws {
        let encoded = try JSONEncoder().encode(census)
        try await store.setSetting(SpendCensus.settingKey, String(decoding: encoded, as: UTF8.self))
    }
}

public struct SpendIndexOutcome: Sendable, Hashable {
    public var filesRead: Int
    public var bytesRead: Int
    public var turns: Int
    public var finished: Bool
    public var abandonedLines: Int
    public var unreadable: Int
    public var rebuilt: Bool

    public init(
        filesRead: Int = 0,
        bytesRead: Int = 0,
        turns: Int = 0,
        finished: Bool = true,
        abandonedLines: Int = 0,
        unreadable: Int = 0,
        rebuilt: Bool = false
    ) {
        self.filesRead = filesRead
        self.bytesRead = bytesRead
        self.turns = turns
        self.finished = finished
        self.abandonedLines = abandonedLines
        self.unreadable = unreadable
        self.rebuilt = rebuilt
    }
}
