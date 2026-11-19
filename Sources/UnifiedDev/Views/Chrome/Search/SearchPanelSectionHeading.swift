import SwiftUI
import Core

struct SearchPanelSectionHeading: View {
    var title: String

    var body: some View {
        Text(title)
            .font(Typo.captionEmphasis)
            .searchPanelInk(SearchPanelRowInk.heading)
            .padding(.horizontal, Metrics.inset)
            .padding(.top, Metrics.gutter)
            .padding(.bottom, Metrics.spacingTight)
            .accessibilityAddTraits(.isHeader)
    }
}
