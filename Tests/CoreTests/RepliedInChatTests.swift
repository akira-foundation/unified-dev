import Foundation
import Testing
@testable import Core

@Suite("Replying in the chat instead of answering a card")
struct RepliedInChatTests {
    @Test("Claude is told the owner replied in the chat, and its turn carries on")
    func claudeKeepsItsTurn() throws {
        let answer = try PermissionAnswer.encode(
            ask: PermissionAskTests.ask(), decision: PermissionDecision.repliedInChat
        )
        let body = PermissionAskTests.object(answer)["response"]?["response"]

        #expect(body?["behavior"]?.stringValue == "deny")
        #expect(body?["message"]?.stringValue == PermissionDecision.repliedInChatMessage)
        #expect(body?["interrupt"]?.boolValue == false)
    }

    @Test("the note names the chat and lets the agent ask again")
    func noteNamesTheChat() {
        let note = PermissionDecision.repliedInChatMessage

        #expect(note != PermissionDecision.defaultDenyMessage)
        #expect(note.contains("chat"))
        #expect(note.contains("ask again"))
    }

    @Test("Codex declines the call rather than cancelling the turn")
    func codexDeclines() {
        #expect(CodexPermission.decision(for: PermissionDecision.repliedInChat) == .decline)
    }

    @Test("Grok rejects once and never for good")
    func grokRejectsOnce() {
        let request = ACPPermissionRequest(
            id: .number(3),
            sessionID: "sess-1",
            toolCall: ACPToolCall.decode(.object([
                "toolCallId": .string("call_1"),
                "toolName": .string("run_terminal_cmd"),
                "rawInput": .object(["command": .string("ls")]),
            ]), isUpdate: false),
            options: [
                ACPPermissionOption(id: "allow-once", name: "Allow once", kind: "allow_once"),
                ACPPermissionOption(id: "reject-always", name: "Never", kind: "reject_always"),
                ACPPermissionOption(id: "reject-once", name: "Reject", kind: "reject_once"),
            ],
            raw: Data()
        )

        #expect(ACPPermission.optionID(for: PermissionDecision.repliedInChat, in: request) == "reject-once")
    }
}
