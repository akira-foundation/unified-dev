import Core
import SwiftUI

struct ProfileSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ProfileDraft
    @State private var isConfirmingDelete = false
    @State private var isSaving = false
    @State private var isSaved = false

    init(request: ProfileSheetRequest, profiles: [Profile], source: (ProfileID) -> ProfileAccountSource) {
        switch request {
        case .new: _draft = State(initialValue: .new(among: profiles))
        case .edit(let profile):
            _draft = State(initialValue: ProfileDraft(editing: profile, accounts: source(profile.id)))
        }
    }

    var body: some View {
        ProfileSheetBody(
            draft: $draft,
            isNew: draft.profileID == nil,
            isSaving: isSaving,
            cancelTitle: isSaved ? "Close" : "Cancel",
            deletionRefusal: deletionRefusal,
            onDelete: { isConfirmingDelete = true },
            onCancel: { dismiss() },
            onSave: save
        ) {
            if let editing, draft.accounts == .own, !draft.accountsChanged {
                ProfileAgentAccountSection(profile: editing.id)
                ProfileAccountSignInSection(profile: editing)
            }
            if let editing {
                ProfileGitHubSection(profile: editing)
                ProfileBitbucketSection(profile: editing)
                ProfileBridgeSection(profile: editing.id)
            }
        }
        .confirmationDialog(
            "Delete \(editing?.name ?? "")?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Profile", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This profile has no projects, so nothing else changes.")
        }
    }

    private var editing: Profile? {
        guard let id = draft.profileID else { return nil }
        return app.profiles.first { $0.id == id }
    }

    private var deletionRefusal: String? {
        guard let editing else { return nil }
        return ProfileDeletionRefused.refusal(
            for: editing.id,
            projectCount: ProfileScope.repos(app.repos, in: editing.id).count
        )?.sentence
    }

    private func save() {
        guard draft.canSave, !isSaving else { return }
        isSaving = true
        let saved = draft
        let name = saved.savedName
        Task {
            if let id = saved.profileID {
                await app.updateProfile(id) { profile in
                    profile.name = name
                    profile.colour = saved.colour
                    profile.symbol = saved.symbol
                }
                if saved.accountsChanged { await app.setAccountSource(saved.accounts, for: id) }
                guard ProfileAccountSignIn.keepsSheetOpen(after: saved),
                      let updated = app.profiles.first(where: { $0.id == id }) else {
                    dismiss()
                    return
                }
                draft = ProfileDraft(editing: updated, accounts: saved.accounts)
                isSaved = true
                isSaving = false
            } else {
                let made = await app.createProfile(
                    name: name, colour: saved.colour, symbol: saved.symbol, accounts: saved.accounts
                )
                guard let made, ProfileAccountSignIn.keepsSheetOpen(after: saved) else {
                    dismiss()
                    return
                }
                draft = ProfileDraft(editing: made, accounts: saved.accounts)
                isSaved = true
                isSaving = false
            }
        }
    }

    private func delete() {
        guard let id = draft.profileID else { return }
        Task { await app.deleteProfile(id) }
        dismiss()
    }
}

struct ProfileSheetBody<Accounts: View>: View {
    @Binding var draft: ProfileDraft
    var isNew: Bool
    var isSaving = false
    var cancelTitle = "Cancel"
    var deletionRefusal: String?
    var onDelete: () -> Void
    var onCancel: () -> Void
    var onSave: () -> Void
    @ViewBuilder var accounts: Accounts

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(isNew ? "New Profile" : "Profile Settings") {
                    TextField(text: $draft.name, prompt: Text("Required")) {
                        Text("Name")
                        if let problem = draft.nameProblem {
                            Text(problem)
                        }
                    }
                }

                Section("Colour") {
                    ProfileColourGrid(selection: $draft.colour)
                }

                Section("Icon") {
                    ProfileSymbolGrid(selection: $draft.symbol, colour: draft.colour)
                }

                if draft.choosesAccounts {
                    accountsSection
                }

                accounts

                if !isNew {
                    deleteSection
                }
            }
            .settingsForm()

            HStack {
                Spacer()
                Button(cancelTitle, role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canSave || isSaving)
                    .help(draft.nameProblem ?? "")
            }
            .padding(Metrics.gutter)
        }
        .frame(width: ProfileSheetMetrics.width, height: isNew ? ProfileSheetMetrics.newHeight : ProfileSheetMetrics.editHeight)
    }

    private var accountsSection: some View {
        Section {
            Picker("Agent accounts", selection: $draft.accounts) {
                ForEach(ProfileAccountSource.allCases, id: \.self) { source in
                    Text(ProfileDraft.accountsLabel(source)).tag(source)
                }
            }
        } footer: {
            Text(draft.accountsFootnote)
                .settingsFootnote()
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Profile", role: .destructive, action: onDelete)
                .disabled(deletionRefusal != nil)
        } footer: {
            if let deletionRefusal {
                Text(deletionRefusal)
                    .settingsFootnote()
            }
        }
    }
}

enum ProfileSheetMetrics {
    static let width: CGFloat = 440
    static let newHeight: CGFloat = 540
    static let editHeight: CGFloat = 760
}

struct ProfileColourGrid: View {
    @Binding var selection: String

    private static let size: CGFloat = 22

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: Accent.all.count)) {
            ForEach(Accent.all, id: \.self) { hex in
                swatch(hex)
            }
        }
    }

    private func swatch(_ hex: String) -> some View {
        let isSelected = selection == hex
        let name = ProfileChoices.colourName(hex)

        return Button {
            selection = hex
        } label: {
            Circle()
                .fill(Color(hexString: hex))
                .frame(width: Self.size, height: Self.size)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(Typo.captionEmphasis)
                            .foregroundStyle(.white)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel("Colour \(name)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct ProfileSymbolGrid: View {
    @Binding var selection: String
    var colour: String

    private static let size: CGFloat = 28
    private static let columns = 8

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: Self.columns)) {
            ForEach(ProfileChoices.symbols) { symbol in
                cell(symbol)
            }
        }
    }

    private func cell(_ symbol: ProfileChoices.Symbol) -> some View {
        let isSelected = selection == symbol.name

        return Button {
            selection = symbol.name
        } label: {
            Image(systemName: symbol.name)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Palette.textSecondary))
                .frame(width: Self.size, height: Self.size)
                .background {
                    if isSelected {
                        Circle().fill(Color(hexString: colour))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(symbol.label)
        .accessibilityLabel("Icon \(symbol.label)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
