import Core
import SwiftUI

@MainActor
struct ProfileCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Profile") {
            ForEach(ProfileShortcut.digits, id: \.self) { digit in
                if let id = ProfileShortcut.profile(at: digit, among: model.profiles),
                   let profile = model.profiles.first(where: { $0.id == id }) {
                    Toggle(isOn: isActive(id)) {
                        ProfileMenuLabel(profile: profile)
                    }
                    .keyboardShortcut(
                        ProfileShortcut.key(at: digit).equivalent,
                        modifiers: ProfileShortcut.key(at: digit).eventModifiers
                    )
                }
            }

            Divider()

            Button("New Profile\u{2026}") { model.askForProfileSheet(.new) }

            Button("Profile Settings\u{2026}") {
                guard let active = model.activeProfile else { return }
                model.askForProfileSheet(.edit(active))
            }
            .disabled(model.activeProfile == nil)
        }
    }

    private func isActive(_ id: ProfileID) -> Binding<Bool> {
        Binding(
            get: { model.activeProfileID == id },
            set: { _ in Task { await model.switchProfile(to: id) } }
        )
    }
}
