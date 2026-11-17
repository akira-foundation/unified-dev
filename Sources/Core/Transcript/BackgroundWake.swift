import Foundation

public struct BackgroundWake: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case command
        case agent
    }

    public enum Outcome: Sendable, Equatable {
        case finished
        case failed
        case stopped
    }

    public var source: Source
    public var outcome: Outcome
    public var name: String?
    public var exitCode: Int?
    public var summary: String
    public var outputFile: String?

    public init(_ report: SubagentReport) {
        let summary = report.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let exitCode = Self.exitCode(in: summary)
        self.summary = summary
        self.exitCode = exitCode
        self.name = Self.quotedName(in: summary)
        self.source = summary.hasPrefix("Background command") ? .command : .agent
        self.outcome = Self.outcome(status: report.status, exitCode: exitCode)
        self.outputFile = report.outputFile.flatMap { $0.isEmpty ? nil : $0 }
    }

    public var title: String {
        let noun = source == .command ? "Background command" : "Background agent"
        return switch outcome {
        case .finished: "\(noun) finished"
        case .failed: "\(noun) failed"
        case .stopped: "\(noun) stopped"
        }
    }

    public var exitLabel: String? { exitCode.map { "exit \($0)" } }

    private static let marker = Data("\"subtype\":\"task_notification\"".utf8)

    public static func isRow(kind: MessageKind, payload: Data) -> Bool {
        kind == .system && payload.prefix(TranscriptRowInk.probeLength).range(of: marker) != nil
    }

    public static func opensTurn(during state: SessionState) -> Bool {
        switch state {
        case .idle, .failed, .cancelled: true
        case .running, .waiting: false
        }
    }

    private static func quotedName(in summary: String) -> String? {
        guard let open = summary.firstIndex(of: "\""),
              let close = summary.lastIndex(of: "\""),
              open < close else { return nil }
        let name = summary[summary.index(after: open)..<close]
        return name.isEmpty ? nil : String(name)
    }

    private static func exitCode(in summary: String) -> Int? {
        guard let match = summary.firstMatch(of: /\(exit code (-?\d+)\)/) else { return nil }
        return Int(match.1)
    }

    private static func outcome(status: String, exitCode: Int?) -> Outcome {
        switch status {
        case "failed": .failed
        case "killed", "stopped", "cancelled": .stopped
        default: (exitCode ?? 0) == 0 ? .finished : .failed
        }
    }
}
