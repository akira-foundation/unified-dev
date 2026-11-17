import SwiftUI
import Core

struct ProjectSetupSheet: View {
    let request: ProjectSetup.Request
    let onFinish: (String?) -> Void

    private enum Choice: Equatable {
        case local
        case gitHub
    }

    private enum Phase: Equatable {
        case choosing
        case working(RepositoryStartStep)
        case failed(RepositoryStartFailure)
        case stopped(RepositoryStartAbandonment)
        case finished(RepositoryStartOutcome)
    }

    @State private var choice: Choice
    @State private var owners: [GitHubOwner] = []
    @State private var owner = ""
    @State private var name = ""
    @State private var availability: NameAvailability = .idle
    @State private var access: GitHubAvailability.State = .unknown
    @State private var phase: Phase = .choosing
    @State private var signIn: GitHubSignIn.Request?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app

    @State private var isShowingExcluded = false
    @State private var availabilityCheck: Task<Void, Never>?
    @State private var isLoadingOwners = false
    @State private var startTask: Task<Void, Never>?
    @State private var isStepSlow = false
    @State private var isStopping = false

    private static let availabilityDelay = Duration.milliseconds(450)
    private static let width: CGFloat = 560
    private static let excludedShown = 8

    init(request: ProjectSetup.Request, onFinish: @escaping (String?) -> Void) {
        self.request = request
        self.onFinish = onFinish
        _choice = State(initialValue: ProjectSetup.capturedChoice == "github" ? .gitHub : .local)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()

            VStack(alignment: .leading, spacing: Metrics.gutter) {
                switch phase {
                case .choosing: offer
                case .working(let step): working(step)
                case .failed(let failure): failed(failure)
                case .stopped(let left): stopped(left)
                case .finished(let outcome): finished(outcome)
                }
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)

            Hairline()
            footer
        }
        .frame(width: Self.width)
        .background(Palette.surface)
        .task { await probeGitHub() }
        .onAppear { name = GitHubRepositoryName.suggestion(from: request.folderName) }
        .onDisappear {
            availabilityCheck?.cancel()
            startTask?.cancel()
        }
        .sheet(item: $signIn) { pending in
            GitHubSignInSheet(request: pending) { connected in
                signIn = nil
                if connected { Task { await probeGitHub() } }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.spacingWide) {
            Image(systemName: "folder.badge.questionmark")
                .font(Typo.bodyEmphasis)
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Metrics.spacingTight) {
                Text(title)
                    .font(Typo.title)
                    .foregroundStyle(Palette.textPrimary)
                Text(request.path)
                    .font(Typo.codeTiny)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, Metrics.inset)
    }

    private var title: String {
        switch phase {
        case .choosing: "\(request.folderName) is not a git repository"
        case .working: "Setting up \(request.folderName)"
        case .failed(let failure): failure.title
        case .stopped: "Stopped setting up \(request.folderName)"
        case .finished: "\(request.folderName) is ready"
        }
    }

    @ViewBuilder
    private var offer: some View {
        Text(
            "Unified Dev runs every agent in a git worktree, so a project has to be a repository. "
                + "Unified Dev can make this folder one."
        )
        .font(Typo.body)
        .foregroundStyle(Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

        if let problem = request.identityProblem {
            Callout(text: problem, symbol: "exclamationmark.triangle.fill", tone: .warning)
        }

        firstCommit

        VStack(spacing: Metrics.spacing) {
            option(
                .local,
                title: "Here on this Mac",
                caption: "git init and a first commit, and nothing else. No account, no network. "
                    + "Worktrees, agents, diffs and merging all work on this."
            )
            option(
                .gitHub,
                title: "And a private repository on GitHub",
                caption: "The same, then a private repository, origin, and a first push. "
                    + "Needed only for pull requests and checks."
            )
        }

        if choice == .gitHub { gitHub }
    }

    private func option(_ value: Choice, title: String, caption: String) -> some View {
        Button {
            choice = value
            if value == .gitHub { scheduleAvailabilityCheck() }
        } label: {
            HStack(alignment: .top, spacing: Metrics.spacingWide) {
                Image(systemName: choice == value ? "largecircle.fill.circle" : "circle")
                    .font(Typo.body)
                    .foregroundStyle(choice == value ? Palette.controlAccent : Palette.textTertiary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Metrics.spacingTight) {
                    Text(title)
                        .font(Typo.labelEmphasis)
                        .foregroundStyle(Palette.textPrimary)
                    Text(caption)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(Metrics.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                choice == value ? Palette.selected : Palette.surfaceSunken,
                in: RoundedRectangle(cornerRadius: Metrics.corner)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.corner)
                    .strokeBorder(
                        choice == value ? Palette.controlAccent : Palette.border,
                        lineWidth: Metrics.outline
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice == value ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var firstCommit: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing) {
            LabeledLine(label: "First commit", value: request.contents.summary)

            if !request.contents.excluded.isEmpty {
                Button {
                    isShowingExcluded.toggle()
                } label: {
                    HStack(spacing: Metrics.spacingSmall) {
                        Image(systemName: isShowingExcluded ? "chevron.down" : "chevron.right")
                            .font(Typo.micro)
                        Text(request.contents.excludedSummary ?? "")
                            .font(Typo.caption)
                    }
                    .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .animation(reduceMotion ? nil : Motion.pane, value: isShowingExcluded)
                .accessibilityValue(isShowingExcluded ? "Expanded" : "Collapsed")
                .help(isShowingExcluded ? "Hide what is left out" : "Show what is left out")

                if isShowingExcluded {
                    VStack(alignment: .leading, spacing: Metrics.spacingTight) {
                        ForEach(request.contents.excluded.prefix(Self.excludedShown)) { item in
                            HStack(spacing: Metrics.spacingSmall) {
                                Image(systemName: item.reason == .sensitive
                                    ? "key.fill" : "folder.badge.gearshape")
                                    .font(Typo.codeTiny)
                                    .foregroundStyle(Palette.textTertiary)
                                Text(item.path)
                                    .font(Typo.codeTiny)
                                    .foregroundStyle(Palette.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        if request.contents.excluded.count > Self.excludedShown {
                            Text("and \(request.contents.excluded.count - Self.excludedShown) more")
                                .font(Typo.codeTiny)
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .padding(.leading, Metrics.inset)
                }
            }

            if request.contents.isEmpty == false && request.contents.hasGitignore == false {
                Text("There is no .gitignore here, so everything else in the folder goes in.")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Metrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: Metrics.corner))
    }

    @ViewBuilder
    private var gitHub: some View {
        VStack(alignment: .leading, spacing: Metrics.gutter) {
            switch access {
            case .ready:
                ownerAndName
            case .unknown:
                HStack(spacing: Metrics.spacingWide) {
                    ProgressView().controlSize(.small)
                    Text("Checking the GitHub CLI")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            case .notInstalled, .signedOut:
                VStack(alignment: .leading, spacing: Metrics.spacingWide) {
                    Text(access == .notInstalled
                        ? "Creating a repository needs the gh command, and it is not installed."
                        : "Creating a repository needs GitHub access.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(access == .notInstalled ? "Install the GitHub CLI" : "Connect GitHub") {
                        signIn = GitHubSignIn.Request(access: access, directory: request.path, login: app.activeGitHubLogin)
                    }
                    .controlSize(.small)
                }
            }

            if !request.contents.oversizeFiles.isEmpty {
                Callout(
                    text: "GitHub refuses any file over 100 MB, and this folder has "
                        + "\(request.contents.oversizeFiles.count). The push will fail: "
                        + request.contents.oversizeFiles.prefix(3).joined(separator: ", "),
                    symbol: "exclamationmark.triangle.fill",
                    tone: .negative
                )
            }
            if request.contents.oversizeFiles.isEmpty, request.contents.isLargeUpload {
                Callout(
                    text: "That is a lot to upload, and all of it becomes a repository on GitHub. "
                        + "Worth a look before you press.",
                    symbol: "exclamationmark.triangle.fill",
                    tone: .warning
                )
            }
        }
        .padding(Metrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.border, lineWidth: Metrics.outline)
        )
    }

    private var ownerAndName: some View {
        VStack(alignment: .leading, spacing: Metrics.spacingWide) {
            HStack(spacing: Metrics.spacingWide) {
                Picker("Owner", selection: $owner) {
                    ForEach(owners) { candidate in
                        Text(candidate.login).tag(candidate.login)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
                .disabled(owners.isEmpty)
                .onChange(of: owner) { _, _ in scheduleAvailabilityCheck() }

                Text("/")
                    .font(Typo.body)
                    .foregroundStyle(Palette.textTertiary)

                TextField("Repository name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, _ in scheduleAvailabilityCheck() }

                if isLoadingOwners {
                    ProgressView().controlSize(.small)
                }
            }

            if let problem = GitHubRepositoryName.problem(with: trimmedName) {
                Label(problem.sentence, systemImage: "exclamationmark.circle.fill")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.negative)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: Metrics.spacingWide) {
                    Text("Will create \(owner)/\(trimmedName), private.")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.textSecondary)
                    availabilityLine
                }
            }
        }
    }

    @ViewBuilder
    private var availabilityLine: some View {
        switch availability {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.mini)
        case .available:
            Label("available", systemImage: "checkmark.circle.fill")
                .font(Typo.micro)
                .foregroundStyle(Palette.positive)
        case .taken:
            Label("already taken", systemImage: "xmark.circle.fill")
                .font(Typo.micro)
                .foregroundStyle(Palette.negative)
        case .unknown(let why):
            Label(why, systemImage: "questionmark.circle")
                .font(Typo.micro)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private func working(_ step: RepositoryStartStep) -> some View {
        VStack(alignment: .leading, spacing: Metrics.gutter) {
            VStack(alignment: .leading, spacing: Metrics.spacing) {
                ForEach(RepositoryStartStep.steps(for: destination), id: \.self) { candidate in
                    HStack(spacing: Metrics.spacingWide) {
                        switch candidate {
                        case ..<step:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Palette.positive)
                                .accessibilityHidden(true)
                        case step:
                            ProgressView().controlSize(.small)
                                .accessibilityHidden(true)
                        default:
                            Image(systemName: "circle")
                                .foregroundStyle(Palette.textTertiary)
                                .accessibilityHidden(true)
                        }
                        Text(candidate.label)
                            .font(Typo.label)
                            .foregroundStyle(candidate == step ? Palette.textPrimary : Palette.textSecondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(candidate.label)
                    .accessibilityValue(
                        candidate < step ? "Done" : candidate == step ? "Running" : "Not started"
                    )
                }
            }

            if isStepSlow {
                Callout(text: step.slowNotice, symbol: "clock.badge.exclamationmark", tone: .warning)
            }

            if isStopping {
                HStack(spacing: Metrics.spacingWide) {
                    ProgressView().controlSize(.small)
                    Text("Stopping, and putting the folder back")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .task(id: step) {
            isStepSlow = false
            try? await Task.sleep(for: step.patience)
            guard !Task.isCancelled else { return }
            isStepSlow = true
        }
    }

    private func stopped(_ left: RepositoryStartAbandonment) -> some View {
        VStack(alignment: .leading, spacing: Metrics.spacingTight) {
            Text("What the folder is now")
                .font(Typo.captionEmphasis)
                .foregroundStyle(Palette.textPrimary)
            Text(left.state)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Metrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: Metrics.corner))
    }

    private func failed(_ failure: RepositoryStartFailure) -> some View {
        VStack(alignment: .leading, spacing: Metrics.gutter) {
            Callout(text: failure.message, symbol: "exclamationmark.triangle.fill", tone: .negative)

            VStack(alignment: .leading, spacing: Metrics.spacingTight) {
                Text("What the folder is now")
                    .font(Typo.captionEmphasis)
                    .foregroundStyle(Palette.textPrimary)
                Text(failure.state)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Metrics.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: Metrics.corner))
        }
    }

    private func finished(_ outcome: RepositoryStartOutcome) -> some View {
        VStack(alignment: .leading, spacing: Metrics.spacing) {
            LabeledLine(
                label: "Branch",
                value: "\(outcome.branch), \(outcome.committedFiles.formatted()) "
                    + (outcome.committedFiles == 1 ? "file committed" : "files committed")
            )
            if let page = outcome.page {
                LabeledLine(label: "GitHub", value: page)
            }
            if !outcome.excluded.isEmpty {
                LabeledLine(
                    label: "Kept out",
                    value: outcome.excluded.map(\.path).joined(separator: ", ")
                        + ". They are in .gitignore, and still on disk."
                )
            }
            if outcome.commitWasUnsigned {
                Callout(
                    text: "Your git is set to sign commits and the signing failed, so the first "
                        + "commit was made without a signature.",
                    symbol: "signature",
                    tone: .warning
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Metrics.spacingWide) {
            Spacer(minLength: 0)

            switch phase {
            case .choosing:
                Button("Cancel", role: .cancel) { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle) { start() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.controlAccent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart)

            case .working:
                Button("Stop", role: .cancel) { stop() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isStopping)

            case .stopped(let left):
                if left.isUsableProject {
                    Button("Add the project anyway") { onFinish(request.path) }
                }
                Button("Close", role: .cancel) { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Try again") { phase = .choosing }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.controlAccent)
                    .keyboardShortcut(.defaultAction)

            case .failed(let failure):
                if failure.isUsableProject {
                    Button("Add the project anyway") { onFinish(request.path) }
                }
                if failure.step >= .createRemoteRepository {
                    Button("Back") { phase = .choosing }
                }
                Button("Close", role: .cancel) { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Try again") { start(resuming: failure.completed) }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.controlAccent)
                    .keyboardShortcut(.defaultAction)

            case .finished(let outcome):
                if let page = outcome.page {
                    Button("Open on GitHub") { GitHubBridge.open(page) }
                }
                Button("Add project") { onFinish(request.path) }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.controlAccent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, Metrics.inset)
    }

    private var primaryTitle: String {
        choice == .local ? "Create Repository" : "Create and Push"
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var destination: RepositoryDestination {
        choice == .local
            ? .local
            : .gitHub(owner: owner, name: trimmedName, isPrivate: true)
    }

    private var canStart: Bool {
        guard request.identityProblem == nil else { return false }
        guard choice == .gitHub else { return true }
        guard access == .ready, !owner.isEmpty else { return false }
        guard GitHubRepositoryName.isValid(trimmedName) else { return false }
        return !availability.blocksCreation
    }

    private func probeGitHub() async {
        let login = app.activeGitHubLogin
        access = await GitHubAvailability.shared.check(login: login)
        guard access == .ready else { return }
        guard owners.isEmpty else { return }

        isLoadingOwners = true
        defer { isLoadingOwners = false }
        guard let found = try? await GitHub.$login.withValue(login, operation: { try await GitHub.owners() }),
              !found.isEmpty else { return }
        owners = found
        if owner.isEmpty { owner = found[0].login }
        if choice == .gitHub { scheduleAvailabilityCheck() }
    }

    private func scheduleAvailabilityCheck() {
        availabilityCheck?.cancel()

        let candidate = trimmedName
        let account = owner
        guard choice == .gitHub, access == .ready, !account.isEmpty,
              GitHubRepositoryName.isValid(candidate) else {
            availability = .idle
            return
        }

        availability = .checking
        let login = app.activeGitHubLogin
        availabilityCheck = Task {
            try? await Task.sleep(for: Self.availabilityDelay)
            guard !Task.isCancelled else { return }
            let answer = await GitHub.$login.withValue(login) {
                await GitHub.repositoryAvailability(owner: account, name: candidate)
            }
            guard !Task.isCancelled else { return }
            guard candidate == trimmedName, account == owner else { return }
            availability = answer
        }
    }

    private func start(resuming completed: Set<RepositoryStartStep> = []) {
        let target = destination
        isStepSlow = false
        phase = .working(RepositoryStartStep.steps(for: target).first ?? .initialise)

        startTask?.cancel()
        let login = app.activeGitHubLogin
        startTask = Task {
            do {
                let outcome = try await GitHub.$login.withValue(login) {
                    try await RepositoryStarter.start(
                        at: request.path,
                        destination: target,
                        completed: completed
                    ) { step in
                        phase = .working(step)
                    }
                }
                guard !Task.isCancelled else { return }
                if target.isGitHub || !outcome.excluded.isEmpty || outcome.commitWasUnsigned {
                    phase = .finished(outcome)
                } else {
                    onFinish(request.path)
                }
            } catch let failure as RepositoryStartFailure {
                guard !Task.isCancelled else { return }
                phase = .failed(failure)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(RepositoryStartFailure(
                    step: .initialise,
                    message: RepositoryStarter.sentence(from: error),
                    completed: completed,
                    destination: target
                ))
            }
        }
    }

    private func stop() {
        startTask?.cancel()
        startTask = nil
        isStopping = true
        Task {
            let left = await RepositoryStarter.abandon(at: request.path)
            isStopping = false
            isStepSlow = false
            phase = .stopped(left)
        }
    }
}

private struct LabeledLine: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacingTight) {
            Text(label)
                .font(Typo.micro)
                .foregroundStyle(Palette.textTertiary)
            Text(value)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
