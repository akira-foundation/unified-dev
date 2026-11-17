import Testing
import Foundation
@testable import Core

@Suite("What a transcript row keeps of its payload once loaded")
struct TranscriptRowPayloadTests {
    private func payload(_ text: String) -> Data { Data(text.utf8) }

    private var claudeInit: Data {
        let tools = (0..<200).map { "\"mcp__server__tool_\($0)\"" }.joined(separator: ",")
        let commands = (0..<300).map { "\"command-\($0)\"" }.joined(separator: ",")
        return payload(
            #"{"type":"system","subtype":"init","cwd":"/tmp/work","session_id":"s-1","#
                + #""tools":[\#(tools)],"slash_commands":[\#(commands)],"agents":["general"],"#
                + #""mcp_servers":[{"name":"bridge","status":"connected"}],"model":"claude-opus-5-5","#
                + #""permissionMode":"acceptEdits","claude_code_version":"2.1.0","output_style":"default","#
                + #""uuid":"u-1","parent_tool_use_id":"toolu_parent"}"#
        )
    }

    @Test("a row of any other kind keeps its payload byte for byte")
    func otherKindsAreUntouched() {
        let row = payload(#"{"type":"system","subtype":"commands_changed","commands":["a"]}"#)
        for kind in MessageKind.allCases where kind != .system {
            #expect(TranscriptRowPayload.retained(kind: kind, payload: row) == row)
        }
    }

    private func front(of row: Data) -> Data { row.prefix(TranscriptRowInk.probeLength) }

    @Test("a system row the transcript never draws keeps only the bytes the probes read")
    func undrawnSystemRowsKeepTheirFront() {
        let output = String(repeating: "x", count: 4_000)
        let rows = [
            payload(#"{"type":"system","subtype":"commands_changed","commands":["review","plan"]}"#),
            payload(#"{"type":"system","subtype":"hook_response","hook_name":"Stop","output":"\#(output)"}"#),
            payload(#"{"type":"stream_event","event":{"type":"content_block_delta","text":"\#(output)"}}"#),
        ]
        for row in rows {
            let kept = TranscriptRowPayload.retained(kind: .system, payload: row)
            #expect(kept == front(of: row))
            #expect(kept.count <= TranscriptRowInk.probeLength)
        }
    }

    @Test("the kept bytes are a copy, not a window onto the whole payload")
    func keptBytesAreACopy() {
        let row = payload(#"{"type":"system","subtype":"hook_response","output":"\#(String(repeating: "x", count: 4_000))"}"#)
        let kept = TranscriptRowPayload.retained(kind: .system, payload: row)
        #expect(kept.startIndex == 0)
        #expect(kept.count == TranscriptRowInk.probeLength)
    }

    @Test("a hook named anywhere in the front still reads as one once trimmed")
    func hookMarkerSurvivesWherever() {
        let rows = [
            payload(#"{"type":"system","subtype":"hook_started","hook_name":"SessionStart"}"#),
            payload(#"{"type":"system","subtype":"commands_changed","commands":["hook_review"]}"#),
        ]
        let marker = Data(#""hook_"#.utf8)
        for row in rows {
            let kept = TranscriptRowPayload.retained(kind: .system, payload: row)
            #expect(front(of: row).range(of: marker) != nil)
            #expect(kept.range(of: marker) != nil)
        }
    }

    @Test("an init that names a hook in its front is left as the probes saw it")
    func initNamingAHookKeepsItsFront() {
        let row = payload(#"{"type":"system","subtype":"init","tools":["hook_run"],"slash_commands":["\#(String(repeating: "c", count: 2_000))"]}"#)
        let kept = TranscriptRowPayload.retained(kind: .system, payload: row)
        #expect(kept == front(of: row))
    }

    @Test("a trimmed row still draws nothing")
    func trimmedRowStaysBlank() {
        let row = payload(#"{"type":"system","subtype":"commands_changed"}"#)
        let kept = TranscriptRowPayload.retained(kind: .system, payload: row)
        #expect(TranscriptRowInk.drawsNothing(kind: .system, payload: kept))
    }

    @Test("an init row keeps what its row draws and drops the lists")
    func initKeepsItsHeader() throws {
        let kept = TranscriptRowPayload.retained(kind: .system, payload: claudeInit)
        #expect(kept.count * 10 < claudeInit.count)
        #expect(!TranscriptRowInk.drawsNothing(kind: .system, payload: kept))

        let event = AgentEvent.decode(line: String(decoding: kept, as: UTF8.self))
        guard case .initialized(let info)? = event else {
            Issue.record("the kept payload no longer decodes as an init")
            return
        }
        #expect(info.model == "claude-opus-5-5")
        #expect(info.permissionMode == "acceptEdits")
        #expect(info.agentKind == .claudeCode)
        #expect(info.sessionID == "s-1")
        #expect(info.cwd == "/tmp/work")
        #expect(info.version == "2.1.0")
        #expect(info.uuid == "u-1")
        #expect(info.tools.isEmpty)
        #expect(info.slashCommands.isEmpty)
        let json = try #require(JSONValue.parse(kept))
        #expect(json["parent_tool_use_id"]?.stringValue == "toolu_parent")
    }

    @Test("a Codex init keeps the agent it names")
    func codexInitKeepsItsAgent() {
        let row = payload(
            #"{"type":"system","subtype":"init","session_id":"t","cwd":"/w","model":"gpt-5","#
                + #""permissionMode":"default","claude_code_version":"0.1","agent_kind":"codex"}"#
        )
        let kept = TranscriptRowPayload.retained(kind: .system, payload: row)
        guard case .initialized(let info)? = AgentEvent.decode(line: String(decoding: kept, as: UTF8.self)) else {
            Issue.record("the kept payload no longer decodes as an init")
            return
        }
        #expect(info.agentKind == .codex)
        #expect(info.model == "gpt-5")
    }

    @Test("an init with a long working directory is still found as an init")
    func longCwdStillDraws() {
        let cwd = "/" + String(repeating: "deep/", count: 60)
        let row = payload(#"{"type":"system","subtype":"init","cwd":"\#(cwd)","model":"opus","tools":["Read"]}"#)
        let kept = TranscriptRowPayload.retained(kind: .system, payload: row)
        #expect(!TranscriptRowInk.drawsNothing(kind: .system, payload: kept))
    }

    @Test("a background wake keeps its payload byte for byte")
    func backgroundWakeIsUntouched() {
        let row = payload(
            #"{"type":"system","subtype":"task_notification","task_id":"b1","status":"completed","summary":"done"}"#
        )
        #expect(TranscriptRowPayload.retained(kind: .system, payload: row) == row)
    }

    @Test("an init that is not an object is left as it came")
    func unreadableInitIsLeft() {
        let row = payload(#"{"type":"system","subtype":"init""#)
        #expect(TranscriptRowPayload.retained(kind: .system, payload: row) == row)
    }

    @Test("an init with nothing worth keeping is still a whole init")
    func bareInitStaysValid() {
        let row = payload(#"{"type":"system","subtype":"init","tools":["Read"]}"#)
        let kept = TranscriptRowPayload.retained(kind: .system, payload: row)
        #expect(kept == payload(#"{"type":"system","subtype":"init"}"#))
        guard case .initialized? = AgentEvent.decode(line: String(decoding: kept, as: UTF8.self)) else {
            Issue.record("a bare init no longer decodes")
            return
        }
    }

    @Test("a subtype that only starts like init is not rewritten as one")
    func lookalikeSubtypeIsLeft() {
        let row = payload(#"{"type":"system","subtype":"initialize","detail":"x"}"#)
        #expect(TranscriptRowPayload.retained(kind: .system, payload: row) == row)
    }

    @Test("an init payload under another kind is left whole")
    func initUnderAnotherKindIsLeft() {
        for kind in MessageKind.allCases where kind != .system {
            #expect(TranscriptRowPayload.retained(kind: kind, payload: claudeInit) == claudeInit)
        }
    }

    @Test("a hook named at the very end of the probed bytes is still a hook once trimmed")
    func hookAtTheEdgeSurvives() {
        let head = #"{"type":"system","subtype":"commands_changed","pad":""#
        let pad = String(repeating: "f", count: TranscriptRowInk.probeLength - head.utf8.count - 12)
        let row = payload(head + pad + #"","x":"hook_","tail":""# + String(repeating: "t", count: 500) + #""}"#)
        let kept = TranscriptRowPayload.retained(kind: .system, payload: row)
        #expect(TranscriptRowInk.namesHook(kind: .system, payload: row))
        #expect(TranscriptRowInk.namesHook(kind: .system, payload: kept))
        #expect(kept.count < row.count)
    }

    @Test("a background wake that names a hook is left whole")
    func wakeNamingAHookIsLeft() {
        let summary = "hook_check finished " + String(repeating: "s", count: 2_000)
        let row = payload(
            #"{"type":"system","subtype":"task_notification","task_id":"b1","status":"completed","summary":"\#(summary)","tool":"hook_"}"#
        )
        #expect(TranscriptRowPayload.retained(kind: .system, payload: row) == row)
    }

    @Test("a long row of another kind that names a hook is left whole")
    func otherKindsNamingAHookAreLeft() {
        let row = payload(#"{"type":"assistant","note":"hook_","text":"\#(String(repeating: "t", count: 4_000))"}"#)
        for kind in MessageKind.allCases where kind != .system {
            #expect(TranscriptRowPayload.retained(kind: kind, payload: row) == row)
        }
    }
}
