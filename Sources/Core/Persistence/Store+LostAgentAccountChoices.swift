import Foundation

extension Store {
    public func takeLostAgentAccountChoices() throws -> [RepoID] {
        guard let value = try setting(LostAgentAccountChoices.settingKey) else { return [] }
        try setSetting(LostAgentAccountChoices.settingKey, nil)
        return LostAgentAccountChoices.decoded(value).map { RepoID($0) }
    }
}
