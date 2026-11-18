import Foundation

public struct OutputStyleShelf: Hashable, Sendable {
    public let project: String
    public let account: AgentAccountID?
    public let refused: Bool

    public init(project: String?, account: AgentAccountHome?, refused: Bool = false) {
        self.project = project ?? ""
        self.account = account?.id
        self.refused = refused
    }
}

@MainActor
public protocol AccountBound {
    init(account: AgentAccountHome?, refused: Bool)
}

@MainActor
public final class OutputStyleShelves<Catalogue: AccountBound> {
    private var held: [OutputStyleShelf: Catalogue] = [:]

    public init() {}

    public func catalogue(project: String?, account: AgentAccountHome?, refused: Bool = false) -> Catalogue {
        let shelf = OutputStyleShelf(project: project, account: account, refused: refused)
        if let standing = held[shelf] { return standing }
        let made = Catalogue(account: account, refused: refused)
        held[shelf] = made
        return made
    }
}
