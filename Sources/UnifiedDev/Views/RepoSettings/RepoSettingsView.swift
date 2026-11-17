import SwiftUI
import AppKit
import Core

struct RepoSettingsView: View {
    let repo: Repo

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var model: RepoSettingsModel
    @State private var name = ""
    @State private var navigation: SettingsNavigation<RepoSettingsPane>
    @State private var isConfirmingRemove = false
    @State private var iconNotice: String?
    @FocusState private var isEditingName: Bool

    init(repo: Repo) {
        self.repo = repo
        _model = State(initialValue: RepoSettingsModel(repo: repo))
        _navigation = State(initialValue: SettingsNavigation(
            current: RepoSettingsPaneRequest.takePending(for: repo.id) ?? RepoSettingsPane.requested ?? .project
        ))
    }

    static var idealSize: CGSize { SettingsWindowShell<RepoSettingsPane, EmptyView>.idealSize }
    static var minimumSize: CGSize { SettingsWindowShell<RepoSettingsPane, EmptyView>.minimumSize }

    var body: some View {
        SettingsWindowShell(
            navigation: $navigation,
            sections: [SettingsSidebarSection(pages: RepoSettingsPane.allCases)]
        ) { pane in
            detail(pane)
        }
        .navigationSubtitle(repo.name)
        .showsProjectInTitleBar(repo)
        .task {
            name = repo.name
            await model.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: RepoSettingsPaneRequest.name)) { notification in
            guard let pane = RepoSettingsPaneRequest.pane(in: notification, for: repo.id) else { return }
            _ = RepoSettingsPaneRequest.takePending(for: repo.id)
            navigation.select(pane)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
        .confirmationDialog(
            removal.title,
            isPresented: $isConfirmingRemove,
            titleVisibility: .visible
        ) {
            Button(removal.confirmLabel, role: .destructive, action: removeProject)
            Button(removal.cancelLabel, role: .cancel) {}
        } message: {
            Text(removal.message)
        }
    }

    private func detail(_ pane: RepoSettingsPane) -> some View {
        VStack(spacing: 0) {
            Group {
                switch pane {
                case .project:
                    Form {
                        projectSection
                        Section {
                            DisclosureGroup("Settings files") {
                                filesSection
                            }
                        }
                        removeSection
                    }
                    .settingsForm()
                case .agents:
                    Form {
                        AgentAccountSection(target: AccountScope(workspaceID: nil, repoID: repo.id))
                    }
                    .settingsForm()
                case .workspaces:
                    Form {
                        branchSection
                        RepoMergeMethodSection(repo: repo)
                        RepoPullRequestAutoFixSection(repo: repo)
                        browserSection
                        RepoFilesToCopySection(model: model)
                        RepoOrchestratorSection(repo: repo)
                    }
                    .settingsForm()
                case .scripts:
                    Form {
                        RepoScriptsSection(model: model)
                    }
                    .settingsForm()
                case .instructions:
                    Form {
                        RepoInstructionsSection(model: model)
                    }
                    .settingsForm()
                }
            }
        }
        .focusedValue(
            \.saveAction,
            SaveAction(subject: "project settings", isEnabled: model.isDirty) {
                Task { await model.writeNow() }
            }
        )
        .onChange(of: model.savedPaths) { _, written in
            guard !written.isEmpty else { return }
            app.refreshSettings(for: model.repo.id, savedPaths: written)
        }
    }

    private var projectSection: some View {
        Section {
            SettingsRow("Name") {
                TextField("Name", text: $name)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($isEditingName)
                    .onSubmit(saveName)
                    .onChange(of: isEditingName) { wasEditing, editing in
                        if wasEditing, !editing { saveName() }
                    }
            }

            markRow

            if drawsColour {
                SettingsRow("Colour") {
                    AccentSwatches(selection: accentBinding)
                        .settingsRowBaseline()
                }
            }

            SettingsRow("Folder") {
                HStack(spacing: Metrics.gutter) {
                    Text(shortPath(repo.path))
                        .font(Typo.codeSmall)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(repo.path)

                    Button("Reveal") { Reveal.inFinder(repo.path) }
                }
            }
        } footer: {
            Text("Name, icon and colour save automatically in Unified Dev. Other panes use Save Files to update the repository.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var markRow: some View {
        SettingsRow("Icon") {
            VStack(alignment: .leading, spacing: Metrics.spacing) {
                HStack(spacing: Metrics.gutter) {
                    markTile(size: Self.markTileSize)

                    Button(repo.iconSource == .undetected ? "Find icon" : "Look again", action: findIcon)
                    Button("Choose…", action: chooseIcon)
                    Button("Use initials", action: useInitials)
                        .disabled(!repo.hasIcon && !canDropMark)
                }
                .controlSize(.small)

                summaryLine
            }
        }
    }

    private var summaryLine: some View {
        Text(markSummary)
            .font(Typo.caption)
            .foregroundStyle(iconNotice == nil ? Palette.textSecondary : Palette.warning)
            .lineLimit(2, reservesSpace: true)
            .truncationMode(.middle)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(repo.iconPath ?? "")
    }

    private var drawsColour: Bool {
        RepoIconArt.artwork(for: repo) == nil
    }

    static let markTileSize: CGFloat = Metrics.repoIcon * 1.75

    @ViewBuilder
    private func markTile(size: CGFloat) -> some View {
        if repo.hasIcon {
            RepoIcon(repo: repo, size: size)
        } else {
            RepoIcon(name: previewName, accent: repo.accent, size: size)
        }
    }

    private var markSummary: String {
        if let iconNotice { return iconNotice }
        if repo.hasIcon, let path = repo.iconPath {
            let location = shortPath(path)
            return repo.iconSource == .chosen ? "Chosen: \(location)" : "Found: \(location)"
        }
        if !RepoMonogram.mark(in: name).isEmpty {
            return "The emoji at the front of the name."
        }
        switch repo.iconSource {
        case .undetected: return "Unified Dev has not looked for an icon here."
        case .monogram, .detected, .chosen: return "Initials on the project's colour."
        }
    }

    private func findIcon() {
        iconNotice = nil
        let path = repo.path
        Task {
            guard let found = await Task.detached(operation: { RepoIconDetector.detect(in: path) }).value
            else {
                iconNotice = "Nothing found. Unified Dev looks for a favicon, a manifest icon and an app icon."
                return
            }
            await apply(icon: found.path, source: .detected)
        }
    }

    private func chooseIcon() {
        iconNotice = nil
        Task {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.image, .svg]
            panel.prompt = "Use icon"
            panel.message = "Choose the picture to draw \(repo.name) with."
            panel.directoryURL = URL(fileURLWithPath: repo.path)
            guard await panel.present() == .OK, let url = panel.url else { return }

            guard NSImage(contentsOf: url) != nil else {
                iconNotice = "That file could not be read as a picture."
                return
            }
            await apply(icon: url.path, source: .chosen)
        }
    }

    private func useInitials() {
        iconNotice = nil
        if canDropMark {
            name = RepoMonogram.nameWithoutMark(name)
            saveName()
        }
        guard repo.hasIcon else { return }
        Task { await apply(icon: nil, source: .monogram) }
    }

    private var canDropMark: Bool {
        let stripped = RepoMonogram.nameWithoutMark(name)
        return stripped != name.trimmingCharacters(in: .whitespaces) && !stripped.isEmpty
    }

    private func apply(icon: String?, source: RepoIconSource) async {
        guard let store = app.store else { return }
        RepoIconArt.forget(repo.iconPath)
        RepoIconArt.forget(icon)
        _ = try? await store.update(repoID: repo.id) {
            $0.iconPath = icon
            $0.iconSource = source
        }
    }

    private var previewName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var accentBinding: Binding<Color> {
        Binding(
            get: { Color(hexString: repo.accent) },
            set: { color in
                guard let hex = color.hexString, hex != repo.accent else { return }
                Task {
                    guard let store = app.store else { return }
                    _ = try? await store.update(repoID: repo.id) { $0.accent = hex }
                }
            }
        )
    }

    private func saveName() {
        let trimmed = previewName
        guard !trimmed.isEmpty else {
            name = repo.name
            return
        }
        guard trimmed != repo.name else { return }
        Task { await app.rename(repo, to: trimmed) }
    }

    private var branchSection: some View {
        Section {
            SettingsRow("Branch prefix") {
                VStack(alignment: .leading, spacing: Metrics.spacingTight) {
                    TextField("", text: $model.draft.branchPrefix, prompt: Text("None"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    SettingsDestinationLabel(model: model, key: .branchPrefix)
                }
            }

            Toggle(isOn: $model.draft.deleteBranchOnArchive) {
                Text("Delete the branch when a workspace is archived")
                Text("Archiving always removes the worktree. Turn this on to remove its branch too. The project's default branch is never removed.")
                SettingsDestinationLabel(model: model, key: .deleteBranchOnArchive)
            }

            Toggle(isOn: $model.draft.archiveOnMerge) {
                Text("Archive a workspace when its pull request merges")
                Text("Only a pull request seen open first counts. Nothing is archived while an agent or a command is running, or with work that is not in git.")
                SettingsDestinationLabel(model: model, key: .archiveOnMerge)
            }
        } header: {
            Text("Branches")
        }
    }

    private var browserSection: some View {
        Section {
            SettingsRow("Address") {
                TextField("", text: $model.draft.browserURL, prompt: Text(Self.browserPrompt))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
            }
        } header: {
            Text("Browser")
        } footer: {
            VStack(alignment: .leading, spacing: Metrics.spacingTight) {
                Text(Self.browserFootnote)
                SettingsDestinationLabel(model: model, key: .browserURL)
            }
            .font(Typo.caption)
            .foregroundStyle(Palette.textSecondary)
        }
    }

    private static let browserPrompt = "http://localhost:$\(WorkspaceManager.environmentPrefix)_PORT"

    private static let browserFootnote = "Where a browser pane opens when you ask a workspace for "
        + "one. Script variables are expanded, so a path or a hostname can be stated once for "
        + "every workspace. A setup script that writes an address to "
        + "$\(WorkspaceManager.environmentPrefix)_URL_FILE beats this, for the workspaces where "
        + "only the script knows where the site ended up."

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: Metrics.gutter) {
            if model.loaded.sources.isEmpty {
                Text("No settings file applies to this project yet. Saving creates \(shortPath(SettingsWriter.defaultFile(repo: repo.path))).")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                ForEach(model.loaded.sources, id: \.self) { source in
                    HStack(spacing: Metrics.gutter) {
                        Text(shortPath(source))
                            .font(Typo.codeSmall)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(source)

                        Spacer(minLength: Metrics.spacingSmall)

                        Button("Open") { Reveal.inEditor(source, repo: repo.id) }
                    }
                }
            }
            Text("Listed from lowest to highest priority. Project files override machine settings; .local files override shared files.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func shortPath(_ path: String) -> String {
        if path.hasPrefix(repo.path + "/") {
            return String(path.dropFirst(repo.path.count + 1))
        }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private var removeSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingRemove = true
            } label: {
                Label("Remove Project", systemImage: "trash")
                    .foregroundStyle(Palette.negative)
            }
        } footer: {
            Text("Unified Dev forgets the project. Nothing on disk is deleted.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var removal: Confirmation {
        app.projectRemoval(repo)
    }

    private func removeProject() {
        Task {
            await app.removeRepository(repo)
            dismiss()
        }
    }
}

struct SettingsDestinationLabel: View {
    let model: RepoSettingsModel
    let key: SettingsKey

    var body: some View {
        Text(text)
            .font(Typo.caption)
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(help)
    }

    private var destination: String { model.destination(for: key) }
    private var origin: String? { model.loaded.origins[key] }

    private var tint: Color {
        if SettingsSaveLabel.isFailure(model.phase) { return Palette.negative }
        return isForking ? Palette.warning : Palette.textSecondary
    }

    private var isForking: Bool {
        guard let origin, SettingsLoader.repoPaths(repo: model.repo.path).contains(origin)
        else { return false }
        return origin != destination
    }

    private var text: String {
        guard model.phase == .idle else {
            return SettingsSaveLabel.text(destination: short(destination), phase: model.phase)
        }
        if isForking, let origin {
            return "Read from \(short(origin)), saved to \(short(destination))"
        }
        if let origin, !SettingsLoader.repoPaths(repo: model.repo.path).contains(origin) {
            return "Saved to \(short(destination)), overriding \(short(origin))"
        }
        return "Saved to \(short(destination))"
    }

    private var help: String {
        guard isForking, let origin else { return text }
        return """
            \(short(origin)) was written for Conductor. Unified Dev reads it but does not edit it, \
            so saving states this setting in \(short(destination)) as well. Unified Dev uses the new \
            value; Conductor keeps reading the old one until the line is removed by hand.
            """
    }

    private func short(_ path: String) -> String {
        path.hasPrefix(model.repo.path + "/")
            ? String(path.dropFirst(model.repo.path.count + 1))
            : (path as NSString).abbreviatingWithTildeInPath
    }
}

struct AccentSwatches: View {
    @Binding var selection: Color

    private static let size: CGFloat = 14
    private static let padding: CGFloat = 3

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Accent.all, id: \.self) { hex in
                swatch(hex)
            }

            ColorPicker("Another colour", selection: $selection, supportsOpacity: false)
                .labelsHidden()
                .help("Another colour")
                .padding(.leading, Metrics.spacingWide)
        }
        .padding(.leading, -Self.padding)
    }

    private func swatch(_ hex: String) -> some View {
        let isSelected = selection.hexString?.caseInsensitiveCompare(hex) == .orderedSame

        return Button {
            selection = Color(hexString: hex)
        } label: {
            Circle()
                .fill(Color(hexString: hex))
                .frame(width: Self.size, height: Self.size)
                .overlay {
                    Circle().strokeBorder(Palette.textPrimary.opacity(0.12), lineWidth: Metrics.outline)
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(Palette.surface, lineWidth: 2)
                            .padding(2)
                    }
                }
                .padding(Self.padding)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("#\(hex)")
        .accessibilityLabel("Colour #\(hex)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
