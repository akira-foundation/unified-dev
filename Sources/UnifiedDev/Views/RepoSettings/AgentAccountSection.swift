import SwiftUI
import Core

struct AgentAccountSection: View {
    var target: AccountScope

    @Environment(AppModel.self) private var app

    @State private var options: AgentAccountOptions?
    @State private var failure: String?

    var body: some View {
        AgentAccountRows(options: options, failure: failure, onPick: choose)
            .task(id: app.accountFingerprint(for: target)) {
                options = await app.accountOptions(in: target)
            }
    }

    private func choose(_ group: AgentAccountOptions.Group, _ pick: AgentAccountOptions.Pick) {
        guard pick != group.selected, let chosen = group.chosen(for: pick) else { return }
        failure = nil
        Task {
            failure = await app.chooseAccount(chosen, in: target)
        }
    }
}

struct ProfileAgentAccountSection: View {
    var profile: ProfileID

    @Environment(AppModel.self) private var app

    @State private var options: AgentAccountOptions?
    @State private var failure: String?

    var body: some View {
        AgentAccountRows(options: options, failure: failure, onPick: choose, onAddAccount: nil)
            .task(id: ProfileOptionsKey(
                fingerprint: app.accountFingerprint(for: AccountScope(profileID: profile)),
                accounts: app.agentAccounts.standings.map(\.home.id)
            )) {
                options = await app.profileAccountOptions(for: profile)
            }
    }

    private func choose(_ group: AgentAccountOptions.Group, _ pick: AgentAccountOptions.Pick) {
        guard pick != group.selected, let chosen = group.chosen(for: pick) else { return }
        failure = nil
        Task {
            failure = await app.chooseAccount(chosen, forProfile: profile)
        }
    }
}

private struct ProfileOptionsKey: Hashable {
    var fingerprint: AccountFingerprint
    var accounts: [AgentAccountID]
}

struct AgentAccountRows: View {
    var options: AgentAccountOptions?
    var failure: String?
    var onPick: (AgentAccountOptions.Group, AgentAccountOptions.Pick) -> Void
    var onAddAccount: (() -> Void)? = {
        SettingsTabRequest.post(.agents)
        SettingsWindow.open()
    }

    var body: some View {
        Section {
            if let options {
                if let words = options.footer { note(words, warns: false) }
                if options.offersToAddAnAccount, let onAddAccount {
                    Button("Open Agents Settings\u{2026}", action: onAddAccount)
                }
                ForEach(options.groups) { group in
                    SettingsRow(group.title) { row(group) }
                }
            } else {
                SettingsRow("Account") { ProgressView().controlSize(.small) }
            }
        } header: {
            Text("Agent account")
        } footer: {
            if let failure {
                Text(failure)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.negative)
            }
        }
    }

    private func row(_ group: AgentAccountOptions.Group) -> some View {
        VStack(alignment: .leading, spacing: Metrics.spacingSmall) {
            picker(group)
            note(group.note, warns: group.warns)
        }
    }

    private func note(_ words: String, warns: Bool) -> some View {
        Text(words)
            .font(Typo.caption)
            .foregroundStyle(warns ? Palette.warning : Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func picker(_ group: AgentAccountOptions.Group) -> some View {
        ViewThatFits(in: .horizontal) {
            menu(group).fixedSize()
            menu(group).truncationMode(.middle)
        }
        .help(group.selectedTitle)
    }

    private func menu(_ group: AgentAccountOptions.Group) -> some View {
        Picker(
            group.title,
            selection: Binding(get: { group.selected }, set: { onPick(group, $0) })
        ) {
            Text(group.inherit.title).tag(group.inherit.pick)

            ForEach(group.entries) { entry in
                Text(entry.title).tag(entry.pick)
            }

            if let unavailable = group.unavailable {
                Text(unavailable.title).tag(unavailable.pick)
            }
        }
        .labelsHidden()
    }
}
