import SwiftUI
import Core

struct Gallery {
    let name: String
    let title: String
    let size: CGSize
    let needsFocus: Bool
    let view: @MainActor (AppModel) -> AnyView

    init(
        name: String,
        title: String,
        size: CGSize,
        needsFocus: Bool,
        view: @escaping @MainActor (AppModel) -> AnyView
    ) {
        self.name = name
        self.title = title
        self.size = size
        self.needsFocus = needsFocus
        self.view = view
    }
}

extension Snapshot {
    static let galleries: [Gallery] = [
        .reviewComments,
        .inspectorTabs,
        .diffScope,
        .pendingDelete,
        .runningGlyph,
        .statusColumn,
        .retries,
        .subagentRows,
        .subagentOutput,
        .paneTabs,
        .sidebarSelection,
        .quickPrompts,
        .composerPickers,
        .hoverCard,
        .panelTabs,
        .browserToolbar,
        .systemAccent,
        .sidebarIndent,
        .runningColour,
        .proseLeading,
        .crewMessages,
        .chatSegments,
        .diffRun,
        .commandMenu,
        .notes,
        .notices,
        .pullRequestBar,
        .cloneFailure,
    ]

    static func gallery(named name: String?) -> Gallery {
        galleries.first { $0.name == name } ?? galleries[0]
    }
}
