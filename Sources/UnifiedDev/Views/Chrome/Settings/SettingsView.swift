import AppKit
import SwiftUI
import Core

@MainActor
enum AppearancePreference {
    static func apply(_ value: String) {
        NSApplication.shared.appearance = switch value {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var navigation = SettingsNavigation(
        current: SettingsTabRequest.takePending() ?? Snapshot.requestedSettingsTab ?? SettingsTab.general
    )
    @State private var defaults = AppDefaults()
    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var saveError: String?

    var body: some View {
        SettingsWindowShell(navigation: $navigation, sections: SettingsTab.sections, searchPrompt: "Search") { _ in
            detail
        }
        .task {
            guard !isLoaded, let store = app.store else { return }
            defaults = await AppDefaults.load(from: store)
            isLoaded = true
        }
        .onReceive(NotificationCenter.default.publisher(for: SettingsTabRequest.name)) { notification in
            if let requested = SettingsTabRequest.tab(in: notification) { navigation.select(requested) }
            _ = SettingsTabRequest.takePending()
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if let saveError {
                ErrorBanner(title: "Could not save settings", message: saveError) {
                    self.saveError = nil
                }
                .padding(Metrics.inset)
                .frame(maxWidth: SettingsColumn.width)
            }
            pane
        }
    }

    private var defaultsBinding: Binding<AppDefaults> {
        Binding(get: { defaults }, set: { updated in
            guard isLoaded, let store = app.store else { return }
            let previous = defaults
            defaults = updated
            let pending = saveTask
            saveTask = Task {
                await pending?.value
                do {
                    try await updated.saveChanges(from: previous, to: store)
                    saveError = nil
                } catch {
                    saveError = error.readableMessage
                }
            }
        })
    }

    @ViewBuilder
    private var pane: some View {
        switch navigation.current {
        case .general: GeneralSettingsView()
        case .workspaces: WorkspacesSettingsView()
        case .appearance: AppearanceSettingsView()
        case .menuBar: MenuBarSettingsView(app: app)
        case .notifications: NotificationSettingsView()
        case .agents: AgentsSettingsView()
        case .sessions: ModelSettingsView(defaults: defaultsBinding).disabled(!isLoaded)
        case .presets: ModelPresetSettingsView()
        case .permissions: ApprovalSettingsView(defaults: defaultsBinding, isReady: isLoaded)
        case .prompts: PromptSettingsView()
        case .terminal: TerminalSettingsView()
        case .commandLine: CommandLineSettingsView()
        case .gitHosting: GitHostingSettingsView()
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage(LinkOpening.settingKey) private var opensLinksInside = LinkOpening.isOnByDefault

    var body: some View {
        Form {
            Section("Links") {
                Toggle(isOn: $opensLinksInside) {
                    Text(LinkOpening.settingTitle)
                    Text(LinkOpening.settingDetail)
                }
            }

            DirectorySettingsSection()

            SleepSettingsSection()

            OpenInSettingsSection()

            UpdateSettingsSection()
            CrashReportingSettingsSection()
        }
        .settingsForm()
    }
}
