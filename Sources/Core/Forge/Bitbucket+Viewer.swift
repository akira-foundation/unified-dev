import Foundation

struct BitbucketCommitPayload: Decodable {
    struct Author: Decodable {
        let user: BitbucketPullRequestPayload.User?
    }

    let hash: String?
    let author: Author?
}

extension Bitbucket {
    static func viewer(in directory: String) async -> String? {
        guard let (_, context) = try? await connection(in: directory),
              let result = try? await run(["api", "/user", "--context", context], directory: directory),
              result.ok,
              let user = try? decode(BitbucketPullRequestPayload.User.self, from: result.stdout)
        else { return nil }
        return user.identity
    }

    static func commitAuthorsArguments(number: Int, in repository: ForgeRepository, context: String) -> [String] {
        [
            "api", "\(path(of: repository))/pullrequests/\(number)/commits",
            "--param", "pagelen=100", "--context", context,
        ]
    }

    static func decodeCommitAuthors(_ output: String) -> PullRequestAutoFix.CommitAuthors? {
        guard let page = try? decode(BitbucketPage<BitbucketCommitPayload>.self, from: output),
              page.next == nil,
              let head = page.values.first?.hash, !head.isEmpty
        else { return nil }
        let identities = page.values.map { $0.author?.user?.identity ?? "" }
        return PullRequestAutoFix.CommitAuthors(headCommit: head, logins: Set(identities))
    }

    static func commitAuthors(of pullRequest: PullRequest, in directory: String) async -> PullRequestAutoFix.CommitAuthors? {
        guard let (repository, context) = try? await connection(in: directory) else { return nil }
        let arguments = commitAuthorsArguments(number: pullRequest.number, in: repository, context: context)
        guard let result = try? await run(arguments, directory: directory, timeout: .seconds(30)), result.ok
        else { return nil }
        return decodeCommitAuthors(result.stdout)
    }
}

extension BitbucketPullRequestPayload.User {
    var identity: String? {
        [uuid, accountID].compactMap { $0 }.first { !$0.isEmpty }
    }

    var name: String? {
        [nickname, username, displayName].compactMap { $0 }.first { !$0.isEmpty }
    }
}
