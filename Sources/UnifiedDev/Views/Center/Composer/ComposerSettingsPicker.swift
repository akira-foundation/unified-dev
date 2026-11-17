import SwiftUI
import Core

struct ComposerSettingsPicker: View {
    var controls: ComposerControls
    var models: [ComposerModelSection]
    var catalogModels: [AgentKind: [AgentModel]]
    var efforts: [ComposerOption]
    var outputStyles: [ComposerOption]
    var permissionModes: [ComposerOption]
    var orchestrates: Bool = false
    var isCompact: Bool
    var account: ComposerAccountSection?
    var onPreset: @MainActor (ModelPreset) -> Void
    var onModel: @MainActor (String) -> Void
    var onEffort: @MainActor (String) -> Void
    var onOutputStyle: @MainActor (String) -> Void
    var onPermissionMode: @MainActor (String) -> Void
    var onContextWindow: @MainActor (Int) -> Void
    var onInteractionMode: @MainActor (InteractionMode) -> Void = { _ in }
    var onOpenInNewChat: (@MainActor (AgentKind) -> Void)?
    var sends: Int = 0

    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var isOpen = false

    private var library: ModelPresetLibrary { .shared }

    var body: some View {
        let summary = ComposerPresetSummary(
            controls: controls, presets: library.list, modelLabel: modelLabel,
            effortLabel: effortLabel, models: catalogModels, orchestrates: orchestrates
        )

        Group {
            if library.presets.isEmpty {
                Button { isOpen = true } label: { settingsLabel(summary) }
            } else {
                ComposerPresetMenu(
                    presets: library.presets,
                    matched: summary.matched,
                    account: account,
                    onPreset: onPreset,
                    onChangeAccount: changeAccount,
                    onCustom: { DispatchQueue.main.async { isOpen = true } },
                    onManage: managePresets
                ) {
                    settingsLabel(summary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .opensDuringCapture(.agentSettings, $isOpen)
        .help(account?.warns == true ? "\(summary.help)\n\(account?.sentence ?? "")" : summary.help)
        .accessibilityLabel("Agent settings")
        .accessibilityValue(controls.settingsLabel(model: summary.accessibilityValue))
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            ComposerSettingsPanel(
                controls: controls,
                models: models,
                efforts: efforts,
                outputStyles: outputStyles,
                permissionModes: permissionModes,
                orchestrates: orchestrates,
                account: account,
                matchedPreset: summary.matched,
                suggestedPresetName: summary.suggestedName,
                onModel: settling(onModel),
                onEffort: settling(onEffort),
                onOutputStyle: settling(onOutputStyle),
                onPermissionMode: settling(onPermissionMode),
                onContextWindow: settling(onContextWindow),
                onInteractionMode: settling(onInteractionMode),
                onOpenInNewChat: closingThenOpeningNewChat,
                onChangeAccount: changeAccount,
                onSavePreset: savePreset
            )
            .environment(\.fontScale, 1)
        }
        .onChange(of: sends) { _, _ in close(on: .sentMessage) }
        .task { await library.load(from: app.store) }
    }

    private func close(on event: AgentSettingsEvent) {
        if event.closesSettings { isOpen = false }
    }

    private func settling<Value>(_ choose: @escaping @MainActor (Value) -> Void) -> @MainActor (Value) -> Void {
        { value in
            choose(value)
            close(on: .changedSetting)
        }
    }

    private var closingThenOpeningNewChat: (@MainActor (AgentKind) -> Void)? {
        guard let onOpenInNewChat else { return nil }
        return { kind in
            close(on: .openedInNewChat)
            onOpenInNewChat(kind)
        }
    }

    private func settingsLabel(_ summary: ComposerPresetSummary) -> some View {
        ComposerSettingsLabel(
            text: isCompact ? nil : controls.settingsLabel(model: summary.title),
            isActive: isOpen,
            isOneOff: summary.isOneOff,
            warns: account?.warns == true
        )
    }

    private func changeAccount() {
        guard let account else { return }
        close(on: .changedAccount)
        RepoSettingsPaneRequest.post(.agents, for: account.repoID)
        openWindow(id: RepoSettingsWindow.id, value: account.repoID)
    }

    private var allModels: [ComposerOption] { models.flatMap(\.options) }

    private var modelLabel: String {
        ComposerOption.label(for: controls.model, in: allModels)
    }

    private var effortLabel: String {
        ComposerOption.effortLabel(for: controls.effort, in: efforts)
    }

    private func managePresets() {
        SettingsTabRequest.post(.presets)
        SettingsWindow.open()
    }

    private func savePreset(_ name: String) {
        guard let name = ModelPreset.cleanName(name) else { return }
        close(on: .savedPreset)
        library.add(ModelPreset(name: name, controls: controls), in: app.store)
    }
}
