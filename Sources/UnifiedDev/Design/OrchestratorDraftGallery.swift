import SwiftUI
import Core

#if DEBUG
struct OrchestratorDraftGallery: View {
    var app: AppModel

    private static let repo = Repo(id: RepoID("lantern"), name: "lantern", path: "/Users/x/dev/lantern")

    var body: some View {
        VStack(spacing: 48) {
            header(isOn: false)
            header(isOn: true)
        }
        .padding(Metrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
        .environment(app)
    }

    private func header(isOn: Bool) -> some View {
        NewWorkspaceHeader(
            point: .newBranch(from: "main"),
            remote: "origin",
            isBusy: false,
            busyLabel: "",
            roleNote: isOn ? "It plans and starts other workspaces, and never edits its own worktree." : nil
        ) {
            NewWorkspaceProjectChip(repo: Self.repo) { _ in }
            StartingPointChip(
                point: .newBranch(from: "main"),
                remote: "origin",
                catalogue: nil,
                pullRequests: .loading,
                cameFrom: nil,
                isPresented: .constant(false),
                onPick: { _ in }
            )
            NewWorkspaceOrchestratorChip(isOn: .constant(isOn))
        }
    }
}
#endif
