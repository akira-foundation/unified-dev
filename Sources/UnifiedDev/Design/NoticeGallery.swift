import SwiftUI
import Core

struct NoticeGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            group("A passing notice in each tone, over a transcript") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(NoticeTone.allCases, id: \.self) { tone in
                        NoticeBanner(notice: Notice.sample(tone), onDismiss: {})
                    }
                }
                .background { backdrop }
                .clipped()
            }

            group("A notice with a path and a reason") {
                NoticeBanner(
                    notice: Notice(
                        message: "Harbour was archived. Its folder at `~/unifieddev/harbour` was kept.",
                        tone: .warning
                    ),
                    onDismiss: {}
                )
                .background { backdrop }
                .clipped()
            }

            group("A project whose chosen account no longer exists") {
                if let notice = LostAgentAccountChoiceNotice.notice(
                    [lostProject.id], repos: [lostProject]
                ) {
                    NoticeBanner(notice: notice, onDismiss: {})
                        .background { backdrop }
                        .clipped()
                }
            }

            group("The error in Settings") {
                ErrorBanner(
                    title: "Could not save settings",
                    message: "The settings file is read only. Unified Dev kept the previous values.",
                    onDismiss: {}
                )
            }

            group("The strips inside a workspace, at the column's width") {
                VStack(spacing: 0) {
                    WorkspaceNoticeStrip(tone: .information, title: "Run the setup script when this workspace opens?") {
                        Text(verbatim: "bun install")
                            .font(Typo.codeSmall)
                            .foregroundStyle(Palette.textPrimary)
                    } actions: {
                        Button("Not Now") {}
                        Button("Allow") {}
                            .buttonStyle(.glassProminent)
                    }
                    WorkspaceNoticeStrip(tone: .warning, title: "1 entry in unifieddev.json was skipped", onDismiss: {}) {
                        Text(verbatim: "run: expected a string.")
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textSecondary)
                    } actions: {
                        Button("Open File") {}
                    }
                    WorkspaceNoticeStrip(tone: .error, title: "unifieddev.json could not be read", onDismiss: {}) {
                        Text(verbatim: "Unexpected end of file at line 4.")
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textSecondary)
                    } actions: {
                        Button("Open File") {}
                    }
                }
                .padding(.bottom, Metrics.spacingWide)
                .background { backdrop }
                .clipped()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private let lostProject = Repo(name: "harbour", path: "/projects/harbour")

    private var backdrop: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing) {
            ForEach(0..<12, id: \.self) { line in
                Text(verbatim: line.isMultiple(of: 3)
                     ? "The lamp is lit and the pier is painted."
                     : "Ring the bell when the boats are home, and write down which came in last.")
                    .font(Typo.label)
                    .foregroundStyle(line.isMultiple(of: 4) ? Palette.accent : Palette.textPrimary)
            }
        }
        .padding(Metrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typo.micro)
                .foregroundStyle(Palette.textSecondary)
                .textCase(.uppercase)
            content()
        }
    }
}

extension Gallery {
    static let notices = Gallery(
        name: "notices",
        title: "Notices",
        size: CGSize(width: 720, height: 1200),
        needsFocus: false,
        view: { _ in AnyView(NoticeGallery()) }
    )
}
