import SwiftUI
import Core

struct AgentAccountsSection: View {
    let panel: AgentAccountPanel
    let activity: AgentAccountsModel.Activity
    var removalNotice: AgentAccountRemovalNotice?
    var onDismissRemovalNotice: () -> Void = {}
    let canSignIn: Bool
    let onAdd: () -> Void
    let onRemove: (AgentAccountPanel.Row) -> Void
    let onSignInAgain: (AgentAccountPanel.Row) -> Void

    var body: some View {
        ForEach(panel.rows) { row in
            AgentAccountRowSection(
                row: row,
                refusal: removalNotice.flatMap { $0.belongs(to: row) ? $0.message : nil },
                canSignIn: canSignIn && activity != .confirmingSignIn,
                onDismissRefusal: onDismissRemovalNotice,
                onRemove: onRemove,
                onSignInAgain: onSignInAgain
            )
        }

        Section {
            switch panel.offer {
            case .available:
                HStack(spacing: Metrics.gutter) {
                    Button("Add account…", action: onAdd)
                        .disabled(!canSignIn || activity == .confirmingSignIn)
                    if let progress {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                        Text(progress)
                            .settingsFootnote()
                    }
                }
            case .unavailable(let reason):
                Label {
                    Text(reason)
                        .settingsFootnote()
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: Metrics.spacingSmall) {
                if let footer = panel.footer {
                    Text(footer)
                        .settingsFootnote()
                }
                if panel.offer.isAvailable {
                    Text("Sign in with another \(panel.provider.label) account. Each project can then choose which account runs.")
                        .settingsFootnote()
                }
            }
        }
    }

    private var progress: String? {
        switch activity {
        case .idle: nil
        case .checkingSessions: "Checking sessions"
        case .confirmingSignIn: "Confirming the sign-in"
        }
    }
}

private struct AgentAccountRowSection: View {
    let row: AgentAccountPanel.Row
    let refusal: String?
    let canSignIn: Bool
    let onDismissRefusal: () -> Void
    let onRemove: (AgentAccountPanel.Row) -> Void
    let onSignInAgain: (AgentAccountPanel.Row) -> Void

    var body: some View {
        Section {
            ForEach(row.fields) { field in
                SettingsRow(field.label) {
                    Text(field.value)
                        .foregroundStyle(field.isKnown ? Palette.textSecondary : Palette.textTertiary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if !row.isDefault, let note = row.note {
                Text(note)
                    .font(Typo.caption)
                    .foregroundStyle(row.warns ? Palette.warning : Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if row.offersSignInAgain {
                Button("\(AgentAccountSignInAgain.actionTitle)…") { onSignInAgain(row) }
                    .disabled(!canSignIn)
            }

            if let removal = row.removal {
                Button("\(removal.actionTitle)…", role: .destructive) { onRemove(row) }
            }

            if let refusal {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.spacing) {
                    Label(refusal, systemImage: "exclamationmark.triangle.fill")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.negative)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Dismiss", systemImage: "xmark.circle.fill", action: onDismissRefusal)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        } header: {
            Text(row.title)
        } footer: {
            if row.isDefault, let note = row.note {
                Text(note).settingsFootnote()
            }
        }
    }
}
