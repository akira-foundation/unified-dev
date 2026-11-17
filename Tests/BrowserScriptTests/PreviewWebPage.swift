@testable import Core
import Foundation
import Testing
import WebKit

@MainActor
final class PreviewWebPage {
    private let webView: WKWebView
    private let handler: PreviewFilesHandler

    private init(webView: WKWebView, handler: PreviewFilesHandler) {
        self.webView = webView
        self.handler = handler
    }

    static func open(
        files: [String: String], configure: (WKWebViewConfiguration) async throws -> Void
    ) async throws -> PreviewWebPage {
        let handler = PreviewFilesHandler(files: files)
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: DocumentPreview.scheme)
        configuration.websiteDataStore = .nonPersistent()
        try await configure(configuration)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let page = PreviewWebPage(webView: webView, handler: handler)
        webView.load(URLRequest(url: try #require(URL(string: "\(DocumentPreview.scheme)://worktree/index.html"))))
        let deadline = ContinuousClock.now + .seconds(10)
        while webView.isLoading || webView.url == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        return page
    }

    static func blockNetwork(in configuration: WKWebViewConfiguration) async throws {
        let rules = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: DocumentPreview.networkRuleListIdentifier,
            encodedContentRuleList: DocumentPreview.networkRules
        )
        configuration.userContentController.add(try #require(rules))
    }

    func evaluate(_ expression: String) async throws -> String? {
        try await webView.evaluateJavaScript(expression) as? String
    }
}

@MainActor
private final class PreviewFilesHandler: NSObject, WKURLSchemeHandler {
    private let files: [String: String]

    init(files: [String: String]) {
        self.files = files
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let file = files[String(url.path.dropFirst())] else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let body = Data(file.utf8)
        let headers = DocumentPreview.responseHeaders(
            contentType: DocumentPreview.contentType(forFile: url.path), length: body.count
        )
        guard let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers
        ) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(body)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
