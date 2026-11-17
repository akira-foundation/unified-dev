import Foundation

struct BitbucketPage<Value: Decodable>: Decodable {
    let values: [Value]
    var next: String?
}

struct BitbucketPullRequestPayload: Decodable {
    struct Endpoint: Decodable {
        struct Branch: Decodable { let name: String? }
        struct Commit: Decodable { let hash: String? }
        struct Repository: Decodable {
            let fullName: String?

            enum CodingKeys: String, CodingKey { case fullName = "full_name" }
        }

        let branch: Branch?
        let commit: Commit?
        let repository: Repository?
    }

    struct User: Decodable {
        let nickname: String?
        let username: String?
        let displayName: String?
        var uuid: String?
        var accountID: String?

        enum CodingKeys: String, CodingKey {
            case nickname, username, uuid
            case displayName = "display_name"
            case accountID = "account_id"
        }
    }

    struct Participant: Decodable {
        let state: String?
        let approved: Bool?
    }

    struct Links: Decodable {
        struct Link: Decodable { let href: String? }
        let html: Link?
    }

    let id: Int?
    let title: String?
    let state: String?
    let draft: Bool?
    let updatedOn: String?
    let author: User?
    let source: Endpoint?
    let destination: Endpoint?
    let links: Links?
    let participants: [Participant]?

    enum CodingKeys: String, CodingKey {
        case id, title, state, draft, author, source, destination, links, participants
        case updatedOn = "updated_on"
    }

    var unifiedState: String {
        switch state?.uppercased() {
        case "OPEN": "OPEN"
        case "MERGED": "MERGED"
        case "DECLINED", "SUPERSEDED": "CLOSED"
        default: "UNKNOWN"
        }
    }

    var reviewDecision: String? {
        let states = (participants ?? []).map { $0.state?.lowercased() }
        if states.contains("changes_requested") { return "CHANGES_REQUESTED" }
        if states.contains("approved") || (participants ?? []).contains(where: { $0.approved == true }) {
            return "APPROVED"
        }
        return nil
    }

    var sourceRepository: String? { source?.repository?.fullName }

    var isFromFork: Bool? {
        guard let head = source?.repository?.fullName, let base = destination?.repository?.fullName else {
            return nil
        }
        return head.caseInsensitiveCompare(base) != .orderedSame
    }

    var pageFallback: String {
        let repository = destination?.repository?.fullName ?? ""
        return "https://bitbucket.org/\(repository)/pull-requests/\(id ?? 0)"
    }

    func pullRequest(runs read: [CheckRun]?) -> PullRequest {
        let runs = read ?? []
        let (checks, summary) = read.map(GitHub.rollup) ?? (.unavailable, GitHub.checksUnavailableSummary)
        let closed = unifiedState == "MERGED" || unifiedState == "CLOSED"
        return PullRequest(
            number: id ?? 0,
            title: title ?? "",
            url: links?.html?.href.flatMap { $0.isEmpty ? nil : $0 } ?? pageFallback,
            state: unifiedState,
            isDraft: draft ?? false,
            checks: checks,
            checksSummary: summary,
            reviewDecision: reviewDecision,
            branch: source?.branch?.name ?? "",
            baseBranch: destination?.branch?.name ?? "",
            closedAt: closed ? BitbucketDates.parse(updatedOn) : nil,
            headCommit: source?.commit?.hash,
            author: author?.identity,
            isFromFork: isFromFork,
            hasUnfinishedChecks: read.map { _ in runs.contains { CheckState($0) == .running || CheckState($0) == .queued } },
            hasFixableCheckFailure: read.map { _ in runs.contains { CheckState($0) == .failed } }
        )
    }
}

struct BitbucketCommitStatusPayload: Decodable {
    let key: String?
    let name: String?
    let state: String?
    let url: String?
    let createdOn: String?
    let updatedOn: String?

    enum CodingKeys: String, CodingKey {
        case key, name, state, url
        case createdOn = "created_on"
        case updatedOn = "updated_on"
    }

    var checkRun: CheckRun {
        let state = state?.uppercased() ?? ""
        let running = state == "INPROGRESS"
        let conclusion: String? = switch state {
        case "SUCCESSFUL": "SUCCESS"
        case "FAILED": "FAILURE"
        case "STOPPED": "CANCELLED"
        default: nil
        }
        return CheckRun(
            name: name ?? key ?? "Build",
            status: running ? "IN_PROGRESS" : (conclusion == nil ? "QUEUED" : "COMPLETED"),
            conclusion: conclusion,
            detailsURL: url,
            startedAt: BitbucketDates.parse(createdOn),
            completedAt: running ? nil : BitbucketDates.parse(updatedOn)
        )
    }
}

enum BitbucketDates {
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let trimmed = trimFraction(value)
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(trimmed))
            ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(trimmed))
    }

    private static func trimFraction(_ value: String) -> String {
        guard let dot = value.firstIndex(of: ".") else { return value }
        let digits = value[value.index(after: dot)...].prefix { $0.isNumber }
        guard digits.count > 3 else { return value }
        let end = value.index(value.index(after: dot), offsetBy: digits.count)
        return String(value[...value.index(dot, offsetBy: 3)]) + value[end...]
    }
}
