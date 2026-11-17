import AppKit
import Core
import SwiftUI

struct ProfileSwitcherToolbar: ToolbarContent {
    var placement: ToolbarItemPlacement
    var profiles: [Profile]
    var activeID: ProfileID
    var drawsSidebar: Bool
    var barIsHidden = false
    var sidebarWidth: CGFloat
    var onSwitch: (ProfileID) -> Void
    var onNew: () -> Void
    var onSettings: () -> Void

    var body: some ToolbarContent {
        if let active = profiles.first(where: { $0.id == activeID }) {
            let label = ProfileToolbarLabel.resolve(
                profileName: active.name,
                drawsSidebar: drawsSidebar,
                barIsHidden: barIsHidden,
                sidebarWidth: sidebarWidth
            )
            ToolbarItem(placement: placement) {
                ProfileSwitcherMenu(
                    active: active,
                    label: label,
                    items: ProfileSwitcherItems(
                        profiles: profiles, activeID: activeID, onSwitch: onSwitch, onNew: onNew, onSettings: onSettings
                    )
                )
            }
            .sharedBackgroundVisibility(label.sitsOnGlass ? .automatic : .hidden)
        }
    }
}

extension ProfileSwitcherToolbar {
    @MainActor
    init(
        app: AppModel,
        placement: ToolbarItemPlacement,
        drawsSidebar: Bool,
        barIsHidden: Bool = false,
        sidebarWidth: CGFloat
    ) {
        self.init(
            placement: placement,
            profiles: app.profiles,
            activeID: app.activeProfileID,
            drawsSidebar: drawsSidebar,
            barIsHidden: barIsHidden,
            sidebarWidth: sidebarWidth,
            onSwitch: { id in Task { await app.switchProfile(to: id) } },
            onNew: { app.askForProfileSheet(.new) },
            onSettings: {
                guard let active = app.activeProfile else { return }
                app.askForProfileSheet(.edit(active))
            }
        )
    }
}

struct ProfileSwitcherMenu: View {
    var active: Profile
    var label: ProfileToolbarLabel
    var items: ProfileSwitcherItems

    static func nameWidth(_ name: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return ceil((name as NSString).size(withAttributes: [.font: font]).width)
    }

    var body: some View {
        styledMenu
            .menuIndicator(.hidden)
            .frame(maxWidth: label.menuWidth)
            .help(label.help)
            .accessibilityLabel(label.accessibilityLabel)
            .id(label.measureKey)
    }

    @ViewBuilder
    private var styledMenu: some View {
        if label.sitsOnGlass {
            menu
        } else {
            menu.menuStyle(.button).buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var mark: some View {
        if label.sitsOnGlass, let image = ProfileMarkImage.of(symbol: active.symbol, colour: active.colour) {
            Image(nsImage: image).renderingMode(.original).accessibilityHidden(true)
        } else {
            ProfileMark(symbol: active.symbol, colour: active.colour)
        }
    }

    private var menu: some View {
        Menu {
            items
        } label: {
            HStack(spacing: Metrics.spacingSmall) {
                HStack(spacing: SidebarMetrics.navGap) {
                    mark
                        .font(.system(size: SidebarMetrics.navIconSize))
                        .frame(width: SidebarMetrics.navIconColumn)

                    if label.menuWidth != nil {
                        Text(active.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                if label.menuWidth != nil {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
    }
}

struct ProfileSwitcherItems: View {
    var profiles: [Profile]
    var activeID: ProfileID
    var onSwitch: (ProfileID) -> Void
    var onNew: () -> Void
    var onSettings: () -> Void

    var body: some View {
        Picker(selection: selection) {
            ForEach(profiles) { profile in
                ProfileMenuLabel(profile: profile)
                    .tag(profile.id)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.inline)

        Button("New Profile\u{2026}", action: onNew)
        Button("Profile Settings\u{2026}", action: onSettings)
    }

    private var selection: Binding<ProfileID> {
        Binding(get: { activeID }, set: { onSwitch($0) })
    }
}
