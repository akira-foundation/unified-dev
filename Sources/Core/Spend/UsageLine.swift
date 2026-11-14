import Foundation

public enum UsageLine {
    public static func record(
        in bytes: UnsafeBufferPointer<UInt8>,
        from start: Int,
        to end: Int,
        provider: AgentKind,
        carry: inout TranscriptCarry
    ) -> SpendRecord? {
        switch provider {
        case .claudeCode:
            ClaudeUsageLine.record(in: bytes, from: start, to: end)
        case .codex:
            CodexUsageLine.record(in: bytes, from: start, to: end, carry: &carry)
        case .grok, .antigravity, .cursor, .openCode:
            nil
        }
    }

    static func record(
        inLine line: String,
        provider: AgentKind,
        carry: inout TranscriptCarry
    ) -> SpendRecord? {
        let bytes = [UInt8](line.utf8)
        var carried = carry
        let record = bytes.withUnsafeBufferPointer { buffer in
            UsageLine.record(
                in: buffer, from: 0, to: buffer.count, provider: provider, carry: &carried
            )
        }
        carry = carried
        return record
    }
}
