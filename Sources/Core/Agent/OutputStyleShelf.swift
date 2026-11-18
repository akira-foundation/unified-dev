import Foundation

public struct OutputStyleShelf: Hashable, Sendable {
    public let project: String
    public let account: AgentAccountID?
    public let refused: Set<AgentKind>

    public init(project: String?, account: AgentAccountHome?, refusing refused: Set<AgentKind> = []) {
        self.project = project ?? ""
        self.account = account?.id
        self.refused = refused
    }
}

@MainActor
public protocol AccountBound {
    init(account: AgentAccountHome?, refusing: Set<AgentKind>)
}

@MainActor
public final class OutputStyleShelves<Catalogue: AccountBound> {
    private var held: [OutputStyleShelf: Catalogue] = [:]

    public init() {}

    public func catalogue(
        project: String?,
        account: AgentAccountHome?,
        refusing refused: Set<AgentKind> = []
    ) -> Catalogue {
        let shelf = OutputStyleShelf(project: project, account: account, refusing: refused)
        if let standing = held[shelf] { return standing }
        let made = Catalogue(account: account, refusing: refused)
        held[shelf] = made
        return made
    }
}
