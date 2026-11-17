import Foundation
import Testing
@testable import Core

@Suite("A stored row decided before it reaches the screen")
struct DecidedMessageTests {
    private static let session = SessionID("decided")

    private static func message(_ kind: MessageKind, _ line: String, seq: Int = 1) -> Message {
        Message(sessionID: session, seq: seq, kind: kind, payload: Data(line.utf8), refID: "toolu_big")
    }

    private static func toolResult(body: String, isError: Bool, parent: String? = nil, refused: Bool = false) -> String {
        let object: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": [
                ["type": "tool_result", "tool_use_id": "toolu_big", "content": body, "is_error": isError],
            ]],
            "parent_tool_use_id": parent.map { $0 as Any } ?? NSNull(),
            "tool_result_meta": refused ? [[
                "id": "toolu_big", "non_execution_kind": "permission-rule",
                "permission_decision": ["decision": "reject", "source": "hook"],
            ]] : [],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static let severalMegabytes = String(repeating: "a line of a very long file\n", count: 160_000)

    @Test("a result of several megabytes is decided an error, with its refusal and its reason")
    func aLargeRefusedResult() {
        let line = Self.toolResult(
            body: "PreToolUse:Bash hook error: BLOCKED\n" + Self.severalMegabytes, isError: true, parent: "toolu_agent", refused: true
        )
        #expect(line.utf8.count > 4_000_000)

        let decided = DecidedMessage(Self.message(.toolResult, line))

        #expect(decided.result == ToolResultSummary(isError: true, refusal: .hookRefused, reason: "PreToolUse:Bash hook error: BLOCKED"))
        #expect(decided.parentToolUseID == "toolu_agent")
        #expect(decided.ask == nil)
    }

    @Test("a result of several megabytes that did not fail is decided clean")
    func aLargeCleanResult() {
        let decided = DecidedMessage(Self.message(.toolResult, Self.toolResult(body: Self.severalMegabytes, isError: false)))

        #expect(decided.result == ToolResultSummary())
        #expect(decided.parentToolUseID == nil)
    }

    @Test("an error with no refusal is an error and nothing more")
    func aPlainError() {
        let decided = DecidedMessage(Self.message(.toolResult, Self.toolResult(body: "exit 1", isError: true)))

        #expect(decided.result == ToolResultSummary(isError: true))
    }

    @Test("a row that is not a result names its parent and is never an error")
    func aCallNamesItsParent() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_big","name":"Read","is_error":true}]},"parent_tool_use_id":"toolu_task"}"#

        let decided = DecidedMessage(Self.message(.toolUse, line))

        #expect(decided.parentToolUseID == "toolu_task")
        #expect(decided.result == ToolResultSummary())
    }

    @Test("a permission ask arrives decoded, and nothing else does")
    func anAskArrivesDecoded() {
        let ask = DecidedMessage(Self.message(.permissionAsk, AnsweredAskTests.questionLine))
        let notAnAsk = DecidedMessage(Self.message(.toolUse, AnsweredAskTests.questionLine))

        #expect(ask.ask == PermissionAsk.decode(payload: Data(AnsweredAskTests.questionLine.utf8)))
        #expect(ask.ask != nil)
        #expect(notAnAsk.ask == nil)
    }

    @Test("a payload that is not JSON decides nothing and keeps the row")
    func unreadablePayload() {
        let decided = DecidedMessage(Self.message(.toolResult, "not json"))

        #expect(decided.result == ToolResultSummary())
        #expect(decided.parentToolUseID == nil)
        #expect(decided.message.payload == Data("not json".utf8))
    }

    @Test("the summary is the one the payload alone gives")
    func agreesWithTheSummary() {
        let lines = [
            Self.toolResult(body: "x", isError: true, refused: true),
            Self.toolResult(body: "x", isError: true),
            Self.toolResult(body: "x", isError: false),
        ]
        for line in lines {
            #expect(DecidedMessage(Self.message(.toolResult, line)).result == ToolResultSummary.decode(Data(line.utf8)))
        }
    }

    @Test("deciding a batch off the main actor keeps its order")
    func decidingKeepsOrder() async {
        let messages = (1...5).map { Self.message(.toolResult, Self.toolResult(body: "\($0)", isError: $0 == 3), seq: $0) }

        let decided = await DecidedMessage.deciding(messages)

        #expect(decided.map(\.message.seq) == [1, 2, 3, 4, 5])
        #expect(decided.map(\.result.isError) == [false, false, true, false, false])
    }
}
