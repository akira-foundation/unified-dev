import SwiftUI
import Core

struct RepoSettingSwitch: View {
    let repo: Repo
    let copy: RepoSettingSwitchCopy
    let read: @Sendable (RepoID, Store) async -> Bool
    let write: @Sendable (Bool, RepoID, Store) async throws -> Void

    @Environment(AppModel.self) private var app

    @State private var isOn = false
    @State private var isLoaded = false
    @State private var failure: String?
    @State private var saving: Task<Void, Never>?

    var body: some View {
        RepoSettingSwitchRows(copy: copy, isOn: binding, isEnabled: isLoaded, failure: failure)
            .task(id: repo.id) {
                guard let store = app.store else { return }
                let changes = store.changes(of: [.settings])
                isOn = await read(repo.id, store)
                isLoaded = true
                for await _ in changes {
                    isOn = await read(repo.id, store)
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
                saving = Task { [saving, repoID = repo.id] in
                    await saving?.value
                    do {
                        try await write(chosen, repoID, store)
                    } catch {
                        isOn = await read(repoID, store)
                        failure = copy.saveFailure
                    }
                }
            }
        )
    }
}

struct RepoSettingSwitchCopy {
    let title: String
    let header: String
    let caveat: String
    let saveFailure: String
}

struct RepoSettingSwitchRows: View {
    let copy: RepoSettingSwitchCopy
    @Binding var isOn: Bool
    var isEnabled: Bool
    var failure: String?

    var body: some View {
        Section {
            LabeledContent(copy.title) {
                Toggle(copy.title, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!isEnabled)
            }
        } header: {
            Text(copy.header)
        } footer: {
            VStack(alignment: .leading, spacing: Metrics.spacingSmall) {
                Text(copy.caveat)
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
