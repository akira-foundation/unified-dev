import SwiftUI
import Core

struct ModelPresetDraft: Identifiable {
    let id = UUID()
    var preset: ModelPreset
}

struct ModelPresetEditor: View {
    var refusing: Set<AgentKind>
    var onSave: (ModelPreset) -> Void
    var onCancel: () -> Void

    @State private var preset: ModelPreset

    init(
        draft: ModelPresetDraft,
        refusing: Set<AgentKind>,
        onSave: @escaping (ModelPreset) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.refusing = refusing
        self.onSave = onSave
        self.onCancel = onCancel
        _preset = State(initialValue: draft.preset)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $preset.name, prompt: Text("Opus 5 High"))

                SettingsRow("Model") {
                    ModelAndEffortPickers(
                        model: $preset.model, effort: $preset.effort, backend: backendBinding,
                        offersAgentDefault: true
                    )
                }

                if preset.backend == .claudeCode {
                    Picker(selection: $preset.outputStyle) {
                        ForEach(outputStyles.options(includingCurrent: preset.outputStyle)) { option in
                            Text(option.label).tag(option.id)
                        }
                    } label: {
                        Text("Output style")
                        Text(refusing.contains(.claudeCode) ? "Built-in styles only" : "From the default Claude Code account")
                    }
                }

                Picker("Permissions", selection: $preset.permissionMode) {
                    ForEach(ComposerControls(agentKind: preset.backend).permissionModeChoices) { choice in
                        Text(choice.label).tag(choice.mode)
                    }
                }
            }
            .settingsForm()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let name = ModelPreset.cleanName(preset.name) else { return }
                    var saved = preset
                    saved.name = name
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(ModelPreset.cleanName(preset.name) == nil)
            }
            .padding(Metrics.gutter)
        }
        .frame(width: 480, height: 300)
        .task(id: refusing) { await outputStyles.refreshIfStale(project: nil) }
    }

    private var outputStyles: ComposerOutputStyleCatalog {
        .appWide(refusing: refusing)
    }

    private var backendBinding: Binding<AgentKind> {
        Binding(
            get: { preset.backend },
            set: { kind in
                preset.backend = kind
                preset.permissionMode = preset.permissionMode.nearest(on: kind)
            }
        )
    }
}
