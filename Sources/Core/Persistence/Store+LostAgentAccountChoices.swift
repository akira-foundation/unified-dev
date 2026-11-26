import Foundation

extension Store {
    public func lostAgentAccountChoices() throws -> [RepoID] {
        try setting(LostAgentAccountChoices.settingKey).map(LostAgentAccountChoices.decoded) ?? []
    }

    public func forgetLostAgentAccountChoices() throws {
        try setSetting(LostAgentAccountChoices.settingKey, nil)
    }
}
