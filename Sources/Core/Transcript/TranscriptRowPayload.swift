import Foundation

public enum TranscriptRowPayload {
    private static let initHead = #"{"type":"system","subtype":"init""#

    private static let initKeys: Set<String> = [
        "session_id", "cwd", "model", "permissionMode", "agent_kind",
        "claude_code_version", "output_style", "uuid", "parent_tool_use_id",
    ]

    public static func retained(kind: MessageKind, payload: Data) -> Data {
        guard kind == .system, !BackgroundWake.isRow(kind: kind, payload: payload) else { return payload }
        if TranscriptRowInk.drawsNothing(kind: kind, payload: payload)
            || TranscriptRowInk.namesHook(kind: kind, payload: payload) {
            return Data([UInt8](payload.prefix(TranscriptRowInk.probeLength)))
        }
        return compactInit(payload) ?? payload
    }

    private static func compactInit(_ payload: Data) -> Data? {
        guard case .object(let fields)? = JSONValue.parse(payload),
              fields["subtype"]?.stringValue == "init" else { return nil }
        let kept = fields.filter { initKeys.contains($0.key) }
        let rest = JSONValue.object(kept).compactJSON.dropFirst()
        return Data((initHead + (kept.isEmpty ? "" : ",") + rest).utf8)
    }
}
