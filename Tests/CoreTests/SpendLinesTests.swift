import Testing
import Foundation
@testable import Core

private var calendar: Calendar {
    var made = Calendar(identifier: .gregorian)
    made.timeZone = TimeZone(secondsFromGMT: 0)!
    return made
}

private let now = Date(timeIntervalSince1970: 1_791_676_800)

private func day(_ daysAgo: Int) -> Date {
    calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
}

private func row(
    _ daysAgo: Int,
    provider: AgentKind = .claudeCode,
    model: String = "claude-opus-5",
    directory: String = "/Users/ada/work",
    file: String = "/t/one.jsonl",
    usage: TokenUsage = TokenUsage(freshInput: 1_000_000, output: 1_000_000),
    turns: Int = 1
) -> SpendDay {
    SpendDay(
        provider: provider,
        day: day(daysAgo),
        model: model,
        directory: directory,
        file: file,
        usage: usage,
        turns: turns,
        tier: .base
    )
}

private func census(_ entries: [AgentKind: SpendProviderCensus]) -> SpendCensus {
    SpendCensus(providers: Dictionary(entries.map { ($0.key.rawValue, $0.value) }, uniquingKeysWith: { a, _ in a }))
}

private let measured = SpendProviderCensus(keepsTranscripts: true, files: 3, pending: 0)
private let nothing = SpendProviderCensus(keepsTranscripts: false, files: 0, pending: 0)

@Suite("Spend lines")
struct SpendLinesTests {
    @Test("a provider whose every turn ran on an unpriced model says so rather than nothing spent")
    func unpricedProviderLine() {
        let spend = ModelPrices.spend(
            of: TokenUsage(freshInput: 10, output: 20), model: "codex-auto-review", provider: .codex
        )
        let line = SpendLines.cost(spend)
        #expect(line.contains(SpendLines.noPublishedPrice))
        #expect(!line.contains("$0.00"))
    }

    @Test("a provider with a real cost reads as that cost")
    func pricedProviderLine() {
        let spend = ModelPrices.spend(
            of: TokenUsage(output: 1_000_000), model: "claude-opus-5", provider: .claudeCode
        )
        #expect(spend.cost.total == 25)
        #expect(SpendLines.cost(spend) == SpendFormat.money(25))
    }

    @Test("a provider with nothing in the window says so")
    func emptyProviderLine() {
        let line = SpendLines.providerLine(SpendBoard.ProviderLine(
            kind: .claudeCode, reading: .measured, spend: .none, turns: 0, files: 2
        ))
        #expect(line == SpendLines.nothingYet)
    }

    @Test("a provider still being read says how many transcripts are left of how many")
    func stillReadingLine() {
        let line = SpendLines.providerLine(SpendBoard.ProviderLine(
            kind: .claudeCode, reading: .stillReading(pending: 4), spend: .none, turns: 0, files: 112
        ))
        #expect(line == "still reading 4 of 112 transcripts")
    }

    @Test("one of a thing is named in the singular")
    func singulars() {
        #expect(SpendLines.turns(1) == "1 turn")
        #expect(SpendLines.turns(2) == "2 turns")
        #expect(SpendLines.sessions(1) == "1 chat")
        #expect(SpendLines.sessions(2) == "2 chats")
        #expect(SpendLines.stillReading(1, of: 1) == "still reading 1 transcript")
        #expect(SpendLines.stillReading(2, of: 2) == "still reading 2 transcripts")
    }

    @Test("a provider never read yet says so rather than nothing spent")
    func notReadLine() {
        let line = SpendLines.providerLine(SpendBoard.ProviderLine(
            kind: .codex, reading: .notRead, spend: .none, turns: 0, files: 0
        ))
        #expect(line == SpendLines.notRead)
    }

    @Test("a provider that keeps no usage on disk is never asked for a cost")
    func keepsNoUsageLine() {
        let line = SpendLines.providerLine(SpendBoard.ProviderLine(
            kind: .grok, reading: .keepsNoUsage, spend: .none, turns: 0, files: 0
        ))
        #expect(line == SpendLines.keepsNoUsage)
    }

    @Test("the rates badge says the figure is not a bill, and the note still dates the table")
    func ratesBadge() {
        #expect(SpendLines.apiRates.contains("API rates"))
        #expect(SpendLines.apiRates.lowercased().contains("not your bill"))
        let note = SpendLines.priceNote(ModelPrices.measuredOn)
        #expect(note.hasPrefix(SpendLines.apiRates))
        #expect(note.contains(SpendFormat.pricedOn(ModelPrices.measuredOn)))
    }

    @Test("a provider with nothing measured is left without a figure beside it")
    func providerCost() {
        let nothing = SpendBoard.ProviderLine(
            kind: .codex, reading: .notRead, spend: .none, turns: 0, files: 0
        )
        #expect(SpendLines.providerCost(nothing).isEmpty)
        let measured = SpendBoard.ProviderLine(
            kind: .claudeCode,
            reading: .measured,
            spend: Spend(
                usage: TokenUsage(output: 1_000_000),
                cost: SpendCost(output: 25),
                unpriced: TokenUsage()
            ),
            turns: 3,
            files: 1
        )
        #expect(SpendLines.providerCost(measured) == SpendLines.cost(measured.spend))
        #expect(SpendLines.providerCaption(measured).contains("3 turns"))
        #expect(SpendLines.providerCaption(nothing) == SpendLines.notRead)
    }

    @Test("a column caption names its share of the cost and nothing else")
    func columnCaption() {
        let column = SpendBoard.ColumnLine(
            column: .cacheRead, tokens: 2_000_000, cost: 1, tokenShare: 0.5, costShare: 0.25
        )
        let caption = SpendLines.columnCaption(column)
        #expect(caption == SpendFormat.share(0.25) + " of the cost")
        #expect(!caption.contains("tokens"))
    }

    @Test("a window with no priced day says so rather than naming one")
    func dearestLine() {
        let empty = SpendBoard.make(SpendBoard.Input(days: [], now: now, calendar: calendar))
        #expect(SpendLines.dearestLine(empty) == SpendBoard.emptyLine)
    }

    @Test("an unknown account claims only that Unified Dev does not know it, and that the spend is historic")
    func accountCaption() {
        let spend = Spend.sum([])
        let known = SpendAccountLine(
            accountID: AgentAccountID("work"), name: "work", provider: .claudeCode, spend: spend,
            sessions: []
        )
        let gone = SpendAccountLine(
            accountID: nil, name: SpendAccounts.unknown, provider: .codex, spend: spend, sessions: []
        )
        #expect(SpendLines.accountCaption(known) == "Claude Code, 0 chats")
        #expect(SpendLines.accountCaption(gone).contains("Not an account Unified Dev knows"))
        #expect(!SpendLines.accountCaption(gone).contains("No longer"))
        #expect(SpendLines.accountCaption(gone).contains("Historic " + AgentKind.codex.label + " spend"))
    }

    @Test("an account caption counts one chat in the singular, known or gone")
    func accountCaptionCountsOneChat() {
        let session = SpendSessionLine(
            file: "/Users/ada/.claude/projects/-x/a.jsonl",
            agentSessionID: "a",
            provider: .claudeCode,
            models: ["claude-opus-5"],
            spend: Spend.sum([]),
            turns: 1,
            lastDay: now
        )
        let known = SpendAccountLine(
            accountID: AgentAccountID("work"), name: "work", provider: .claudeCode,
            spend: Spend.sum([]), sessions: [session]
        )
        let gone = SpendAccountLine(
            accountID: nil, name: SpendAccounts.unknown, provider: .claudeCode,
            spend: Spend.sum([]), sessions: [session]
        )
        #expect(SpendLines.accountCaption(known) == "Claude Code, 1 chat")
        #expect(
            SpendLines.accountCaption(gone)
                == "Not an account Unified Dev knows. Historic Claude Code spend, 1 chat"
        )
    }

    @Test("an account half spent on an unpriced model names the tokens its cost leaves out")
    func accountCaptionNamesUnpricedTokens() throws {
        let lines = SpendBoard.accountLines(SpendBoard.Input(
            days: [
                row(0, model: "claude-opus-5", usage: TokenUsage(output: 1_000_000)),
                row(0, model: "claude-unpublished", usage: TokenUsage(output: 2_000_000))
            ],
            now: now,
            calendar: calendar
        ))
        let account = try #require(lines.first)
        #expect(lines.count == 1)
        #expect(SpendLines.cost(account.spend) == SpendFormat.money(25))
        #expect(
            SpendLines.accountCaption(account)
                == "Not an account Unified Dev knows. Historic Claude Code spend, 1 chat, "
                + SpendFormat.tokens(2_000_000) + " tokens had no published price"
        )
    }

    @Test("a project half spent on an unpriced model names the tokens its cost leaves out")
    func projectCaptionNamesUnpricedTokens() {
        let mixed = SpendProjectLine(
            repoID: nil,
            name: "work",
            spend: Spend(
                usage: TokenUsage(output: 3_000_000),
                cost: SpendCost(output: 25),
                unpriced: TokenUsage(output: 2_000_000)
            ),
            sessions: []
        )
        let priced = SpendProjectLine(
            repoID: nil,
            name: "work",
            spend: Spend(usage: TokenUsage(output: 1_000_000), cost: SpendCost(output: 25)),
            sessions: []
        )
        #expect(
            SpendLines.projectCaption(mixed)
                == "0 chats, " + SpendFormat.tokens(2_000_000) + " tokens had no published price"
        )
        #expect(SpendLines.projectCaption(priced) == "0 chats")
    }

    @Test("a known account with every token unpriced says so in the cost and counts the tokens in the caption")
    func whollyUnpricedKnownAccount() {
        let spend = ModelPrices.spend(
            of: TokenUsage(output: 2_000_000), model: "codex-auto-review", provider: .codex
        )
        let account = SpendAccountLine(
            accountID: AgentAccountID("work"), name: "work", provider: .codex, spend: spend, sessions: []
        )
        #expect(SpendLines.cost(account.spend) == SpendLines.noPublishedPrice)
        #expect(
            SpendLines.accountCaption(account)
                == "Codex, 0 chats, " + SpendFormat.tokens(2_000_000) + " tokens had no published price"
        )
    }

    @Test("a known account half spent on an unpriced model names the tokens its cost leaves out")
    func knownAccountCaptionNamesUnpricedTokens() {
        let account = SpendAccountLine(
            accountID: AgentAccountID("work"),
            name: "work",
            provider: .claudeCode,
            spend: Spend(
                usage: TokenUsage(output: 3_000_000),
                cost: SpendCost(output: 25),
                unpriced: TokenUsage(output: 2_000_000)
            ),
            sessions: []
        )
        #expect(
            SpendLines.accountCaption(account)
                == "Claude Code, 0 chats, " + SpendFormat.tokens(2_000_000) + " tokens had no published price"
        )
    }

    @Test("a chat half spent on an unpriced model names the tokens its cost leaves out")
    func sessionCaptionNamesUnpricedTokens() throws {
        let lines = SpendBoard.accountLines(SpendBoard.Input(
            days: [
                row(0, model: "claude-opus-5", usage: TokenUsage(output: 1_000_000)),
                row(0, model: "claude-unpublished", usage: TokenUsage(output: 2_000_000))
            ],
            now: now,
            calendar: calendar
        ))
        let session = try #require(lines.first?.sessions.first)
        #expect(SpendLines.cost(session.spend) == SpendFormat.money(25))
        #expect(
            SpendLines.sessionCaption(session)
                == "claude-opus-5, claude-unpublished, 2 turns, "
                + SpendFormat.tokens(2_000_000) + " tokens had no published price"
        )
    }
}
