import SwiftUI
import Core

struct MenuBarProviderModule: View {
    let provider: MenuBarPanelContent.Provider
    let plan: String?
    let options: UsageDisplayOptions
    let now: Date
    var focus: FocusState<MenuBarPanelFocus?>.Binding?
    let retry: () -> Void
    let toggleFold: () -> Void
    var useAccount: (AgentAccountHome) -> Void = { _ in }

    private var section: UsageLayout.Section? { provider.section }

    private static let mark: CGFloat = 15

    var body: some View {
        let compact = section.map { UsageCompactSection.make($0, at: now, options: options) }
        VStack(alignment: .leading, spacing: Metrics.spacing) {
            header(summary: provider.reading == .measured ? compact?.summary : nil)
            switch provider.reading {
            case .unavailable: unavailable
            case .measured:
                if let note = provider.note {
                    Text(note)
                        .font(UsageScale.supporting)
                        .foregroundStyle(MenuInk.secondary)
                }
                if let compact {
                    meters(compact)
                }
            }
            if let offer = provider.offer {
                accountOffer(offer)
            }
        }
        .menuBarModule(provider.kind.label)
    }

    private func header(summary: String?) -> some View {
        HStack(spacing: Metrics.spacing) {
            ProviderMarkView(provider: provider.kind)
                .foregroundStyle(MenuInk.secondary)
                .frame(width: Self.mark, height: Self.mark)
            Text(provider.kind.label)
                .font(UsageScale.header)
                .foregroundStyle(MenuInk.primary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            if let plan {
                Text(plan)
                    .font(UsageScale.plan.weight(.medium))
                    .foregroundStyle(MenuInk.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, Metrics.spacing)
                    .padding(.vertical, Metrics.spacingHair)
                    .background(Capsule().fill(MenuInk.primary.opacity(0.1)))
            }
            Spacer(minLength: Metrics.spacingWide)
            if let summary {
                Text(summary)
                    .font(UsageScale.plan)
                    .foregroundStyle(MenuInk.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
    }

    private func meters(_ compact: UsageCompactSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(compact.rows) { row in
                UsageMenuRow(row: row)
            }
            if compact.isFoldable {
                fold(compact)
            }
        }
        .padding(.leading, Self.mark + Metrics.spacing)
    }

    private func fold(_ compact: UsageCompactSection) -> some View {
        HStack(spacing: Metrics.spacingWide) {
            Button(action: toggleFold) {
                HStack(spacing: Metrics.spacingSmall) {
                    Text(compact.foldTitle)
                    Image(systemName: compact.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(UsageScale.supporting.weight(.medium))
                .foregroundStyle(.tint)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(compact.foldSpoken)
            .panelFocus(focus, .fold(provider.kind))
            if let names = compact.foldedNames {
                Spacer(minLength: Metrics.spacingWide)
                Text(names)
                    .font(UsageScale.plan)
                    .foregroundStyle(MenuInk.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(minHeight: UsageColumns.rowHeight)
    }

    private var unavailable: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.spacingWide) {
            Text(provider.note ?? MenuBarPanelContent.unavailableLine(for: provider.kind))
                .font(UsageScale.supporting)
                .foregroundStyle(MenuInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Metrics.spacingWide)
            Button(MenuBarPanelContent.retryTitle, action: retry)
                .linkButton()
                .panelFocus(focus, .retry(provider.kind))
        }
    }

    private func accountOffer(_ offer: QuotaAccountOffer) -> some View {
        VStack(alignment: .leading, spacing: Metrics.spacing) {
            Text(offer.headline)
                .font(UsageScale.supporting)
                .foregroundStyle(MenuInk.primary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(offer.choices) { choice in
                Button(choice.button) { useAccount(choice.home) }
                    .linkButton()
                    .font(UsageScale.supporting)
                    .multilineTextAlignment(.leading)
                    .panelFocus(focus, .account(provider.kind, choice.id))
            }
            ForEach(offer.notes, id: \.self) { note in
                Text(note)
                    .font(UsageScale.supporting)
                    .foregroundStyle(MenuInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
