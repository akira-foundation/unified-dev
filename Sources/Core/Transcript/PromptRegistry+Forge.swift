import Foundation

public extension PromptRegistry {
    static func defaultTemplate(for id: PromptID, forge: ForgeKind) -> String {
        if forge == .bitbucket, let bitbucket = bitbucketDefaults[id] { return bitbucket }
        return definition(for: id).defaultTemplate
    }

    static let bitbucketDefaults: [PromptID: String] = [
        .markReadyForReview: """
        Mark pull request {{url}} ready for review on Bitbucket using `bkt pr ready <number>`, the \
        number being the last part of that URL, then verify with `bkt pr view <number> --json` that \
        it is no longer a draft. If Bitbucket refuses, explain why. Do not merge the pull request, \
        commit or push changes, or start any other work.
        """,
    ]
}
