import AppKit
import SwiftUI
import Core

@MainActor
@Observable
final class SearchPanelModel {
    static let shared = SearchPanelModel()

    private(set) var files: FileSearchModel?
    private(set) var isOpen = false
    private(set) var field = SearchPanelField()
    var scope: HomeScope = .all
    var highlighted: Int?
    private(set) var listing = SearchPanelListing.empty
    private(set) var runnable: Set<MenuBarAction> = []
    private(set) var selectAllToken = 0
    private(set) var archived: [Workspace] = []
    var caretAtEnd = true

    private init() {}

    func openFiles(app: AppModel) {
        guard let workspace = app.selectedWorkspace else { return }
        if isOpen, files?.workspace.id == workspace.id {
            selectAllToken &+= 1
            return
        }
        close(app: app)
        files = FileSearchModel(workspace: workspace)
        isOpen = true
    }

    func open(scope: HomeScope = .all, app: AppModel) {
        if files != nil { close(app: app) }
        if isOpen {
            selectAllToken &+= 1
        } else {
            isOpen = true
            field = SearchPanelField()
            highlighted = nil
            listing = .empty
        }
        self.scope = HomeScope.settle(scope, searching: true)
        Task { archived = await app.archivedWorkspaces() }
        rebuild(app: app)
    }

    func close(app: AppModel) {
        guard isOpen else { return }
        isOpen = false
        files = nil
        field = SearchPanelField()
        scope = .all
        highlighted = nil
        listing = .empty
        app.searchTranscripts("")
    }

    func type(_ text: String, app: AppModel) {
        let before = field.mode
        field.type(text)
        if before != field.mode || field.mode == .things {
            app.searchTranscripts(field.mode == .things ? field.query : "")
        }
        rebuild(app: app)
    }

    @discardableResult
    func drill(app: AppModel) -> Bool {
        guard let row = listing.row(at: highlighted), let id = row.drillable else { return false }
        guard field.enterActions(on: id) else { return false }
        app.searchTranscripts("")
        rebuild(app: app)
        return true
    }

    @discardableResult
    func leaveMode(app: AppModel) -> Bool {
        guard field.leaveMode() else { return false }
        app.searchTranscripts(field.mode == .things ? field.query : "")
        rebuild(app: app)
        return true
    }

    func clearQuery(app: AppModel) {
        field.clear()
        app.searchTranscripts("")
        rebuild(app: app)
    }

    func setScope(_ scope: HomeScope, app: AppModel) {
        self.scope = scope
        rebuild(app: app)
    }

    private static var showsHiddenProjects: Bool {
        UserDefaults.standard.bool(forKey: ProjectVisibility.showsHiddenKey)
    }

    func rebuild(app: AppModel) {
        guard isOpen, files == nil else { return }
        switch field.mode {
        case .things:
            let reach = SearchPanelReach.reading(
                scope: scope, showsHiddenProjects: Self.showsHiddenProjects
            )
            listing = field.isEmpty
                ? SearchPanelResting.build(
                    workspaces: app.profileWorkspaces,
                    repos: app.profileRepos,
                    activity: HomeActivity(
                        running: app.runningWorkspaceIDs, waiting: app.waitingWorkspaceIDs
                    ),
                    reach: reach
                )
                : SearchPanelResults.build(
                    query: field.query,
                    repos: app.profileRepos,
                    workspaces: app.profileWorkspaces,
                    archived: app.inActiveProfile(archived),
                    transcripts: app.transcriptResults,
                    scope: scope,
                    profiles: app.profiles,
                    activeProfile: app.activeProfileID,
                    reach: reach
                )
        case .commands:
            let sections = SearchPanelCommands.sections(SearchPanelCommands.rank(field.query))
            listing = SearchPanelListing(
                sections: sections,
                isSearching: !field.isEmpty,
                nothing: sections.isEmpty && !field.isEmpty ? .noCommand(field.query) : nil
            )
        case .actions(let id):
            listing = SearchPanelListing(sections: SearchPanelActions.sections(for: subject(id)))
        }

        runnable = MainMenuActions.runnable()
        highlighted = listing.rows.isEmpty ? nil : min(highlighted ?? 0, listing.rows.count - 1)
    }

    private func subject(_ id: WorkspaceID) -> WorkspaceMenuSubject {
        archived.contains { $0.id == id } ? .archived(id) : .live(id)
    }

    func drilledWorkspace(app: AppModel) -> Workspace? {
        guard let id = field.mode.workspaceID else { return nil }
        return app.workspaces.first { $0.id == id } ?? archived.first { $0.id == id }
    }

    #if DEBUG
    func presentIfRequested(app: AppModel) {
        let arguments = CommandLine.arguments
        guard arguments.contains("--search-panel") else { return }

        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
                return nil
            }
            return arguments[index + 1]
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            let scope = value("--search-panel-scope").flatMap(HomeScope.init(rawValue:)) ?? .all
            open(scope: scope, app: app)
            if let query = value("--search-panel-query") {
                type(query, app: app)
                try? await Task.sleep(for: .seconds(2))
                rebuild(app: app)
            }
            if arguments.contains("--search-panel-drill") {
                highlighted = 0
                drill(app: app)
            }
        }
    }
    #endif

    var keyContext: SearchPanelKeyContext {
        SearchPanelKeyContext(
            mode: field.mode,
            rowCount: listing.rows.count,
            highlighted: highlighted,
            isQueryEmpty: field.isEmpty,
            scope: scope,
            scopes: HomeScope.offered(searching: true),
            canDrill: listing.row(at: highlighted)?.drillable != nil,
            caretAtEnd: caretAtEnd
        )
    }
}
