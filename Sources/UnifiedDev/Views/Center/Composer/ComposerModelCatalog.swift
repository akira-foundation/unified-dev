import SwiftUI
import Core

struct ComposerModelSection: Identifiable, Equatable {
    var kind: AgentKind
    var options: [ComposerOption]

    var id: String { kind.rawValue }
    var title: String { kind.label }
}

@MainActor
@Observable
final class ComposerModelCatalog {
    static let shared = ComposerModelCatalog()

    private(set) var models: [AgentKind: [AgentModel]] = [:]
    private(set) var isLoading = false
    private(set) var failures: [AgentKind: ModelListFailure] = [:]
    private(set) var reportedClaudeModels: [String: String] = [:]

    private var sources: [AgentKind: AgentModelSource]
    private var accounts: [AgentKind: AgentAccountHome] = [:]
    private var accountsAreKnown = false
    private var store: Store?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = UUID()
    private var observationTask: Task<Void, Never>?

    init(sources: [AgentKind: AgentModelSource] = AgentModelSource.live()) {
        self.sources = sources
    }

    func configure(store: Store) {
        self.store = store
        Task { await ComposerPlanningSupport.shared.refresh(from: store) }
        sources = AgentModelSource.live(store: store, accounts: accounts)
        guard accountsAreKnown else { return }
        followClaudeReports(in: store)
        refresh()
    }

    func adopt(accounts adopted: [AgentKind: AgentAccountHome], store: Store) {
        guard adopted != accounts || !accountsAreKnown else { return }
        accountsAreKnown = true
        accounts = adopted
        self.store = store
        sources = AgentModelSource.live(store: store, accounts: adopted)
        followClaudeReports(in: store)
        refresh()
    }

    private func followClaudeReports(in store: Store) {
        observationTask?.cancel()
        let account = accounts[.claudeCode]
        observationTask = Task { [weak self] in
            var changes = store.changes(of: [.settings]).makeAsyncIterator()
            self?.refreshClaudeAliases()
            repeat {
                self?.adoptClaudeReports(await ClaudeResolvedModel.reported(account: account, in: store))
            } while await changes.next() != nil
        }
    }

    private func refreshClaudeAliases() {
        guard let store else { return }
        let account = accounts[.claudeCode]
        Task { await ClaudeAliasRefresh.shared.refresh(account: account, in: store) }
    }

    private func adoptClaudeReports(_ reported: [String: String]) {
        guard !Task.isCancelled, reported != reportedClaudeModels else { return }
        reportedClaudeModels = reported
    }

    func load() {
        guard accountsAreKnown else { return }
        refreshClaudeAliases()
        guard loadTask == nil else { return }
        let needed = AgentModelSource.kindsAwaitingModels(sources: sources, loaded: models)
        guard !needed.isEmpty else { return }
        isLoading = true
        let generation = loadGeneration
        loadTask = Task { [sources] in
            var collected: [AgentKind: ModelListFailure] = [:]
            for kind in needed {
                guard generation == self.loadGeneration else { return }
                guard let source = sources[kind] else { continue }
                do {
                    let fetched = try await source.models()
                    guard generation == self.loadGeneration else { return }
                    self.models[kind] = fetched
                } catch {
                    collected[kind] = await source.failure(of: kind, because: error)
                }
            }
            guard generation == self.loadGeneration else { return }
            self.failures = collected
            self.isLoading = false
            self.loadTask = nil
        }
    }

    func refresh() {
        loadTask?.cancel()
        loadGeneration = UUID()
        let generation = loadGeneration
        models = [:]
        failures = [:]
        isLoading = true
        loadTask = Task { [sources] in
            for source in sources.values { await source.invalidate() }
            guard generation == self.loadGeneration else { return }
            self.loadTask = nil
            self.isLoading = false
            load()
        }
    }

    func hasGivenUp(on kind: AgentKind) -> Bool {
        ModelListFailure.hasGivenUp(on: kind, among: failures, isLoading: isLoading)
    }

    func sections(includingCurrent current: String, on kind: AgentKind) -> [ComposerModelSection] {
        let owner = backend(ofModel: current, current: kind)
        return AgentKind.allCases.filter(\.canRunWorkspaces).compactMap { backend in
            let options = self.options(for: backend, including: backend == owner ? current : "")
            guard !options.isEmpty else { return nil }
            let tagged = options.map { option in
                var option = option
                option.id = ModelSectionTag.tag(option.id, in: backend, running: kind, models: models)
                return option
            }
            return ComposerModelSection(kind: backend, options: tagged)
        }
    }

    func options(for kind: AgentKind, including current: String = "") -> [ComposerOption] {
        let known = (models[kind] ?? []).filter { !$0.hidden }
        if kind == .claudeCode {
            return ComposerOption.options(
                ClaudeModelCatalog.offered(read: known, including: current, reported: reportedClaudeModels)
            )
        }
        let options = ComposerOption.options(known)
        return current.isEmpty ? options : ComposerOption.adding([current], to: options)
    }

    func choice(_ tag: String, current: AgentKind) -> (kind: AgentKind, model: String) {
        ModelSectionTag.choice(tag, running: current, models: models)
    }

    func backend(ofModel id: String, current: AgentKind) -> AgentKind {
        DefaultBackend.kind(
            ofModel: id,
            running: current,
            models: models
        )
    }

    func efforts(for kind: AgentKind, model: String, offeringAgentDefault: Bool) -> [ComposerOption] {
        let announced = kind.announcesModelEfforts ? models[kind]?.first { $0.id == model } : nil
        let supported = announced?.supportedEfforts
            ?? ComposerOption.efforts.map { AgentModelEffort(id: $0.id, label: $0.label) }
        return ComposerEffort.choices(supported, offeringUnset: offeringAgentDefault).map {
            ComposerOption(id: $0.id, label: $0.label)
        }
    }

    func resolvedEffort(_ wanted: String, for kind: AgentKind, model: String) -> String {
        DefaultBackend.effort(
            wanted,
            on: kind,
            model: model,
            models: models
        )
    }
}
