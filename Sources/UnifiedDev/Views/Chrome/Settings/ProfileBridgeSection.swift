import SwiftUI
import Core

struct ProfileBridgeSection: View {
    let profile: ProfileID

    @Environment(AppModel.self) private var app

    @State private var isOn = false
    @State private var isLoaded = false
    @State private var failure: String?
    @State private var saving: Task<Void, Never>?

    var body: some View {
        ProfileBridgeRows(isOn: binding, isEnabled: isLoaded, failure: failure)
            .task(id: profile) {
                guard let store = app.store else { return }
                let changes = store.changes(of: [.settings])
                isOn = await ProfileBridgeSwitch.isOn(profile: profile, in: store)
                isLoaded = true
                for await _ in changes {
                    isOn = await ProfileBridgeSwitch.isOn(profile: profile, in: store)
                }
            }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { chosen in
                isOn = chosen
                failure = nil
                guard let store = app.store else { return }
                saving = Task { [saving, profile] in
                    await saving?.value
                    do {
                        try await ProfileBridgeSwitch.save(chosen, profile: profile, to: store)
                    } catch {
                        isOn = await ProfileBridgeSwitch.isOn(profile: profile, in: store)
                        failure = ProfileBridgeSwitch.saveFailure
                    }
                }
            }
        )
    }
}

struct ProfileBridgeRows: View {
    @Binding var isOn: Bool
    var isEnabled: Bool
    var failure: String?

    var body: some View {
        Section {
            LabeledContent(ProfileBridgeSwitch.settingTitle) {
                Toggle(ProfileBridgeSwitch.settingTitle, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!isEnabled)
            }
        } footer: {
            VStack(alignment: .leading, spacing: Metrics.spacingSmall) {
                Text(ProfileBridgeSwitch.caveat)
                    .settingsFootnote()
                if let failure {
                    Text(failure)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.negative)
                }
            }
        }
    }
}
