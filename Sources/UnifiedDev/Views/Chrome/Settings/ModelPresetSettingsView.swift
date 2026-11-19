import SwiftUI
import Core

struct ModelPresetSettingsView: View {
    @Environment(AppModel.self) private var app

    @State private var editing: ModelPresetDraft?
    @State private var renaming: ModelPreset?
    @State private var renameText = ""

    private var library: ModelPresetLibrary { .shared }
    private var catalog: ComposerModelCatalog { .shared }

    var body: some View {
        VStack(spacing: 0) {
            if let failure = library.saveFailure {
                ErrorBanner(title: "Could not save presets", message: failure) {
                    library.dismissSaveFailure()
                }
                .padding(Metrics.inset)
            }
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                if library.presets.isEmpty {
                    Text("No presets yet. Add one here, or choose Save as Preset\u{2026} in a chat's agent settings.")
                        .settingsFootnote()
                } else {
                    ForEach(library.presets) { preset in
                        row(preset)
                            .contextMenu { actions(for: preset) }
                    }
                    .onMove { source, destination in
                        library.move(fromOffsets: source, toOffset: destination, in: app.store)
                    }
                }

                Button("Add Preset\u{2026}") { editing = ModelPresetDraft(preset: newPreset()) }
            } header: {
                Text("Presets")
            } footer: {
                Text("Shown in the composer's agent settings menu, in this order.")
                    .settingsFootnote()
            }

            Section {
                Picker("Default for new sessions", selection: defaultBinding) {
                    Text("None").tag(ModelPresetID?.none)
                    ForEach(library.presets) { preset in
                        Text(preset.name).tag(ModelPresetID?.some(preset.id))
                    }
                }
            } header: {
                Text("New sessions")
            } footer: {
                Text("With a default preset, new sessions start on its model, reasoning, output style and permissions instead of the choices under Sessions. Project model settings still take priority.")
                    .settingsFootnote()
            }
        }
        .settingsForm()
        .disabled(!library.isLoaded)
        .task {
            catalog.load()
            await library.load(from: app.store)
        }
        .sheet(item: $editing) { draft in
            ModelPresetEditor(draft: draft, reading: app.appWideOutputStyles) { saved in
                save(saved)
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
        .alert("Rename Preset", isPresented: isRenaming) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let renaming { library.rename(id: renaming.id, to: renameText, in: app.store) }
                renaming = nil
            }
            .disabled(ModelPreset.cleanName(renameText) == nil)
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func row(_ preset: ModelPreset) -> some View {
        HStack(spacing: Metrics.gutter) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Palette.textTertiary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Metrics.spacingTight) {
                HStack(spacing: Metrics.spacing) {
                    Text(preset.name)
                        .lineLimit(1)
                    if library.list.defaultID == preset.id {
                        defaultBadge
                    }
                }
                Text(summary(of: preset))
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Metrics.spacing)

            Menu {
                actions(for: preset)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Preset actions")
            .accessibilityLabel("Actions for \(preset.name)")
        }
        .padding(.vertical, Metrics.spacingTight)
    }

    private var defaultBadge: some View {
        Text("Default")
            .font(Typo.caption)
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, Metrics.spacingSmall)
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cornerSmall)
                    .strokeBorder(Palette.accent.opacity(0.4), lineWidth: Metrics.outline)
            }
    }

    @ViewBuilder
    private func actions(for preset: ModelPreset) -> some View {
        Button("Edit\u{2026}") { editing = ModelPresetDraft(preset: preset) }
        Button("Rename\u{2026}") {
            renameText = preset.name
            renaming = preset
        }
        if library.list.defaultID == preset.id {
            Button("Stop Using for New Sessions") { library.setDefault(nil, in: app.store) }
        } else {
            Button("Use for New Sessions") { library.setDefault(preset.id, in: app.store) }
        }
        Divider()
        Button("Move Up") { library.move(id: preset.id, by: -1, in: app.store) }
            .disabled(library.presets.first?.id == preset.id)
        Button("Move Down") { library.move(id: preset.id, by: 1, in: app.store) }
            .disabled(library.presets.last?.id == preset.id)
        Divider()
        Button("Delete", role: .destructive) { library.delete(id: preset.id, in: app.store) }
    }

    private func save(_ preset: ModelPreset) {
        guard library.list.preset(id: preset.id) != nil else {
            library.add(preset, in: app.store)
            return
        }
        library.update(preset, in: app.store)
    }

    private func summary(of preset: ModelPreset) -> String {
        let model = ComposerOption.label(
            for: preset.model,
            in: catalog.sections(includingCurrent: preset.model, on: preset.backend).flatMap(\.options)
        )
        let effort = ComposerOption.effortLabel(
            for: preset.effort,
            in: catalog.efforts(for: preset.backend, model: preset.model, offeringAgentDefault: true)
        )
        return "\(model) \u{00B7} \(effort) \u{00B7} \(preset.permissionMode.label(on: preset.backend))"
    }

    private func newPreset() -> ModelPreset {
        ModelPreset(
            name: "",
            model: AppDefaults.fallbackModel,
            effort: AppDefaults.fallbackEffort,
            backend: AppDefaults.fallbackBackend,
            permissionMode: AppDefaults.fallbackPermissionMode
        )
    }

    private var defaultBinding: Binding<ModelPresetID?> {
        Binding(
            get: { library.list.defaultID },
            set: { id in MainActor.assumeIsolated { library.setDefault(id, in: app.store) } }
        )
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }
}
