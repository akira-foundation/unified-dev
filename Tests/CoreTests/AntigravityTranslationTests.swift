import Testing
import Foundation
@testable import Core

private func update(_ line: String) throws -> ACPSessionUpdate {
    guard case .notification(let notification) = try #require(ACPFrame.decode(line: line)) else {
        throw WireMismatch(line: line)
    }
    return try #require(ACPSessionUpdate.decode(params: notification.params))
}

private func permission(_ line: String) throws -> ACPPermissionRequest {
    guard case .request(let request) = try #require(ACPFrame.decode(line: line)) else {
        throw WireMismatch(line: line)
    }
    return try #require(ACPPermissionRequest.decode(request))
}

private func call(_ line: String) throws -> ACPToolCall {
    switch try update(line).kind {
    case .toolCall(let call), .toolCallUpdate(let call): return call
    default: throw WireMismatch(line: line)
    }
}

private struct WireMismatch: Error {
    let line: String
}

private func translation() -> ACPTranslation {
    ACPTranslation(context: ACPTranslation.Context(agentKind: .antigravity, model: "gemini-3.8-flash-low", cwd: "/tmp/w"))
}

@Suite("Antigravity translation")
struct AntigravityTranslationTests {
    @Test("a measured run_command call reads as Bash with its command line")
    func commandIsBash() throws {
        let measured = try call(AntigravityWire.commandCall)
        #expect(ACPTranslation.toolName(for: measured, kind: .antigravity) == "Bash")
        #expect(ACPTranslation.input(for: measured)["command"]?.stringValue == "echo probe")
    }

    @Test("a measured edit_file request reads as Edit with the old and new text")
    func editIsEdit() throws {
        let measured = try permission(AntigravityWire.editPermission).toolCall
        let input = ACPTranslation.input(for: measured)
        #expect(ACPTranslation.toolName(for: measured, kind: .antigravity) == "Edit")
        #expect(input["old_string"]?.stringValue == "beta")
        #expect(input["new_string"]?.stringValue == "gamma")
        #expect(input["file_path"]?.stringValue == "/private/tmp/gemini-acp-probe/work/notes.txt")
    }

    @Test("a measured read_file call reads as Read")
    func readIsRead() throws {
        let measured = try call(AntigravityWire.readCall)
        #expect(ACPTranslation.toolName(for: measured, kind: .antigravity) == "Read")
        #expect(ACPTranslation.input(for: measured)["file_path"]?.stringValue == "/private/tmp/gemini-acp-probe/work/notes.txt")
    }

    @Test("an MCP tool named mcp_<server>_<tool> reads as the double underscore form the guards know")
    func mcpNameIsNormalised() throws {
        let measured = try call(AntigravityWire.mcpCall)
        #expect(ACPTranslation.toolName(for: measured, kind: .antigravity) == "mcp__probe-bridge__ping")
        #expect(ACPTranslation.mcpName("mcp_unifieddev-workspace-bridge_workspace_say")
            == "mcp__unifieddev-workspace-bridge__workspace_say")
        #expect(ACPTranslation.mcpName("mcp_nothing") == nil)
    }

    @Test("an unnamed tool falls back to the agent's own label, so Grok keeps its stored names")
    func fallbackNameFollowsTheAgent() {
        let unnamed = ACPToolCall.decode(.object(["toolCallId": .string("c"), "kind": .string("other")]), isUpdate: false)
        #expect(ACPTranslation.toolName(for: unnamed, kind: .antigravity) == "Antigravity.other")
        #expect(ACPTranslation.toolName(for: unnamed, kind: .grok) == "Grok.other")
    }

    @Test("the stored init line names Antigravity")
    func initNamesAntigravity() throws {
        var translation = translation()
        let events = translation.translate(.sessionReady(ACPSession(id: "s", currentModelID: "gemini-3.8-flash-high")))
        guard case .initialized(let value) = events.first else {
            Issue.record("expected init")
            return
        }
        #expect(value.agentKind == .antigravity)
        #expect(value.model == "gemini-3.8-flash-low")
        #expect(JSONValue.parse(value.raw)?["agent_kind"]?.stringValue == "antigravity")
    }

    @Test("the turn's usage comes from the session/prompt reply")
    func usageFromThePromptReply() throws {
        var translation = translation()
        _ = translation.translate(.sessionReady(ACPSession(id: "s")))
        _ = translation.translate(.update(try update(AntigravityWire.textChunk)))
        guard case .response(let id, let result, _) = try #require(ACPFrame.decode(line: AntigravityWire.promptResult)) else {
            Issue.record("expected a response")
            return
        }
        let events = translation.translate(.promptCompleted(ACPPromptResult(
            requestID: id, sessionID: "s", stopReason: result["stopReason"]?.stringValue ?? "", raw: result
        )))
        guard case .result(let ended) = events.last else {
            Issue.record("expected a result")
            return
        }
        #expect(!ended.isError)
        #expect(ended.usage.inputTokens == 9193)
        #expect(ended.usage.outputTokens == 1)
    }

    @Test("a denied write ends as a failed tool result")
    func deniedWriteFails() throws {
        var translation = translation()
        _ = translation.translate(.sessionReady(ACPSession(id: "s")))
        let events = translation.translate(.update(try update(AntigravityWire.writeDenied)))
        guard case .toolResult(let result) = events.last else {
            Issue.record("expected a tool result")
            return
        }
        #expect(result.isError)
    }
}

@Suite("Antigravity permissions")
struct AntigravityPermissionTests {
    @Test("a measured request with a string id becomes an ask keyed to Antigravity, with no always")
    func askFromMeasuredRequest() throws {
        let request = try permission(AntigravityWire.commandPermission)
        #expect(request.id == .text("1"))
        let ask = ACPPermission.ask(for: request, kind: .antigravity)
        #expect(ask.requestID.hasPrefix("antigravity:"))
        #expect(ask.toolName == "Bash")
        #expect(ask.suppressesAlwaysAllow)
        #expect(ask.suggestions.isEmpty)
        #expect(JSONValue.parse(ask.raw)?["agent_kind"]?.stringValue == "antigravity")
    }

    @Test("allowing for the session falls back to the only allow Antigravity offers")
    func sessionAllowPicksAllow() throws {
        let request = try permission(AntigravityWire.commandPermission)
        #expect(ACPPermission.optionID(for: .allow(scope: .session), in: request) == "allow")
        #expect(ACPPermission.optionID(for: .allow(scope: .once), in: request) == "allow")
        #expect(ACPPermission.optionID(for: .deny(message: "", endsTurn: true), in: request) == "deny")
    }
}
