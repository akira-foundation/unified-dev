import Testing
import Foundation
@testable import Core

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
}()

private let evening = Date(timeIntervalSince1970: 1_791_742_800)

private struct World {
    let home: SpendHome
    let support: URL
    let store: Store

    init() throws {
        home = try SpendHome()
        store = try makeTestStore("account-indexing")
        support = URL(filePath: store.path).deletingLastPathComponent()
    }

    var defaults: [AgentAccountHome] { SpendAccounts.defaultHomes(home: home.root, environment: [:]) }

    var indexer: SpendIndexer { SpendIndexer(store: store, home: home.root, environment: [:]) }

    func createAccount(label: String, provider: AgentKind = .claudeCode) async throws -> AgentAccountHome {
        let plan = try AgentAccountCreation.reserve(
            provider: provider,
            label: label,
            existing: try await store.agentAccounts().map(\.id),
            support: support
        ).plan
        try await store.add(AgentAccountRow(
            id: plan.id, provider: plan.provider, directory: plan.directory.path, label: plan.label
        ))
        return plan.home
    }

    func transcript(_ lines: [String], in account: AgentAccountHome, named name: String = "s") throws {
        let file = account.directory.appending(path: "projects/-Users-ada-work/\(name).jsonl")
        try write(lines, to: file)
    }

    func write(_ lines: [String], to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try home.write(lines.joined(separator: "\n") + "\n", to: file)
    }

    func signIn(_ account: AgentAccountHome, as email: String) throws {
        let json = #"{"oauthAccount":{"emailAddress":"\#(email)"}}"#
        try FileManager.default.createDirectory(
            at: account.identityPath.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: account.identityPath)
    }

    func lines() async throws -> [SpendAccountLine] {
        let days = try await store.spendDays(since: Date(timeIntervalSince1970: 0))
        let input = SpendBoard.Input(days: days, window: .week, now: evening, calendar: utc)
        return try await SpendBoard.accounts(input, reading: store, defaults: defaults)
    }

    func refresh() async throws -> SpendIndexOutcome {
        try await indexer.refresh(calendar: utc, at: evening)
    }
}

@Suite("Spend of the accounts the app creates", .tags(.persistence))
struct SpendAccountIndexingTests {
    @Test("an account made in Settings is indexed beside the default ones")
    func createdAccountIsIndexed() async throws {
        let world = try World()
        try world.write([claudeLine(10)], to: world.home.claude)
        let work = try await world.createAccount(label: "Client")
        try world.transcript([claudeLine(70, identity: "msg_work")], in: work)

        _ = try await world.refresh()

        #expect(try await spendTotals(in: world.store).output == 80)
        let days = try await world.store.spendDays(since: Date(timeIntervalSince1970: 0))
        #expect(days.contains { $0.file.contains("/AgentAccounts/claudeCode/") })
    }

    @Test("a folder under the accounts root with no row in the store is not indexed")
    func folderWithoutRowIsNotIndexed() async throws {
        let world = try World()
        try world.write([claudeLine(10)], to: world.home.claude)
        let unfinished = try AgentAccountCreation.reserve(
            provider: .claudeCode, label: "Unfinished", existing: [], support: world.support
        ).plan.home
        try world.transcript([claudeLine(99, identity: "msg_unfinished")], in: unfinished)

        let outcome = try await world.refresh()

        #expect(outcome.filesRead == 1)
        #expect(try await spendTotals(in: world.store).output == 10)
    }

    @Test("an account made again under a removed account's label does not inherit its spend")
    func recreatedAccountStartsClean() async throws {
        let world = try World()
        let first = try await world.createAccount(label: "Client")
        try world.transcript([claudeLine(90, identity: "msg_before")], in: first)
        _ = try await world.refresh()
        try await AgentAccountRemoval.remove(first, support: world.support, store: world.store, keychain: .untouched, processes: { [] })

        let second = try await world.createAccount(label: "Client")
        try world.transcript([claudeLine(20, identity: "msg_after")], in: second)
        _ = try await world.refresh()
        let lines = try await world.lines()

        #expect(second.directory != first.directory)
        let known = lines.filter { $0.isKnown }
        let unknown = lines.filter { !$0.isKnown }
        #expect(known.map(\.spend.usage.output) == [20])
        #expect(unknown.map(\.spend.usage.output) == [90])
    }

    @Test("the census counts the files of every account of a provider, not the last one's")
    func censusSumsTheAccountsOfAProvider() async throws {
        let world = try World()
        try world.write([claudeLine(10)], to: world.home.claude)
        let first = try await world.createAccount(label: "First")
        let second = try await world.createAccount(label: "Second")
        try world.transcript([claudeLine(20, identity: "msg_first")], in: first)
        try world.transcript([claudeLine(30, identity: "msg_second")], in: second)

        _ = try await world.refresh()

        let census = try #require(try await spendCensus(in: world.store))
        #expect(census[.claudeCode]?.files == 3)
        #expect(census[.claudeCode]?.pending == 0)
    }

    @Test("the files an interrupted build never reached stay pending across every account")
    func pendingSumsTheAccountsOfAProvider() async throws {
        let world = try World()
        try world.write([claudeLine(10)], to: world.home.claude)
        let first = try await world.createAccount(label: "First")
        try world.transcript([claudeLine(20, identity: "msg_first")], in: first)
        let second = try await world.createAccount(label: "Second")
        try world.transcript([claudeLine(30, identity: "msg_second")], in: second)

        let indexer = world.indexer
        let task = Task { () async throws -> SpendIndexOutcome in
            while !Task.isCancelled { await Task.yield() }
            return try await indexer.refresh()
        }
        task.cancel()
        _ = try await task.value

        let census = try #require(try await spendCensus(in: world.store))
        #expect(census[.claudeCode]?.pending == 3)
    }

    @Test("the spend screen names the accounts by the same email the panel shows")
    func accountsAreNamedByTheirIdentity() async throws {
        let world = try World()
        try world.write([claudeLine(10)], to: world.home.claude)
        let work = try await world.createAccount(label: "Client")
        try world.transcript([claudeLine(70, identity: "msg_work")], in: work)
        let personal = try #require(world.defaults.first { $0.provider == .claudeCode })
        try world.signIn(personal, as: "ada@home.example")
        try world.signIn(work, as: "ada@client.example")

        _ = try await world.refresh()
        let lines = try await world.lines()

        #expect(lines.map(\.name) == ["ada@client.example", "ada@home.example"])
        let allKnown = lines.allSatisfy { $0.isKnown }
        #expect(allKnown)
    }

    @Test("an account with no sign-in on disk is named by its label")
    func accountWithoutIdentityKeepsItsLabel() async throws {
        let world = try World()
        let work = try await world.createAccount(label: "Client")
        try world.transcript([claudeLine(70, identity: "msg_work")], in: work)

        _ = try await world.refresh()
        let lines = try await world.lines()

        #expect(lines.map(\.name) == ["Client"])
    }

    @Test("spend left by a removed account is the only spend called unknown")
    func onlyRemovedAccountsAreUnknown() async throws {
        let world = try World()
        try world.write([claudeLine(10)], to: world.home.claude)
        let kept = try await world.createAccount(label: "Kept")
        let removed = try await world.createAccount(label: "Removed")
        try world.transcript([claudeLine(20, identity: "msg_kept")], in: kept)
        try world.transcript([claudeLine(90, identity: "msg_removed")], in: removed)
        _ = try await world.refresh()

        try await AgentAccountRemoval.remove(removed, support: world.support, store: world.store, keychain: .untouched, processes: { [] })
        _ = try await world.refresh()
        let lines = try await world.lines()

        let unknown = lines.filter { !$0.isKnown }
        #expect(unknown.count == 1)
        #expect(unknown.first?.spend.usage.output == 90)
        #expect(unknown.first?.name == SpendAccounts.unknown)
        #expect(Set(lines.filter(\.isKnown).map(\.name)) == ["Default account", "Kept"])
    }

    @Test("turns the indexer had not read yet are kept when their account is removed")
    func removalReadsTheTurnsNotYetIndexed() async throws {
        let world = try World()
        let removed = try await world.createAccount(label: "Removed")
        try world.transcript([claudeLine(40, identity: "msg_read")], in: removed)
        _ = try await world.refresh()
        try world.transcript(
            [claudeLine(40, identity: "msg_read"), claudeLine(60, identity: "msg_unread")], in: removed
        )

        try await AgentAccountRemoval.remove(removed, support: world.support, store: world.store, keychain: .untouched, processes: { [] })

        #expect(!FileManager.default.fileExists(atPath: removed.directory.path))
        #expect(try await spendTotals(in: world.store).output == 100)
    }

    @Test("an account whose transcripts cannot be read is kept, folder and all")
    func unreadableTranscriptKeepsTheAccount() async throws {
        let world = try World()
        let held = try await world.createAccount(label: "Held")
        try world.transcript([claudeLine(60, identity: "msg_held")], in: held)
        let file = held.directory.appending(path: "projects/-Users-ada-work/s.jsonl")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

        var refusal: AgentAccountError?
        do {
            try await AgentAccountRemoval.remove(held, support: world.support, store: world.store, keychain: .untouched, processes: { [] })
        } catch let error as AgentAccountError {
            refusal = error
        }

        guard case .spendUnread(let path) = refusal else {
            Issue.record("the removal went ahead: \(String(describing: refusal))")
            return
        }
        #expect(path.hasSuffix("/projects/-Users-ada-work/s.jsonl"))

        #expect(FileManager.default.fileExists(atPath: held.directory.path))
        #expect(try await world.store.agentAccounts().map(\.id) == [held.id])
    }

    @Test("a removal reads a turn whose line is longer than a refresh would hold")
    func removalReadsALongLine() async throws {
        let world = try World()
        let removed = try await world.createAccount(label: "Long")
        let padding = String(repeating: "x", count: TranscriptReader.defaultBudget + 1_000)
        let long = claudeLine(70, identity: "msg_long")
            .replacingOccurrences(of: "\"type\":\"assistant\",", with: "\"type\":\"assistant\",\"padding\":\"\(padding)\",")
        try world.transcript([long], in: removed)

        try await AgentAccountRemoval.remove(removed, support: world.support, store: world.store, keychain: .untouched, processes: { [] })

        #expect(try await spendTotals(in: world.store).output == 70)
    }

    @Test("a removal cancelled before it reads stops as cancelled and keeps the account")
    func cancelledRemovalKeepsTheAccount() async throws {
        let world = try World()
        let held = try await world.createAccount(label: "Held")
        try world.transcript([claudeLine(60, identity: "msg_held")], in: held)
        let (support, store) = (world.support, world.store)

        let removal = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await AgentAccountRemoval.remove(held, support: support, store: store, keychain: .untouched, processes: { [] })
        }

        await #expect(throws: CancellationError.self) { try await removal.value }
        #expect(FileManager.default.fileExists(atPath: held.directory.path))
        #expect(try await store.agentAccounts().map(\.id) == [held.id])
    }
}
