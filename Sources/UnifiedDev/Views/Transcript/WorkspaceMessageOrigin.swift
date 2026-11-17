import SwiftUI
import Core

struct WorkspaceMessageOrigin: View {
    enum Direction {
        case from
        case to
    }

    var end: WorkspaceMessageEnd?
    var direction: Direction

    @Environment(AppModel.self) private var app

    private var resolved: WorkspaceMessageEnd { end ?? .ownerClient }

    private var detail: String {
        [resolved.profile ?? "", resolved.project, resolved.chat].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Metrics.spacingSmall) {
            Text(String(resolved.workspace.prefix(1)).uppercased())
                .font(Typo.micro)
                .fontWeight(.bold)
                .foregroundStyle(Palette.windowBackground)
                .frame(width: 16, height: 16)
                .background(Palette.workspaceMessage, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)

            if direction == .to {
                Text("To").foregroundStyle(Palette.textTertiary)
            }
            title
            if !detail.isEmpty {
                Text("· \(detail)").foregroundStyle(Palette.textTertiary)
            }
        }
        .font(Typo.caption)
        .lineLimit(1)
        .truncationMode(.middle)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var title: some View {
        if let id = resolved.workspaceID, app.canRevealWorkspace(id) {
            Button(resolved.workspace) { app.revealWorkspace(id) }
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.workspaceMessage)
                .pointerStyle(.link)
                .accessibilityLabel("Open \(resolved.workspace)")
        } else {
            Text(resolved.workspace)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.workspaceMessage)
        }
    }
}
