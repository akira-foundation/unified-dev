import Foundation

public struct AgentAccountRemovalNotice: Sendable, Equatable {
    public let account: AgentAccountID
    public let provider: AgentKind
    public let message: String
    public let forgotTheAccount: Bool

    public static func after(_ error: any Error, removing row: AgentAccountPanel.Row) -> AgentAccountRemovalNotice {
        let (message, forgot) = describe(error, removing: row)
        return AgentAccountRemovalNotice(
            account: row.id, provider: row.home.provider, message: message, forgotTheAccount: forgot
        )
    }

    public func belongs(to row: AgentAccountPanel.Row) -> Bool {
        row.id == account && row.home.provider == provider
    }

    public func isShown(among rows: [AgentAccountPanel.Row]) -> Bool {
        rows.contains(where: belongs)
    }

    public func isShownAbove(_ panel: AgentAccountPanel) -> Bool {
        panel.provider == provider && !isShown(among: panel.rows)
    }

    private static func describe(_ error: any Error, removing row: AgentAccountPanel.Row) -> (String, Bool) {
        let forgets = !row.isUnfinished
        switch error as? AgentAccountError {
        case .folderLeftAlone(let path)? where row.isUnfinished:
            return ("Could not remove \(row.title): its folder is not where Unified Dev expected it, so it was left alone: \(path)", false)
        case .folderLeftAlone(let path)?:
            return ("\(row.title) was forgotten, but its folder is not where Unified Dev expected it, so it was left alone: \(path)", true)
        case .forgottenWithFolderKept(let path)?:
            return ("\(row.title) was forgotten, but its folder may still be in use, so it was left alone and is listed as an unfinished sign-in: \(path)", forgets)
        case .keychainEntriesLeft(let services)?:
            return ("\(row.title) was removed. \(AgentAccountError.keychainEntriesLeft(services).readableMessage)", forgets)
        default:
            return ("Could not remove \(row.title): \(error.readableMessage)", false)
        }
    }
}
