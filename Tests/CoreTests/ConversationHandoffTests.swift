import Foundation
import Testing
@testable import Core

@Suite("ConversationHandoff")
struct ConversationHandoffTests {
    private let chat = SessionID("chat-1")

    private func row(_ seq: Int, _ kind: MessageKind, _ json: JSONValue? = nil, ref: String? = nil) -> Message {
        let fallback: JSONValue = kind == .result
            ? .object(["subtype": .string("success"), "is_error": .bool(false)]) : .object([:])
        return Message(sessionID: chat, seq: seq, kind: kind, payload: Data((json ?? fallback).compactJSON.utf8), refID: ref)
    }

    private func user(_ seq: Int, _ text: String) -> Message {
        row(seq, .user, .object([
            "type": .string("user"),
            "message": .object(["content": .string(text)]),
        ]))
    }

    private func assistant(_ seq: Int, _ text: String) -> Message {
        row(seq, .assistantText, .object([
            "type": .string("assistant"),
            "message": .object([
                "model": .string("claude-test"),
                "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            ]),
        ]))
    }

    private func thinking(_ seq: Int, _ text: String) -> Message {
        row(seq, .thinking, .object([
            "type": .string("assistant"),
            "message": .object([
                "content": .array([.object(["type": .string("thinking"), "thinking": .string(text)])]),
            ]),
        ]))
    }

    private func toolUse(
        _ seq: Int, id: String, name: String = "Bash", command: String, parent: String? = nil
    ) -> Message {
        row(seq, .toolUse, .object([
            "type": .string("assistant"),
            "parent_tool_use_id": parent.map(JSONValue.string) ?? .null,
            "message": .object([
                "content": .array([.object([
                    "type": .string("tool_use"), "id": .string(id), "name": .string(name),
                    "input": .object(["command": .string(command)]),
                ])]),
            ]),
        ]), ref: id)
    }

    private func toolResult(_ seq: Int, id: String, text: String) -> Message {
        row(seq, .toolResult, .object([
            "type": .string("user"),
            "message": .object([
                "content": .array([.object([
                    "type": .string("tool_result"), "tool_use_id": .string(id), "content": .string(text),
                ])]),
            ]),
        ]), ref: id)
    }

    private func make(
        _ rows: [Message], budget: Int = 100_000, worktree: ConversationHandoff.Worktree? = nil,
        agent: AgentKind = .claudeCode
    ) -> String {
        ConversationHandoff.text(messages: rows, worktree: worktree, chatID: chat, budget: budget, agent: agent) ?? ""
    }

    @Test func carriesEveryOwnerMessageInFull() {
        let long = Array(repeating: "owner words", count: 400).joined(separator: " ")
        let text = make([
            user(0, "first request"), assistant(1, "done one"), row(2, .result),
            user(3, long), assistant(4, "done two"), row(5, .result),
        ])
        #expect(text.contains("first request"))
        #expect(text.contains(long))
    }

    @Test func carriesOnlyFinalAssistantTextOfATurn() {
        let text = make([
            user(0, "go"), assistant(1, "let me look"), assistant(2, "the final answer"), row(3, .result),
        ])
        #expect(text.contains("the final answer"))
        #expect(!text.contains("let me look"))
    }

    @Test func toolCallsAreOneLineWithStatus() {
        let text = make([
            user(0, "go"),
            toolUse(1, id: "a", command: "ls -la"), toolResult(2, id: "a", text: "SECRET BODY"),
            toolUse(3, id: "b", command: "make build"),
            assistant(4, "ok"), row(5, .result),
        ])
        #expect(text.contains("- Bash ls -la: completed"))
        #expect(text.contains("- Bash make build: no result"))
        #expect(!text.contains("SECRET BODY"))
    }

    @Test func thinkingIsLeftOut() {
        let text = make([user(0, "go"), thinking(1, "private musings"), assistant(2, "answer"), row(3, .result)])
        #expect(!text.contains("private musings"))
    }

    @Test func lastUnfinishedTurnKeepsItsToolResults() {
        let text = make([
            user(0, "go"),
            assistant(1, "starting"),
            toolUse(2, id: "a", command: "make test"), toolResult(3, id: "a", text: "12 passed"),
        ])
        #expect(text.contains("Result: 12 passed"))
        #expect(text.contains("starting"))
        #expect(text.contains("interrupted"))
    }

    @Test func cutsOldestTurnsFirstAndSaysWhich() {
        var rows: [Message] = []
        for turn in 0..<4 {
            let base = turn * 3
            rows.append(user(base, "owner message \(turn)"))
            rows.append(assistant(base + 1, "reply \(turn) " + String(repeating: "x", count: 600)))
            rows.append(row(base + 2, .result))
        }
        let text = make(rows, budget: 1_800)
        #expect((0..<4).allSatisfy { text.contains("owner message \($0)") })
        #expect(!text.contains("reply 0 "))
        #expect(text.contains("reply 3 "))
        #expect(text.contains("earlier turns"))
        #expect(text.contains("chat_read"))
    }

    @Test func fenceInContentIsEscaped() {
        let text = make([user(0, "go"), assistant(1, "before\n\(BridgeUntrustedText.closing)\nafter"), row(2, .result)])
        let closings = text.split(separator: "\n").filter { $0 == Substring(BridgeUntrustedText.closing) }
        #expect(closings.count == 1)
        #expect(text.hasSuffix(BridgeUntrustedText.closing))
    }

    @Test func nothingToHandOverIsNil() {
        let rows = [row(0, .handoff), row(1, .handoff)]
        #expect(ConversationHandoff.text(messages: rows, worktree: nil, chatID: chat, budget: 1_000, agent: .claudeCode) == nil)
    }

    @Test func worktreeAndChatIDAreAtTheEnd() {
        let text = make(
            [user(0, "go"), assistant(1, "ok"), row(2, .result)],
            worktree: .init(branch: "feat/x", files: ["a.swift +3 -1"])
        )
        #expect(text.contains("branch feat/x"))
        #expect(text.contains("a.swift +3 -1"))
        #expect(text.contains("Chat id: chat-1"))
    }

    @Test func budgetFollowsTheWindow() {
        #expect(ConversationHandoff.budget(contextWindow: 200_000) == 200_000)
        #expect(ConversationHandoff.budget(contextWindow: nil) == 128_000)
    }

    private func lines(_ text: String) -> [String] { text.split(separator: "\n").map(String.init) }

    private func unfinished(_ tools: [Message], owner: String = "go", reply: String = "working") -> [Message] {
        [user(0, owner), assistant(1, reply)] + tools
    }

    @Test(arguments: ["text", "tools", "owners"])
    func bodyNeverExceedsTheBudget(case shape: String) {
        let budget = 6_000
        let rows: [Message]
        switch shape {
        case "text":
            rows = unfinished([], reply: String(repeating: "a", count: 2_000_000))
        case "tools":
            rows = unfinished((0..<600).flatMap { index in
                [toolUse(2 + index * 2, id: "t\(index)", command: "cmd \(index)"),
                 toolResult(3 + index * 2, id: "t\(index)", text: String(repeating: "r", count: 500))]
            })
        default:
            rows = (0..<200).flatMap { index in
                [user(index * 3, "owner \(index) " + String(repeating: "o", count: 400)),
                 assistant(index * 3 + 1, "reply"), row(index * 3 + 2, .result)]
            }
        }
        let text = make(rows, budget: budget)
        #expect(text.count <= budget)
        #expect(text.contains("chat_read"))
        #expect(text.hasSuffix(BridgeUntrustedText.closing))
    }

    @Test func cuttingOwnerMessagesSaysSo() {
        let rows = (0..<50).flatMap { index in
            [user(index * 3, "owner \(index) " + String(repeating: "o", count: 300)),
             assistant(index * 3 + 1, "reply"), row(index * 3 + 2, .result)]
        }
        let text = make(rows, budget: 4_000)
        #expect(text.range(of: #"The oldest \d+ messages were left out to fit\."#, options: .regularExpression) != nil)
        #expect(!text.contains("owner's oldest"))
        #expect(text.contains("owner 49 "))
        #expect(!text.contains("owner 0 "))
    }

    @Test func nestedCallsInTheUnfinishedTurnAreListed() {
        let text = make(unfinished([
            toolUse(2, id: "p", name: "Task", command: "explore"),
            toolUse(3, id: "c", name: "Edit", command: "patch file", parent: "p"),
            toolResult(4, id: "c", text: "edited"),
        ]))
        #expect(text.contains("within Task: Edit patch file: completed"))
    }

    @Test func parentLineCountsItsSubCalls() {
        let text = make([
            user(0, "go"),
            toolUse(1, id: "p", name: "Task", command: "explore"),
            toolUse(2, id: "c1", command: "ls", parent: "p"),
            toolUse(3, id: "c2", command: "pwd", parent: "p"),
            toolResult(4, id: "p", text: "done"),
            assistant(5, "ok"), row(6, .result),
        ])
        #expect(text.contains("Task explore: completed (made 2 sub-calls)"))
        #expect(!text.contains("pwd"))
    }

    @Test func noResultSaysItMayHaveRun() {
        let text = make(unfinished([toolUse(2, id: "a", command: "git push")]))
        #expect(text.contains("git push: no result recorded, it may have run"))
    }

    private func turnClosed(by closing: Message) -> [Message] {
        [user(0, "go"), assistant(1, "pushing"), toolUse(2, id: "a", command: "git push"),
         toolResult(3, id: "a", text: "pushed")] + [closing]
    }

    @Test func aCleanResultStaysComplete() {
        let text = make(turnClosed(by: row(4, .result)))
        #expect(!text.contains("no result recorded, it may have run"))
        #expect(!text.contains("interrupted"))
    }

    @Test func anInterruptedTurnTellsTheAgentToCheckTheRepositoryFirst() {
        let interrupted = make([user(0, "go"), toolUse(1, id: "a", command: "git push")])
        let clean = make(turnClosed(by: row(4, .result)))
        let sentence = "Check the real state of the repository before repeating any action it took."
        #expect(interrupted.contains(sentence))
        #expect(!clean.contains(sentence))
    }

    private func closingRow(_ raw: Data, seq: Int = 4) -> Message {
        Message(sessionID: chat, seq: seq, kind: .result, payload: raw)
    }

    private func codexClosing(_ subtype: String, isError: Bool) -> Message {
        closingRow(CodexTranslation.resultLine(
            subtype: subtype, isError: isError, summary: "", durationMS: 0,
            usage: AgentUsage(), model: "gpt-5", sessionID: "thread"
        ))
    }

    private func grokClosing(_ subtype: String, isError: Bool) -> Message {
        closingRow(ACPTranslation.resultLine(
            subtype: subtype, isError: isError, summary: "", durationMS: 0,
            usage: AgentUsage(), model: "grok", sessionID: "session"
        ))
    }

    @Test func aCodexTurnTheOwnerStoppedIsInterrupted() {
        let text = make(turnClosed(by: codexClosing("interrupted", isError: false)))
        #expect(text.contains("The last turn was interrupted"))
    }

    @Test func aGrokTurnTheOwnerStoppedIsInterrupted() {
        let text = make(turnClosed(by: grokClosing("error_during_execution", isError: false)))
        #expect(text.contains("The last turn was interrupted"))
    }

    @Test func aFinishedTurnFromEachAgentIsComplete() {
        for closing in [codexClosing("success", isError: false), grokClosing("success", isError: false)] {
            #expect(!make(turnClosed(by: closing)).contains("interrupted"))
        }
    }

    @Test func theLastTurnEndedCleanlyOnlyOnACleanResult() {
        let clean = turnClosed(by: codexClosing("success", isError: false))
        let stopped = turnClosed(by: codexClosing("interrupted", isError: false))
        let open = [user(0, "go"), assistant(1, "working")]
        let older = clean + [user(5, "again")]

        #expect(ConversationHandoff.lastTurnEndedCleanly(newestFirst: clean.reversed(), agent: .codex))
        #expect(!ConversationHandoff.lastTurnEndedCleanly(newestFirst: stopped.reversed(), agent: .codex))
        #expect(!ConversationHandoff.lastTurnEndedCleanly(newestFirst: open.reversed(), agent: .codex))
        #expect(!ConversationHandoff.lastTurnEndedCleanly(newestFirst: older.reversed(), agent: .codex))
        #expect(!ConversationHandoff.lastTurnEndedCleanly(newestFirst: [Message](), agent: .codex))
    }

    @Test func aMoveAfterACleanTurnLeavesItClean() {
        let mark = Message(
            sessionID: chat, seq: 5, kind: .handoff,
            payload: HandoffMark.continued(agent: .grok, model: "g", from: .codex).payload
        )
        let rows = turnClosed(by: codexClosing("success", isError: false)) + [mark]

        #expect(ConversationHandoff.lastTurnEndedCleanly(newestFirst: rows.reversed(), agent: .grok))
    }

    @Test func aLimitStopIsNotCleanEvenWithACleanResultAfterAMove() throws {
        let limit = Message(
            sessionID: chat, seq: 1, kind: .assistantText,
            payload: Data(try fixtureLines("claude-usage-limit.ndjson")[0].utf8)
        )
        let clean = row(2, .result)
        let mark = Message(
            sessionID: chat, seq: 3, kind: .handoff,
            payload: HandoffMark.continued(agent: .codex, model: "g", from: .claudeCode).payload
        )

        #expect(!ConversationHandoff.lastTurnEndedCleanly(newestFirst: [mark, clean, limit, user(0, "go")], agent: .codex))
    }

    private func longContext() throws -> ConversationHandoff.Context {
        let rows = (0..<200).flatMap { index in
            [user(index * 3, "question \(index)"),
             assistant(index * 3 + 1, String(repeating: "r", count: 400)),
             row(index * 3 + 2, .result)]
        } + [user(600, "still going"), toolUse(601, id: "a", command: "git push")]
        return try #require(ConversationHandoff.context(messages: rows, worktree: nil, chatID: chat, agent: .claudeCode))
    }

    @Test func fittingARecordRendersEachTurnOnlyAFewTimes() throws {
        let context = try longContext()
        let measure = ConversationHandoff.Measure()

        let text = ConversationHandoff.fitted(context, budget: 8_000, measure: measure)

        #expect(text.count <= 8_000)
        #expect(measure.renderedTurns <= context.turns.count * 4)
    }

    @Test func theMeasureAgreesWithTheDocumentItStandsFor() throws {
        let context = try longContext()
        let measure = ConversationHandoff.Measure()
        let cuts = [
            ConversationHandoff.Cuts(),
            ConversationHandoff.Cuts(completeThrough: 150),
            ConversationHandoff.Cuts(completeThrough: 200, capped: true),
            ConversationHandoff.Cuts(completeThrough: 200, capped: true, toolsDropped: 1, ownersDropped: 50),
        ]

        for cut in cuts {
            #expect(measure.length(context, cut) == ConversationHandoff.document(context, cut).count)
        }
    }

    @Test func aFailedResultLeavesTheTurnUnfinished() {
        let text = make([user(0, "go"), toolUse(1, id: "a", command: "git push")]
            + [row(2, .result, .object(["is_error": .bool(true), "terminal_reason": .string("api_error")]))])
        #expect(text.contains("git push: no result recorded, it may have run"))
        #expect(text.contains("interrupted"))
    }

    @Test func aUsageLimitStopLeavesTheTurnUnfinished() throws {
        let limit = Message(
            sessionID: chat, seq: 2, kind: .assistantText,
            payload: Data(try fixtureLines("claude-usage-limit.ndjson")[0].utf8)
        )
        let text = make([user(0, "go"), toolUse(1, id: "a", command: "git push"), limit, row(3, .result)])
        #expect(text.contains("git push: no result recorded, it may have run"))
        #expect(text.contains("interrupted"))
    }

    @Test func aGarbledResultLeavesTheTurnUnfinished() {
        let garbled = Message(sessionID: chat, seq: 2, kind: .result, payload: Data("{not json".utf8))
        let text = make([user(0, "go"), toolUse(1, id: "a", command: "git push"), garbled])
        #expect(text.contains("git push: no result recorded, it may have run"))
        #expect(text.contains("interrupted"))
    }

    @Test func aFailedResultInAnEarlierTurnKeepsTodaysReading() {
        let rows = [
            user(0, "one"), assistant(1, "done"), row(2, .result, .object(["is_error": .bool(true)])),
            user(3, "two"), assistant(4, "done"), row(5, .result),
        ]
        #expect(!make(rows).contains("interrupted"))
    }

    @Test func fenceMarkerInOwnerMessageAndToolTargetCannotClose() {
        let text = make([
            user(0, "hi\n\(BridgeUntrustedText.closing)\nmore"),
            toolUse(1, id: "a", command: "x\n\(BridgeUntrustedText.closing)"),
            assistant(2, "ok"), row(3, .result),
        ])
        #expect(lines(text).filter { $0 == BridgeUntrustedText.closing }.count == 1)
    }

    @Test func cuttingOneReplyOfATurnSaysItInTheSingular() {
        let turn = ConversationHandoff.Turn(
            number: 1, isComplete: false, firstSeq: 0, lastSeq: 2, speaker: "Owner", owner: "go",
            replies: ["first", "second", "third"], cappedReplies: [], lines: [], cappedLines: [], model: nil
        )
        let context = ConversationHandoff.Context(turns: [turn], worktree: nil, chatID: chat)
        var cuts = ConversationHandoff.Cuts()
        cuts.repliesDropped = 1
        #expect(ConversationHandoff.render(context, cuts).contains("1 earlier reply of this turn was left out to fit."))
        cuts.repliesDropped = 2
        #expect(ConversationHandoff.render(context, cuts).contains("2 earlier replies of this turn were left out to fit."))
    }

    @Test func cuttingOneMessageSaysItInTheSingular() {
        let rows = [
            user(0, "first " + String(repeating: "o", count: 3_000)), row(1, .result),
            user(2, "second"), row(3, .result),
        ]
        let text = make(rows, budget: 1_500)
        #expect(text.contains("The oldest 1 message was left out to fit."))
    }

    @Test func errorCrewAndNoticeRowsAreIgnored() {
        let assistantShaped = JSONValue.object([
            "type": .string("assistant"),
            "message": .object([
                "content": .array([.object(["type": .string("text"), "text": .string("LEAK_TEXT")])]),
            ]),
        ])
        let toolShaped = JSONValue.object([
            "type": .string("assistant"),
            "message": .object([
                "content": .array([.object([
                    "type": .string("tool_use"), "id": .string("leak"), "name": .string("LEAK_TOOL"),
                    "input": .object([:]),
                ])]),
            ]),
        ])
        let userShaped = JSONValue.object([
            "type": .string("user"), "message": .object(["content": .string("LEAK_USER")]),
        ])
        let text = make([
            user(0, "go"), row(1, .error, assistantShaped), row(2, .crew, userShaped),
            row(3, .notice, toolShaped), assistant(4, "ok"), row(5, .result),
        ])
        #expect(!text.contains("LEAK"))
        #expect(text.contains("Assistant: ok"))
    }

    @Test(arguments: ["replies", "cutTurns", "narration"])
    func theWholeTextStaysWithinTheBudget(case shape: String) {
        let budget = ConversationHandoff.defaultBudget
        let rows: [Message]
        switch shape {
        case "replies":
            rows = [user(0, "go")] + (1...300).map { assistant($0, String(repeating: "r", count: 500)) }
        case "cutTurns":
            rows = (0..<5_000).flatMap { index in
                [user(index * 3, "q\(index)"), assistant(index * 3 + 1, "a"), row(index * 3 + 2, .result)]
            }
        default:
            rows = [user(0, "go")] + (0..<400).flatMap { index in
                [assistant(1 + index * 3, String(repeating: "n", count: 400)),
                 toolUse(2 + index * 3, id: "t\(index)", command: "c\(index)"),
                 toolResult(3 + index * 3, id: "t\(index)", text: String(repeating: "r", count: 400))]
            }
        }
        let text = make(rows, budget: budget)
        #expect(text.count <= budget)
        #expect(text.contains("chat_read"))
        #expect(text.hasSuffix(BridgeUntrustedText.closing))
    }

    @Test func newestOwnerMessageSurvivesWorktreeDropping() {
        let files = (0..<50).map { "file\($0)-" + String(repeating: "f", count: 100) }
        let rows = (0..<20).flatMap { index in
            [user(index * 3, "owner \(index) " + String(repeating: "o", count: 200)),
             assistant(index * 3 + 1, "reply"), row(index * 3 + 2, .result)]
        }
        let text = make(rows, budget: 2_500, worktree: .init(branch: "feat/x", files: files))
        #expect(text.count <= 2_500)
        #expect(!text.contains("Worktree:"))
        #expect(text.contains("owner 19 "))
    }

    @Test func aBudgetFarBelowTheRecordKeepsTheNewestPart() {
        let rows = [user(0, String(repeating: "u", count: 50_000)), assistant(1, "ok"), row(2, .result)]
        let text = make(rows, budget: 650)
        #expect(text.count <= 650)
        #expect(text.contains("newest part"))
        #expect(text.contains("Chat id: chat-1"))
    }

    @Test func nestedCallWhoseParentComesLaterStillNamesIt() {
        let text = make(unfinished([
            toolUse(2, id: "c", name: "Edit", command: "patch", parent: "p"),
            toolUse(3, id: "p", name: "Task", command: "explore"),
        ]))
        #expect(text.contains("within Task: Edit patch"))
    }

    @Test func nestedCallWithNoParentInTheRowsIsStillListed() {
        let text = make(unfinished([toolUse(2, id: "c", name: "Edit", command: "patch", parent: "gone")]))
        #expect(text.contains("within a sub-agent: Edit patch"))
    }

    @Test func aHugeNewestOwnerMessageKeepsItsTail() {
        let opening = "OPENING-MARK"
        let tail = "TAIL-MARK"
        let huge = opening + String(repeating: "h", count: 20_000) + tail
        let rows = [user(0, huge), assistant(1, "ok"), row(2, .result)]
        let text = make(rows, budget: 3_000)
        #expect(text.count <= 3_000)
        #expect(text.contains(tail))
        #expect(!text.contains(opening))
        #expect(text.contains("chat_read"))
    }
}
