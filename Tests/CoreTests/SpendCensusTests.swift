import Testing
import Foundation
@testable import Core

@Suite("Spend census", .tags(.persistence))
struct SpendCensusTests {
    @Test("a cancelled build does not report the transcripts it never read as measured")
    func cancellationLeavesThemPending() async throws {
        let home = try SpendHome()
        try home.write([claudeLine(10), claudeLine(20)].joined(separator: "\n") + "\n", to: home.claude)
        try home.write(codexCount(1) + "\n", to: home.codex)

        let store = try makeTestStore("indexer")
        let indexer = SpendIndexer(store: store, home: home.root)
        let task = Task { () async throws -> SpendIndexOutcome in
            while !Task.isCancelled { await Task.yield() }
            return try await indexer.refresh()
        }
        task.cancel()
        _ = try await task.value

        let census = try #require(try await spendCensus(in: store))
        #expect(census[.claudeCode]?.pending == 1)
        let board = SpendBoard.make(SpendBoard.Input(
            days: [], census: census, installed: [.claudeCode], window: .week
        ))
        #expect(board.providers.first?.reading == .stillReading(pending: 1))
    }

    @Test("a provider that keeps no usage on disk is recorded as keeping none")
    func providerThatKeepsNoUsage() async throws {
        let home = try SpendHome()
        try home.write(claudeLine(10) + "\n", to: home.claude)

        let store = try makeTestStore("indexer")
        _ = try await SpendIndexer(store: store, home: home.root).refresh()

        let census = try #require(try await spendCensus(in: store))
        #expect(census[.grok]?.keepsTranscripts == false)
        let board = SpendBoard.make(SpendBoard.Input(
            days: [], census: census, installed: [.grok], window: .week
        ))
        #expect(board.providers.first?.reading == .keepsNoUsage)
    }

    @Test("a provider whose transcript directory is empty is not read as keeping none")
    func providerWithoutTranscripts() async throws {
        let home = try SpendHome()
        try home.write(claudeLine(10) + "\n", to: home.claude)

        let store = try makeTestStore("indexer")
        let indexer = SpendIndexer(store: store, home: home.root)
        _ = try await indexer.refresh()

        let census = try #require(try await spendCensus(in: store))
        #expect(census[.claudeCode]?.keepsTranscripts == true)
        #expect(census[.codex]?.keepsTranscripts == true)
        #expect(census[.codex]?.files == 0)
        let board = SpendBoard.make(SpendBoard.Input(
            days: [], census: census, installed: [.codex], window: .week
        ))
        #expect(board.providers.first?.reading == .notRead)
    }
}
