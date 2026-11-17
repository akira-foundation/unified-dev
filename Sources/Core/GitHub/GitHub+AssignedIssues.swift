import Foundation

extension GitHub {
    static let issuesDisabled = "has disabled issues"

    public static func issuesAssignedToViewer(repoPath: String) async -> [AssignedIssue]? {
        let arguments = [
            "issue", "list", "--state", "open", "--assignee", "@me",
            "--limit", String(viewerListLimit), "--json", "number,title",
        ]
        guard let result = try? await run("gh", arguments, cwd: repoPath, timeout: .seconds(20)) else { return nil }
        guard result.ok else { return result.stderr.contains(issuesDisabled) ? [] : nil }
        return decodeAssignedIssues(from: Data(result.stdout.utf8))
    }

    static func decodeAssignedIssues(from data: Data) -> [AssignedIssue]? {
        struct Payload: Decodable {
            let number: Int?
            let title: String?
        }
        guard let payloads = try? JSONDecoder().decode([Payload].self, from: data) else { return nil }
        return payloads.compactMap { payload in
            guard let number = payload.number, number > 0 else { return nil }
            return AssignedIssue(number: number, title: payload.title ?? "")
        }
    }
}
