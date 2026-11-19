import Testing
import Foundation
@testable import Core

@Suite("Spend indexer", .tags(.persistence))
struct SpendIndexerTests {
    @Test("the first build reads both providers and keeps what it found")
    func firstBuild() async throws {
        let home = try SpendHome()
        try home.write([claudeLine(10), claudeLine(20)].joined(separator: "\n") + "\n", to: home.claude)
        try home.write([codexContext("gpt-6-sol", directory: "/Users/ada/api"), codexCount(7)]
            .joined(separator: "\n") + "\n", to: home.codex)

        let store = try makeTestStore("indexer")
        let indexer = SpendIndexer(store: store, home: home.root)
        let outcome = try await indexer.refresh()

        #expect(outcome.finished)
        #expect(outcome.filesRead == 2)
        #expect(outcome.turns == 3)
        let days = try await store.spendDays(since: Date(timeIntervalSince1970: 0))
        #expect(Set(days.map(\.provider)) == [.claudeCode, .codex])
        #expect(TokenUsage.sum(days.map(\.usage)).output == 37)
        #expect(days.first { $0.provider == .codex }?.model == "gpt-6-sol")
        #expect(days.first { $0.provider == .codex }?.directory == "/Users/ada/api")
    }

    @Test("each request is charged at the rate its own prompt earned, not the day's")
    func tierIsDecidedPerRequest() async throws {
        let home = try SpendHome()
        try home.write(
            [
                claudeLine(10, identity: "msg_a", model: "claude-haiku-5-5", input: 60_000),
                claudeLine(20, identity: "msg_b", model: "claude-haiku-5-5", input: 60_000),
                claudeLine(30, identity: "msg_c", model: "claude-haiku-5-5", input: 100_001),
            ].joined(separator: "\n") + "\n",
            to: home.claude
        )

        let store = try makeTestStore("indexer")
        _ = try await SpendIndexer(store: store, home: home.root).refresh()

        let days = try await store.spendDays(since: Date(timeIntervalSince1970: 0))
        #expect(Set(days.map(\.tier)) == [.base, .longPrompt])
        let base = try #require(days.first { $0.tier == .base })
        #expect(base.turns == 2)
        #expect(abs(base.spend.cost.freshInput - 0.012) < 0.000_001)
        let long = try #require(days.first { $0.tier == .longPrompt })
        #expect(abs(long.spend.cost.freshInput - 0.050_000_5) < 0.000_001)
    }

    @Test("two turns with no response id of their own are two turns, not one")
    func idlessTurnsStayApart() async throws {
        let home = try SpendHome()
        try home.write([idlessLine(10), idlessLine(20)].joined(separator: "\n") + "\n", to: home.claude)

        let store = try makeTestStore("indexer")
        _ = try await SpendIndexer(store: store, home: home.root).refresh()
        let days = try await store.spendDays(since: Date(timeIntervalSince1970: 0))
        #expect(days.first?.turns == 2)
        #expect(try await spendTotals(in: store).output == 30)
    }

    @Test("a transcript that cannot be opened is counted and the others are still read")
    func unreadableTranscript() async throws {
        let home = try SpendHome()
        try home.write(claudeLine(10) + "\n", to: home.claude)
        let closed = home.root.appending(path: ".claude/projects/-Users-ada-work/closed.jsonl")
        try Data(claudeLine(20).utf8).write(to: closed)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: closed.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: closed.path) }

        let store = try makeTestStore("indexer")
        let outcome = try await SpendIndexer(store: store, home: home.root).refresh()
        #expect(outcome.unreadable == 1)
        #expect(outcome.filesRead == 1)
        #expect(!outcome.finished)
        #expect(try await spendTotals(in: store).output == 10)
    }

    @Test("a second refresh over unchanged transcripts reads nothing at all")
    func refreshReadsNothing() async throws {
        let home = try SpendHome()
        try home.write(claudeLine(10) + "\n", to: home.claude)
        try home.write(codexCount(1) + "\n", to: home.codex)

        let store = try makeTestStore("indexer")
        let indexer = SpendIndexer(store: store, home: home.root)
        _ = try await indexer.refresh()
        let second = try await indexer.refresh()

        #expect(second.filesRead == 0)
        #expect(second.bytesRead == 0)
        #expect(try await spendTotals(in: store).output == 11)
    }

    @Test("a transcript that grew while the app was open adds only its new turns")
    func growthIsAddedOnce() async throws {
        let home = try SpendHome()
        try home.write(claudeLine(10) + "\n", to: home.claude)
        try home.write(codexCount(1) + "\n", to: home.codex)

        let store = try makeTestStore("indexer")
        let indexer = SpendIndexer(store: store, home: home.root)
        _ = try await indexer.refresh()

        try home.write([claudeLine(10), claudeLine(30)].joined(separator: "\n") + "\n", to: home.claude)
        let second = try await indexer.refresh()

        #expect(second.turns == 1)
        #expect(try await spendTotals(in: store).output == 41)
    }

    @Test("a build that stopped at an unfinished line carries on when the line is finished")
    func resumesFromTheCursor() async throws {
        let home = try SpendHome()
        let second = claudeLine(30, identity: "msg_b")
        try home.write(
            claudeLine(10, identity: "msg_a") + "\n" + String(second.prefix(40)), to: home.claude
        )
        try home.write(codexCount(1) + "\n", to: home.codex)

        let store = try makeTestStore("indexer")
        let indexer = SpendIndexer(store: store, home: home.root)
        _ = try await indexer.refresh()
        #expect(try await spendTotals(in: store).output == 11)

        try home.write(
            claudeLine(10, identity: "msg_a") + "\n" + second + "\n", to: home.claude
        )
        let second2 = try await indexer.refresh()
        #expect(second2.turns == 1)
        #expect(try await spendTotals(in: store).output == 41)
    }

    @Test("a transcript rewritten shorter is counted once, not twice")
    func rotationIsNotCountedTwice() async throws {
        let home = try SpendHome()
        try home.write([claudeLine(10), claudeLine(20), claudeLine(30)].joined(separator: "\n") + "\n", to: home.claude)
        try home.write(codexCount(1) + "\n", to: home.codex)

        let store = try makeTestStore("indexer")
        let indexer = SpendIndexer(store: store, home: home.root)
        _ = try await indexer.refresh()
        #expect(try await spendTotals(in: store).output == 61)

        try home.write(claudeLine(5) + "\n", to: home.claude)
        _ = try await indexer.refresh()
        #expect(try await spendTotals(in: store).output == 6)
    }

    @Test("a cancelled build reports that it did not finish and writes nothing")
    func cancellationStops() async throws {
        let home = try SpendHome()
        try home.write(claudeLine(10) + "\n", to: home.claude)
        try home.write(codexCount(1) + "\n", to: home.codex)

        let store = try makeTestStore("indexer")
        let indexer = SpendIndexer(store: store, home: home.root)
        let task = Task { () async throws -> SpendIndexOutcome in
            while !Task.isCancelled { await Task.yield() }
            return try await indexer.refresh()
        }
        task.cancel()
        let outcome = try await task.value

        #expect(!outcome.finished)
        #expect(outcome.filesRead == 0)
        #expect(try await spendTotals(in: store).isEmpty)
    }

    @Test("one response written as several lines is counted once")
    func repeatedResponseCountedOnce() async throws {
        let home = try SpendHome()
        try home.write(
            [
                claudeLine(10, identity: "msg_a"),
                claudeLine(10, identity: "msg_a"),
                claudeLine(10, identity: "msg_a"),
                claudeLine(30, identity: "msg_b"),
            ].joined(separator: "\n") + "\n",
            to: home.claude
        )

        let store = try makeTestStore("indexer")
        let indexer = SpendIndexer(store: store, home: home.root)
        _ = try await indexer.refresh()

        let days = try await store.spendDays(since: Date(timeIntervalSince1970: 0))
        #expect(days.count == 1)
        #expect(days.first?.turns == 2)
        #expect(try await spendTotals(in: store).output == 40)
    }

    @Test("a provider every one of whose turns is unpriced is not read as nothing spent")
    func unpricedProviderIsNotZero() async throws {
        let home = try SpendHome()
        try home.write(
            [codexContext("codex-auto-review", directory: "/Users/ada/api"), codexCount(9)]
                .joined(separator: "\n") + "\n",
            to: home.codex
        )

        let store = try makeTestStore("indexer")
        let indexer = SpendIndexer(store: store, home: home.root)
        _ = try await indexer.refresh()

        let days = try await store.spendDays(since: Date(timeIntervalSince1970: 0))
        let spend = Spend.sum(days.map(\.spend))
        #expect(spend.hasUnpricedTokens)
        #expect(SpendLines.cost(spend) == SpendLines.noPublishedPrice)
    }
}
