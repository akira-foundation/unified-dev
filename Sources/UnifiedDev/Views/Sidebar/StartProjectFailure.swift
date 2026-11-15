import SwiftUI
import Core

struct StartProjectFailure: View {
    var fault: StartProjectFault

    var body: some View {
        Text(fault.title)
            .font(Typo.bodyEmphasis)
            .foregroundStyle(Palette.textPrimary)
        Callout(
            text: fault.message,
            symbol: "exclamationmark.triangle.fill",
            tone: .negative
        )
        if let advice = fault.advice {
            Text(advice)
                .font(Typo.label)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let offer = fault.hostOffer {
            VStack(alignment: .leading, spacing: Metrics.spacingTight) {
                Text(offer.host)
                    .font(Typo.captionEmphasis)
                    .foregroundStyle(Palette.textPrimary)
                ForEach(offer.fingerprints, id: \.self) { fingerprint in
                    Text(fingerprint)
                        .font(Typo.codeSmall)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                }
            }
        }
        if let detail = fault.detail {
            DisclosureGroup("Show details") {
                ScrollView {
                    Text(detail)
                        .font(Typo.codeTiny)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: Self.detailHeight)
            }
            .font(Typo.label)
        }
    }

    private static let detailHeight: CGFloat = 160
}
