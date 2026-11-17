import Core
import SwiftUI

struct NotificationBellButton: View {
    let inbox: NotificationInboxModel
    let profiles: [Profile]

    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Label {
                Text(NotificationBellReading.title(unseen: inbox.unseen))
            } icon: {
                NotificationBellIcon(badge: NotificationBellReading.badge(unseen: inbox.unseen))
            }
            .labelStyle(.iconOnly)
        }
        .help("Notifications")
        .accessibilityLabel(NotificationBellReading.accessibilityLabel(unseen: inbox.unseen))
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            NotificationBellList(
                rows: inbox.rows,
                profiles: profiles,
                now: Date(),
                onOpen: { row in
                    isShowing = false
                    Task { await inbox.open(row) }
                },
                onMarkAll: inbox.markAllRead
            )
        }
    }
}

struct NotificationBellIcon: View {
    let badge: String?

    var body: some View {
        if let badge {
            HStack(spacing: Metrics.spacingSmall) {
                Image(systemName: "bell.badge")
                Text(badge).monospacedDigit()
            }
        } else {
            Image(systemName: "bell")
        }
    }
}

struct NotificationBellList: View {
    let rows: [InboxNotification]
    let profiles: [Profile]
    let now: Date
    let onOpen: (InboxNotification) -> Void
    let onMarkAll: () -> Void

    @State private var contentHeight: CGFloat = 0

    private var unseen: Int { NotificationInbox.unseenCount(rows) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if rows.isEmpty {
                ContentUnavailableView("No Notifications", systemImage: "bell.slash")
                    .padding(.bottom)
            } else {
                Divider()
                list
            }
        }
        .frame(width: NotificationBellReading.popoverWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack {
            Text("Notifications")
                .font(.headline)
            Spacer()
            if NotificationBellReading.offersMarkAllRead(unseen: unseen) {
                Button("Mark All as Read", action: onMarkAll)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    NotificationBellRow(
                        reading: InboxRowReading(row, profileName: profile(of: row)?.name, now: now),
                        isUnseen: row.counts,
                        profile: profile(of: row),
                        onOpen: { onOpen(row) }
                    )
                    if row.id != rows.last?.id {
                        Divider().padding(.leading)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: NotificationBellReading.listHeight(content: contentHeight))
    }

    private func profile(of row: InboxNotification) -> Profile? {
        profiles.first { $0.id == row.profileID }
    }
}

private struct NotificationBellRow: View {
    let reading: InboxRowReading
    let isUnseen: Bool
    let profile: Profile?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                mark
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading.title)
                        .fontWeight(isUnseen ? .semibold : .regular)
                        .lineLimit(1)
                    Text(reading.origin)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(reading.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(reading.age)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isUnseen {
                        Circle()
                            .fill(.tint)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .opacity(reading.isDimmed ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!reading.opens)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.accessibilityLabel)
        .accessibilityAddTraits(reading.opens ? .isButton : [])
    }

    @ViewBuilder private var mark: some View {
        if let profile {
            ProfileMark(symbol: profile.symbol, colour: profile.colour)
        } else {
            Image(systemName: "bell")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
