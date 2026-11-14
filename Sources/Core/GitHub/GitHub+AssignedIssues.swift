import Foundation

extension GitHub {
    public static func issuesAssignedToViewer(repoPath: String) async -> [AssignedIssue]? {
        let arguments = [
            "issue", "list", "--state", "open", "--assignee", "@me",
            "--limit", String(awaitingViewerLimit), "--json", "number,title",
        ]
        guard let result = try? await run("gh", arguments, cwd: repoPath, timeout: .seconds(20)), result.ok,
              let issues = decodeAssignedIssues(from: Data(result.stdout.utf8)) else { return nil }
        return issues
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
