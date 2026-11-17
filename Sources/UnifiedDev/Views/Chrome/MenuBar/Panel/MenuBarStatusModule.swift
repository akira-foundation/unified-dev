import SwiftUI
import Core

struct MenuBarStatusModule: View {
    let content: MenuBarPanelContent
    var focus: FocusState<MenuBarPanelFocus?>.Binding?
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacingWide) {
            HStack(spacing: Metrics.spacingWide) {
                Circle()
                    .fill(dot)
                    .frame(width: 8, height: 8)
                    .frame(width: MenuBarModuleStyle.chip)
                    .accessibilityHidden(true)
                Text(content.headline)
                    .font(Typo.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Metrics.spacingWide)
                if let profile = content.profile {
                    profilePill(profile)
                }
            }
            .help(content.sentence)
            if content.needsSetup {
                Button(MenuBarPanelContent.setupAction, action: openSettings)
                    .linkButton()
                    .panelFocus(focus, .setup)
            }
        }
        .menuBarModule(MenuBarPanelContent.statusTitle, inset: Metrics.inset)
        .accessibilityValue(content.sentence)
    }

    private var dot: Color {
        switch content.activity {
        case .running: Palette.running
        case .waiting: Palette.warning
        case .idle: Palette.textSecondary.opacity(0.5)
        }
    }

    private func profilePill(_ profile: Profile) -> some View {
        Label {
            Text(profile.name)
                .lineLimit(1)
        } icon: {
            ProfileMark(symbol: profile.symbol, colour: profile.colour)
        }
        .font(Typo.captionEmphasis)
        .padding(.horizontal, Metrics.spacingWide)
        .padding(.vertical, Metrics.spacingTight)
        .background(Capsule().fill(Palette.textPrimary.opacity(0.1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profile.activeLabel)
    }
}
