import SwiftUI
import Core

enum InspectorToolbar {
    struct GroupingButton: View {
        @Bindable var model: WorkspaceModel

        @AppStorage(ChangedFilePresentation.storageKey)
        private var isTree = ChangedFilePresentation.defaultsToTree

        var body: some View {
            Button { isTree.toggle() } label: {
                Image(systemName: isTree ? "folder.fill" : "folder")
            }
            .disabled(model.inspectorTab != .changes || model.changedFiles.isEmpty)
            .accessibilityLabel("Group changes by folder")
            .accessibilityAddTraits(isTree ? .isSelected : [])
            .help(
                isTree
                    ? "Show the changed files as a flat list"
                    : "Group the changed files by folder"
            )
        }
    }

    struct ScopeMenu: View {
        @Bindable var model: WorkspaceModel

        var body: some View {
            Menu {
                DiffScopeMenuItems(model: model)
            } label: {
                Label(
                    "What the changes are measured from",
                    systemImage: "line.3.horizontal.decrease"
                )
            }
            .disabled(model.inspectorTab != .changes)
            .help("What the changes are measured from")
        }
    }

    struct MergeButton: View {
        @Bindable var model: WorkspaceModel

        @Environment(AppModel.self) private var app

        @State private var isWorking = false
        @State private var pendingMerge: GitHub.MergeMethod?

        var body: some View {
            Menu {
                Picker("Merge method", selection: binding) {
                    ForEach(MergeMethodChoice.offered, id: \.self) { offered in
                        Text(offered.label).tag(offered)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(model.mergeMethod.buttonLabel)
            } primaryAction: {
                propose()
            }
            .disabled(isWorking)
            .help(model.mergeMethod.buttonLabel)
            .id(model.mergeMethod)
            .mergeConfirmation(
                $pendingMerge, model: model, canConfirm: canConfirm, arrowEdge: .bottom, onConfirm: merge
            )
        }

        private var canConfirm: Bool {
            model.canConfirmMerge(
                branchActions: .mayActOnBranch(
                    isAgentBusy: app.isRunning(model.workspace), pullRequest: model.pullRequest
                ),
                isWorking: isWorking
            )
        }

        private func propose() {
            guard canConfirm else { return }
            GitHubSignIn.shared.run(directory: model.workspace.path) { pendingMerge = model.mergeMethod }
        }

        private var binding: Binding<GitHub.MergeMethod> {
            Binding(
                get: { model.mergeMethod },
                set: { method in Task { await model.chooseMergeMethod(method) } }
            )
        }

        private func merge(_ method: GitHub.MergeMethod, confirmed: InstructionAuthority) {
            guard let pullRequest = model.pullRequest else { return }
            isWorking = true
            model.pullRequestNotice = nil
            Task {
                defer { isWorking = false }
                if let refusal = await model.requestMerge(
                    pullRequest, method: method, from: .inspectorToolbar, confirmed: confirmed
                ) {
                    model.pullRequestNotice = PullRequestNotice(
                        tone: .info, title: "Nothing was sent", message: refusal
                    )
                }
            }
        }
    }

    struct PushButton: View {
        @Bindable var model: WorkspaceModel

        @State private var isWorking = false

        var body: some View {
            Button {
                isWorking = true
                Task {
                    defer { isWorking = false }
                    _ = await model.requestPush(from: .inspectorToolbar)
                }
            } label: {
                Label("Push", systemImage: "arrow.up.circle")
            }
            .disabled(isWorking)
            .help("Hand the outstanding work to the agent to commit and push")
        }
    }

    struct MoreMenu: View {
        @Bindable var model: WorkspaceModel

        var body: some View {
            Menu {
                WorktreeMenuItems(workspace: model.workspace, pullRequest: model.pullRequest)
            } label: {
                Label("More for this worktree", systemImage: "ellipsis")
            }
            .help("More for this worktree")
        }
    }
}

@MainActor
enum InspectorTabTitle {
    static func of(_ tab: InspectorTab, model: WorkspaceModel) -> String {
        guard tab == .changes, !model.changedFiles.isEmpty else { return tab.rawValue }
        return "\(tab.rawValue) (\(model.changedFiles.count))"
    }
}

struct InspectorViewPicker: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        Menu {
            ForEach(model.availableInspectorTabs, id: \.self) { tab in
                Button {
                    model.inspectorTab = tab
                } label: {
                    Label(
                        InspectorTabTitle.of(tab, model: model),
                        systemImage: tab == model.inspectorTab ? "checkmark" : tab.symbol
                    )
                }
            }
        } label: {
            Label(title, systemImage: model.inspectorTab.symbol)
        }
        .labelStyle(.iconOnly)
        .help(title)
        .accessibilityLabel("Inspector view, \(title)")
        .fixedSize()
    }

    private var title: String { InspectorTabTitle.of(model.inspectorTab, model: model) }
}
