import SwiftUI
import Core

struct SearchPanelScopes: View {
    var counts: HomeScopeCounts
    @Binding var scope: HomeScope

    var body: some View {
        Picker("Scope", selection: selection) {
            ForEach(SearchPanelScopeSegment.offered(counts: counts)) { segment in
                Text(segment.title)
                    .accessibilityLabel("\(segment.name), \(segment.count)")
                    .tag(segment.scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, Metrics.inset)
        .padding(.bottom, Metrics.spacingSmall)
        .accessibilityHint("Narrows the answer to one kind of thing.")
    }

    private var selection: Binding<HomeScope> {
        Binding(
            get: { SearchPanelScopeSegment.selected(scope) },
            set: { scope = $0 }
        )
    }
}
