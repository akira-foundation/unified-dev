import SwiftUI
import Core

struct SearchPanelNothingView: View {
    var nothing: SearchPanelNothing
    var isIndexing: Bool

    var body: some View {
        EmptyStateView(glyph: glyph, title: nothing.title, message: nothing.message)
            .overlay(alignment: .bottom) { notice }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
    }

    private var glyph: String {
        switch nothing {
        case .nothingYet: "square.stack.3d.up.slash"
        case .noMatch, .noLiveMatch, .noHiddenMatch, .noCommand: "magnifyingglass"
        }
    }

    @ViewBuilder
    private var notice: some View {
        if let sentence = nothing.indexNotice(isIndexing: isIndexing) {
            Label(sentence, systemImage: "clock")
                .font(Typo.caption)
                .searchPanelInk(SearchPanelRowInk.detail())
                .multilineTextAlignment(.leading)
                .padding(.horizontal, Metrics.pane)
                .padding(.bottom, Metrics.gutter)
        }
    }
}
