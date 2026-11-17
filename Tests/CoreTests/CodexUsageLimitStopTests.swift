import Testing
import Foundation
@testable import Core

@Suite("Recognising a Codex turn stopped by the usage limit")
struct CodexUsageLimitStopTests {
    private let chat = SessionID("chat-codex-stop")

    private func owner(_ seq: Int) -> Message {
        Message(sessionID: chat, seq: seq, kind: .user, payload: Data(#"{"type":"user","message":{"role":"user","content":"go on"}}"#.utf8))
    }

    private func failedTurn(code: String?, status: String = "failed") throws -> CodexTurn {
        let info = code.map { #","codexErrorInfo":"\#($0)""# } ?? ""
        let json = try #require(JSONValue.parse(
            #"{"id":"turn-1","status":"\#(status)","items":[],"error":{"message":"You've hit your usage limit."\#(info)}}"#
        ))
        return CodexTurn.decode(json, threadID: "thread-1", raw: Data())
    }

    private func closing(_ turn: CodexTurn, seq: Int = 2) throws -> Message {
        var translation = CodexTranslation(context: CodexTranslation.Context(model: "gpt-5.6-sol"))
        guard case .result(let result)? = translation.translate(.turnCompleted(turn)).first else {
            Issue.record("expected a result")
            return Message(sessionID: chat, seq: seq, kind: .result, payload: Data())
        }
        return Message(sessionID: chat, seq: seq, kind: .result, payload: result.raw)
    }

    @Test func theTypedCodeOfAFailedTurnIsRead() throws {
        #expect(try failedTurn(code: "usageLimitExceeded").errorCode == "usageLimitExceeded")
        #expect(try failedTurn(code: nil).errorCode == nil)
    }

    @Test func aFailedTurnWithTheUsageLimitCodeIsTheLimit() throws {
        let rows = [owner(1), try closing(try failedTurn(code: "usageLimitExceeded"))]

        #expect(TurnStopCause.ofLastTurn(messages: rows, agent: .codex) == .usageLimit)
    }

    @Test func otherCodesAreNotTheLimit() throws {
        for code in ["rateLimitExceeded", "sessionBudgetExceeded", "serverOverloaded", "other"] {
            let rows = [owner(1), try closing(try failedTurn(code: code))]
            #expect(TurnStopCause.ofLastTurn(messages: rows, agent: .codex) == .other)
        }
    }

    @Test func aFailedTurnWithNoCodeIsNotTheLimitWhateverItsWordsSay() throws {
        let rows = [owner(1), try closing(try failedTurn(code: nil))]

        #expect(TurnStopCause.ofLastTurn(messages: rows, agent: .codex) == .other)
    }

    @Test func theCodeIsKeptOnlyWhenTheTurnFailed() throws {
        let interrupted = try closing(try failedTurn(code: "usageLimitExceeded", status: "interrupted"))
        let failed = try closing(try failedTurn(code: "usageLimitExceeded"))

        #expect(JSONValue.parse(interrupted.payload)?["codex_error"] == nil)
        #expect(JSONValue.parse(failed.payload)?["codex_error"]?.stringValue == "usageLimitExceeded")
        #expect(TurnStopCause.ofLastTurn(messages: [owner(1), interrupted], agent: .codex) == .other)
    }

    @Test func theCodexLimitIsNotReadForAnotherProvider() throws {
        let rows = [owner(1), try closing(try failedTurn(code: "usageLimitExceeded"))]

        #expect(TurnStopCause.ofLastTurn(messages: rows, agent: .claudeCode) == .other)
        #expect(TurnStopCause.ofLastTurn(messages: rows, agent: .grok) == .other)
    }

    @Test func aLimitAlreadyResumedIsNotReadAgain() throws {
        let rows = [
            owner(1), try closing(try failedTurn(code: "usageLimitExceeded")),
            Message(sessionID: chat, seq: 3, kind: .handoff, payload: HandoffMark.resuming.payload),
        ]

        #expect(TurnStopCause.ofLastTurn(messages: rows, agent: .codex) == .other)
    }

    @Test func aLimitInAnOlderTurnDoesNotCount() throws {
        let rows = [owner(1), try closing(try failedTurn(code: "usageLimitExceeded")), owner(3)]

        #expect(TurnStopCause.ofLastTurn(messages: rows, agent: .codex) == .other)
    }

    @Test func aReplyAfterTheFailedResultEndsTheLimit() throws {
        let reply = Message(
            sessionID: chat, seq: 3, kind: .assistantText,
            payload: Data(#"{"type":"assistant","message":{"content":[{"type":"text","text":"back"}]}}"#.utf8)
        )
        let rows = [owner(1), try closing(try failedTurn(code: "usageLimitExceeded")), reply]

        #expect(TurnStopCause.ofLastTurn(messages: rows, agent: .codex) == .other)
    }
}
