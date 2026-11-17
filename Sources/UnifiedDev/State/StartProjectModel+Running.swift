import Foundation
import Core

extension StartProjectModel {
    func start() {
        let inspected = NewProjectStarter.inspect(typed: typed, defaultLocation: defaultLocation)
        adopt(inspected)
        let current = checked(inspected)
        let decided = ProjectTargetVerdict.of(current)
        guard decided.isAllowed, !current.path.isEmpty else { return }
        guard identityProblem == nil || !decided.makesACommit else { return }

        if case .add(let root) = decided {
            return adoptExisting(at: root, checking: current.path)
        }

        let target = current.path
        let opensWorkspace = decided.opensAWorkspace
        stage = .creating(.initialise)

        run { [self] in
            do {
                let creation = try await NewProjectStarter.create(at: target) { step in
                    stage = .creating(step)
                }
                guard !Task.isCancelled else { return }
                finish(StartedProject(path: creation.path, opensWorkspace: opensWorkspace))
            } catch let failure as NewProjectFailure {
                guard !Task.isCancelled else { return }
                stage = .after(failure)
            } catch {
                guard !Task.isCancelled else { return }
                stage = .after(NewProjectFailure(
                    title: "Could not start the project",
                    message: RepositoryStarter.sentence(from: error),
                    folderWasCreated: false
                ))
            }
        }
    }

    func clone() {
        guard let target = cloneVerdict.target else { return }
        adopt(fetching: target)
        stage = .fetching

        let login = gitHubLogin
        run { [self] in
            do {
                let cloned = try await GitHub.$login.withValue(login) {
                    try await RepositoryCloner.clone(target.remote, into: target.destination)
                }
                guard !Task.isCancelled else { return }
                finish(StartedProject(path: cloned.path, opensWorkspace: false))
            } catch let failure as CloneFailure {
                guard !Task.isCancelled else { return }
                stage = .after(failure)
            } catch {
                guard !Task.isCancelled else { return }
                stage = .after(CloneFailure(
                    message: RepositoryStarter.sentence(from: error),
                    folderWasCreated: false
                ))
            }
        }
    }

    func trustHostAndClone() {
        guard case .failed(var fault) = stage, let offer = fault.hostOffer else { return }
        do {
            try KnownHosts.trust(offer)
        } catch {
            fault.hostOffer = nil
            fault.message = "Could not add \(offer.host) to the known hosts: \(error.readableMessage)"
            stage = .failed(fault)
            return
        }
        clone()
    }

    func stop() {
        cancelWork()
        let leftBehind = leftovers(folderWasCreated: folderWasCreated)
        run { [self] in
            await leftBehind?.discard()
            finish(nil)
        }
    }

    func discardAndLeave() {
        guard case .failed(let fault) = stage else { return finish(nil) }
        let leftBehind = leftovers(folderWasCreated: fault.folderWasCreated)
        run { [self] in
            await leftBehind?.discard()
            finish(nil)
        }
    }

    func discardIfLeavingMidWork() {
        cancelWork()
        guard !isFinishing, stage.discardsOnLeaving else { return }
        let leftBehind = leftovers(folderWasCreated: folderWasCreated)
        Task { await leftBehind?.discard() }
    }

    private var folderWasCreated: Bool { !facts.targetExists }

    private func leftovers(folderWasCreated made: Bool) -> StartProjectLeftovers? {
        StartProjectLeftovers.of(
            stage,
            namedFolder: facts.path,
            namedFolderWasCreated: made,
            clonedInto: fetching?.destination
        )
    }

    private func adoptExisting(at root: String, checking path: String) {
        run { [self] in
            let check = await RepositoryCheck.asking(gitAbout: path)
            guard !Task.isCancelled, !isFinishing else { return }
            adopt(check)
            guard check.problem == nil else { return }
            finish(StartedProject(path: root, opensWorkspace: false))
        }
    }
}
