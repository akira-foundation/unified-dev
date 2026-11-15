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

    static let commitPagesRead = 10

    static func commitAuthorsArguments(
        number: Int, in repository: ForgeRepository, context: String, page: String? = nil
    ) -> [String] {
        ["api", "\(path(of: repository))/pullrequests/\(number)/commits", "--param", "pagelen=100"]
            + (page.map { ["--param", "page=\($0)"] } ?? [])
            + ["--context", context]
    }

    static func nextCommitPage(_ next: String?, number: Int, in repository: ForgeRepository) -> String? {
        guard let next, let components = URLComponents(string: next),
              components.scheme == "https",
              components.host?.lowercased() == BitbucketAuthStatus.cloudHostKey,
              components.percentEncodedPath.lowercased()
                == "/2.0\(path(of: repository))/pullrequests/\(number)/commits".lowercased(),
              let page = components.queryItems?.first(where: { $0.name == "page" })?.value,
              !page.isEmpty, !page.hasPrefix("-")
        else { return nil }
        return page
    }

    static func decodeCommitPage(_ output: String) -> BitbucketPage<BitbucketCommitPayload>? {
        try? decode(BitbucketPage<BitbucketCommitPayload>.self, from: output)
    }

    static func commitAuthors(from pages: [BitbucketPage<BitbucketCommitPayload>]) -> PullRequestAutoFix.CommitAuthors? {
        guard let last = pages.last, last.next == nil,
              let head = pages.first?.values.first?.hash, !head.isEmpty
        else { return nil }
        let identities = pages.flatMap(\.values).map { $0.author?.user?.identity ?? "" }
        return PullRequestAutoFix.CommitAuthors(headCommit: head, logins: Set(identities))
    }

    static func commitAuthors(of pullRequest: PullRequest, in directory: String) async -> PullRequestAutoFix.CommitAuthors? {
        guard let (repository, context) = try? await connection(in: directory) else { return nil }
        var pages: [BitbucketPage<BitbucketCommitPayload>] = []
        var cursor: String?
        while pages.count < commitPagesRead {
            let arguments = commitAuthorsArguments(number: pullRequest.number, in: repository, context: context, page: cursor)
            guard let result = try? await run(arguments, directory: directory, timeout: .seconds(30)), result.ok,
                  let page = decodeCommitPage(result.stdout)
            else { return nil }
            pages.append(page)
            guard page.next != nil else { return commitAuthors(from: pages) }
            guard let following = nextCommitPage(page.next, number: pullRequest.number, in: repository) else { return nil }
            cursor = following
        }
        return nil
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
