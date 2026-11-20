import Foundation

extension AgentAccountSwitch {
    public func destination(of account: AgentAccountHome) -> AgentAccountHome? {
        guard relaunch, refusal == nil, let directory else { return nil }
        return AgentAccountHome(
            provider: account.provider,
            id: account.id,
            directory: directory,
            isDefault: account.isDefault,
            label: account.label,
            identityBesideDirectory: account.identityBesideDirectory
        )
    }
}
