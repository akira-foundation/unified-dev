import AppKit
import SwiftUI
import Core

struct AgentsSettingsView: View {
    @Environment(AppModel.self) private var app

    @State private var selection: AgentKind = .claudeCode
    @State private var statuses: [AgentKind: AgentStatus] = [:]
    @State private var overrides: [AgentKind: String] = [:]
    @State private var catalog: AgentCatalog?
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var saveFailure: String?
    @State private var accountsFlow = AgentAccountsFlow()
    @State private var pathDraft = ""
    @State private var draftKind: AgentKind = .claudeCode
    @FocusState private var isEditingPath: Bool

    private var status: AgentStatus? { statuses[selection] }

    private var accounts: AgentAccountsModel { app.agentAccounts }

    private var accountPanel: AgentAccountPanel {
        accounts.panel(for: selection, in: app.activeProfileID, profiles: app.profiles, repos: app.repos)
    }

    private var executables: [AgentKind: String] { statuses.compactMapValues(\.executablePath) }

    var body: some View {
        Form {
            ProviderIdleSettingsSection()
            Section {
                Picker("Agent", selection: $selection) {
                    ForEach(AgentKind.allCases) { kind in
                        Text(kind.label)
                            .tag(kind)
                            .accessibilityValue(
                                statuses[kind].map { stateTitle($0.connection) } ?? "Checking"
                            )
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let saveFailure {
                Section {
                    ErrorBanner(title: "Could not save", message: saveFailure) {
                        self.saveFailure = nil
                    }
                }
            }

            if let failure = accounts.failure {
                Section {
                    ErrorBanner(title: "Accounts", message: failure) {
                        accounts.dismissFailure()
                    }
                }
            }

            if let notice = accounts.removalNotice, notice.isShownAbove(accountPanel) {
                Section {
                    ErrorBanner(title: "Accounts", message: notice.message) {
                        accounts.dismissRemovalNotice()
                    }
                }
            }

            if isLoading {
                Section {
                    LoadingView("Looking for agent CLIs")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Metrics.gutter)
                }
            }
            if !isLoading, let status {
                statusSection(status)

                capabilitySection

                if selection == .claudeCode {
                    ClaudeChromeSettingsSection()
                }

                AgentAccountsSection(
                    panel: accountPanel,
                    activity: accounts.activity,
                    removalNotice: accounts.removalNotice,
                    onDismissRemovalNotice: { accounts.dismissRemovalNotice() },
                    canSignIn: status.executablePath != nil,
                    onAdd: { accountsFlow.isNamingAccount = true },
                    onRemove: { accountsFlow.removing = $0 },
                    onSignInAgain: { accountsFlow.signInAgain($0, executable: status.executablePath) }
                )

                if status.connection == .notInstalled {
                    notInstalledSection
                }

                Section("GitHub") {
                    SettingsRow("Account") {
                        Text(GitHubIdentity.cachedUsername ?? "Not available")
                            .foregroundStyle(Palette.textSecondary)
                            .textSelection(.enabled)
                    }
                }

                Section {
                    DisclosureGroup("Advanced configuration") {
                        executableSection(status)
                        configurationSection(status)
                    }
                }
            }
        }
        .settingsForm()
        .task { await bootstrap() }
        .agentAccountsFlow(
            accountsFlow, app: app, provider: selection, executables: executables,
            onSignInClosed: { Task { await refresh() } }
        )
        .onDisappear { commitPathDraft() }
        .onChange(of: selection) { _, kind in
            commitPathDraft()
            draftKind = kind
            pathDraft = overrides[kind] ?? ""
        }
    }

    private func statusSection(_ status: AgentStatus) -> some View {
        Section {
            HStack(spacing: Metrics.gutter) {
                StateDot(connection: status.connection)

                Text(stateTitle(status.connection))
                    .font(Typo.bodyEmphasis)

                if let version = status.version {
                    Chip(text: version, monospaced: true)
                }

                Spacer()

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }

                Button("Refresh") {
                    Task { await refresh() }
                }
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh \(selection.label)")
            }

            ForEach(status.details.filter { $0.label != "Version" || $0.value != status.version }) { detail in
                SettingsRow(detail.label) {
                    Text(detail.value)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(detail.value)
                }
            }

            if status.connection != .notInstalled {
                Button(status.connection == .connected ? "Sign in with another account…" : "Sign in…", action: runLogin)
                    .help("Sign in to \(selection.label) in Unified Dev.")
            }
        } header: {
            Text(selection.label)
        }
    }

    private var notInstalledSection: some View {
        Section {
            Label {
                Text("Unified Dev looked for \(selection.executableName) on your PATH and did not find it. Install the CLI, or point Unified Dev at the executable below.")
                    .settingsFootnote()
            } icon: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func executableSection(_ status: AgentStatus) -> some View {
        VStack(alignment: .leading, spacing: Metrics.gutter) {
            SettingsRow("Executable") {
                if let path = status.executablePath {
                    Text(path)
                        .font(Typo.codeSmall)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(path)
                } else {
                    Text("Not found on your PATH")
                        .font(Typo.label)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            SettingsRow("Custom path") {
                HStack(spacing: Metrics.spacing) {
                    TextField(
                        "Custom path",
                        text: $pathDraft,
                        prompt: Text("Leave empty to use your PATH")
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(Typo.codeSmall)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .focused($isEditingPath)
                    .onSubmit { commitPathDraft() }
                    .onChange(of: isEditingPath) { wasEditing, editing in
                        if wasEditing && !editing { commitPathDraft() }
                    }

                    Button("Choose executable", systemImage: "folder", action: chooseExecutable)
                        .labelStyle(.iconOnly)
                        .help("Choose the \(selection.executableName) executable")
                }
            }

            if overrides[selection] != nil {
                Button("Use system \(selection.executableName)") {
                    pathDraft = ""
                    commitPathDraft()
                }
                .help("Clears the custom path and goes back to whatever is first on your PATH.")
            }
        }
        .padding(.top, Metrics.gutter)
    }

    @ViewBuilder
    private func configurationSection(_ status: AgentStatus) -> some View {
        if let path = status.configPath, let isDirectory = existenceKind(of: path) {
            VStack(alignment: .leading, spacing: Metrics.gutter) {
                SettingsRow(isDirectory ? "Config folder" : "Config file") {
                    HStack(spacing: Metrics.gutter) {
                        Text(path)
                            .font(Typo.codeSmall)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button("Open") { Reveal.inEditor(path) }

                        Button("Reveal in Finder") { Reveal.inFinder(path) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var capabilitySection: some View {
        if !selection.canRunWorkspaces {
            Section {
                Label {
                    Text("\(selection.label) cannot run workspaces in Unified Dev yet. Use \(AgentKind.runnableSentence).")
                        .settingsFootnote()
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    private func existenceKind(of path: String) -> Bool? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue
    }

    private func stateTitle(_ connection: AgentStatus.Connection) -> String {
        switch connection {
        case .connected: "Connected"
        case .installed: "Installed"
        case .notInstalled: "Not installed"
        }
    }

    private func runLogin() {
        guard let executable = status?.executablePath else { return }
        accountsFlow.loginRequest = AgentSignInSheet.Request(
            kind: selection,
            executable: executable,
            isSwitchingAccount: status?.connection == .connected
        )
    }

    private func chooseExecutable() {
        Task { await pickExecutable() }
    }

    private func pickExecutable() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Use Executable"
        panel.message = "Choose the \(selection.executableName) executable"
        guard await panel.present() == .OK, let url = panel.url else { return }
        pathDraft = url.path
        commitPathDraft()
    }

    private func bootstrap() async {
        let loaded = await loadOverrides()
        overrides = loaded
        draftKind = selection
        pathDraft = loaded[selection] ?? ""

        let catalog = AgentCatalog(overrides: loaded)
        self.catalog = catalog
        await read(from: catalog)
        isLoading = false
        await accounts.askIfDue(after: 0, executables: executables, store: app.store)
    }

    private func refresh() async {
        guard let catalog else { return }
        isRefreshing = true
        await catalog.invalidate()
        await read(from: catalog)
        ComposerModelCatalog.shared.load()
        isRefreshing = false
        await accounts.askIfDue(after: 0, executables: executables, store: app.store)
    }

    private func read(from catalog: AgentCatalog) async {
        let found: [AgentStatus]
        if let seeded = PreviewScenario.AgentSettings.seeded() {
            found = seeded.statuses
        } else {
            found = await catalog.statuses()
        }
        statuses = Dictionary(found.map { ($0.kind, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    private func loadOverrides() async -> [AgentKind: String] {
        await AgentCatalog.executablePathOverrides(in: app.store)
    }

    private func commitPathDraft() {
        let kind = draftKind
        let trimmed = pathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        guard value != overrides[kind] else { return }

        if let value {
            overrides[kind] = value
        } else {
            overrides.removeValue(forKey: kind)
        }

        let updated = overrides
        Task {
            if let store = app.store {
                do {
                    try await store.setSetting(AgentCatalog.executablePathSettingKey(kind), value)
                    if kind == .grok { ComposerModelCatalog.shared.refresh() }
                    saveFailure = nil
                } catch {
                    saveFailure = "The executable path for \(kind.label) could not be stored."
                }
            } else {
                saveFailure = "The executable path for \(kind.label) could not be stored."
            }

            let catalog = AgentCatalog(overrides: updated)
            self.catalog = catalog
            await read(from: catalog)
            await accounts.askIfDue(after: 0, executables: executables, store: app.store)
        }
    }
}

private struct StateDot: View {
    let connection: AgentStatus.Connection

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: Metrics.dot, height: Metrics.dot)
            .accessibilityHidden(true)
    }

    private var tint: Color {
        switch connection {
        case .connected: Palette.positive
        case .installed: Palette.warning
        case .notInstalled: Palette.textTertiary
        }
    }
}
