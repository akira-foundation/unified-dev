import Foundation
import Testing
@testable import Core

@Suite("What a document preview may reach over the network")
struct DocumentPreviewNetworkTests {
    private var filters: [String] {
        get throws {
            let data = Data(DocumentPreview.networkRules.utf8)
            let rules = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: [String: String]]])
            #expect(rules.allSatisfy { $0["action"]?["type"] == "block" })
            return rules.compactMap { $0["trigger"]?["url-filter"] }
        }
    }

    private func isBlocked(_ address: String) throws -> Bool {
        try filters.contains { filter in
            address.range(of: filter, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    @Test("every address on the network is blocked", arguments: [
        "http://127.0.0.1:8765/",
        "https://example.com/font.woff2",
        "HTTPS://EXAMPLE.COM/",
        "ws://example.com/socket",
        "wss://example.com/socket",
    ])
    func networkIsBlocked(address: String) throws {
        #expect(try isBlocked(address))
    }

    @Test("the preview's own files and inline data are not", arguments: [
        "unified-dev-preview://worktree/docs/report.html",
        "data:image/png;base64,AAAA",
        "blob:unified-dev-preview://worktree/1234",
        "about:srcdoc",
    ])
    func localIsAllowed(address: String) throws {
        #expect(try !isBlocked(address))
    }
}
