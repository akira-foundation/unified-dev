import SwiftUI
import Observation
import Core

struct TranscriptRow: Identifiable, Hashable, Sendable {
    var id: Int64
    var seq: Int
    var kind: MessageKind
    var payload: Data
    var createdAt: Date
    var durationMS: Int?
    var refID: String?

    var resultPayload: Data?
    var isError = false
    var refusal: ToolRefusal?
    var refusalReason = ""
    var parentToolUseID: String?

    var permissionDecision: String?
    var isQuestion = false
    var permissionNote = ""
    var permissionAnswers: [String: String] = [:]

    init(message: Message) {
        id = message.id
        seq = message.seq
        kind = message.kind
        payload = message.payload
        createdAt = message.createdAt
        durationMS = message.durationMS
        refID = message.refID
    }
}

@MainActor
@Observable
final class TranscriptModel {
    var session: Session
    let history = TranscriptHistory()
    let workspace: Workspace?
    let cwd: String
    private unowned let app: AppModel

    var home: TranscriptHome {
        TranscriptHome(workspaceID: workspace?.id, worktree: cwd)
    }

    private var workspaceNow: Workspace? {
        guard let workspace else { return nil }
        return app.existingModel(for: workspace.id)?.workspace ?? workspace
    }

    var orchestrates: Bool { workspaceNow?.isOrchestrator == true }

    private(set) var rows: [TranscriptRow] = []
    private(set) var presentationRevision = 0
    @ObservationIgnored private var foldCache = TranscriptFoldCache()
    @ObservationIgnored private var questionIndex = PinnedQuestionIndex()
    @ObservationIgnored private var freshCalls: Set<String> = []

    func presentationFolds() -> TranscriptFold.Folds {
        let freshCalls = freshCalls
        return foldCache.resolve(rows.lazy.map { row in
            row.foldFact(
                isFresh: row.kind == .toolUse && row.refID.map(freshCalls.contains) == true
            )
        })
    }

    func pinnedQuestion(atOrBefore seq: Int) -> PinnedQuestion? {
        questionIndex.update(session: session.id, rows: rows)
        return questionIndex.latest(atOrBefore: seq)
    }

    var isRunning: Bool { storedIsRunning }
    private var storedIsRunning = false

    var isAwaitingPermission: Bool { storedIsAwaitingPermission }
    private var storedIsAwaitingPermission = false
    private(set) var isLoaded = false
    @ObservationIgnored private var rowsReleased = false
    @ObservationIgnored private var releasedNotes: [Int: String] = [:]
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var lastShown = 0
    @ObservationIgnored private static var showings = 0

    private(set) var contextUsage: ContextWindowUsage?

    private(set) var streamingText = ""
    private(set) var streamingThinking = ""
    @ObservationIgnored private(set) var messageArrivals = MessageArrivals()
    private(set) var streamingToolName: String?
    private(set) var thinkingTokens = 0
    private(set) var statusLabel: String?

    private(set) var retryRun: RetryRun?

    private(set) var recoveredRuns: [Int: RetryRun] = [:]

    private var clearedTasks = ClearedBackgroundTasks()

    private(set) var subagents = SubagentRoster() {
        didSet {
            if let id = workspace?.id { app.noteSubagentsChanged(workspaceID: id) }
            if oldValue.isWorking != subagents.isWorking { app.noteAgentTurnsChanged() }
            clearedTasks.forgetRunning(in: subagents)
            let note = BackgroundWork.note(for: subagents)
            if note != backgroundWork { backgroundWork = note }
        }
    }

    private(set) var backgroundWork: String?

    #if DEBUG
    func probeApply(_ signal: SubagentSignal) {
        subagents.apply(signal)
    }
    #endif

    var draft = ""

    private(set) var pendingDeliveries: [Delivery] = []

    private(set) var sending: Delivery?

    var waitingDeliveries: [Delivery] {
        let messages = Delivery.messages(in: pendingDeliveries)
        guard let sending else { return messages }
        return messages.filter { $0.id != sending.id }
    }

    var hasNothingToShow: Bool {
        !rowsReleased && rows.allSatisfy { AppRequest.isHidden(kind: $0.kind, payload: $0.payload) }
            && sending == nil && Delivery.messages(in: pendingDeliveries).isEmpty
    }

    private var chatStop = ChatStop.notStopped
    private var wasStoppedByHand: Bool {
        get { chatStop.holdsMessages }
        set { chatStop = newValue ? .byOwner : .notStopped }
    }
    private var owesDrainAfterAgentFailure = false
    private var editedDraftHoldsCanvasComments = false
    @ObservationIgnored private var drainState = DeliveryDrainState.idle

    private var steering: Delivery?

    private var hasReportedTurnEnded = false

    @ObservationIgnored private var agentSwitchStage = AgentSwitchStage.idle
    @ObservationIgnored private var isTornDown = false

    private(set) var liveEndRequests = 0

    private(set) var composerFocusRequests = 0

    private(set) var replyQuotes: [ReplyQuote] = []

    @ObservationIgnored private var replyQuoteWrite: Task<Void, Never>?

    @ObservationIgnored private var removedReplyQuotes: Set<ReplyQuoteID> = []

    private(set) var chapters: [TranscriptChapter] = []

    @ObservationIgnored private var chapterWrite: Task<Void, Never>?

    @ObservationIgnored private var chapterEdits = 0

    private(set) var messageRevealRequests = 0

    private(set) var messageRevealSeq: Int?

    func appendSourceContext(_ context: String) {
        draft += (draft.isEmpty ? "" : "\n\n") + "Ask about this code:\n\n" + context + "\n\n"
        focusComposer()
    }

    func reply(with selection: String, from seq: Int? = nil, typed: String = "") {
        guard let quote = ReplyQuote(selection: selection, sourceSeq: seq) else { return }
        replyQuotes.append(quote)
        let sessionID = session.id
        writeReplyQuotes { try await $0.add(quote, sessionID: sessionID) }
        draft = ReplyQuote.draft(draft, adding: typed)
        focusComposer()
    }

    func removeReplyQuote(id: ReplyQuoteID) {
        replyQuotes.removeAll { $0.id == id }
        removedReplyQuotes.insert(id)
        writeReplyQuotes { try await $0.removeReplyQuotes(ids: [id]) }
    }

    private func writeReplyQuotes(_ write: @escaping @Sendable (Store) async throws -> Void) {
        guard let store else { return }
        let previous = replyQuoteWrite
        replyQuoteWrite = Task {
            await previous?.value
            do {
                try await write(store)
            } catch {
                Log.composer.error(
                    "a reply quote could not be saved: \(error.readableMessage, privacy: .public)"
                )
            }
        }
    }

    func isChapter(_ seq: Int) -> Bool {
        chapters.contains { $0.seq == seq }
    }

    func pinChapter(_ row: TranscriptRow) {
        guard let chapter = TranscriptChapter(seq: row.seq, kind: row.kind, payload: row.payload) else { return }
        chapters = TranscriptChapter.ordered(chapters.filter { $0.seq != row.seq } + [chapter])
        chapterEdits += 1
        let sessionID = session.id
        writeChapters { try await $0.pin(chapter, sessionID: sessionID) }
    }

    func unpinChapter(seq: Int) {
        chapters.removeAll { $0.seq == seq }
        chapterEdits += 1
        let sessionID = session.id
        writeChapters { try await $0.unpinChapter(seq: seq, sessionID: sessionID) }
    }

    private func writeChapters(_ write: @escaping @Sendable (Store) async throws -> Void) {
        guard let store else { return }
        let previous = chapterWrite
        chapterWrite = Task {
            await previous?.value
            do {
                try await write(store)
            } catch {
                Log.composer.error("a chapter could not be saved: \(error.readableMessage, privacy: .public)")
            }
        }
    }

    func revealMessage(seq: Int) {
        messageRevealSeq = seq
        messageRevealRequests += 1
    }

    func focusComposer() { composerFocusRequests += 1 }

    private var isReconcilingPresentation = false
    private var isReplayingPastTurn = false
    private var presentationMessageSeq: Int?
    @ObservationIgnored private var probeRelay: StoredMessageRelay?
    private var dispatchingDeliveryID: DeliveryID?
    private var activeInteractionMode: InteractionMode?
    private var runner: (any SessionRunner)?
    @ObservationIgnored private var idleEvictionTask: Task<Void, Never>?

    func codexSubagentTranscript(for id: SubagentID) async -> SubagentTranscript? {
        guard let codex = runner as? CodexRunner else { return nil }
        return await codex.subagentTranscript(for: id)
    }
    private var pumpTask: Task<Void, Never>?
    private var runnerBuild: Task<(any SessionRunner)?, Never>?
    private var runnerFingerprint: AgentRunnerFingerprint?
    private var runnerProfile: ProfileID?
    private var runnerFailure: String?
    private var ownerStops = 0
    private var resumeStopMark: Int?
    private var runnerIsSettled = false

    var quotaHolder: QuotaHolder {
        QuotaHolder(provider: session.agentKind, account: session.accountID)
    }

    var accountScope: AccountScope {
        AccountScope.chat(
            workspace: workspace,
            activeProfile: app.activeProfileID,
            pinnedProfile: isRunning ? runnerProfile : nil
        )
    }
    private var indexByRefID: [String: Int] = [:]
    private let loader = SingleFlight()
    @ObservationIgnored private var highestSeenMessageSeq = -1
    private var turnStartedAt: Date?

    init(session: Session, workspace: Workspace, app: AppModel) {
        self.session = session
        self.workspace = workspace
        self.cwd = workspace.path
        self.app = app
        history.report = { [unowned app] in app.notice = Notice(message: $0, tone: .error) }
    }

    init(askSession session: Session, directory: String, app: AppModel) {
        self.session = session
        self.workspace = nil
        self.cwd = directory
        self.app = app
        history.report = { [unowned app] in app.notice = Notice(message: $0, tone: .error) }
    }

    private var store: Store? { app.store }

    private var historyWorkspaceHeld: Bool {
        workspace.map { HistoryWorkspaceGate.shared.holds($0.id) } ?? false
    }

    private func historyBlocksSending() async -> Bool {
        if historyWorkspaceHeld { return true }
        guard let store, let workspace else { return false }
        do {
            guard let journal = try await store.pendingCheckpointRewind(workspaceID: workspace.id) else { return false }
            HistoryWorkspaceGate.shared.mark(workspace.id, unresolved: true)
            history.blockingSessionID = journal.checkpoint.sessionID
            history.failure = "Resolve the interrupted rewind in its conversation before sending more messages."
            if journal.checkpoint.sessionID == session.id { history.pendingRewind = journal }
            return true
        } catch {
            history.failure = "Could not check the workspace's rewind state: \(error)"
            return true
        }
    }

    func providerTurnPresence(_ turnID: String) async throws -> ConversationTurnPresence {
        guard let runner = await ensureRunner(purpose: .answering), runner.supportsConversationRewind else { throw ConversationRewindError.unsupported }
        return try await runner.turnPresence(turnID)
    }

    func rewindProvider(beforeTurnID: String) async throws {
        guard let runner = await ensureRunner(purpose: .answering), runner.supportsConversationRewind else { throw ConversationRewindError.unsupported }
        try await runner.rewind(beforeTurnID: beforeTurnID)
    }

    func reloadAfterRewind() async {
        guard let store else { return }
        chatStop = chatStop.afterRewind
        sending = nil
        steering = nil
        clearStreaming()
        let draftBefore = draft
        await read(from: store)
        editedDraftHoldsCanvasComments = PendingMessageReturn.holdsCanvasCommentsAfterRewind(
            heldBefore: editedDraftHoldsCanvasComments, draftBefore: draftBefore, restoredDraft: draft
        )
        await refreshSession()
        PromptAttachmentStore.shared.restoreDraftAttachments(draft, sessionID: session.id.rawValue)
        composerFocusRequests += 1
    }

    func load() async {
        guard let store, !isLoaded else {
            if let store, rowsReleased {
                await loader.run { [self] in await restoreRows(from: store) }
                await appendLatestMessages()
                return
            }
            SwitchTrace.mark("transcript.reused", workspace: workspace?.id)
            SwitchTrace.markOnScreen("transcript.reused", workspace: workspace?.id)
            return
        }
        await loader.run { [self] in await read(from: store) }
    }

    private func read(from store: Store) async {
        SwitchTrace.mark("transcript.read.start", workspace: workspace?.id)
        let messages = (try? await store.messages(sessionID: session.id)) ?? []
        SwitchTrace.mark("transcript.read.done", workspace: workspace?.id)
        let built = await builtRows(from: messages, store: store)
        adopt(built)

        let unread = firstUnreadSeq
        Task.detached(priority: .utility) { [rows = built.rows, worktree = cwd] in
            await TranscriptPrime.run(rows: rows, worktree: worktree, unreadSeq: unread)
        }

        contextUsage = ContextWindowUsage.latest(in: built.rows)
        SwitchTrace.mark("transcript.rows.built", workspace: workspace?.id)
        SwitchTrace.markOnScreen("transcript.rows.built", workspace: workspace?.id)

        let draftBeforeReading = draft
        let storedDraft = (try? await store.draft(sessionID: session.id)) ?? ""
        if draft == draftBeforeReading { draft = storedDraft }
        await replyQuoteWrite?.value
        let storedQuotes = (try? await store.replyQuotes(sessionID: session.id)) ?? []
        replyQuotes = ReplyQuote.merging(stored: storedQuotes, into: replyQuotes, removed: removedReplyQuotes)
        await chapterWrite?.value
        let editsBeforeReading = chapterEdits
        let storedChapters = (try? await store.chapters(sessionID: session.id)) ?? []
        if chapterEdits == editsBeforeReading { chapters = storedChapters }
        await refreshQueue()
        await history.load(store: store, sessionID: session.id, workspaceID: workspace?.id)
        if workspace != nil { await history.cleanupRetired(store: store, sessionID: session.id, cwd: cwd) }
        isLoaded = true
    }

    private typealias BuiltRows = (rows: [TranscriptRow], index: [String: Int], highestMessageSeq: Int)

    private func builtRows(from messages: [Message], store: Store) async -> BuiltRows {
        let decisions = (try? await store.permissionAskDecisions(sessionID: session.id)) ?? [:]
        let answers = (try? await store.permissionAskAnswers(sessionID: session.id)) ?? [:]
        let inWorkspace = session.workspaceID != nil
        return await Task.detached(priority: .userInitiated) {
            var rows: [TranscriptRow] = []
            var index: [String: Int] = [:]
            var highestMessageSeq = -1
            for message in messages {
                highestMessageSeq = max(highestMessageSeq, message.seq)
                Self.absorb(
                    DecidedMessage(message),
                    decisions: decisions,
                    answers: answers,
                    inWorkspace: inWorkspace,
                    into: &rows,
                    indexByRefID: &index
                )
            }
            return (rows: rows, index: index, highestMessageSeq: highestMessageSeq)
        }.value
    }

    private func adopt(_ built: BuiltRows) {
        foldCache.reset()
        freshCalls = []
        questionIndex = PinnedQuestionIndex()
        rows = built.rows
        presentationRevision += 1
        indexByRefID = built.index
        highestSeenMessageSeq = built.highestMessageSeq
        rowsReleased = false
        releasedNotes = [:]
    }

    var retention: TranscriptRetention.Chat {
        TranscriptRetention.Chat(
            session: session.id,
            workspace: workspace?.id,
            holdsRows: isLoaded && !rowsReleased && !rows.isEmpty,
            isShown: viewers > 0,
            isBusy: isRunning || isAwaitingPermission || isStreaming || sending != nil
                || !pendingDeliveries.isEmpty || subagents.isWorking || history.isFinalisingTurn,
            lastShown: lastShown
        )
    }

    func beginShowing() {
        viewers += 1
        Self.showings += 1
        lastShown = Self.showings
    }

    func endShowing() {
        viewers = max(0, viewers - 1)
    }

    func releaseRows() {
        guard isLoaded, !rowsReleased else { return }
        releasedNotes = Dictionary(
            rows.filter { !$0.permissionNote.isEmpty }.map { ($0.seq, $0.permissionNote) }
        ) { first, _ in first }
        rows = []
        indexByRefID = [:]
        foldCache.reset()
        freshCalls = []
        questionIndex = PinnedQuestionIndex()
        presentationRevision += 1
        rowsReleased = true
    }

    private func restoreRows(from store: Store) async {
        guard rowsReleased else { return }
        let ceiling = highestSeenMessageSeq
        guard let stored = try? await store.messages(sessionID: session.id) else { return }
        let built = await builtRows(from: stored.filter { $0.seq <= ceiling }, store: store)
        guard rowsReleased else { return }
        var restored = built.rows
        for index in restored.indices {
            if let note = releasedNotes[restored[index].seq] { restored[index].permissionNote = note }
        }
        adopt((rows: restored, index: built.index, highestMessageSeq: max(ceiling, built.highestMessageSeq)))
    }

    nonisolated private static func absorb(
        _ decided: DecidedMessage,
        decisions: [String: String],
        answers: [String: [String: String]] = [:],
        inWorkspace: Bool,
        into rows: inout [TranscriptRow],
        indexByRefID: inout [String: Int]
    ) {
        let message = decided.message
        if message.kind == .toolResult, let refID = message.refID,
           let index = indexByRefID[refID] {
            rows[index].resultPayload = message.payload
            rows[index].isError = decided.result.isError
            rows[index].refusal = decided.result.refusal
            rows[index].refusalReason = decided.result.reason
            if let duration = message.durationMS { rows[index].durationMS = duration }
            return
        }

        var row = TranscriptRow(message: message)
        row.parentToolUseID = decided.parentToolUseID
        row.payload = TranscriptRowPayload.retained(kind: message.kind, payload: message.payload)
        if let ask = decided.ask {
            row.permissionDecision = ask.standing(in: decisions, inWorkspace: inWorkspace)
            row.isQuestion = ask.isQuestion
            row.permissionAnswers = answers[ask.requestID] ?? [:]
        }
        rows.append(row)
        if message.kind == .toolUse, let refID = message.refID {
            indexByRefID[refID] = rows.count - 1
        }
    }

    nonisolated static func rows(from messages: [Message]) -> [TranscriptRow] {
        var built: [TranscriptRow] = []
        var indexByRefID: [String: Int] = [:]
        for message in messages {
            Self.absorb(DecidedMessage(message), decisions: [:], inWorkspace: false, into: &built, indexByRefID: &indexByRefID)
        }
        return built
    }

    private func absorb(_ decided: DecidedMessage, decisions: [String: String] = [:]) {
        let message = decided.message
        messageArrivals.persisted(seq: message.seq, kind: message.kind, sending: sending?.id)
        let changedIndex = message.kind == .toolResult
            ? message.refID.flatMap { indexByRefID[$0] } ?? rows.count : rows.count
        foldCache.invalidate(row: changedIndex)
        Self.absorb(
            decided, decisions: decisions, inWorkspace: session.workspaceID != nil,
            into: &rows, indexByRefID: &indexByRefID
        )
        presentationRevision += 1
        if SendingSlot.retires(sending, onPersisting: message.kind) { sending = nil }
    }

    var stoppedTurnSeq: Int? {
        guard session.state == .cancelled else { return nil }
        guard let index = StoppedTurn.closingRow(in: rows.lazy.map(\.kind)) else { return nil }
        return rows[index].seq
    }

    var lastTurnEndedCleanly: Bool {
        ConversationHandoff.lastTurnEndedCleanly(
            newestFirst: rows.reversed().lazy.map { [id = session.id] row in
                Message(sessionID: id, seq: row.seq, kind: row.kind, payload: row.payload)
            },
            agent: session.agentKind
        )
    }

    var firstUnreadSeq: Int? {
        rows.first { $0.seq > session.lastReadSeq && !AppRequest.isHidden(kind: $0.kind, payload: $0.payload) }?.seq
    }

    func markAllRead() async {
        guard let store, let last = rows.last?.seq, last != session.lastReadSeq else { return }
        session.lastReadSeq = last
        try? await store.updateLastReadSeq(sessionID: session.id, seq: last)
    }

    func refreshSession() async {
        guard let store, let fresh = try? await store.session(id: session.id) else { return }
        session = fresh
        let isStale = turnStartedAt.map { fresh.updatedAt < $0 } ?? false
        if !isStale, fresh.state == .failed || fresh.state == .cancelled {
            setRunning(false)
            statusLabel = nil
        }
    }

    func updatePreferences(
        title: String? = nil,
        model: String? = nil,
        effort: String? = nil,
        permissionMode: PermissionMode? = nil,
        interactionMode: InteractionMode? = nil,
        implementationMode: PermissionMode? = nil,
        agentKind: AgentKind? = nil
    ) async {
        guard let store else { return }
        try? await store.updateSessionPreferences(
            id: session.id,
            title: title,
            model: model,
            effort: effort,
            permissionMode: permissionMode,
            interactionMode: interactionMode,
            implementationMode: implementationMode,
            agentKind: agentKind
        )
        await refreshSession()
    }

    func jumpToLiveEnd() {
        liveEndRequests += 1
    }

    @discardableResult
    func submit(_ text: String, clearingDraft sourceDraft: String? = nil,
                clearingQuotes sentQuotes: [ReplyQuote] = [],
                interactionMode: InteractionMode? = nil, sourcePlan: PlanArtefact? = nil,
                dismissingAsks: Bool = false) async -> Bool {
        guard let body = acceptableBody(of: text), let store else { return false }
        if let dropped = try? await store.dropUnstartedResumes(sessionID: session.id, onlyWaiting: true), dropped > 0 {
            app.notice = Notice(message: InterruptedTurnResume.replacedByMessage)
            await refreshQueue()
        }

        let submittedDraft = SubmittedDraft.matching(current: draft, message: body, source: sourceDraft)
        let draftHeldComments = editedDraftHoldsCanvasComments
        if submittedDraft != nil {
            draft = ""
            editedDraftHoldsCanvasComments = false
        }
        replyQuotes.removeAll(where: sentQuotes.contains)
        removedReplyQuotes.formUnion(sentQuotes.map(\.id))

        let delivery = Delivery(targetSessionID: session.id, body: body, interactionMode: interactionMode ?? session.interactionMode)
        messageArrivals.sent(delivery.id)
        hold(delivery)

        do {
            await replyQuoteWrite?.value
            _ = try await store.enqueueDelivery(
                delivery, clearingDraftMatching: submittedDraft,
                clearingQuotes: sentQuotes.map(\.id), sourcePlan: sourcePlan
            )
        } catch {
            letGo(delivery)
            if sentQuotes.isEmpty {
                draft = PendingMessageReturn.draft(taking: [delivery], into: draft)
            } else {
                removedReplyQuotes.subtract(sentQuotes.map(\.id))
                replyQuotes = sentQuotes + replyQuotes.filter { !sentQuotes.contains($0) }
                if let submittedDraft { draft = ReplyQuote.draft(submittedDraft, adding: draft) }
            }
            editedDraftHoldsCanvasComments = PendingMessageReturn.holdsCanvasCommentsAfterFailedSubmit(
                heldBefore: draftHeldComments, draft: draft
            )
            composerFocusRequests += 1
            await saveDraft()
            Log.composer.error(
                "the message could not be queued: \(error.readableMessage, privacy: .public)"
            )
            app.alert = AppAlert(
                title: "Could not queue the message",
                message: TranscriptStanding.complaint(about: error)
            )
            return false
        }

        if dismissingAsks { await setAsksAside() }
        wasStoppedByHand = false
        await drain()
        return true
    }

    @discardableResult
    func submitAppRequest(_ text: String, keepsPlace: Bool = false) async -> Bool {
        guard let body = acceptableBody(of: text), let store else { return false }

        let delivery = AppRequest.delivery(to: session.id, text: body, interactionMode: session.interactionMode)
        hold(delivery, followsLiveEnd: !keepsPlace)

        do {
            _ = try await store.enqueueDelivery(delivery)
        } catch {
            letGo(delivery)
            Log.composer.error(
                "the app's request could not be queued: \(error.readableMessage, privacy: .public)"
            )
            app.alert = AppAlert(
                title: "Could not queue the request",
                message: TranscriptStanding.complaint(about: error)
            )
            return false
        }

        chatStop = chatStop.afterAppRequest
        await drain()
        return true
    }

    private func acceptableBody(of text: String) -> String? {
        guard !isWorkspaceArchiving else { return nil }
        if usesInteractiveTerminal {
            app.alert = AppAlert(
                title: "This agent runs in a terminal",
                message: "Open its agent tab and enter the prompt in the CLI."
            )
            return nil
        }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    private func hold(_ delivery: Delivery, followsLiveEnd: Bool = true) {
        if queuesNextMessage || (isRunning && delivery.interactionMode != activeInteractionMode) {
            pendingDeliveries.append(delivery)
        } else {
            sending = delivery
        }
        if followsLiveEnd { jumpToLiveEnd() }
    }

    private func letGo(_ delivery: Delivery) {
        if sending?.id == delivery.id { sending = nil }
        pendingDeliveries.removeAll { $0.id == delivery.id }
    }

    private func setAsksAside() async {
        let decision = PermissionDecision.repliedInChat
        for ask in pendingPermissionAsks {
            await answer(requestID: ask.requestID, decision: decision)
            try? await store?.resolvePermissionAsk(id: ask.requestID, decision: decision.storedName)
        }
    }

    var deliveryHold: DeliveryHold {
        let model = workspace.flatMap { app.existingModel(for: $0.id) }
        return DeliveryHold.of(
            isRunningSetup: model?.isRunningSetup ?? false,
            isTurnRunning: isRunning,
            isAwaitingQuestion: isAwaitingPermission
        )
    }

    var queuesNextMessage: Bool {
        if isSavingTurn || historyWorkspaceHeld { return true }
        if isRunning, session.interactionMode != activeInteractionMode { return true }
        return !Delivery.goesImmediately(
            behind: pendingDeliveries, hold: deliveryHold, on: session.agentKind
        )
    }

    var holdSentence: String? {
        if historyWorkspaceHeld { return AgentDeliveryGate.rewindHeld }
        if history.isCapturing || history.isFinalisingTurn { return "Saving this turn's file changes." }
        let messages = Delivery.messages(in: pendingDeliveries)
        if let first = messages.first, first.state == .uncertain, AppRequest.isHidden(first) {
            return AppRequest.unconfirmedSentence
        }
        if messages.first?.state == .uncertain {
            return "Unified Dev could not confirm delivery. Check the conversation before sending again."
        }
        if isRunning, let mode = messages.first?.interactionMode, mode != activeInteractionMode {
            return "Goes when this turn ends."
        }
        return deliveryHold.sentence(on: session.agentKind)
    }

    func drain() async {
        guard !isTornDown, agentSwitchStage == .idle else { return }
        guard !usesInteractiveTerminal else { return }
        guard !isReconcilingPresentation else { return }
        guard !isSavingTurn, !(await historyBlocksSending()) else { return }
        guard !isWorkspaceArchiving, !wasStoppedByHand, store != nil else { return }
        guard drainState.begin() else { return }
        var allowRepeat = true
        defer { finishDrain(allowRepeat: allowRepeat) }
        owesDrainAfterAgentFailure = false
        if !isRunning { endCanvasCommentTurn() }
        await refreshQueue()
        await dropCanvasCommentsThatCannotGo()

        for var next in Delivery.deliverable(
            from: pendingDeliveries, hold: deliveryHold, on: session.agentKind
        ) {
            guard !isWorkspaceArchiving, !wasStoppedByHand,
                  deliveryHold.allowsDelivery(on: session.agentKind) else { return }
            if isRunning, let mode = next.interactionMode, mode != activeInteractionMode { return }
            guard pendingDeliveries.contains(where: { $0.id == next.id }) else { continue }
            if InterruptedTurnResume.shouldDropWaiting(in: [next], markedAt: resumeStopMark, now: ownerStops) {
                _ = try? await store?.dropUnstartedResumes(sessionID: session.id)
                await refreshQueue()
                continue
            }
            if next.isCanvasComment {
                guard CanvasCommentDelivery.mayStart(under: deliveryHold, draftBeingEdited: draftHoldsCanvasComments, stop: chatStop),
                      let current = await currentCanvasComment(next) else { return }
                next = current
            }

            sending = next

            guard await claimForDelivery(next) else {
                allowRepeat = false
                return
            }
            if next.isCanvasComment {
                guard CanvasCommentDelivery.mayStart(under: deliveryHold, draftBeingEdited: draftHoldsCanvasComments, stop: chatStop),
                      liveWorkspaceModel?.canvasCommentDispatch(of: next) != .waitForDocument else {
                    await putBackCanvasComment(next)
                    return
                }
                liveWorkspaceModel?.canvasCommentStarted(next, sessionID: session.id)
            }

            guard await deliver(next) else {
                if next.isCanvasComment { await canvasCommentWasNotSent(next) }
                allowRepeat = false
                return
            }
        }
    }

    @discardableResult
    func queueCanvasComment(_ delivery: Delivery) async -> Bool {
        guard let store, (try? await store.enqueueDelivery(delivery)) != nil else { return false }
        await refreshQueue()
        await drainIfOnlyCanvasCommentsWait()
        return true
    }

    var canvasCommentChat: CanvasCommentChat {
        CanvasCommentChat(
            stoppedByHand: chatStop.holdsCanvasComments,
            heldAfterRewind: chatStop == .byRewind,
            draftBeingEdited: draftHoldsCanvasComments,
            hold: deliveryHold,
            savingTurn: isSavingTurn,
            rewindInterrupted: historyWorkspaceHeld,
            runsInTerminal: usesInteractiveTerminal
        )
    }

    private var isSavingTurn: Bool {
        history.isCapturing || history.isFinalisingTurn || (history.hasActiveTurn && !isRunning)
    }

    private var draftHoldsCanvasComments: Bool {
        editedDraftHoldsCanvasComments && !PendingMessageEdit.draftIsAbandoned(draft)
    }

    private var liveWorkspaceModel: WorkspaceModel? {
        workspace.flatMap { app.existingModel(for: $0.id) }
    }

    @discardableResult
    private func endCanvasCommentTurn() -> Bool {
        liveWorkspaceModel?.canvasTurnEnded(sessionID: session.id) ?? false
    }

    private func dropCanvasCommentsThatCannotGo() async {
        guard let store else { return }
        var dropped = false
        for delivery in pendingDeliveries where delivery.isCanvasComment {
            guard (liveWorkspaceModel?.canvasCommentDispatch(of: delivery) ?? .drop) == .drop else { continue }
            _ = try? await store.cancelDelivery(id: delivery.id)
            liveWorkspaceModel?.canvasCommentNotSent(delivery, sessionID: session.id, stillQueued: false)
            dropped = true
        }
        if dropped { await refreshQueue() }
    }

    private func currentCanvasComment(_ delivery: Delivery) async -> Delivery? {
        guard case .send(let body) = liveWorkspaceModel?.canvasCommentDispatch(of: delivery) else { return nil }
        guard body != delivery.body else { return delivery }
        try? await store?.rewriteQueuedDelivery(id: delivery.id, body: body)
        var current = delivery
        current.body = body
        return current
    }

    private func putBackCanvasComment(_ delivery: Delivery) async {
        try? await store?.restoreDelivery(id: delivery.id)
        if sending?.id == delivery.id { sending = nil }
        await refreshQueue()
    }

    private func canvasCommentWasNotSent(_ delivery: Delivery) async {
        guard let store else { return }
        let stillQueued = (try? await store.delivery(id: delivery.id))?.state == .pending
        if !stillQueued { _ = try? await store.cancelDelivery(id: delivery.id) }
        liveWorkspaceModel?.canvasCommentNotSent(delivery, sessionID: session.id, stillQueued: stillQueued)
        await refreshQueue()
    }

    func drainIfOnlyCanvasCommentsWait() async {
        guard !chatStop.holdsCanvasComments, !draftHoldsCanvasComments else { return }
        await refreshQueue()
        guard let released = chatStop.releasedForCanvasComments(pending: pendingDeliveries) else { return }
        chatStop = released
        await drain()
    }

    private func drainAfterAgentFailure() async {
        guard owesDrainAfterAgentFailure else { return }
        owesDrainAfterAgentFailure = false
        await drainIfOnlyCanvasCommentsWait()
    }

    private func finishDrain(allowRepeat: Bool) {
        let again = drainState.finish(allowRepeat: allowRepeat)
        if again, !wasStoppedByHand, !isWorkspaceArchiving {
            Task { await drain() }
        }
    }

    private func claimForDelivery(_ delivery: Delivery) async -> Bool {
        guard let store else { return false }
        do {
            let claimed = try await store.claimDelivery(id: delivery.id)
            guard claimed else {
                if sending?.id == delivery.id { sending = nil }
                await refreshQueue()
                return false
            }
            await refreshQueue()
            if isWorkspaceArchiving || wasStoppedByHand {
                try await store.restoreDelivery(id: delivery.id)
                if sending?.id == delivery.id { sending = nil }
                await refreshQueue()
                return false
            }
            return true
        } catch {
            if sending?.id == delivery.id { sending = nil }
            app.alert = AppAlert(
                title: "Could not send the message",
                message: TranscriptStanding.complaint(about: error)
            )
            return false
        }
    }

    func canRetry(_ delivery: Delivery) -> Bool {
        Delivery.messages(in: pendingDeliveries).first?.id == delivery.id
            && dispatchingDeliveryID != delivery.id && drainState == .idle
            && deliveryHold.allowsDelivery(on: session.agentKind)
    }

    func retryPending() async {
        guard let candidate = Delivery.messages(in: pendingDeliveries).first, canRetry(candidate) else { return }
        if candidate.state == .uncertain {
            do { try await store?.restoreDelivery(id: candidate.id) } catch { return }
            await refreshQueue()
        }
        wasStoppedByHand = false
        await drain()
    }

    var discarding: Delivery?

    func askToDiscard(_ delivery: Delivery) {
        guard dispatchingDeliveryID != delivery.id, PendingMessageDiscard.canDiscard(delivery) else { return }
        discarding = delivery
    }

    func confirmDiscard(_ delivery: Delivery) async {
        discarding = nil
        guard dispatchingDeliveryID != delivery.id else { return }
        guard let store else { return }
        let recovery = PendingMessageDiscard.recovery(of: delivery, composerDraft: draft)
        let removed = (try? await store.cancelDelivery(id: delivery.id)) ?? false
        await refreshQueue()

        guard removed else {
            app.notice = Notice(message: PendingMessageDiscard.alreadySentSentence)
            return
        }

        if delivery.crewMessage?.event == .relayed {
            await app.noteDeliveryCancelled(delivery.id)
        }

        if case .toComposer(let text) = recovery {
            draft = text
            editedDraftHoldsCanvasComments = recovery.holdsCanvasComments
            await saveDraft()
        }
        await drainIfOnlyCanvasCommentsWait()
    }

    func editPending(_ delivery: Delivery) async {
        guard dispatchingDeliveryID != delivery.id, PendingMessageEdit.canEdit(delivery), let store else { return }
        let removed = (try? await store.cancelDelivery(id: delivery.id)) ?? false
        await refreshQueue()

        guard removed else {
            app.notice = Notice(message: PendingMessageEdit.alreadySentSentence)
            return
        }

        draft = PendingMessageEdit.draft(taking: delivery, into: draft)
        composerFocusRequests += 1
        jumpToLiveEnd()
        editedDraftHoldsCanvasComments = true
        await saveDraft()
    }

    private func returnQueueToComposer() async {
        guard let store else { return }
        _ = try? await store.dropUnstartedResumes(sessionID: session.id)
        await refreshQueue()
        for request in PendingMessageReturn.dropping(from: pendingDeliveries) {
            _ = try? await store.cancelDelivery(id: request.id)
        }
        await refreshQueue()
        let wanted = PendingMessageReturn.returning(from: pendingDeliveries)
        guard !wanted.isEmpty else { return }

        var returned: [Delivery] = []
        for delivery in wanted {
            let left = (try? await store.cancelDelivery(id: delivery.id)) ?? false
            guard left else { continue }
            returned.append(delivery)
        }
        await refreshQueue()
        await takeIntoComposer(returned)
    }

    private func takeIntoComposer(_ returned: [Delivery]) async {
        guard !returned.isEmpty else { return }

        draft = PendingMessageReturn.draft(taking: returned, into: draft)
        composerFocusRequests += 1
        await saveDraft()
    }

    func canSteer(_ delivery: Delivery) -> Bool {
        DeliverySteer.canSteer(delivery, hold: deliveryHold, on: session.agentKind)
    }

    func steer(_ delivery: Delivery) async {
        guard canSteer(delivery) else { return }
        steering = delivery
        cancelTurn()
    }

    private func sendSteered(_ delivery: Delivery) async {
        guard !isWorkspaceArchiving, !wasStoppedByHand, store != nil else { return }
        guard drainState.begin() else { return }
        var allowRepeat = true
        defer { finishDrain(allowRepeat: allowRepeat) }
        guard !isRunning else { return }

        await refreshQueue()
        guard pendingDeliveries.contains(where: { $0.id == delivery.id }) else { return }

        sending = delivery
        guard await claimForDelivery(delivery) else {
            allowRepeat = false
            return
        }
        allowRepeat = await deliver(delivery)
    }

    private func dropDiscardIfDelivered() {
        guard let discarding else { return }
        guard !pendingDeliveries.contains(where: { $0.id == discarding.id }) else { return }
        self.discarding = nil
        app.notice = Notice(message: PendingMessageDiscard.alreadySentSentence)
    }

    func refreshQueue() async {
        guard let store else { return }
        pendingDeliveries = (try? await store.pendingDeliveries(sessionID: session.id)) ?? []
        dropDiscardIfDelivered()
    }

    @discardableResult
    private func deliver(_ delivery: Delivery) async -> Bool {
        guard !isTornDown else {
            try? await store?.releaseDeliveryClaim(id: delivery.id)
            return false
        }
        dispatchingDeliveryID = delivery.id
        defer { if dispatchingDeliveryID == delivery.id { dispatchingDeliveryID = nil } }
        guard let runner = await ensureRunner() else {
            await abandon(delivery, saying: runnerFailure ?? "Unified Dev could not open an agent for this chat.")
            return false
        }
        chatStop = chatStop.afterDelivering(delivery)
        if delivery.isCanvasComment { liveWorkspaceModel?.canvasCommentBegan(delivery, sessionID: session.id) }

        let startsATurn = !isRunning
        if startsATurn {
            activeInteractionMode = delivery.interactionMode ?? session.interactionMode
            turnStartedAt = Date()
            hasReportedTurnEnded = false
            subagents.turnStarted()
            setRunning(true)
            statusLabel = "Starting"
            if let store, workspace != nil { await history.begin(delivery: delivery, store: store, cwd: cwd) }
            guard !wasStoppedByHand else {
                await abandon(delivery, saying: DeliveryAbandonment.stoppedBeforeSending)
                if let store { await history.finish(store: store, cwd: cwd, endSeq: highestSeenMessageSeq) }
                return false
            }
        }

        do {
            try await runner.sendDelivery(delivery)
            if startsATurn, let store { await history.sent(delivery: delivery, store: store) }
            await appendLatestMessages()
            return true
        } catch ProviderIdleError.retired {
            if self.runner === runner {
                pumpTask?.cancel()
                pumpTask = nil
                self.runner = nil
                runnerFingerprint = nil
            }
            return await deliver(delivery)
        } catch {
            if startsATurn {
                if let store { await history.finish(store: store, cwd: cwd, endSeq: highestSeenMessageSeq) }
                setRunning(false)
                statusLabel = nil
            }
            await abandon(delivery, saying: DeliveryAbandonment.complaint(for: error))
            return false
        }
    }

    private func abandon(_ delivery: Delivery, saying complaint: String) async {
        sending = nil

        Log.composer.error(
            "the agent would not start, so the prompt stayed in the queue: \(complaint, privacy: .public)"
        )

        guard let store else {
            app.alert = AppAlert(title: "Could not start the agent", message: complaint)
            return
        }

        try? await store.releaseOrDropClaim(of: delivery)
        await refreshQueue()

        let row = AgentError.notStarted(message: complaint)
        _ = try? await store.appendNext(sessionID: session.id, kind: .error, payload: row.raw)
        await appendLatestMessages()
    }

    func saveDraft() async {
        guard let store else { return }
        try? await store.saveDraft(sessionID: session.id, body: draft)
        guard editedDraftHoldsCanvasComments, PendingMessageEdit.draftIsAbandoned(draft) else { return }
        editedDraftHoldsCanvasComments = false
        await drainIfOnlyCanvasCommentsWait()
    }

    private func noteTheAgentStartedItsOwnTurn() {
        turnStartedAt = Date()
        wasStoppedByHand = false
        hasReportedTurnEnded = false
        subagents.turnStarted()
        setRunning(true)
    }

    private func setRunning(_ value: Bool) {
        if !value { setAwaitingPermission(false) }

        guard storedIsRunning != value else { return }
        storedIsRunning = value
        if workspace == nil { holdProfile(whileRunning: value) }
        app.noteAgentTurnsChanged()
    }

    private func holdProfile(whileRunning isTurnRunning: Bool) {
        guard isTurnRunning else {
            app.bridge?.registry.releaseProfilePin(forSession: session.id)
            return
        }
        app.bridge?.registry.pinProfile(runnerProfile ?? app.activeProfileID, forSession: session.id)
    }

    private func setAwaitingPermission(_ value: Bool) {
        guard storedIsAwaitingPermission != value else { return }
        storedIsAwaitingPermission = value
        app.noteAgentTurnsChanged()
    }

    private func refreshAwaitingPermission() {
        setAwaitingPermission(!pendingPermissionAsks.isEmpty)
    }

    func stop() {
        ownerStops += 1
        steering = nil
        cancelTurn()

        Task { await returnQueueToComposer() }
    }

    var stopsBackgroundTasks: Bool { runner?.stopsBackgroundTasks ?? false }

    func stopBackgroundTask(_ id: SubagentID) {
        guard let runner else { return }
        Task { _ = await runner.stopTask(id) }
    }

    func clearFinishedTasks() {
        clearedTasks.clear(subagents)
    }

    var hasBackgroundTasks: Bool { clearedTasks.hasVisibleTasks(in: subagents) }

    func backgroundTaskList(now: Date = Date()) -> BackgroundTaskList {
        BackgroundTaskList(subagents, cleared: clearedTasks, stopsTasks: stopsBackgroundTasks, now: now)
    }

    private func cancelTurn() {
        liveWorkspaceModel?.canvasTurnStopped(sessionID: session.id)
        wasStoppedByHand = true
        runner?.cancelNow()
        setRunning(false)
        statusLabel = nil
        clearStreaming()
    }

    func terminateNow() {
        ownerStops += 1
        cancelTurn()
        steering = nil
        runner?.terminateNow()
    }

    func teardown() {
        isTornDown = true
        idleEvictionTask?.cancel()
        idleEvictionTask = nil
        terminateNow()
        pumpTask?.cancel()
        pumpTask = nil
    }

    func shutdown() async {
        idleEvictionTask?.cancel()
        idleEvictionTask = nil
        if isLoaded, !draft.isEmpty { await saveDraft() }
        guard let runner else { return }
        terminateNow()

        let deadline = ContinuousClock.now.advanced(by: .seconds(3.5))
        while ContinuousClock.now < deadline {
            let alive = await runner.isProcessAlive
            if !alive { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func readOrchestratorRole(from store: Store) async -> Bool {
        guard let id = workspace?.id else { return false }
        return await store.orchestratesAtLaunch(workspaceID: id)
    }

    private var isWorkspaceArchiving: Bool {
        workspace.map { app.isArchiving($0.id) } ?? false
    }

    var pullRequestAutoFixReading: PullRequestAutoFix.ChatReading {
        PullRequestAutoFix.ChatReading(
            runsInTerminal: !acceptsMessages,
            isBusy: isRunning || sending != nil || !pendingDeliveries.isEmpty || queuesNextMessage,
            isAwaitingAnswer: isAwaitingPermission || !pendingPermissionAsks.isEmpty,
            wasStoppedByOwner: wasStoppedByHand || session.state == .cancelled,
            permissionMode: session.permissionMode,
            interactionMode: session.interactionMode
        )
    }

    var acceptsMessages: Bool {
        !usesInteractiveTerminal && !isWorkspaceArchiving
    }

    private func ensureRunner(purpose: AgentSessionSettlement.Purpose = .sending) async -> (any SessionRunner)? {
        let previous = runnerBuild
        let build = Task { [weak self] () -> (any SessionRunner)? in
            _ = await previous?.value
            guard let self else { return nil }
            return await buildRunner(purpose: purpose)
        }
        runnerBuild = build
        let built = await build.value
        if runnerBuild == build { runnerBuild = nil }
        return built
    }

    private func buildRunner(
        purpose: AgentSessionSettlement.Purpose, isRetry: Bool = false
    ) async -> (any SessionRunner)? {
        runnerFailure = nil
        guard let store else { return nil }
        guard var seat = await readSeat(from: store) else { return nil }
        session = seat.session
        let scope = accountScope
        let resolved: AgentAccountHome?
        do {
            resolved = try await app.account(for: session.agentKind, in: scope)
        } catch {
            runnerFailure = AgentSessionSettlement.resolutionFailure(error)
            return nil
        }
        let account = resolved
        guard !usesInteractiveTerminal else { return nil }
        let orchestrates = await readOrchestratorRole(from: store)
        let gitHub = await store.gitHubLogin(for: scope)
        let usesChrome = await ClaudeChrome.launches(in: store, orchestrates: orchestrates)
        let fingerprint = AgentRunnerFingerprint(
            session: session, account: account, orchestrates: orchestrates, segment: seat.segmentID, gitHub: gitHub,
            usesChrome: usesChrome
        )
        let setup = AgentRunnerSetup.decide(
            gate: AgentDeliveryGate.decide(
                purpose: purpose, isArchiving: isWorkspaceArchiving, isHeld: historyWorkspaceHeld
            ),
            hasRunner: runner != nil,
            preferencesChanged: runnerFingerprint != fingerprint,
            isSettled: runnerIsSettled,
            purpose: purpose,
            settlement: AgentSessionSettlement.decide(
                session: session, account: account, purpose: purpose, lostItsAccount: seat.lostItsAccount
            )
        )
        let plan: AgentRunnerSetup.Plan
        switch setup {
        case .refused(let sentence):
            runnerFailure = sentence
            return nil
        case .ready(let ready):
            plan = ready
        }
        if plan.retiresRunner { retireRunner() }
        guard await apply(plan.settlement, account: account) else { return nil }
        runnerProfile = scope.profileID
        runnerIsSettled = plan.isSettledAfterwards
        if plan.keepsRunner, let runner {
            if pumpTask == nil { startPump(on: runner) }
            return runner
        }
        if case .refuse(let sentence) = AgentDeliveryGate.decide(
            purpose: purpose, isArchiving: isWorkspaceArchiving, isHeld: historyWorkspaceHeld
        ) {
            runnerFailure = sentence
            return nil
        }
        if !plan.settlement.changesNothing {
            guard let settled = await readSeat(from: store) else { return nil }
            guard settled.session.accountID == account?.id else {
                if !isRetry { return await buildRunner(purpose: purpose, isRetry: true) }
                runnerFailure = AgentSessionSettlement.chatMoved
                return nil
            }
            seat = settled
        }
        session = seat.session
        if let notice = plan.settlement.notice(
            on: account, among: app.agentAccounts.standings,
            besides: AgentAccountEnvironment.strippedNotice(
                AgentAccountEnvironment.applied(account, to: Shell.environment()).stripped
            )
        ) {
            app.notice = Notice(message: notice)
        }
        let bridge = workspace.map { app.bridge?.register(session: session, workspace: $0, orchestrates: orchestrates) }
            ?? app.bridge?.register(askSession: session)
        let runner = Self.makeRunner(
            session: session,
            workspacePath: cwd,
            store: store,
            segmentID: seat.segmentID,
            bridge: bridge,
            account: account,
            gitHub: gitHub,
            usesChrome: usesChrome
        )
        self.runner = runner
        runnerFingerprint = AgentRunnerFingerprint(
            session: session, account: account, orchestrates: orchestrates, segment: seat.segmentID, gitHub: gitHub,
            usesChrome: usesChrome
        )
        startIdleEviction()
        startPump(on: runner)
        return runner
    }

    private func apply(_ settlement: AgentSessionSettlement, account: AgentAccountHome?) async -> Bool {
        guard !settlement.changesNothing, let store else { return true }
        do {
            try await AgentSessionRecord.write(
                settlement, session: session.id, account: account,
                standings: app.agentAccounts.standings, in: store
            )
        } catch {
            runnerFailure = AgentSessionSettlement.writeFailure(error.readableMessage)
            return false
        }
        await refreshSession()
        return true
    }

    private func readSeat(from store: Store) async -> RunnerSeat? {
        do {
            if let seat = try await store.runnerSeat(sessionID: session.id) { return seat }
            runnerFailure = AgentSessionSettlement.noSegment
        } catch {
            runnerFailure = AgentSessionSettlement.resolutionFailure(error.readableMessage)
        }
        return nil
    }

    private func retireRunner() {
        runner?.terminateNow()
        detachRunner()
    }

    private func detachRunner() {
        pumpTask?.cancel()
        pumpTask = nil
        runner = nil
        runnerFingerprint = nil
        runnerProfile = nil
        runnerIsSettled = false
    }

    func restartTurn(on target: AgentAccountHome, resume origin: InterruptedTurnResume.Origin) async -> String? {
        await refreshSession()
        let resolution: AgentTurnRestart.Resolution
        do {
            resolution = .resolved(try await app.accounts(in: accountScope)?.home(for: session.agentKind))
        } catch {
            resolution = .failed(error.readableMessage)
        }
        let decision = AgentTurnRestart.decide(AgentTurnRestart.Input(
            isWorkspaceArchiving: isWorkspaceArchiving,
            session: session,
            resolution: resolution,
            target: target,
            isTurnInFlight: isRunning,
            switchRefusal: agentSwitchRefusal,
            usesInteractiveTerminal: usesInteractiveTerminal
        ))
        switch decision {
        case .failure(let refused): return refused.sentence
        case .success(let restart): return await carryOut(restart, target: target, resume: origin)
        }
    }

    private func carryOut(
        _ restart: AgentTurnRestart, target: AgentAccountHome, resume origin: InterruptedTurnResume.Origin
    ) async -> String? {
        for step in restart.steps {
            switch step {
            case .chooseAccount:
                if let complaint = await app.chooseAccount(
                    ChosenAgentAccount(target), in: accountScope
                ) {
                    return complaint
                }
                app.noteSwitched(to: target.id)
            case .switchAgent:
                if let refusal = agentSwitchRefusal { return refusal }
                agentSwitchStage = .writing
                await carryOutAgentSwitch(to: currentControls, account: restart.destination, from: session, resume: origin)
            }
        }
        return nil
    }

    private var currentControls: ComposerControls {
        ComposerControls(
            model: session.model, effort: session.effort, agentKind: session.agentKind,
            permissionMode: session.permissionMode, interactionMode: session.interactionMode
        )
    }

    private enum AgentSwitchStage {
        case idle
        case writing
        case flushing
    }

    var isWritingAgentSwitch: Bool { agentSwitchStage == .writing }

    private var agentSwitchRefusal: String? {
        AgentSwitch.refusal(AgentSwitch.Facts(
            isArchiving: isWorkspaceArchiving,
            isRewindHeld: historyWorkspaceHeld,
            isSavingTurn: history.isCapturing || history.isFinalisingTurn,
            isCatchingUp: isReconcilingPresentation,
            isAlreadySwitching: agentSwitchStage != .idle
        ))
    }

    func switchAgent(to controls: ComposerControls) -> Task<Void, Never>? {
        if let refusal = agentSwitchRefusal {
            app.notice = Notice(message: refusal, tone: .error)
            return nil
        }
        agentSwitchStage = .writing
        let source = session
        session.agentKind = controls.agentKind
        session.model = controls.model
        session.effort = controls.effort
        session.permissionMode = controls.permissionMode
        session.interactionMode = controls.interactionMode
        return Task { await carryOutAgentSwitch(to: controls, account: nil, from: source, resume: .providerSwitch) }
    }

    private func carryOutAgentSwitch(
        to controls: ComposerControls, account given: AgentAccountHome?, from source: Session,
        resume origin: InterruptedTurnResume.Origin
    ) async {
        defer { agentSwitchStage = .idle }
        guard let store else { return }
        let account: AgentAccountHome?
        do {
            if let given {
                account = given
            } else {
                account = try await app.account(for: controls.agentKind, in: accountScope)
            }
        } catch {
            noteAgentSwitchFailed(to: controls.agentKind, error)
            await refreshSession()
            agentSwitchStage = .idle
            await drain()
            return
        }
        let stopsAtStart = ownerStops
        await appendLatestMessages()
        let reading = try? await store.lastTurnReading(
            sessionID: session.id, agent: source.agentKind, newestSeq: highestSeenMessageSeq
        )
        let turn = AgentSwitch.Turn(
            isRunning: isRunning, hasActiveTurn: history.hasActiveTurn, hasOpenAsks: !pendingPermissionAsks.isEmpty
        )
        var exit: Task<(any SessionRunner)?, Never>?
        var outcome = AgentSwitch.Outcome(written: false, queueSettled: true)
        steering = nil
        for step in AgentSwitch.steps(for: turn) {
            guard !isTornDown else { return }
            switch step {
            case .stopTurn:
                cancelTurn()
                abandonRetryRun()
            case .denyOpenAsks:
                await denyOpenAsks(in: store)
            case .retireRunnerAndSwitch:
                let dying = runner
                dying?.terminateNow()
                detachRunner()
                exit = holdRunnerBuilds(untilExitOf: dying)
                outcome = await moveChat(to: controls, from: source, dying: dying, account: account, in: store)
                agentSwitchStage = .flushing
                await appendLatestMessages()
            case .endSubagents:
                subagents.agentExited()
            case .waitForRetiredRunner:
                _ = await exit?.value
                await appendLatestMessages()
                if isRunning, runner == nil {
                    await history.finish(store: store, cwd: cwd, endSeq: highestSeenMessageSeq)
                    setRunning(false)
                    statusLabel = nil
                }
            case .closeTurn:
                await history.finish(store: store, cwd: cwd, endSeq: highestSeenMessageSeq)
                await reportToOrchestrator(CrewMessage.stoppedByOwner(name: session.title))
                await app.noteWorkspaceTurnEnded(.stoppedByOwner, in: session)
            case .drainQueue:
                wasStoppedByHand = false
                await queueResume(reading, origin: origin, outcome: outcome, stopsAtStart: stopsAtStart, in: store)
                agentSwitchStage = .idle
                if outcome.queueSettled { await drain() }
            }
        }
    }

    private func queueResume(
        _ reading: Store.TurnReading?, origin: InterruptedTurnResume.Origin,
        outcome: AgentSwitch.Outcome, stopsAtStart: Int, in store: Store
    ) async {
        guard let reading else { return }
        let queue = (try? await store.pendingDeliveries(sessionID: session.id)) ?? []
        let decision = InterruptedTurnResume.decide(InterruptedTurnResume.Facts(
            origin: origin, cause: reading.cause, hasOwnerTurn: reading.hasOwnerTurn, outcome: outcome,
            stopsAtStart: stopsAtStart, stopsNow: ownerStops, queue: queue
        ))
        switch decision {
        case .skip:
            break
        case .tell(let sentence):
            app.notice = Notice(
                message: InterruptedTurnResume.told(sentence, after: app.notice?.message),
                tone: app.notice?.tone ?? .information
            )
        case .queue(let instruction):
            let resume = InterruptedTurnResume.delivery(for: session.id, instruction: instruction)
            guard (try? await store.enqueueDelivery(resume)) != nil else { return }
            resumeStopMark = stopsAtStart
            await refreshQueue()
        }
    }

    private func moveChat(
        to controls: ComposerControls, from source: Session, dying: (any SessionRunner)?,
        account: AgentAccountHome?, in store: Store
    ) async -> AgentSwitch.Outcome {
        let queue = (try? await store.pendingDeliveries(sessionID: session.id)) ?? []
        let workMode = AgentSwitchWorkMode.decide(
            from: source, to: controls, queue: queue,
            route: await AgentSwitchWorkMode.PlanRoute.read(controls.agentKind, from: store)
        )
        do {
            session = try await AgentSwitch.retireAndSwitch(
                runner: dying, store: store, sessionID: session.id,
                controls: workMode.applied(to: controls), account: account,
                standings: app.agentAccounts.standings
            )
        } catch {
            noteAgentSwitchFailed(to: controls.agentKind, error)
            await refreshSession()
            return AgentSwitch.Outcome(written: false, queueSettled: true)
        }
        contextUsage = nil
        activeInteractionMode = session.interactionMode
        do {
            let returned = try await store.settleQueue(
                rewriting: workMode.rewritten, taking: workMode.returning(from: queue)
            )
            if let sending, returned.contains(where: { $0.id == sending.id }) { self.sending = nil }
            await takeIntoComposer(returned)
            await refreshQueue()
        } catch {
            app.notice = Notice(
                message: AgentSwitch.queueFailure(to: controls.agentKind, detail: error.readableMessage), tone: .error
            )
            return AgentSwitch.Outcome(written: true, queueSettled: false)
        }
        if let notice = workMode.notice { app.notice = Notice(message: notice, tone: workMode.noticeTone) }
        return AgentSwitch.Outcome(written: true, queueSettled: true)
    }

    private func denyOpenAsks(in store: Store) async {
        let asks = pendingPermissionAsks.map(\.requestID)
        for id in asks {
            settle(PermissionResolution(requestID: id, decision: PermissionAskOutcome.stopped))
        }
        await AgentSwitch.denyAsks(asks, in: store)
        refreshAwaitingPermission()
        statusLabel = nil
    }

    private func holdRunnerBuilds(
        untilExitOf dying: (any SessionRunner)?
    ) -> Task<(any SessionRunner)?, Never>? {
        guard let dying else { return nil }
        let previous = runnerBuild
        let hold = Task { () -> (any SessionRunner)? in
            _ = await previous?.value
            _ = await AgentSwitch.waitForExit(of: dying)
            return nil
        }
        runnerBuild = hold
        return hold
    }

    private func noteAgentSwitchFailed(to wanted: AgentKind, _ error: Error) {
        app.notice = Notice(
            message: AgentSwitch.failure(to: wanted, detail: error.readableMessage), tone: .error
        )
    }

    private func noteAccountStanding(after result: AgentResult) {
        guard let account = runnerFingerprint?.account else { return }
        app.observeAccount(
            AgentAccountSignOut.observe(
                result,
                isReplayingPastTurn: isReplayingPastTurn,
                isReconcilingPresentation: isReconcilingPresentation
            ),
            on: account
        )
    }

    var usesInteractiveTerminal: Bool {
        guard let workspaceID = session.workspaceID else { return false }
        CenterTabStore.shared.load(workspaceID: workspaceID)
        return CenterTabStore.shared.terminal(for: session.id, in: workspaceID) != nil
    }

    static func makeRunner(
        session: Session,
        workspacePath: String,
        store: Store,
        segmentID: SessionSegmentID,
        bridge: BridgeHandle? = nil,
        account: AgentAccountHome? = nil,
        gitHub: GitHubLogin = .thisMac,
        usesChrome: Bool = false
    ) -> any SessionRunner {
        switch session.agentKind {
        case .codex:
            return CodexRunner(
                workspacePath: workspacePath,
                session: session,
                store: store,
                segmentID: segmentID,
                bridge: bridge?.attachment,
                account: account,
                gitHub: gitHub
            )
        case .grok:
            return GrokRunner(
                workspacePath: workspacePath,
                session: session,
                store: store,
                segmentID: segmentID,
                bridge: bridge?.attachment,
                account: account,
                gitHub: gitHub
            )
        case .claudeCode, .cursor, .openCode:
            return AgentRunner(
                workspacePath: workspacePath,
                session: session,
                store: store,
                segmentID: segmentID,
                mcpConfigPath: bridge?.mcpConfigPath,
                account: account,
                gitHub: gitHub,
                usesChrome: usesChrome
            )
        }
    }

    private func startIdleEviction() {
        guard idleEvictionTask == nil else { return }
        idleEvictionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard let self else { return }
                await evictIdleProvider()
            }
        }
    }

    private func evictIdleProvider() async {
        guard let store, let current = runner, !isRunning, !isAwaitingPermission,
              sending == nil, pendingDeliveries.isEmpty, !subagents.isAnythingRunning else { return }
        guard let duration = await ProviderIdlePolicy.duration(in: store),
              let waiting = try? await store.pendingDeliveries(sessionID: session.id), waiting.isEmpty,
              !isRunning, sending == nil else { return }
        guard await current.evictIfIdle(for: duration), runner === current else { return }
        pumpTask?.cancel()
        pumpTask = nil
        runner = nil
        runnerFingerprint = nil
    }

    private func startPump(on runner: any SessionRunner) {
        pumpTask?.cancel()
        if let feed = runner.presentationFeed {
            let baseline = feed.snapshot()
            let baselineProcessEnds = feed.processEnds
            let subscriber = UUID()
            let notifications = feed.notifications(id: subscriber, after: baseline.revision)
            pumpTask = Task { [weak self] in
                defer { feed.unsubscribe(subscriber) }
                var cursor = baseline.revision
                var seenProcessEnds = baselineProcessEnds
                var pendingResult: AgentResult?
                if baseline.revision > 0, let recovery = baseline.recovery, let self {
                    await recoverPresentation(recovery, after: baseline.revision)
                    setRunning(session.state.isMidTurn)
                }
                for await _ in notifications {
                    guard let self, !Task.isCancelled else { return }
                    let batch = feed.read(after: cursor)
                    do {
                        if let failure = batch.failure { throw PresentationFailure(message: failure) }
                        let result = try await consumePresentation(batch, from: feed, after: cursor)
                        pendingResult = result ?? pendingResult
                        cursor = batch.revision
                        await feed.acknowledgePage(subscriber: subscriber, through: cursor)
                        let latest = feed.snapshot()
                        guard latest.revision == cursor else { continue }
                        if let event = latest.recovery?.stateEvent, case .error = event { pendingResult = nil }
                        let mayDrain = AgentPresentationReconciliation.permitsAutomaticDrain(
                            isCatchingUp: isReconcilingPresentation, isTurnRunning: isRunning || feed.isTurnRunning
                        )
                        if mayDrain, let result = pendingResult {
                            pendingResult = nil
                            await finishPresentationTurn(result)
                        }
                        if mayDrain { await drainAfterAgentFailure() }
                        let processEnds = feed.processEnds
                        if processEnds != seenProcessEnds {
                            seenProcessEnds = processEnds
                            await closeTurnEndedWithoutResult()
                        }
                    } catch {
                        runner.terminateNow()
                        if self.runner === runner {
                            pumpTask = nil
                            self.runner = nil
                            runnerFingerprint = nil
                        }
                        await handle(.error(AgentError(message: error.localizedDescription)))
                        return
                    }
                }
            }
            return
        }
        pumpTask = Task { [weak self] in
            for await event in runner.events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func closeTurnEndedWithoutResult() async {
        if !isRunning { endCanvasCommentTurn() }
        guard history.hasActiveTurn, !isRunning, let store else {
            if !isRunning {
                owesDrainAfterAgentFailure = true
                await drainAfterAgentFailure()
            }
            return
        }
        await appendLatestMessages()
        await history.finish(store: store, cwd: cwd, endSeq: highestSeenMessageSeq)
        guard let steered = steering else {
            if !wasStoppedByHand { await drain() }
            return
        }
        steering = nil
        wasStoppedByHand = false
        await sendSteered(steered)
    }

    private struct PresentationFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func consumePresentation(
        _ batch: AgentPresentationBatch, from feed: AgentPresentationFeed, after cursor: UInt64
    ) async throws -> AgentResult? {
        isReconcilingPresentation = true
        defer {
            isReconcilingPresentation = false
            isReplayingPastTurn = false
            presentationMessageSeq = nil
        }
        var result: AgentResult?
        if let recovery = batch.recovery {
            var lifecycleCursor = cursor
            while true {
                let page = try await feed.lifecyclePage(after: lifecycleCursor, through: batch.revision)
                guard !page.isEmpty else { break }
                for entry in page {
                    isReplayingPastTurn = feed.hasLaterTurn(than: entry.revision)
                    presentationMessageSeq = entry.messageSeq
                    await handle(entry.event)
                    if case .result(let terminal) = entry.event { result = terminal }
                    lifecycleCursor = entry.revision
                }
            }
            await recoverPresentation(recovery, after: batch.revision)
        } else {
            for index in batch.events.indices {
                isReplayingPastTurn = feed.hasLaterTurn(than: batch.eventRevisions[index])
                presentationMessageSeq = batch.messageSequences[index]
                let event = batch.events[index]
                await handle(event)
                if case .result(let terminal) = event { result = terminal }
            }
        }
        return result
    }

    private func continueAfterTurn() async {
        if let steered = steering {
            steering = nil
            wasStoppedByHand = false
            await sendSteered(steered)
            return
        }
        guard !wasStoppedByHand else { return }
        await drain()
    }

    private func finishPresentationTurn(_ result: AgentResult) async {
        if !isRunning { endCanvasCommentTurn() }
        await continueAfterTurn()
        if !isRunning {
            await reportToOrchestrator(CrewMessage.stopped(name: session.title, lastMessage: result.summary))
            await app.noteWorkspaceTurnEnded(.ofResult(result, stoppedByOwner: wasStoppedByHand), in: session)
        }
    }

    private func recoverPresentation(_ recovery: AgentPresentationRecovery, after cursor: UInt64) async {
        await appendLatestMessages()
        await refreshSession()
        if let store {
            let decisions = (try? await store.permissionAskDecisions(sessionID: session.id)) ?? [:]
            let answers = (try? await store.permissionAskAnswers(sessionID: session.id)) ?? [:]
            for (id, decision) in decisions {
                settle(PermissionResolution(
                    requestID: id, decision: decision, answers: answers[id] ?? [:]
                ))
            }
        }
        refreshAwaitingPermission()
        subagents = recovery.subagents
        if recovery.stateRevision > cursor, let event = recovery.stateEvent {
            await handle(event)
        }
        clearStreaming()
        streamingText = recovery.text
        streamingThinking = recovery.thinking
        streamingToolName = recovery.toolName
        thinkingTokens = recovery.thinkingTokens
        if let status = recovery.status { await handle(.status(status)) }
        if let retry = recovery.retry { absorb(retry) }
        if let quota = recovery.quota {
            await app.recordQuotas(AgentQuotaAdapters.quotas(fromRateLimitEvent: quota), heldBy: quotaHolder)
        }
        if isAwaitingPermission { statusLabel = "Waiting on you" }
    }

    func acceptForProbe(_ event: AgentEvent) async {
        await handle(event)
    }

    func acceptForProbe(_ event: AgentEvent, messageSeq: Int, relayedBy relay: StoredMessageRelay? = nil) async {
        presentationMessageSeq = messageSeq
        probeRelay = relay
        await handle(event)
        probeRelay = nil
        presentationMessageSeq = nil
    }

    private func handle(_ event: AgentEvent) async {
        switch event {
        case .initialized:
            if !isRunning { noteTheAgentStartedItsOwnTurn() }
            await refreshSession()
            statusLabel = "Working"

        case .status(let label):
            statusLabel = label.lowercased() == "requesting"
                ? "Waiting for model"
                : label.capitalizedFirst

        case .retrying(let retry):
            absorb(retry)

        case .thinkingTokens(let total):
            thinkingTokens = total

        case .streamDelta(let delta):
            switch delta {
            case .text(let chunk): buffer.text += chunk
            case .thinking(let chunk): buffer.thinking += chunk
            case .toolName(let name): streamingToolName = name
            case .toolInput: break
            case .blockFinished: break
            }
            scheduleStreamFlush()

        case .assistantText, .thinking, .toolUse, .toolResult:
            settleRetryRun()
            let runningTool = streamingToolName
            let callsBefore = freshCalls
            await appendLatestMessages(announced: presentationMessageSeq)
            clearStreaming()
            if case .toolUse = event, !freshCalls.isSubset(of: callsBefore) {
                streamingToolName = runningTool
            }

        case .error(let failure):
            history.isFinalisingTurn = true
            steering = nil
            abandonRetryRun()
            clearStreaming()
            await appendLatestMessages(announced: presentationMessageSeq)
            if let store { await history.finish(store: store, cwd: cwd, endSeq: presentationMessageSeq ?? highestSeenMessageSeq, captureFiles: !isReplayingPastTurn) }
            setRunning(false)
            statusLabel = nil
            subagents.agentExited()
            if !isReplayingPastTurn { endCanvasCommentTurn() }
            await refreshSession()
            app.alert = AppAlert(
                title: "The agent stopped in \(workspaceNow?.name ?? AskConversation.title)",
                message: failure.message.isEmpty ? "It exited without finishing the turn." : failure.message
            )
            if let workspaceNow {
                NotificationService.shared.agentFailed(
                    workspace: workspaceNow, sessionID: session.id, message: failure.message
                )
            }
            await reportToOrchestrator(
                CrewMessage.failed(name: session.title, reason: failure.message)
            )
            if !isReplayingPastTurn {
                await app.noteWorkspaceTurnEnded(
                    .failed(reason: failure.message), in: session, wasStoppedByHand: wasStoppedByHand
                )
            }
            if let workspaceNow {
                await app.archiveIfRequested(
                    workspaceNow, endedIn: session.id, wasStopped: wasStoppedByHand
                )
            }

            history.isFinalisingTurn = false
            if !isReplayingPastTurn {
                owesDrainAfterAgentFailure = true
                if !isReconcilingPresentation { await drainAfterAgentFailure() }
            }

        case .result(let result):
            history.isFinalisingTurn = true
            if result.succeeded { settleRetryRun() } else { abandonRetryRun() }
            clearStreaming()
            await appendLatestMessages(announced: presentationMessageSeq)
            fileRecoveredRun()
            if let store { await history.finish(store: store, cwd: cwd, endSeq: presentationMessageSeq ?? highestSeenMessageSeq, captureFiles: !isReplayingPastTurn) }
            setRunning(false)
            statusLabel = nil
            if wasStoppedByHand { subagents.agentExited() }
            await refreshSession()
            noteAccountStanding(after: result)
            await notifyFinished(result: result)
            history.isFinalisingTurn = false
            if !isReconcilingPresentation { endCanvasCommentTurn() }
            if !isReconcilingPresentation { await continueAfterTurn() }
            if !isReconcilingPresentation, !isRunning {
                await reportToOrchestrator(
                    CrewMessage.stopped(name: session.title, lastMessage: result.summary)
                )
                await app.noteWorkspaceTurnEnded(.ofResult(result, stoppedByOwner: wasStoppedByHand), in: session)
            }

        case .permissionAsk:
            clearStreaming()
            await appendLatestMessages(announced: presentationMessageSeq)
            statusLabel = "Waiting on you"
            refreshAwaitingPermission()
            await refreshSession()
            if let workspaceNow {
                NotificationService.shared.agentNeedsPermission(workspace: workspaceNow, sessionID: session.id)
            }
            if !isReconcilingPresentation, !isReplayingPastTurn, let ask = pendingPermissionAsks.last {
                await app.noteWorkspaceTurnEnded(.ofAsk(ask), in: session)
            }

        case .permissionDecided(let resolution):
            settle(resolution)
            refreshAwaitingPermission()
            if !isAwaitingPermission {
                statusLabel = isRunning ? "Working" : nil
            }
            await refreshSession()

        case .rateLimit(let raw):
            await app.recordQuotas(AgentQuotaAdapters.quotas(fromRateLimitEvent: raw), heldBy: quotaHolder)
            if let workspaceNow {
                NotificationService.shared.rateLimitReported(raw, workspace: workspaceNow, sessionID: session.id)
            }

        case .subagent(let signal):
            subagents.apply(signal)
            if case .reported = signal, !isRunning { await appendLatestMessages(announced: presentationMessageSeq) }

        case .hook, .unknown:
            break
        }
    }

    private func absorb(_ retry: AgentRetry) {
        if retryRun != nil {
            retryRun?.absorb(retry)
        } else {
            retryRun = RetryRun(retry)
        }
    }

    private func settleRetryRun() {
        guard let run = retryRun else { return }
        if settledRun == nil { settledRun = run }
        retryRun = nil
    }

    private func fileRecoveredRun() {
        guard let run = settledRun, let seq = rows.last?.seq else { return }
        recoveredRuns[seq] = run
        settledRun = nil
    }

    private var settledRun: RetryRun?

    private func abandonRetryRun() {
        retryRun = nil
        settledRun = nil
    }

    var projectName: String? {
        guard let workspace else { return nil }
        return app.repo(for: workspace)?.name ?? workspaceNow?.name
    }

    var pendingPermissionAsks: [PermissionAsk] {
        rows.compactMap { row in
            guard row.kind == .permissionAsk, row.permissionDecision == nil else { return nil }
            return PermissionAsk.decode(payload: row.payload)
        }
    }

    func answer(requestID: String, decision: PermissionDecision) async {
        if case .approvePlan = decision {
            await runner?.answer(requestID: requestID, decision: decision)
            return
        }
        settle(PermissionResolution(
            requestID: requestID, decision: decision.storedName, answers: decision.answers
        ))
        refreshAwaitingPermission()
        await runner?.answer(requestID: requestID, decision: decision)
    }

    private func settle(_ resolution: PermissionResolution) {
        guard let index = rows.firstIndex(where: {
            $0.kind == .permissionAsk
                && PermissionAsk.decode(payload: $0.payload)?.requestID == resolution.requestID
        }) else { return }

        foldCache.invalidate(row: index)
        rows[index].permissionDecision = resolution.decision
        if !resolution.note.isEmpty { rows[index].permissionNote = resolution.note }
        if !resolution.answers.isEmpty { rows[index].permissionAnswers = resolution.answers }
        presentationRevision += 1
    }

    private func appendLatestMessages(announced: Int? = nil) async {
        guard let store else { return }
        await loader.wait()
        let fresh = await latestDecided(from: store, announced: announced)
        guard !fresh.isEmpty else { return }
        if rowsReleased { await loader.run { [self] in await restoreRows(from: store) } }
        guard !rowsReleased else { return }
        let appendedFrom = rows.count
        var calls: [String] = []
        for decided in fresh where decided.message.seq > highestSeenMessageSeq {
            let message = decided.message
            highestSeenMessageSeq = max(highestSeenMessageSeq, message.seq)
            if message.kind == .toolUse, let id = message.refID { calls.append(id) }
            absorb(decided)
        }
        let stopsOnAQuestion = fresh.contains { $0.message.kind == .permissionAsk }
        if stopsOnAQuestion { endFreshCalls(Array(freshCalls)) }
        if !stopsOnAQuestion, !calls.isEmpty { beginFreshCalls(calls) }
        noteContextWindow(in: rows[min(appendedFrom, rows.count)...])
    }

    private func latestDecided(from store: Store, announced: Int?) async -> [DecidedMessage] {
        let relayed = announced.flatMap {
            (probeRelay ?? runner?.storedMessages)?.take(after: highestSeenMessageSeq, through: $0)
        }
        if let relayed { return await DecidedMessage.deciding(relayed) }
        let fresh = (try? await store.messages(sessionID: session.id, afterSeq: highestSeenMessageSeq)) ?? []
        return await DecidedMessage.deciding(fresh)
    }

    private func beginFreshCalls(_ calls: [String]) {
        freshCalls.formUnion(calls)
        Task { [weak self] in
            try? await Task.sleep(for: TranscriptFold.freshCall)
            self?.endFreshCalls(calls)
        }
    }

    private func endFreshCalls(_ calls: [String]) {
        var revealed = false
        for id in calls where freshCalls.remove(id) != nil {
            guard let index = indexByRefID[id], rows.indices.contains(index),
                  rows[index].resultPayload == nil else { continue }
            foldCache.invalidate(row: index)
            revealed = true
        }
        if revealed { presentationRevision += 1 }
    }

    private func noteContextWindow(in appended: ArraySlice<TranscriptRow>) {
        let usage = ContextWindowUsage.updated(contextUsage, with: appended)
        if usage != contextUsage { contextUsage = usage }
    }

    @ObservationIgnored private var buffer = (text: "", thinking: "")
    private var streamFlush: Task<Void, Never>?

    private static let streamFlushInterval = Duration.milliseconds(50)

    private func scheduleStreamFlush() {
        guard streamFlush == nil else { return }
        streamFlush = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.streamFlushInterval)
            guard let self else { return }
            streamFlush = nil
            flushStream()
        }
    }

    private func flushStream() {
        if !buffer.text.isEmpty {
            if streamingText.isEmpty { messageArrivals.beganStream(.assistantText) }
            streamingText += buffer.text
            buffer.text = ""
        }
        if !buffer.thinking.isEmpty {
            if streamingThinking.isEmpty { messageArrivals.beganStream(.thinking) }
            streamingThinking += buffer.thinking
            buffer.thinking = ""
        }
    }

    private func clearStreaming() {
        streamFlush?.cancel()
        streamFlush = nil
        buffer = ("", "")
        streamingText = ""
        streamingThinking = ""
        streamingToolName = nil
    }

    var isStreaming: Bool {
        !streamingText.isEmpty || !streamingThinking.isEmpty || streamingToolName != nil
    }

    private func reportToOrchestrator(_ message: CrewMessage) async {
        guard let parentID = session.parentSessionID, let store, let workspace else { return }
        guard !hasReportedTurnEnded else { return }
        hasReportedTurnEnded = true

        guard let parent = try? await store.session(id: parentID),
              parent.archivedAt == nil else { return }

        _ = try? await store.enqueueDelivery(
            Delivery(
                targetSessionID: parentID,
                sourceWorkspaceID: workspace.id,
                kind: .report,
                crew: message
            )
        )

        guard let model = app.existingModel(for: workspace.id) else { return }
        let transcript = model.transcript(for: parent)
        await transcript.refreshQueue()
        await transcript.drain()
    }

    private func notifyFinished(result: AgentResult) async {
        guard let store else { return }
        guard let workspace, let workspaceNow else { return }
        try? await store.touch(
            workspaceID: workspace.id, unread: app.selection.workspaceID != workspace.id
        )

        let model = app.model(for: workspaceNow)
        await model.onTurnFinished()

        NotificationService.shared.turnFinished(
            workspace: workspaceNow,
            sessionID: session.id,
            result: result,
            wasCancelled: session.state == .cancelled,
            hookRefusedCalls: rows.hookRefusedCalls
        )

        await app.archiveIfRequested(
            workspaceNow, endedIn: session.id, wasStopped: wasStoppedByHand
        )
    }
}
