import Foundation

public enum TerminalResumeOffer: Sendable, Equatable {
    case forget
    case withdraw
    case remember
    case offer

    public static func decide(launch: AgentAccountLaunch?, isRunning: Bool?) -> TerminalResumeOffer {
        guard launch?.isRefused == true else { return isRunning == true ? .remember : .offer }
        return isRunning == false ? .forget : .withdraw
    }
}
