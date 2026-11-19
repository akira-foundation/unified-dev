import Foundation

public struct DocumentPreviewAnswer: Sendable, Equatable {
    public var status: Int
    public var type: String
    public var body: Data

    public init(status: Int, type: String, body: Data) {
        self.status = status
        self.type = type
        self.body = body
    }

    public static let refused = DocumentPreviewAnswer(
        status: 403, type: "text/plain; charset=utf-8", body: Data("Outside this preview".utf8)
    )

    public static let sizeLimit = 16 * 1_048_576

    public static let tooLarge = DocumentPreviewAnswer(
        status: 413, type: "text/plain; charset=utf-8", body: Data("Too large for this preview".utf8)
    )

    public static func read(_ file: URL, draft: String?, rendersMarkdown: Bool = false) -> DocumentPreviewAnswer {
        let markdown = rendersMarkdown && CanvasMarkdownPage.isMarkdown(path: file.path)
        if let draft {
            if markdown { return page(from: draft, file: file) }
            let type = DocumentPreview.contentType(forFile: file.path)
            return DocumentPreviewAnswer(status: 200, type: type, body: Data(draft.utf8))
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)??.intValue
        if let size, size > sizeLimit { return tooLarge }
        do {
            let body = try Data(contentsOf: file, options: .mappedIfSafe)
            if markdown { return page(from: String(decoding: body, as: UTF8.self), file: file) }
            let type = DocumentPreviewCharset.contentType(forFile: file.path, body: body)
            return DocumentPreviewAnswer(status: 200, type: type, body: body)
        } catch {
            return DocumentPreviewAnswer(
                status: 404, type: "text/plain; charset=utf-8", body: Data(error.localizedDescription.utf8)
            )
        }
    }

    private static func page(from source: String, file: URL) -> DocumentPreviewAnswer {
        let html = CanvasMarkdownPage.html(from: source, title: file.lastPathComponent)
        return DocumentPreviewAnswer(status: 200, type: "text/html; charset=utf-8", body: Data(html.utf8))
    }
}
