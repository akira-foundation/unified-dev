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
        return user.login
    }

    static func commitAuthorsArguments(number: Int, in repository: ForgeRepository, context: String) -> [String] {
        [
            "api", "\(path(of: repository))/pullrequests/\(number)/commits",
            "--param", "pagelen=100", "--context", context,
        ]
    }

    static func decodeCommitAuthors(_ output: String, head: String?) -> PullRequestAutoFix.CommitAuthors? {
        guard let head, !head.isEmpty,
              let page = try? decode(BitbucketPage<BitbucketCommitPayload>.self, from: output),
              !page.values.isEmpty
        else { return nil }
        let logins = page.values.map { $0.author?.user?.login ?? "" }
        return PullRequestAutoFix.CommitAuthors(headCommit: head, logins: Set(logins))
    }

    static func commitAuthors(of pullRequest: PullRequest, in directory: String) async -> PullRequestAutoFix.CommitAuthors? {
        guard let (repository, context) = try? await connection(in: directory) else { return nil }
        let arguments = commitAuthorsArguments(number: pullRequest.number, in: repository, context: context)
        guard let result = try? await run(arguments, directory: directory, timeout: .seconds(30)), result.ok
        else { return nil }
        return decodeCommitAuthors(result.stdout, head: pullRequest.headCommit)
    }
}

extension BitbucketPullRequestPayload.User {
    var login: String? {
        [nickname, username, displayName].compactMap { $0 }.first { !$0.isEmpty }
    }
}
