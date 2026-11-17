import SwiftUI
import Core
enum SettingsTab: String, CaseIterable, SettingsPage {
    case general
    case workspaces
    case appearance
    case menuBar
    case notifications
    case agents
    case sessions
    case presets
    case permissions
    case prompts
    case terminal
    case commandLine
    case gitHosting

    var title: String {
        switch self {
        case .general: "General"
        case .workspaces: "Workspaces"
        case .appearance: "Appearance"
        case .menuBar: "Menu Bar"
        case .notifications: "Notifications"
        case .agents: "Agents"
        case .sessions: "Sessions"
        case .presets: "Model Presets"
        case .permissions: "Permissions"
        case .prompts: "Prompts"
        case .terminal: "Terminal"
        case .commandLine: "Command Line"
        case .gitHosting: GitHostingWording.paneTitle
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .workspaces: "arrow.triangle.branch"
        case .appearance: "paintbrush"
        case .menuBar: "menubar.rectangle"
        case .notifications: "bell"
        case .agents: "person.2"
        case .sessions: "bubble.left.and.bubble.right"
        case .presets: "slider.horizontal.3"
        case .permissions: "hand.raised"
        case .prompts: "text.bubble"
        case .terminal: "terminal"
        case .commandLine: "link"
        case .gitHosting: "server.rack"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .workspaces: .mint
        case .appearance: Palette.accentFill
        case .menuBar: .indigo
        case .notifications: .red
        case .agents: .blue
        case .sessions: .teal
        case .presets: .purple
        case .permissions: .orange
        case .prompts: .pink
        case .terminal: Color(nsColor: .darkGray)
        case .commandLine: .green
        case .gitHosting: .cyan
        }
    }

    var glyph: Color { self == .appearance ? Palette.onAccentFill : .white }

    static let sections = [
        SettingsSidebarSection("Unified Dev", pages: [SettingsTab.general, .workspaces, .appearance, .menuBar, .notifications]),
        SettingsSidebarSection("Agents", pages: [SettingsTab.agents, .sessions, .presets, .permissions, .prompts]),
        SettingsSidebarSection("Terminal & connections", pages: [SettingsTab.terminal, .commandLine, .gitHosting]),
    ]
}
