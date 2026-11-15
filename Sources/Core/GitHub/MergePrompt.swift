import Foundation

public struct MergePromptContext: Sendable, Hashable {
    public static let noBranch = "(gh did not report the branch name: do not guess it, and leave "
        + "the branch on the server alone)"

    public static let noTitle = "(gh did not report the title)"

    public var workspaceName: String
    public var number: Int
    public var title: String
    public var branch: String
    public var baseBranch: String
    public var method: GitHub.MergeMethod
    public var forge: ForgeKind

    public init(
        workspaceName: String,
        number: Int,
        title: String,
        branch: String,
        baseBranch: String,
        method: GitHub.MergeMethod,
        forge: ForgeKind = .gitHub
    ) {
        self.workspaceName = workspaceName
        self.number = number
        self.title = title
        self.branch = branch
        self.baseBranch = baseBranch
        self.method = method
        self.forge = forge
    }

    public init(workspace: Workspace, pullRequest: PullRequest, method: GitHub.MergeMethod) {
        self.init(
            workspaceName: workspace.name,
            number: pullRequest.number,
            title: pullRequest.title,
            branch: pullRequest.branch,
            baseBranch: pullRequest.targetBranch(or: workspace.baseBranch),
            method: method,
            forge: pullRequest.forge
        )
    }

    public var values: [String: String] {
        [
            PromptRegistry.MergePullRequest.workspace: workspaceName,
            PromptRegistry.MergePullRequest.number: String(number),
            PromptRegistry.MergePullRequest.title: title.isEmpty ? missing(Self.noTitle) : title,
            PromptRegistry.MergePullRequest.branch: branch.isEmpty ? missing(Self.noBranch) : branch,
            PromptRegistry.MergePullRequest.baseBranch: baseBranch,
            PromptRegistry.MergePullRequest.method: method.phrase,
            PromptRegistry.MergePullRequest.methodFlag: method.flag(on: forge),
        ]
    }

    public func render(template: String) -> PromptRender {
        PromptTemplate.render(template, values: values)
    }

    private func missing(_ sentence: String) -> String {
        forge == .gitHub ? sentence : sentence.replacingOccurrences(of: "(gh did", with: "(bkt did")
    }
}

public extension GitHub.MergeMethod {
    var phrase: String {
        switch self {
        case .merge: "merge commit"
        case .squash: "squash merge"
        case .rebase: "rebase merge"
        }
    }

    var flag: String { "--\(rawValue)" }

    var bitbucketStrategy: String {
        switch self {
        case .merge: "merge_commit"
        case .squash: "squash"
        case .rebase: "rebase_fast_forward"
        }
    }

    func flag(on forge: ForgeKind) -> String {
        switch forge {
        case .gitHub: flag
        case .bitbucket: "--strategy \(bitbucketStrategy)"
        }
    }
}
