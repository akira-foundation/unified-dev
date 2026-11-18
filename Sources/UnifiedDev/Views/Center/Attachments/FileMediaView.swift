import SwiftUI
import PDFKit
import Core

struct FileMediaView: View {
    var worktree: String
    var path: String

    @State private var width: CGFloat = 0
    @State private var pageCount: Int?
    @State private var document: PDFDocument?
    @State private var countedURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            switch MediaDisplay.of(path: path, pageCount: pageCount, hasCounted: countedURL == url) {
            case .pages:
                PDFPagesView(document: document, name: filename)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .counting:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .still:
                GeometryReader { proxy in
                    AttachmentPreview(
                        url: url,
                        maxWidth: max(proxy.size.width - Metrics.pane * 2, 1),
                        maxHeight: max(proxy.size.height - Metrics.pane * 2, 1)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: url) { await countPages() }
    }

    private func countPages() async {
        pageCount = nil
        document = nil
        countedURL = nil
        guard MediaDisplay.of(path: path, pageCount: nil, hasCounted: false) == .counting else { return }
        let file = url.path
        let counted = await Task.detached(priority: .userInitiated) { ReadablePDF.pageCount(atPath: file) }.value
        guard !Task.isCancelled else { return }
        let opened = counted == nil ? nil : PDFDocument(url: url)
        let agreed = ReadablePDF.agreedPageCount(
            counted: counted,
            opened: opened.map { ReadablePDF.Opened(pageCount: $0.pageCount, isLocked: $0.isLocked) }
        )
        document = agreed == nil ? nil : opened
        pageCount = agreed
        countedURL = url
    }

    private var header: some View {
        HStack(spacing: InspectorLayout.gap) {
            FilePathLabel(path: path, width: width)

            Spacer(minLength: InspectorLayout.tight)

            Button("Reveal in Finder", systemImage: "folder") {
                Reveal.inFinder(url.path)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Show \(filename) in Finder")
        }
        .padding(.horizontal, InspectorLayout.inset)
        .frame(height: InspectorLayout.barHeight)
        .background(Palette.surfaceSunken)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .help(path)
    }

    private var url: URL {
        URL(filePath: (worktree as NSString).appendingPathComponent(path))
    }

    private var filename: String { (path as NSString).lastPathComponent }

    static func isMedia(path: String) -> Bool {
        MediaPresentation.of(path: path) != nil
    }
}
