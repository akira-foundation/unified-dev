import Foundation
import QuartzCore
import Core

@MainActor
enum StreamToolResultsProbe {
    static var isRequested: Bool {
        ProbeHarness.isPresent("--stream-tools") && PreviewIdentity.isPreview(bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    private struct ToolPair {
        let call: String
        let use: Data
        let result: Data
        let isError: Bool
    }

    static func measure(transcript: TranscriptModel, store: Store) async -> [String: JSONValue] {
        let count = ProbeHarness.count("--stream-tools", or: 20)
        let bytes = ProbeHarness.count("--stream-tool-bytes", or: 2_000_000)
        let body = String(repeating: "0123456789abcdef\n", count: max(1, bytes / 17))
        let pairs = (0..<count).map { index in
            let id = "probe_tool_\(index)_\(UUID().uuidString)"
            let isError = index % 5 == 4
            return ToolPair(call: id, use: toolUse(id: id), result: toolResult(id: id, body: body, isError: isError), isError: isError)
        }
        let rowsBefore = transcript.rows.count
        let relay = StoredMessageRelay()

        var acceptCpu = 0.0
        let cpuBefore = ProbeHarness.mainThreadCPUSeconds()
        let wallBefore = CACurrentMediaTime()
        for pair in pairs {
            guard let use = try? await store.appendNext(
                sessionID: transcript.session.id, kind: .toolUse, payload: pair.use, refID: pair.call
            ) else { continue }
            relay.deposit(use)
            acceptCpu += await accept(
                .toolUse(AgentToolUse(id: pair.call, name: "Read", input: .object([:]), raw: pair.use)),
                seq: use.seq, relay: relay, transcript: transcript
            )
            guard let result = try? await store.appendNext(
                sessionID: transcript.session.id, kind: .toolResult, payload: pair.result, refID: pair.call
            ) else { continue }
            relay.deposit(result)
            acceptCpu += await accept(
                .toolResult(AgentToolResult(toolUseID: pair.call, text: "", isError: pair.isError, raw: pair.result)),
                seq: result.seq, relay: relay, transcript: transcript
            )
        }
        let wall = CACurrentMediaTime() - wallBefore
        let cpu = ProbeHarness.mainThreadCPUSeconds() - cpuBefore

        let added = transcript.rows.dropFirst(rowsBefore)
        let decidedRight = pairs.allSatisfy { pair in
            added.first { $0.refID == pair.call }.map { $0.isError == pair.isError && $0.resultPayload != nil } ?? false
        }
        return [
            "results": .integer(count),
            "resultBytes": .integer(pairs.first?.result.count ?? 0),
            "rowsAdded": .integer(added.count),
            "decidedRight": .bool(decidedRight),
            "wallSeconds": .number(wall),
            "mainThreadCpuMs": .number(cpu * 1000),
            "acceptCpuMs": .number(acceptCpu * 1000),
            "mainThreadCpuMsPerResult": .number(count > 0 ? cpu * 1000 / Double(count) : 0),
        ]
    }

    private static func accept(
        _ event: AgentEvent, seq: Int, relay: StoredMessageRelay, transcript: TranscriptModel
    ) async -> Double {
        let before = ProbeHarness.mainThreadCPUSeconds()
        await transcript.acceptForProbe(event, messageSeq: seq, relayedBy: relay)
        return ProbeHarness.mainThreadCPUSeconds() - before
    }

    private static func toolUse(id: String) -> Data {
        encoded([
            "type": "assistant",
            "message": ["role": "assistant", "content": [
                ["type": "tool_use", "id": id, "name": "Read", "input": ["file_path": "/tmp/probe.txt"]],
            ]],
        ])
    }

    private static func toolResult(id: String, body: String, isError: Bool) -> Data {
        encoded([
            "type": "user",
            "message": ["role": "user", "content": [
                ["type": "tool_result", "tool_use_id": id, "content": body, "is_error": isError],
            ]],
        ])
    }

    private static func encoded(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
