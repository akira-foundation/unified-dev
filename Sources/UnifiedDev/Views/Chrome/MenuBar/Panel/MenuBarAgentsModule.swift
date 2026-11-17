import SwiftUI
import Core

struct MenuBarAgentsModule: View {
    let agents: [MenuBarPanelContent.Agent]
    let more: Int
    var focus: FocusState<MenuBarPanelFocus?>.Binding?
    let open: (WorkspaceID) -> Void
    let openRunning: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacingSmall) {
            if agents.isEmpty {
                Text(MenuBarPanelContent.noAgentsLine)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(agents) { agent in
                row(agent)
            }
            if more > 0 {
                Button(MenuBarPanelContent.moreTitle(more), action: openRunning)
                    .linkButton()
                    .panelFocus(focus, .moreAgents)
            }
        }
        .menuBarModule(MenuBarPanelContent.agentsTitle, inset: Metrics.inset)
    }

    private func row(_ agent: MenuBarPanelContent.Agent) -> some View {
        Button {
            open(agent.id)
        } label: {
            HStack(spacing: Metrics.spacingWide) {
                Image(systemName: agent.symbolName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(agent.isWaiting ? Palette.warning : Palette.running)
                    .frame(width: MenuBarModuleStyle.chip, height: MenuBarModuleStyle.chip)
                    .background(Circle().fill((agent.isWaiting ? Palette.warning : Palette.running).opacity(0.18)))
                Text(agent.workspace.name)
                    .font(Typo.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Metrics.spacingWide)
                Text(agent.label)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(agent.workspace.name), \(agent.label)")
        .panelFocus(focus, .agent(agent.id))
    }
}
