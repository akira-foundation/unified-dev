import SwiftUI
import Core

struct SearchPanelFooter: View {
    var keys: [SearchPanelFooterKey]
    var summary: String?

    var body: some View {
        HStack(spacing: Metrics.inset) {
            ForEach(keys) { key in
                Text(key.text)
                    .lineLimit(1)
            }

            Spacer(minLength: Metrics.spacingWide)

            if let summary {
                Text(summary)
                    .lineLimit(1)
            }
        }
        .font(Typo.caption)
        .searchPanelInk(SearchPanelRowInk.detail())
        .padding(.horizontal, Metrics.inset)
        .padding(.vertical, Metrics.spacingSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Hairline() }
        .accessibilityHidden(true)
    }
}
