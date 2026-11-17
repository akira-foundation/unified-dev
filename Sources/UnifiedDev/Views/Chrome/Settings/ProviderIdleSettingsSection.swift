import SwiftUI
import Core

struct ProviderIdleSettingsSection: View {
    @Environment(AppModel.self) private var app
    @State private var minutes = ProviderIdlePolicy.defaultMinutes
    @State private var loaded = false
    @State private var failure: String?

    var body: some View {
        Section("Idle agents") {
            Picker("Release idle processes", selection: $minutes) {
                Text("Never").tag(0)
                ForEach(ProviderIdlePolicy.choices.filter { $0 > 0 }, id: \.self) { value in
                    Text("After \(value) minutes").tag(value)
                }
            }
            Text("Conversations resume when you send again. Active work and waiting questions keep their processes. Codex may ask again for permissions granted only for the previous process.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
            if let failure { Text(failure).foregroundStyle(.red) }
        }
        .task {
            guard let store = app.store else { return }
            do {
                minutes = ProviderIdlePolicy.minutes(stored: try await store.setting(ProviderIdlePolicy.settingKey))
                loaded = true
            } catch { failure = error.localizedDescription }
        }
        .onChange(of: minutes) { _, value in
            guard loaded else { return }
            Task {
                do {
                    try await app.store?.setSetting(ProviderIdlePolicy.settingKey, String(value))
                    failure = nil
                } catch { failure = error.localizedDescription }
            }
        }
    }
}
