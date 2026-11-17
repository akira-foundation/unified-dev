import Core
import SwiftUI

struct TranscriptChaptersMenu: View {
    var chapters: [TranscriptChapter]
    var onOpen: (Int) -> Void

    var body: some View {
        Menu {
            Section("Chapters") {
                ForEach(chapters) { chapter in
                    Button(chapter.title) { onOpen(chapter.seq) }
                }
            }
        } label: {
            Label("Chapters", systemImage: "bookmark")
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .fixedSize()
        .help("Chapters")
        .accessibilityLabel("Chapters")
    }
}
