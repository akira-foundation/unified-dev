import SwiftUI
import Core

struct ClaudeChromeSettingsSection: View {
    @Environment(AppModel.self) private var app
    @State private var isOn: Bool?
    @State private var failure: String?

    private var choice: Binding<Bool> {
        Binding(get: { isOn ?? false }, set: { value in
            isOn = value
            Task { await store(value) }
        })
    }

    var body: some View {
        Section {
            Toggle("Use Claude in Chrome", isOn: choice)
                .disabled(isOn == nil)
            if let failure { Text(failure).foregroundStyle(.red) }
        } footer: {
            Text("Gives Claude Code agents the Claude in Chrome tools, which open tabs and act in your own Chrome with its sign ins. Needs the Claude extension in Chrome and a claude.ai sign in. Each chat restarts its agent with the change on the next message you send it, and a chat run in the terminal on its next launch.")
                .settingsFootnote()
        }
        .task { await load() }
    }

    private func load() async {
        guard let store = app.store else { return }
        do {
            isOn = ClaudeChrome.isEnabled(try await store.setting(ClaudeChrome.settingKey))
        } catch { failure = error.localizedDescription }
    }

    private func store(_ value: Bool) async {
        do {
            try await app.store?.setSetting(ClaudeChrome.settingKey, ClaudeChrome.storedValue(value))
            failure = nil
        } catch {
            failure = error.localizedDescription
            await load()
        }
    }
}
