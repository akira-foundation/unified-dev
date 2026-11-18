import SwiftUI
import Core

struct ModelSettingsView: View {
    @Environment(AppModel.self) private var app
    @Binding var defaults: AppDefaults
    private var outputStyles: ComposerOutputStyleCatalog {
        .appWide(app.appWideOutputStyles)
    }

    private var catalog: ComposerModelCatalog { .shared }

    var body: some View {
        Form {
            Section {
                SettingsRow("New sessions") {
                    ModelAndEffortPickers(
                        model: $defaults.model, effort: $defaults.effort, backend: $defaults.backend,
                        offersAgentDefault: false
                    )
                }
                SettingsRow("Reviews") {
                    ModelAndEffortPickers(
                        model: $defaults.reviewModel, effort: $defaults.reviewEffort,
                        backend: $defaults.reviewBackend, offersAgentDefault: false
                    )
                }
            } header: {
                Text("Models")
            } footer: {
                VStack(alignment: .leading, spacing: Metrics.spacingSmall) {
                    ModelListFailureNote()
                    Text("Each row selects a model and reasoning effort. A Claude family name such as Opus follows the newest version of that family. The number beside it is the version Claude Code last resolved it to for this account, and the transcript says which version ran. Project model settings take priority. Existing sessions keep their settings.")
                        .settingsFootnote()
                    if let preset = ModelPresetLibrary.shared.list.defaultPreset {
                        Text("New sessions start on the default preset, \u{201C}\(preset.name)\u{201D}, rather than on this row. Change that under Model Presets.")
                            .settingsFootnote()
                    }
                }
            }

            Section("New session behaviour") {
                Picker("Open new chats in", selection: $defaults.terminalChat) {
                    Text("Unified Dev chat").tag(false)
                    Text("CLI chat").tag(true)
                }
                Text("Used for new chats, panes and workspaces. CLI chat supports Claude Code and Codex; other agents use Unified Dev chat.")
                    .settingsFootnote()
                Toggle("Start in plan mode", isOn: $defaults.planMode)
                Toggle("Start in fast mode", isOn: $defaults.fastMode)
            }

            Section {
                Picker(selection: $defaults.outputStyle) {
                    ForEach(outputStyles.options(includingCurrent: defaults.outputStyle)) { option in
                        Text(option.label).tag(option.id)
                    }
                } label: {
                    Text("Output style")
                    Text(outputStyles.detail(of: defaults.outputStyle) ?? "How new Claude Code sessions write.")
                }
            } header: {
                Text("Claude Code")
            } footer: {
                Text(app.appWideOutputStyles.settingsFooter)
                    .settingsFootnote()
            }

            Section {
                Picker("Context window", selection: $defaults.codexContextWindow) {
                    ForEach(CodexContextWindow.options(including: defaults.codexContextWindow), id: \.self) { tokens in
                        Text(CodexContextWindow.label(for: tokens)).tag(tokens)
                    }
                }
            } header: {
                Text("Codex")
            } footer: {
                Text("Overrides the context size reported to new Codex sessions. Use the model default unless you need a specific size.")
                    .settingsFootnote()
            }
        }
        .settingsForm()
        .task {
            ComposerModelCatalog.shared.load()
            await ModelPresetLibrary.shared.load(from: app.store)
        }
        .task(id: app.appWideOutputStyles) {
            await outputStyles.refreshIfStale(project: nil)
        }
    }
}
