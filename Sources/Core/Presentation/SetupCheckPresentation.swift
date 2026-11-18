import Foundation

public enum SetupCheckTone: Sendable, Hashable {
    case checking
    case ready
    case needed
    case optional
}

public struct SetupCheckPresentation: Sendable, Hashable {
    public let check: SetupCheck
    public let severity: SetupSeverity
    public let isReportSettled: Bool

    public init(check: SetupCheck, in report: SetupReport) {
        self.check = check
        self.severity = report.severity(for: check.tool)
        self.isReportSettled = report.isSettled
    }

    public init(tool: SetupTool, in report: SetupReport) {
        self.init(check: SetupCheck(tool: tool, outcome: report.outcome(for: tool)), in: report)
    }

    public var tool: SetupTool { check.tool }

    public var fix: SetupFix? { check.fix }

    public var tone: SetupCheckTone {
        switch check.outcome {
        case .pending: .checking
        case .ready: .ready
        case .needsSignIn, .missing: severity == .problem ? .needed : .optional
        }
    }

    public var isUrgent: Bool { tone == .needed }

    public var showsDetailInCode: Bool { tone == .ready && check.outcome.detail != nil }

    public var status: String {
        switch check.outcome {
        case .pending: "Checking"
        case .ready(let detail): detail ?? "Ready"
        case .needsSignIn: stateWord("Not signed in")
        case .missing: stateWord("Not installed")
        }
    }

    private func stateWord(_ state: String) -> String {
        tone == .optional && isReportSettled ? "Optional, \(state.lowercased())" : state
    }
}

public extension SetupReport {
    func presentation(for check: SetupCheck) -> SetupCheckPresentation {
        SetupCheckPresentation(check: check, in: self)
    }
}
