import Foundation

public struct ProfileForgeChoice: Sendable, Hashable {
    public var gitHub: ProfileGitHubSource
    public var bitbucket: ProfileGitHubSource

    public init(gitHub: ProfileGitHubSource, bitbucket: ProfileGitHubSource) {
        self.gitHub = gitHub
        self.bitbucket = bitbucket
    }

    public static let own = ProfileForgeChoice(gitHub: .own, bitbucket: .own)
    public static let thisMac = ProfileForgeChoice(gitHub: .inherits, bitbucket: .inherits)

    public func source(for host: ForgeKind) -> ProfileGitHubSource {
        switch host {
        case .gitHub: gitHub
        case .bitbucket: bitbucket
        }
    }
}
