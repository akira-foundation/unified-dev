import Foundation
import AppKit
import Core

enum GitHubBridge {
    static func readPullRequest(for workspace: Workspace, maxAge: Duration = .zero) async -> PullRequestRead {
        await readPullRequestAndChecks(for: workspace, maxAge: maxAge).pullRequest
    }

    static func readPullRequestAndChecks(for workspace: Workspace, maxAge: Duration) async -> PullRequestReading {
        if let reading = await Bitbucket.readingIfHosted(for: workspace, maxAge: maxAge) { return reading }
        let availability = await GitHubAvailability.shared.check(directory: workspace.path)
        if availability == .notInstalled {
            return PullRequestReading(
                pullRequest: .unavailable(GitHubReadFailure(reason: .unavailable, message: "Install the GitHub CLI to refresh pull requests.")),
                checks: nil
            )
        }
        guard availability == .ready else {
            return PullRequestReading(
                pullRequest: .unavailable(GitHubReadFailure(reason: .authentication, message: "Connect GitHub to refresh pull requests.")),
                checks: nil
            )
        }
        return await GitHub.readPullRequestAndChecks(for: workspace, maxAge: maxAge)
    }

    static func pullRequest(
        for workspace: Workspace, maxAge: Duration = .zero
    ) async -> PullRequest? {
        guard case .current(let pullRequest) = await readPullRequest(for: workspace, maxAge: maxAge) else { return nil }
        return pullRequest
    }

    static func open(_ url: String) {
        guard let target = URL(string: url) else { return }
        NSWorkspace.shared.open(target)
    }
}

enum Reveal {
    static func inFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
    }

    @MainActor
    static func inEditor(_ path: String, repo: RepoID? = nil) {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        let target: OpenInTarget = isDirectory.boolValue ? .folder(path) : .file(path)
        if let app = OpenIn.preferred(for: target, repo: repo) {
            OpenIn.open(path, with: app, repo: repo)
            return
        }

        let url = URL(fileURLWithPath: path)
        for bundleID in ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode"] {
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.open(
                    [url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()
                )
                return
            }
        }
        NSWorkspace.shared.open(url)
    }
}
