import SwiftUI
import Core

struct SearchPanelScopes: View {
    var counts: HomeScopeCounts
    @Binding var scope: HomeScope

    var body: some View {
        Picker("Scope", selection: $scope) {
            ForEach(SearchPanelScopeSegment.offered(counts: counts)) { segment in
                Text(segment.title)
                    .lineLimit(1)
                    .fixedSize()
                    .tag(segment.scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.inset)
        .padding(.bottom, Metrics.spacingSmall)
        .accessibilityHint("Narrows the answer to one kind of thing.")
    }
}
