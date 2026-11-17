import SwiftUI
import Core

struct UsageMenuRow: View {
    let row: UsageCompactRow

    var body: some View {
        HStack(spacing: UsageColumns.gap) {
            Text(row.title)
                .foregroundStyle(MenuInk.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(row.title)
            UsageMeterBar(reading: row.reading, height: 4)
                .frame(width: UsageColumns.bar)
            Text(row.value)
                .fontWeight(.medium)
                .foregroundStyle(row.reading.tone == .critical ? MenuInk.critical : MenuInk.primary)
                .frame(width: UsageColumns.value, alignment: .trailing)
            alert
                .frame(width: UsageColumns.alert, alignment: .leading)
            Text(row.reset)
                .foregroundStyle(MenuInk.secondary)
                .lineLimit(1)
                .frame(width: UsageColumns.reset, alignment: .trailing)
                .help(row.resetHelp ?? "")
        }
        .font(UsageScale.supporting)
        .monospacedDigit()
        .frame(minHeight: UsageColumns.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
    }

    @ViewBuilder
    private var alert: some View {
        if row.showsFlame {
            HStack(spacing: 2) {
                Image(systemName: "flame.fill")
                if let text = row.alert {
                    Text(text)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(MenuInk.critical)
            .help(row.alertHelp ?? "")
        } else {
            Color.clear.frame(height: 1)
        }
    }
}

enum UsageColumns {
    static let gap: CGFloat = 5
    static let bar: CGFloat = 64
    static let value: CGFloat = 34
    static let alert: CGFloat = 52
    static let reset: CGFloat = 52
    static let rowHeight: CGFloat = 22
}

struct UsageMeterBar: View {
    let reading: UsageMeterReading
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(MenuInk.track)
                if reading.tone != .empty, reading.fill > 0 {
                    Capsule()
                        .fill(MenuInk.tone(reading.tone))
                        .frame(width: min(width, max(height, width * reading.fill)))
                }
            }
            .overlay(alignment: .leading) {
                if let tick = reading.paceTick {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(MenuInk.primary.opacity(0.55))
                        .frame(width: 2, height: height + 4)
                        .offset(x: min(max(width * tick - 1, 0), max(0, width - 2)))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
