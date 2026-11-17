import Foundation
import Observation
import Core

struct StartedProject: Equatable {
    var path: String
    var opensWorkspace: Bool
}

enum StartProjectOutcome: Equatable {
    case cancelled
    case started(StartedProject)
}

@MainActor
@Observable
final class StartProjectModel {
    var stage: StartProjectStage = .landing
    var typed = ""
    var remote = ""
    var selectedCompletion: Int?
    var gitHubLogin: GitHubLogin = .thisMac

    private(set) var facts = NewProjectFacts()
    private(set) var contents: FolderContents?
    private(set) var completions: [String] = []
    private(set) var defaultLocation = ""
    private(set) var projectsThere = 0
    private(set) var searchLocations: [String] = []
    private(set) var isLocationLoaded = false
    private(set) var branch = "main"
    private(set) var identityProblem: String?
    private(set) var repositoryCheck: RepositoryCheck?
    private(set) var isStepSlow = false
    private(set) var recent: [String] = []
    private(set) var outcome: StartProjectOutcome?
    private(set) var fetching: CloneTarget?

    private var acceptedCompletion: String?
    private(set) var isFinishing = false

    private var work: Task<Void, Never>?

    static let inspectionDelay = Duration.milliseconds(150)

    var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    var verdict: ProjectTargetVerdict { ProjectTargetVerdict.of(checked(facts)) }

    private(set) var cloneVerdict: CloneVerdict = .refuse(.empty)

    var hasTyped: Bool {
        !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canStart: Bool {
        guard isLocationLoaded, hasTyped, verdict.isAllowed else { return false }
        return identityProblem == nil || !verdict.makesACommit
    }

    var canClone: Bool { isLocationLoaded && cloneVerdict.isAllowed }

    func readAddress() async {
        let typed = remote
        let location = defaultLocation
        let userHome = home
        let read = await Task.detached {
            CloneVerdict.of(remote: typed, into: location, home: userHome)
        }.value
        guard !Task.isCancelled else { return }
        cloneVerdict = read
    }

    var consequence: ProjectConsequence {
        guard isLocationLoaded else {
            return ProjectConsequence(detail: "Loading project folders…", tone: .waiting)
        }
        guard hasTyped else {
            return .opening(location: defaultLocation, projectsThere: projectsThere, home: home)
        }
        return .of(verdict, path: facts.path, home: home, branch: branch, contents: contents)
    }

    var cloneConsequence: ProjectConsequence {
        guard isLocationLoaded else {
            return ProjectConsequence(detail: "Loading project folders…", tone: .waiting)
        }
        return .cloning(cloneVerdict, home: home)
    }

    var repositoryToCheck: String? {
        guard facts.targetIsRepository, !facts.path.isEmpty else { return nil }
        return facts.path
    }

    var pathToScan: String? {
        guard case .track = verdict, !facts.path.isEmpty else { return nil }
        return facts.path
    }

    func checked(_ inspected: NewProjectFacts) -> NewProjectFacts {
        repositoryCheck?.applied(to: inspected) ?? inspected
    }

    func load(projectPaths: [String], store: Store?) async {
        var preferences = DirectoryPreferences()
        if let store {
            preferences = await DirectoryPreferences.load(from: store)
            recent = await DirectoryPreferences.recentFolders(from: store)
        }
        defaultLocation = preferences.projectLocation(projectPaths: projectPaths, home: home)
        searchLocations = preferences.searchLocations(projectPaths: projectPaths, home: home)
        projectsThere = NewProjectPlan.projectsIn(defaultLocation, projectPaths: projectPaths)
        isLocationLoaded = true
        branch = await NewProjectStarter.plannedBranch()
        identityProblem = await RepositoryStarter.identityProblem(at: home)
    }

    func inspect() async {
        let line = typed
        let location = defaultLocation
        let found = await Task.detached {
            NewProjectStarter.inspect(typed: line, defaultLocation: location)
        }.value
        guard !Task.isCancelled else { return }
        facts = found
    }

    func complete() async {
        completions = []
        selectedCompletion = nil
        guard typed != acceptedCompletion else { return }
        try? await Task.sleep(for: Self.inspectionDelay)
        guard !Task.isCancelled else { return }
        let line = typed
        let locations = searchLocations
        let userHome = home
        let matches = await Task.detached {
            ProjectCompletion.matches(line, locations: locations, home: userHome)
        }.value
        guard !Task.isCancelled else { return }
        completions = matches
    }

    func checkRepository() async {
        guard let path = repositoryToCheck else { return }
        let check = await RepositoryCheck.asking(gitAbout: path)
        guard !Task.isCancelled else { return }
        repositoryCheck = check
    }

    func scan() async {
        contents = nil
        guard let path = pathToScan else { return }
        let found = await Task.detached { RepositoryStarter.scan(path) }.value
        guard !Task.isCancelled else { return }
        contents = found
    }

    func watchForSlowness(_ patience: Duration) async {
        isStepSlow = false
        try? await Task.sleep(for: patience)
        guard !Task.isCancelled else { return }
        isStepSlow = true
    }

    func accept(completion index: Int) {
        guard completions.indices.contains(index) else { return }
        let path = NewProjectPlan.display(completions[index], home: home)
        acceptedCompletion = path
        typed = path
        completions = []
        selectedCompletion = nil
    }

    func moveSelection(by step: Int) -> Bool {
        guard !completions.isEmpty else { return false }
        let last = completions.count - 1
        let next = (selectedCompletion ?? (step > 0 ? -1 : 1)) + step
        selectedCompletion = min(max(next, 0), last)
        return true
    }

    func clearCompletions() -> Bool {
        guard !completions.isEmpty else { return false }
        completions = []
        selectedCompletion = nil
        return true
    }

    func folderToOpenFrom() -> String {
        guard !facts.targetExists else { return facts.path }
        return facts.nearestExistingAncestor.isEmpty
            ? defaultLocation
            : facts.nearestExistingAncestor
    }

    func choose(_ path: String) {
        typed = NewProjectPlan.display(path, home: home)
    }

    func use(alternative: String) {
        typed = NewProjectPlan.display(alternative, home: home)
    }

    func show(_ half: StartProjectHalf) {
        cancelWork()
        stage = half.stage
    }

    func leave() {
        guard let back = stage.leaving else { return }
        cancelWork()
        stage = back
    }

    func finish(_ started: StartedProject?) {
        guard !isFinishing else { return }
        isFinishing = true
        outcome = started.map(StartProjectOutcome.started) ?? .cancelled
    }

    func adopt(_ inspected: NewProjectFacts) {
        facts = inspected
    }

    func adopt(_ check: RepositoryCheck) {
        repositoryCheck = check
    }

    func adopt(fetching target: CloneTarget?) {
        fetching = target
    }

    func cancelWork() {
        work?.cancel()
        work = nil
    }

    func run(_ body: @escaping @MainActor () async -> Void) {
        work?.cancel()
        work = Task { await body() }
    }
}
