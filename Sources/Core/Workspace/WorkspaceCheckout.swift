import Foundation

public struct PullRequestListing: Sendable, Hashable, Identifiable, Codable {
    public let number: Int
    public let title: String
    public let author: String
    public let headRefName: String
    public let baseRefName: String
    public let isDraft: Bool
    public let state: String
    public let isCrossRepository: Bool
    public let headRepositoryOwner: String?

    public var id: Int { number }

    public var isOpen: Bool { state.uppercased() == "OPEN" }

    public var qualifiedHead: String {
        guard !headRefName.isEmpty else { return "" }
        guard isCrossRepository, let owner = headRepositoryOwner, !owner.isEmpty else {
            return headRefName
        }
        return "\(owner):\(headRefName)"
    }

    public init(
        number: Int,
        title: String,
        author: String = "",
        headRefName: String,
        baseRefName: String,
        isDraft: Bool = false,
        state: String = "OPEN",
        isCrossRepository: Bool = false,
        headRepositoryOwner: String? = nil
    ) {
        self.number = number
        self.title = title
        self.author = author
        self.headRefName = headRefName
        self.baseRefName = baseRefName
        self.isDraft = isDraft
        self.state = state
        self.isCrossRepository = isCrossRepository
        self.headRepositoryOwner = headRepositoryOwner
    }
}

public struct ExistingBranch: Sendable, Hashable, Identifiable, Codable {
    public let name: String
    public let isLocal: Bool
    public let remoteName: String?
    public let inUseBy: BranchHolder?

    public var id: String { name }

    public init(name: String, isLocal: Bool, inUseBy: BranchHolder? = nil, remoteName: String? = nil) {
        self.name = name
        self.isLocal = isLocal
        self.remoteName = remoteName
        self.inUseBy = inUseBy
    }
}

public enum WorkspaceCheckout: Sendable, Hashable {
    case pullRequest(PullRequestListing)
    case branch(ExistingBranch)
}

public extension WorkspaceCheckout {
    func baseBranch(default defaultBranch: String) -> String {
        switch self {
        case .pullRequest(let request): request.baseRefName
        case .branch: defaultBranch
        }
    }

    var pullRequestNumber: Int? {
        switch self {
        case .pullRequest(let request): request.number
        case .branch: nil
        }
    }

    var workspaceName: String {
        switch self {
        case .pullRequest(let request):
            let title = Git.title(from: request.title, maxLength: 44)
            return title.isEmpty ? "#\(request.number)" : "#\(request.number) \(title)"
        case .branch(let branch):
            return branch.name
        }
    }

    var preferredLocalBranch: String {
        switch self {
        case .pullRequest(let request): request.headRefName
        case .branch(let branch): branch.name
        }
    }

    var alternateLocalBranch: String? {
        guard case .pullRequest(let request) = self,
              request.isCrossRepository,
              let owner = request.headRepositoryOwner,
              !owner.isEmpty
        else { return nil }
        return "\(owner)-\(request.headRefName)"
    }
}

public enum WorkspaceCheckoutPlan {
    public static func offered(_ requests: [PullRequestListing], limit: Int = 30) -> [PullRequestListing] {
        var seen = Set<Int>()
        return requests
            .filter(\.isOpen)
            .sorted { $0.number > $1.number }
            .filter { seen.insert($0.number).inserted }
            .prefix(limit)
            .map { $0 }
    }

    public static func offeredBranches(
        local: [String],
        remote: [String],
        defaultBranch: String,
        inUse: [String: BranchHolder] = [:],
        pullRequestHeads: Set<String> = [],
        remoteNames: [String] = ["origin"]
    ) -> [ExistingBranch] {
        var byName: [String: Bool] = [:]
        var remoteByName: [String: String] = [:]
        for name in local where !name.isEmpty { byName[name] = true }
        for reference in remote {
            let remote = remoteNames.sorted { $0.count > $1.count }.first { reference.hasPrefix($0 + "/") }
            let name = remote.flatMap { remoteBranchName(reference, remote: $0) }
            guard let name, byName[name] == nil else { continue }
            byName[name] = false
            remoteByName[name] = remote
        }
        for name in pullRequestHeads { byName[name] = nil }
        return byName
            .map { ExistingBranch(name: $0.key, isLocal: $0.value, inUseBy: inUse[$0.key], remoteName: remoteByName[$0.key]) }
            .sorted { lhs, rhs in
                let lhsLeads = lhs.name == defaultBranch
                guard lhsLeads == (rhs.name == defaultBranch) else { return lhsLeads }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    public static func everyBranch(
        local: [String], remote: [String], inUse: [String: BranchHolder] = [:], remoteNames: [String] = ["origin"]
    ) -> [ExistingBranch] {
        offeredBranches(local: local, remote: remote, defaultBranch: "", inUse: inUse, remoteNames: remoteNames)
    }

    public static func heads(of requests: [PullRequestListing]) -> Set<String> {
        Set(requests.filter { !$0.isCrossRepository }.map(\.headRefName))
    }

    static func remoteBranchName(_ reference: String, remote: String = "origin") -> String? {
        let prefix = remote + "/"
        guard reference.hasPrefix(prefix) else { return nil }
        let name = String(reference.dropFirst(prefix.count))
        guard !name.isEmpty, name != "HEAD" else { return nil }
        return name
    }

    public static func parseReference(_ text: String) -> PullRequestReference? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let host = url.host, host.contains("github") {
            let parts = url.path.split(separator: "/").map(String.init)
            guard let index = parts.firstIndex(where: { $0 == "pull" || $0 == "pulls" }),
                  index >= 2,
                  parts.count > index + 1,
                  let number = positiveNumber(parts[index + 1])
            else { return nil }
            return PullRequestReference(
                number: number, repository: "\(parts[index - 2])/\(parts[index - 1])"
            )
        }

        let bare = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard let number = positiveNumber(bare) else { return nil }
        return PullRequestReference(number: number, repository: nil)
    }

    private static func positiveNumber(_ text: String) -> Int? {
        guard !text.isEmpty, text.allSatisfy(\.isNumber), let value = Int(text), value > 0 else {
            return nil
        }
        return value
    }

    public static func localBranch(
        for checkout: WorkspaceCheckout, taken: Set<String>
    ) -> String {
        if case .branch(let branch) = checkout {
            return branch.name
        }
        let preferred = checkout.preferredLocalBranch
        guard taken.contains(preferred) else { return preferred }
        if case .pullRequest(let request) = checkout, !request.isCrossRepository {
            return preferred
        }
        if let alternate = checkout.alternateLocalBranch, !taken.contains(alternate) {
            return alternate
        }
        return Git.uniqueBranch(checkout.alternateLocalBranch ?? preferred, taken: taken)
    }

    public static func workspaceHolding(
        branch: String, in repoID: RepoID, among workspaces: [Workspace]
    ) -> Workspace? {
        workspaces.first { $0.state == .active && $0.repoID == repoID && $0.branch == branch }
    }

    public static func warning(for checkout: WorkspaceCheckout) -> String? {
        guard case .pullRequest(let request) = checkout else { return nil }
        switch request.state.uppercased() {
        case "MERGED": return "This pull request is already merged."
        case "CLOSED": return "This pull request was closed without merging."
        default: return nil
        }
    }
}

public struct PullRequestReference: Sendable, Hashable {
    public let number: Int
    public let repository: String?

    public init(number: Int, repository: String? = nil) {
        self.number = number
        self.repository = repository
    }
}

public enum WorkspaceCheckoutResolution: Sendable, Equatable {
    case checkout(WorkspaceCheckout)
    case failure(String)
}

public enum WorkspaceCheckoutResolver {
    public static func problem(
        with text: String, in repository: String?
    ) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Type a pull request number or paste its URL."
        }
        guard let reference = WorkspaceCheckoutPlan.parseReference(text) else {
            return "'\(text.trimmingCharacters(in: .whitespacesAndNewlines))' is not a pull request number or URL."
        }
        if let repository, let named = reference.repository,
           named.lowercased() != repository.lowercased() {
            return "That pull request belongs to \(named), and this project is \(repository)."
        }
        return nil
    }

    public static func resolve(_ text: String, repoPath: String) async -> WorkspaceCheckoutResolution {
        let slug = await ForgePullRequests.repositorySlug(repoPath: repoPath)
        if let problem = problem(with: text, in: slug) { return .failure(problem) }
        guard let reference = WorkspaceCheckoutPlan.parseReference(text) else {
            return .failure("That is not a pull request number or URL.")
        }
        do {
            let summary = try await ForgePullRequests.pullRequestSummary(
                number: reference.number, repoPath: repoPath
            )
            return .checkout(.pullRequest(summary))
        } catch {
            return .failure(error.readableMessage)
        }
    }
}
