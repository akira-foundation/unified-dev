import Core
import WebKit

@MainActor
enum DocumentPreviewNetworkRules {
    private static var compiling: Task<WKContentRuleList?, Never>?

    static func list() async -> WKContentRuleList? {
        if let compiling, let list = await compiling.value { return list }
        let task = Task {
            try? await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: DocumentPreview.networkRuleListIdentifier,
                encodedContentRuleList: DocumentPreview.networkRules
            )
        }
        compiling = task
        return await task.value
    }
}
