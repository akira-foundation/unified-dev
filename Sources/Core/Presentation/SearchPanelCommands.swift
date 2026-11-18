import Foundation

public enum SearchPanelCommands {
    public static let inlineLimit = 4

    public static let inlineMinimumQueryLength = 2

    public static func rank(_ query: String, in commands: [MenuBarItem] = MenuBarCatalogue.commands) -> [SearchPanelCommandHit] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return commands.map { SearchPanelCommandHit(item: $0) }
        }
        return commands
            .compactMap { item in
                guard let hit = FuzzyMatch.hit(item.title, query: trimmed) else { return nil }
                return SearchPanelCommandHit(item: item, highlights: hit.positions, score: hit.score)
            }
            .enumerated()
            .sorted { left, right in
                left.element.score == right.element.score
                    ? left.offset < right.offset
                    : left.element.score > right.element.score
            }
            .map(\.element)
    }

    public static func sections(_ hits: [SearchPanelCommandHit]) -> [SearchPanelSection] {
        MenuBarMenu.allCases.compactMap { menu in
            let rows = hits.filter { $0.item.menu == menu }
            guard !rows.isEmpty else { return nil }
            return SearchPanelSection(
                id: "menu-\(menu.rawValue)",
                title: title(of: menu),
                rows: rows.map { SearchPanelRow.command($0) }
            )
        }
    }

    public static func title(of menu: MenuBarMenu) -> String {
        switch menu {
        case .unifieddev: "Unified Dev"
        case .file: "File"
        case .edit: "Edit"
        case .view: "View"
        case .workspace: "Workspace"
        case .help: "Help"
        }
    }
}
