import Foundation
import Core

extension WorkspaceModel {
    func sendAutoFixRequest(
        _ attempt: PullRequestAutoFix.Attempt, pullRequest: PullRequest, into session: Session
    ) async -> Bool {
        guard let text = await autoFixText(attempt, pullRequest: pullRequest),
              let chat = existingTranscript(for: session.id),
              PullRequestAutoFix.chat(chat.pullRequestAutoFixReading) == .ready
        else { return false }
        return await chat.submitAppRequest(text, keepsPlace: true)
    }

    private func autoFixText(_ attempt: PullRequestAutoFix.Attempt, pullRequest: PullRequest) async -> String? {
        switch attempt.reason {
        case .conflicts: await autoFixConflictsText(pullRequest)
        case .checks: await autoFixChecksText(attempt, pullRequest: pullRequest)
        }
    }

    private func autoFixConflictsText(_ pullRequest: PullRequest) async -> String {
        let context = FixConflictsPromptContext(workspace: workspace, pullRequest: pullRequest)
        let request = context.request(template: PromptOverrides().template(for: .fixConflicts))
        let path = workspace.path
        return await Task.detached(priority: .utility) {
            ConflictInstructions.asking(
                request,
                in: path,
                contents: ConflictInstructions.automaticMarkdown,
                writingTo: ConflictInstructions.automaticScratchPath
            )
        }.value
    }

    private func autoFixChecksText(
        _ attempt: PullRequestAutoFix.Attempt, pullRequest: PullRequest
    ) async -> String? {
        let asked = workspace
        let read = await Task.detached(priority: .utility) {
            try? await ForgePullRequests.headAndChecks(for: asked)
        }.value
        guard let read, read.head == attempt.headCommit else { return nil }
        let failed = read.runs.filter { CheckState($0) == .failed }
        guard !failed.isEmpty else { return nil }
        return await checkFailureRequest(for: failed, number: pullRequest.number)
    }
}
