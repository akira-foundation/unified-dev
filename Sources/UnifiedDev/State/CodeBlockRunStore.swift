import Foundation
import Observation
import Core

@MainActor
@Observable
final class CodeBlockRunStore {
    static let shared = CodeBlockRunStore()

    private struct Key: Hashable {
        var session: SessionID
        var command: String
    }

    struct PendingRun: Identifiable, Equatable {
        let id = UUID()
        var session: SessionID
        var model: WorkspaceModel
        var question: CodeBlockConfirmation

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    var pending: PendingRun?

    private var runs: [Key: CodeBlockRun] = [:]

    @ObservationIgnored private var tasks: [Key: Task<Void, Never>] = [:]

    private init() {}

    func state(of command: String, in session: SessionID) -> CodeBlockRun? {
        runs[Key(session: session, command: command)]
    }

    func canRun(in session: SessionID, of model: WorkspaceModel) -> Bool {
        model.existingTranscript(for: session)?.acceptsMessages == true
    }

    func run(_ command: String, in session: SessionID, of model: WorkspaceModel) {
        guard runs[Key(session: session, command: command)]?.isRunning != true, canRun(in: session, of: model) else { return }
        let folder = model.workspace.path
        switch CodeBlockLaunch.of(command, in: folder, orchestrates: model.workspace.isOrchestrator) {
        case .runs: start(command, in: session, of: model)
        case let .asks(question): pending = PendingRun(session: session, model: model, question: question)
        }
    }

    func answer(_ request: PendingRun, confirmed: Bool) {
        if pending == request { pending = nil }
        guard let command = request.question.answer(confirmed: confirmed) else { return }
        start(command, in: request.session, of: request.model)
    }

    private func start(_ command: String, in session: SessionID, of model: WorkspaceModel) {
        let key = Key(session: session, command: command)
        guard runs[key]?.isRunning != true, canRun(in: session, of: model) else { return }
        runs[key] = .running
        let folder = model.workspace.path
        tasks[key] = Task { [weak self, weak model] in
            let outcome = await Self.outcome(of: command, in: folder)
            self?.tasks[key] = nil
            self?.runs[key] = outcome
            guard let model, let report = CodeBlockReport.message(command: command, run: outcome),
                  let transcript = model.existingTranscript(for: session) else { return }
            await transcript.submitAppRequest(report)
        }
    }

    func stop(_ command: String, in session: SessionID) {
        tasks[Key(session: session, command: command)]?.cancel()
    }

    nonisolated private static func outcome(of command: String, in folder: String) async -> CodeBlockRun {
        let started = ContinuousClock.now
        do {
            let result = try await Shell.script(
                CodeBlockCommand.script(for: command), cwd: folder, outputLimit: CodeBlockCommand.outputLimit
            )
            guard !Task.isCancelled else { return .stopped }
            return .finished(result, after: started.duration(to: .now))
        } catch is CancellationError {
            return .stopped
        } catch {
            return Task.isCancelled ? .stopped : .failed(error.readableMessage)
        }
    }
}
