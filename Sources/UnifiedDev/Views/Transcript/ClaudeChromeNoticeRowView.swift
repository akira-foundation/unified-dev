import SwiftUI
import Core

struct ClaudeChromeNoticeRowView: View {
    var notice: ClaudeChromeNotice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TranscriptLayout.glyphGap) {
            TranscriptGlyph(symbol: "globe", tint: Palette.warning)

            Text("Chrome")
                .font(Typo.label)
                .foregroundStyle(Palette.textSecondary)
                .transcriptLabelColumn("Chrome", font: Typo.label)

            Text(notice.sentence)
                .font(Typo.label)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .transcriptRowFrame()
    }
}
