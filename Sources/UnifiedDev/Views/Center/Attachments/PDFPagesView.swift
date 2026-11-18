import SwiftUI
import PDFKit
import Core

struct PDFPagesView: NSViewRepresentable {
    var document: PDFDocument?
    var name: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.autoScales = true
        view.delegate = context.coordinator
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        view.setAccessibilityLabel("Pages of \(name)")
        guard view.document !== document else { return }
        view.document = document
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency PDFViewDelegate {
        func pdfViewWillClick(onLink sender: PDFView, with url: URL) {
            guard LinkPolicy.opens(url),
                  DocumentPreviewExit.confirm(url, opensInBuiltInBrowser: false) else { return }
            NSWorkspace.shared.open(url)
        }
    }
}
