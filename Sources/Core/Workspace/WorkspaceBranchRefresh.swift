import Foundation

extension WorkspaceManager {
    public func refreshBranch(workspace: Workspace) async {
        guard workspace.state == .active, !Task.isCancelled,
              let checkedOut = await checkedOutBranch(in: workspace.path),
              checkedOut != "HEAD", Git.isValidBranchName(checkedOut),
              checkedOut != workspace.branch, checkedOut != workspace.baseBranch,
              let repo = try? await store.repo(id: workspace.repoID),
              checkedOut != repo.defaultBranch,
              !Task.isCancelled else { return }

        guard Git.isValidBranchName(workspace.branch),
              let old = try? await Git.run(
                  ["show-ref", "--verify", "--quiet", "--", "refs/heads/\(workspace.branch)"],
                  in: workspace.path
              ), old.status == 1, !Task.isCancelled else { return }
        try? await store.updateCheckedOutBranch(checkedOut, observed: workspace)
    }

    private func checkedOutBranch(in path: String) async -> String? {
        if let read = Git.headBranch(in: path), read == "HEAD" || Git.isValidBranchName(read) { return read }
        guard let result = try? await Git.run(
            ["rev-parse", "--show-toplevel", "--symbolic-full-name", "HEAD"], in: path
        ), result.ok else { return nil }
        let lines = result.lines
        guard lines.count == 2,
              URL(fileURLWithPath: lines[0]).resolvingSymlinksInPath().path
                == URL(fileURLWithPath: path).resolvingSymlinksInPath().path else { return nil }
        let prefix = "refs/heads/"
        guard lines[1].hasPrefix(prefix) else { return "HEAD" }
        return String(lines[1].dropFirst(prefix.count))
    }
}
