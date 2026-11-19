import Foundation

public enum BrowserCommand: CaseIterable, Sendable {
    case back
    case forward
    case reload
    case responsivePreview
    case fullSize
    case screenshot
    case comment
    case openInDefaultBrowser

    public static let menuRows: [BrowserCommand] = [
        .reload, .responsivePreview, .fullSize, .screenshot, .comment, .openInDefaultBrowser
    ]

    public var menuAction: MenuBarAction {
        switch self {
        case .back: .fileBack
        case .forward: .fileForward
        case .reload: .browserReload
        case .responsivePreview: .browserResponsivePreview
        case .fullSize: .browserFullSize
        case .screenshot: .browserScreenshot
        case .comment: .browserComment
        case .openInDefaultBrowser: .browserOpenInDefaultBrowser
        }
    }

    var movesThePage: Bool {
        switch self {
        case .back, .forward, .reload, .responsivePreview, .fullSize: true
        case .screenshot, .comment, .openInDefaultBrowser: false
        }
    }
}

public struct BrowserPaneState: Equatable, Sendable {
    public var toolbar: BrowserToolbar
    public var viewport: BrowserViewport
    public var isReviewing: Bool
    public var isSaving: Bool
    public var isEditingComment: Bool

    public init(
        toolbar: BrowserToolbar,
        viewport: BrowserViewport,
        isReviewing: Bool,
        isSaving: Bool,
        isEditingComment: Bool = false
    ) {
        self.toolbar = toolbar
        self.toolbar.isCapturing = toolbar.isCapturing || isReviewing
        self.viewport = viewport
        self.isReviewing = isReviewing
        self.isSaving = isSaving
        self.isEditingComment = isEditingComment
    }

    public func control(for command: BrowserCommand) -> BrowserToolbar.Control {
        switch command {
        case .back: toolbar.back
        case .forward: toolbar.forward
        case .reload: toolbar.reload
        case .responsivePreview: BrowserToolbar.viewport(viewport)
        case .fullSize: BrowserToolbar.fullSize(viewport)
        case .screenshot: toolbar.screenshot
        case .comment: toolbar.comment(isReviewing: isReviewing, isSaving: isSaving)
        case .openInDefaultBrowser: toolbar.openInDefaultBrowser
        }
    }

    public func isEnabled(_ command: BrowserCommand) -> Bool {
        if isReviewing, command.movesThePage { return false }
        if isEditingComment, command == .comment { return false }
        return control(for: command).isEnabled
    }

    public func usesAlternateTitle(_ command: BrowserCommand) -> Bool {
        switch command {
        case .back, .forward: true
        case .reload: toolbar.isLoading
        case .comment: isReviewing
        default: false
        }
    }
}

extension BrowserToolbar {
    static func help(_ text: String, key action: MenuBarAction) -> String {
        MenuBarCatalogue[action].help(text)
    }
}
