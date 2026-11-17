import SwiftUI
import Core

struct MenuBarFooterModule: View {
    var focus: FocusState<MenuBarPanelFocus?>.Binding?
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        HStack(spacing: Metrics.spacingSmall) {
            row(MenuBarPanelContent.settingsTitle, command: .openSettings, target: .settings, action: openSettings)
            Spacer(minLength: Metrics.spacingWide)
            row(MenuBarPanelContent.quitTitle, command: .quit, target: .quit, action: quit)
        }
        .padding(Metrics.spacingSmall)
        .frame(maxWidth: .infinity)
        .menuBarSurface(RoundedRectangle(cornerRadius: MenuBarModuleStyle.corner, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MenuBarPanelContent.footerTitle)
    }

    private func row(
        _ title: String,
        command: MenuBarPanelKey.Command,
        target: MenuBarPanelFocus,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Metrics.spacing) {
                Text(title)
                if let key = MenuBarPanelKey.shortcut(for: command) {
                    Text(key.display)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .font(Typo.label)
            .padding(.horizontal, Metrics.inset - Metrics.spacingSmall)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuBarRowStyle())
        .panelFocus(focus, target)
    }
}
