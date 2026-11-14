import Foundation

public enum FastModeAvailability: Equatable, Sendable {
    case available
    case loading
    case unavailable
}

public extension ComposerControls {
    func fastModeAvailability(codexSpeed: CodexSpeed?, codexSpeedFailed: Bool) -> FastModeAvailability {
        switch agentKind {
        case .claudeCode:
            return .available
        case .codex:
            if let codexSpeed { return codexSpeed.supportsFast ? .available : .unavailable }
            return codexSpeedFailed ? .unavailable : .loading
        case .grok, .antigravity, .cursor, .openCode:
            return .unavailable
        }
    }

    func isFast(codexSpeed: CodexSpeed?) -> Bool {
        agentKind == .codex ? codexSpeed?.isFast(override: codexFastMode) ?? false : isFastMode
    }

    func settingFastMode(_ value: Bool) -> ComposerControls {
        var next = self
        if agentKind == .codex {
            next.codexFastMode = value
        } else {
            next.isFastMode = value
        }
        return next
    }

    func fastModeState(availability: FastModeAvailability, codexSpeed: CodexSpeed?) -> String {
        availability == .loading ? "Checking" : (isFast(codexSpeed: codexSpeed) ? "On" : "Off")
    }

    func fastModeHelp(availability: FastModeAvailability) -> String {
        if availability == .loading { return "Checking whether this model has fast mode." }
        return agentKind == .codex
            ? "Faster replies use more of your Codex allowance. Changes apply to this conversation."
            : "Disable thinking for faster replies. Changes apply to this conversation."
    }
}
