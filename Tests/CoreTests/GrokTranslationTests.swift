import Testing
import Foundation
@testable import Core

@Suite("Grok translation")
struct GrokTranslationTests {
    @Test("prompt errors retain their explanation when stored and decoded")
    func promptErrorSurvivesStorage() throws {
        var translation = ACPTranslation(context: ACPTranslation.Context(agentKind: .grok))
        let events = translation.translate(.promptCompleted(ACPPromptResult(
            requestID: .number(1),
            sessionID: "s",
            stopReason: "refusal",
            raw: .object(["message": .string("Insufficient credits")])
        )))
        guard case .result(let result) = events.last else {
            Issue.record("expected an error result")
            return
        }
        #expect(result.isError)
        #expect(result.summary == "Insufficient credits")
        let line = try #require(String(data: result.raw, encoding: .utf8))
        guard case .result(let restored) = AgentEvent.decode(line: line) else {
            Issue.record("expected a stored result")
            return
        }
        #expect(restored.summary == result.summary)
    }

    @Test("session ready becomes a stored init line naming Grok")
    func sessionReadyIsInit() {
        var translation = ACPTranslation(context: ACPTranslation.Context(
            agentKind: .grok,
            model: "grok-4.6",
            cwd: "/tmp/w",
            permissionMode: "auto"
        ))
        let events = translation.translate(.sessionReady(ACPSession(
            id: "sess-1",
            currentModelID: "grok-4.6"
        )))
        guard case .initialized(let value) = events.first else {
            Issue.record("expected init")
            return
        }
        #expect(value.sessionID == "sess-1")
        #expect(value.agentKind == .grok)
        #expect(value.model == "grok-4.6")
        let json = JSONValue.parse(value.raw)
        #expect(json?["type"]?.stringValue == "system")
        #expect(json?["agent_kind"]?.stringValue == "grok")
    }

    @Test("the model the owner chose survives a session that opens on the CLI's own default")
    func chosenModelSurvivesTheSessionDefault() {
        var translation = ACPTranslation(context: ACPTranslation.Context(
            agentKind: .grok,
            model: "grok-4.6",
            cwd: "/tmp/w",
            permissionMode: "auto"
        ))
        let events = translation.translate(.sessionReady(ACPSession(
            id: "sess-1",
            currentModelID: "grok-4.7"
        )))
        guard case .initialized(let value) = events.first else {
            Issue.record("expected init")
            return
        }
        #expect(value.model == "grok-4.6")
        #expect(translation.context.model == "grok-4.6")
    }

    @Test("a session with no model of ours is named by the one the CLI opened on")
    func theSessionDefaultNamesATurnWeAskedNothingOf() {
        var translation = ACPTranslation(context: ACPTranslation.Context(agentKind: .grok, cwd: "/tmp/w"))
        let events = translation.translate(.sessionReady(ACPSession(
            id: "sess-1",
            currentModelID: "grok-4.7"
        )))
        guard case .initialized(let value) = events.first else {
            Issue.record("expected init")
            return
        }
        #expect(value.model == "grok-4.7")
    }

    @Test("text chunks stream live and flush as one assistant row")
    func textChunksFlush() {
        var translation = ACPTranslation(context: ACPTranslation.Context(agentKind: .grok, model: "grok-4.6"))
        _ = translation.translate(.sessionReady(ACPSession(id: "sess-1")))
        let first = translation.translate(.update(ACPSessionUpdate(
            sessionID: "sess-1",
            kind: .text("Hel"),
            raw: .object([:])
        )))
        #expect(first.contains { if case .streamDelta(.text("Hel")) = $0 { return true }; return false })
        let second = translation.translate(.update(ACPSessionUpdate(
            sessionID: "sess-1",
            kind: .text("lo"),
            raw: .object([:])
        )))
        #expect(second.contains { if case .streamDelta(.text("lo")) = $0 { return true }; return false })
        let done = translation.translate(.promptCompleted(ACPPromptResult(
            requestID: .number(1),
            sessionID: "sess-1",
            stopReason: "end_turn",
            raw: .object([:])
        )))
        guard let text = done.compactMap({ event -> String? in
            if case .assistantText(let block) = event { return block.text }
            return nil
        }).first else {
            Issue.record("expected assistant text")
            return
        }
        #expect(text == "Hello")
        #expect(done.contains { if case .result(let result) = $0 { return !result.isError }; return false })
    }

    @Test("a tool call maps onto Read and carries the path Unified Dev already looks for")
    func toolCallMapsToRead() {
        var translation = ACPTranslation(context: ACPTranslation.Context(agentKind: .grok, model: "grok-4.6"))
        _ = translation.translate(.sessionReady(ACPSession(id: "sess-1")))
        let call = ACPToolCall.decode(.object([
            "toolCallId": .string("call_1"),
            "title": .string("Read"),
            "kind": .string("read"),
            "status": .string("pending"),
            "toolName": .string("read_file"),
            "rawInput": .object(["path": .string("src/main.rs")]),
        ]), isUpdate: false)
        let events = translation.translate(.update(ACPSessionUpdate(
            sessionID: "sess-1",
            kind: .toolCall(call),
            raw: .object([:])
        )))
        guard case .toolUse(let use) = events.first else {
            Issue.record("expected tool use")
            return
        }
        #expect(use.id == "call_1")
        #expect(use.name == "Read")
        #expect(use.filePath == "src/main.rs")
        #expect(ACPTranslation.isACPCall(use.input))
    }

    @Test("a finished tool update becomes a result row")
    func toolUpdateCompletes() {
        var translation = ACPTranslation(context: ACPTranslation.Context(agentKind: .grok, model: "grok-4.6"))
        _ = translation.translate(.sessionReady(ACPSession(id: "sess-1")))
        let started = ACPToolCall.decode(.object([
            "toolCallId": .string("call_1"),
            "toolName": .string("run_terminal_cmd"),
            "status": .string("in_progress"),
            "rawInput": .object(["command": .string("echo hi")]),
        ]), isUpdate: false)
        _ = translation.translate(.update(ACPSessionUpdate(
            sessionID: "sess-1",
            kind: .toolCall(started),
            raw: .object([:])
        )))
        let finished = ACPToolCall.decode(.object([
            "toolCallId": .string("call_1"),
            "status": .string("completed"),
            "content": .array([.object([
                "type": .string("content"),
                "content": .object(["type": .string("text"), "text": .string("hi\n")]),
            ])]),
        ]), isUpdate: true)
        let events = translation.translate(.update(ACPSessionUpdate(
            sessionID: "sess-1",
            kind: .toolCallUpdate(finished),
            raw: .object([:])
        )))
        guard case .toolResult(let result) = events.first else {
            Issue.record("expected tool result")
            return
        }
        #expect(result.toolUseID == "call_1")
        #expect(result.text.contains("hi"))
        #expect(!result.isError)
    }

    @Test("permission options map allow_once onto Unified Dev's once")
    func permissionOptions() {
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
                ACPPermissionOption(id: "reject-once", name: "Reject", kind: "reject_once"),
            ],
            raw: Data()
        )
        let ask = ACPPermission.ask(for: request, kind: .grok)
        #expect(ask.requestID.hasPrefix("grok:"))
        #expect(ask.toolName == "Bash")
        #expect(ask.input["command"]?.stringValue == "ls")
        #expect(ask.suppressesAlwaysAllow)
        #expect(PermissionAsk.decode(payload: ask.raw)?.suppressesAlwaysAllow == true)
        #expect(ACPPermission.optionID(for: .allow(scope: .once), in: request) == "allow-once")
        #expect(ACPPermission.optionID(
            for: .deny(message: "no", endsTurn: false),
            in: request
        ) == "reject-once")
    }

    @Test("reject_always without allow_always does not offer Unified Dev's persistent grant")
    func rejectAlwaysDoesNotOfferAlwaysAllow() {
        let request = ACPPermissionRequest(
            id: .number(3),
            sessionID: "sess-1",
            toolCall: ACPToolCall.decode(.object([
                "toolCallId": .string("call_1"),
                "toolName": .string("read_file"),
                "rawInput": .object(["path": .string("a.rs")]),
            ]), isUpdate: false),
            options: [
                ACPPermissionOption(id: "allow-once", name: "Allow once", kind: "allow_once"),
                ACPPermissionOption(id: "reject-once", name: "Reject", kind: "reject_once"),
                ACPPermissionOption(id: "reject-always", name: "Always reject", kind: "reject_always"),
            ],
            raw: Data()
        )
        let ask = ACPPermission.ask(for: request, kind: .grok)
        #expect(ask.suppressesAlwaysAllow)
        #expect(ask.suggestions.isEmpty)
        #expect(ACPPermission.optionID(for: .allow(scope: .session), in: request) == "allow-once")
    }
}
