import AppKit
import Core
import SwiftUI

struct TranscriptListView: View {
    @Environment(\.composerRoom) private var composerRoom

    let transcript: TranscriptModel
    var isRunningSetup: Bool = false
    var emptyState: TranscriptEmptyState?
    let memory: TranscriptPaneMemory?
    let onScrolledUpChange: (@MainActor @Sendable (Bool) -> Void)?

    init(
        transcript: TranscriptModel,
        isRunningSetup: Bool = false,
        emptyState: TranscriptEmptyState? = nil,
        memory: TranscriptPaneMemory? = nil,
        onScrolledUpChange: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        self.transcript = transcript
        self.isRunningSetup = isRunningSetup
        self.emptyState = emptyState
        self.memory = memory
        self.onScrolledUpChange = onScrolledUpChange
        let remembered = memory?.remembered(session: transcript.session.id)
        _expanded = State(initialValue: remembered?.expanded ?? [])
        _unfolded = State(initialValue: remembered?.unfolded ?? [])
        _liveEndRequest = State(initialValue: TranscriptLiveEndRequest(
            handled: remembered?.liveEndRequest ?? 0
        ))
        let rows = transcript.rows
        _drawn = State(initialValue: Drawn(
            session: transcript.session.id,
            window: TranscriptResume.window(
                remembered,
                tailStart: TranscriptTail.start(in: rows.lazy.map(\.kind)),
                seqs: rows.lazy.map(\.seq)
            )
        ))
    }

    @State private var topInset: CGFloat?
    @State private var expanded: Set<Int> = []
    @State private var isSetupExpanded = false
    @State private var unfolded: Set<Int> = []
    @State private var folds = TranscriptFold.Folds.none
    @State private var suggestions = TranscriptSuggestions()
    @State private var foldSession: SessionID?
    @State private var foldRevision = -1
    @State private var geometry = TranscriptGeometry()
    @State private var bubbleWidth = TranscriptBubbleWidth()
    @State private var hoverHost = TranscriptHoverHost()
    @State private var didPosition = false
    @State private var placeReady: SessionID?
    @State private var showsSetup = false
    @State private var isGrowing = GeometryBox(false)
    @State private var isLiveScrolling = GeometryBox(false)
    @State private var isVisible = GeometryBox(false)
    @State private var resumed: SessionID?
    @State private var opening: Opening?
    @State private var writingTo: WriteTarget?
    @State private var contentOffset = GeometryBox(0.0)
    @State private var reachToEnd = GeometryBox(0.0)
    @State private var topPlace = GeometryBox<(seq: Int, delta: CGFloat)?>(nil)
    @State private var pinnedQuestion: PinnedQuestion?
    @State private var atLiveEnd = GeometryBox(false)
    @State private var seen = GeometryBox<(session: SessionID, state: TranscriptPaneState)?>(nil)

    @State private var arrivals = TranscriptArrivals()

    @State private var arrivalSession: SessionID?

    @State private var controller = TranscriptTableController()
    @State private var scroller = TranscriptLiveEndScroller()
    @State private var liveEndRequest = TranscriptLiveEndRequest()
    @State private var follower = TranscriptLiveEndFollower()
    @State private var selection = TranscriptSelectionReader()

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.fontScale) private var fontScale
    @Environment(\.chatFont) private var chatFont
    @Environment(\.chatLineHeight) private var chatLineHeight

    private struct Drawn: Equatable {
        var session: SessionID
        var window: TranscriptWindow
    }

    private struct SuggestionsToRead: Equatable {
        var session: SessionID
        var revision: Int
    }

    @State private var drawn: Drawn

    private struct WriteTarget {
        var memory: TranscriptPaneMemory
        var session: SessionID
    }

    private enum Opening: Equatable {
        case liveEnd
        case row(Int, UnitPoint)
        case rowOffset(Int, Double)
        case offset(Double)

        var seq: Int? {
            switch self {
            case .row(let seq, _), .rowOffset(let seq, _): seq
            case .liveEnd, .offset: nil
            }
        }
    }

    nonisolated static let bubbleShare: CGFloat = 0.7
    nonisolated static let bubbleFloor: CGFloat = 240

    private var visibleRows: ArraySlice<TranscriptRow> {
        let window = drawnWindow
        return transcript.rows[window.start..<window.end]
    }

    private var drawnWindow: TranscriptWindow {
        let rows = transcript.rows
        guard drawn.session == transcript.session.id else {
            return TranscriptWindow.opening(
                rowCount: rows.count,
                tailStart: TranscriptTail.start(in: rows.lazy.map(\.kind)),
                mustReach: mustReachIndex
            )
        }
        let held = drawn.window.clamped(rowCount: rows.count)
        guard let mustReach = mustReachIndex, mustReach < held.start || mustReach >= held.end else {
            return held
        }
        return TranscriptWindow.opening(
            rowCount: rows.count, tailStart: held.start, mustReach: mustReach
        )
    }

    private var mustReachIndex: Int? {
        let target = app.pendingTranscriptTarget.flatMap {
            $0.sessionID == transcript.session.id ? $0.seq : nil
        }
        return TranscriptResume.mustReach(
            target: target,
            remembered: memory?.remembered(session: transcript.session.id),
            firstUnread: transcript.firstUnreadSeq
        ).flatMap {
            TranscriptWindow.index(ofSeqAtOrAfter: $0, in: transcript.rows.lazy.map(\.seq))
        }
    }

    private var revealedSeqs: Set<Int> {
        var out = expanded
        if let seq = opening?.seq { out.insert(seq) }
        if let target = app.pendingTranscriptTarget, target.sessionID == transcript.session.id {
            out.insert(target.seq)
        }
        if let unread = transcript.firstUnreadSeq { out.insert(unread) }
        return out
    }

    private func foldsForThisPass(drawn: Range<Int>) -> TranscriptFold.Folds {
        guard foldSession == transcript.session.id else { return transcript.presentationFolds() }
        guard foldRevision != transcript.presentationRevision else { return folds }
        let fresh = transcript.presentationFolds()
        return TranscriptFold.mayAdopt(fresh, over: folds, drawn: drawn) ? fresh : folds
    }

    private var linkActions: TranscriptLinkActions {
        TranscriptLink.actions(
            for: transcript.workspace.flatMap { app.existingModel(for: $0.id) }, pane: memory?.pane,
            session: transcript.session.id
        )
    }

    private var showsPlaceholder: Bool {
        transcript.isLoaded
            && !transcript.isRunning
            && !showsSetup
            && transcript.hasNothingToShow
            && !transcript.isStreaming
    }

    private var rowEnvironment: TranscriptRowEnvironment {
        TranscriptRowEnvironment(
            app: app,
            hoverHost: hoverHost,
            bubbleWidth: bubbleWidth,
            linkActions: linkActions,
            fontScale: fontScale,
            chatFont: chatFont,
            lineHeight: chatLineHeight,
            reduceMotion: reduceMotion
        )
    }

    private var entries: [TranscriptTableEntry] {
        let home = transcript.home
        let projectName = transcript.projectName
        let rows = transcript.rows
        let permissionMode = transcript.session.permissionMode
        let agentKind = transcript.session.agentKind
        let orchestrates = transcript.orchestrates
        let recoveredRuns = transcript.recoveredRuns
        let stoppedTurnSeq = transcript.stoppedTurnSeq
        let backgroundWork = transcript.isRunning ? nil : transcript.backgroundWork
        let paneHeight = geometry.paneHeight
        let arrivals = self.arrivals
        let unfolded = self.unfolded
        let revealed = revealedSeqs
        let sessionID = transcript.session.id
        let suggestions = self.suggestions
        let chatIsSubagent = transcript.session.parentSessionID != nil
        let drawnRows = visibleRows
        let drawnRange = drawnRows.startIndex..<drawnRows.endIndex
        let folds = foldsForThisPass(drawn: drawnRange)
        let lastVisibleSeq = drawnRows.last(where: { !TranscriptNoise.isHidden($0) })?.seq
        var foldSeq: Int?
        var hiddenIndices: Set<Int> = []

        let runActions: SubagentRunActions? = home.workspaceID.map { workspaceID in
            SubagentRunActions(
                isLive: { [transcript] in transcript.subagents.subagent(forToolUseID: $0) != nil },
                open: { [app, transcript] toolUseID, hasRecordedRows, isSettled in
                    let target = SubagentRunLink.target(
                        toolUseID: toolUseID,
                        hasRecordedRows: hasRecordedRows,
                        isSettled: isSettled,
                        liveID: { transcript.subagents.subagent(forToolUseID: toolUseID)?.id }
                    )
                    switch target {
                    case let .live(id): app.selection = .subagent(workspaceID, id)
                    case let .recorded(id): app.selection = .subagentCall(workspaceID, toolUseID: id)
                    case .unavailable: break
                    }
                }
            )
        }

        var out: [TranscriptTableEntry] = []
        if let workspaceID = home.workspaceID {
            out.append(TranscriptTableEntry(
                id: .setup,
                contentKey: TranscriptContentKey {
                    $0.combine("setup")
                    $0.combine(workspaceID)
                    $0.combine(isRunningSetup)
                    $0.combine(isSetupExpanded)
                    $0.combine(transcript.hasNothingToShow)
                    $0.combine(Int(paneHeight))
                },
                content: {
                    AnyView(
                        VStack(alignment: .leading, spacing: 0) {
                            Color.clear
                                .frame(height: TranscriptLayout.topSpace)
                                .accessibilityHidden(true)
                            WorkspaceEventsView(
                                workspaceID: workspaceID,
                                isRunning: isRunningSetup,
                                isFirstThing: transcript.hasNothingToShow,
                                paneHeight: paneHeight,
                                onVisibilityChange: { showsSetup = $0 },
                                onShowLogEnd: { wasAsked in showSetupLogEnd(wasAsked: wasAsked) },
                                setupExpansion: $isSetupExpanded,
                                isSetupExpanded: isSetupExpanded
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    )
                }
            ))
        } else {
            out.append(TranscriptTableEntry(
                id: .setup,
                contentKey: TranscriptContentKey { $0.combine("ask-top-spacing") },
                content: {
                    AnyView(Color.clear.frame(height: TranscriptLayout.topSpace).accessibilityHidden(true))
                }
            ))
        }

        for index in drawnRows.indices {
            let row = drawnRows[index]
            if let at = folds.index(containing: index) {
                if folds.all[at].firstSeq != foldSeq {
                    let work = folds.all[at]
                    foldSeq = work.firstSeq
                    let would = TranscriptFold.hiddenIndices(work, revealed: revealed, drawn: drawnRange)
                    hiddenIndices = unfolded.contains(work.firstSeq) ? [] : would
                    let isFolded = !hiddenIndices.isEmpty
                    out.append(foldEntry(
                        firstSeq: work.firstSeq,
                        hiding: isFolded ? would.count : work.rows.count,
                        showsMore: isFolded && would.count < work.rows.count,
                        isFolded: isFolded,
                        isNested: work.isNested,
                        shows: !would.isEmpty,
                        session: sessionID
                    ))
                }
                if !hiddenIndices.isEmpty,
                   hiddenIndices.contains(index)
                    || TranscriptRowInk.drawsNothing(kind: row.kind, payload: row.payload) { continue }
            }
            if folds.absorbs(
                index: index, seq: row.seq, parent: row.parentToolUseID, revealed: revealed
            ) { continue }
            guard !TranscriptNoise.isHidden(row) else { continue }
            let subagentActions = row.kind == .toolUse ? folds.actions(underCall: row.refID) : nil
            let subagentHasRun = row.kind == .toolUse && folds.hasRun(underCall: row.refID)
            let isExpanded = expanded.contains(row.seq)
            let wasStopped = row.seq == stoppedTurnSeq
            let recovered = recoveredRuns[row.seq]
            let closesTranscript = row.kind == .result && row.seq == lastVisibleSeq
            let stillRunning = closesTranscript ? backgroundWork : nil
            let suggestion = row.kind == .suggestion ? suggestions.card(at: row.payload) : nil
            let key = TranscriptRowContentKey(
                id: row.id,
                seq: row.seq,
                kind: row.kind,
                isError: row.isError,
                durationMS: row.durationMS,
                resultPayloadCount: row.resultPayload?.count,
                permissionDecision: row.permissionDecision,
                permissionNote: row.permissionNote,
                permissionAnswers: row.permissionAnswers,
                parentToolUseID: row.parentToolUseID,
                isExpanded: isExpanded,
                subagentActions: subagentActions,
                subagentHasRun: subagentHasRun,
                wasStopped: wasStopped,
                wasRecovered: recovered != nil,
                closesTranscript: closesTranscript,
                stillRunning: stillRunning,
                suggestion: suggestion
            ).contentKey
            let settles = TranscriptMotion.fadesOnArrival(row.kind)
            let blank = TranscriptRowInk.drawsNothing(kind: row.kind, payload: row.payload)
            let shape = TranscriptRowShape.of(kind: row.kind)

            if row.kind == .result {
                out.append(TranscriptTableEntry(
                    id: .row(row.seq), contentKey: key, drawsNothing: blank, shape: shape,
                    content: {
                        AnyView(
                            TurnFooterView(
                                rows: rows,
                                row: row,
                                worktree: home.worktree,
                                permissionMode: permissionMode,
                                agentKind: agentKind,
                                orchestrates: orchestrates,
                                wasStopped: wasStopped,
                                recovered: recovered,
                                stillRunning: stillRunning,
                                transcript: transcript
                            )
                            .arrivingRow(settles && arrivals.isArriving(row.seq))
                            .padding(.horizontal, TranscriptLayout.inset)
                            .padding(
                                .bottom,
                                closesTranscript ? TranscriptLayout.tight : TranscriptLayout.turnGap
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        )
                    }
                ))
            } else {
                out.append(TranscriptTableEntry(
                    id: .row(row.seq), contentKey: key, drawsNothing: blank, shape: shape,
                    content: {
                        AnyView(
                            TranscriptRowView(
                                row: row,
                                home: home,
                                suggestion: suggestion,
                                chatIsSubagent: chatIsSubagent,
                                isExpanded: isExpanded,
                                isNested: row.parentToolUseID != nil,
                                subagentActions: subagentActions,
                                subagentHasRun: subagentHasRun,
                                runActions: runActions,
                                projectName: projectName,
                                onToggle: { toggle(row.seq) },
                                onAnswer: { requestID, decision in
                                    if row.isQuestion { controller.willUnfold(.row(row.seq)) }
                                    Task { await transcript.answer(requestID: requestID, decision: decision) }
                                }
                            )
                            .arrivingRow(settles && arrivals.isArriving(row.seq))
                            .messageArrival(transcript.messageArrivals.row(row.seq))
                            .padding(.horizontal, TranscriptLayout.inset)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        )
                    }
                ))
            }
        }

        out.append(sendingSlotEntry(transcript.sending))

        out.append(TranscriptTableEntry(
            id: .streaming,
            contentKey: TranscriptContentKey {
                $0.combine("streaming")
                $0.combine(transcript.session.id)
            },
            content: {
                AnyView(
                    StreamingTailView(transcript: transcript)
                        .padding(.horizontal, TranscriptLayout.inset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                )
            }
        ))

        let waiting = transcript.waitingDeliveries.filter { SendingSlot.drawing(of: $0) != nil }
        for delivery in waiting {
            let isLast = delivery.id == waiting.last?.id
            let holdSentence = isLast ? transcript.holdSentence : nil
            let canSteer = transcript.canSteer(delivery)
            out.append(TranscriptTableEntry(
                id: .pending(delivery.id),
                contentKey: TranscriptContentKey {
                    $0.combine("pending")
                    $0.combine(delivery.id)
                    $0.combine(isLast)
                    $0.combine(canSteer)
                    $0.combine(holdSentence)
                },
                content: {
                    switch SendingSlot.drawing(of: delivery) {
                    case .workspaceMessage(let crew):
                        return AnyView(
                            WorkspaceMessageRowView(
                                message: crew,
                                isWaiting: true,
                                holdSentence: holdSentence,
                                onDelete: { transcript.askToDiscard(delivery) }
                            )
                            .messageArrival(transcript.messageArrivals.delivery(delivery.id))
                            .padding(.horizontal, TranscriptLayout.inset)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        )
                    case .crewMessage(let crew):
                        return AnyView(
                            CrewMessageRowView(message: crew, isWaiting: true)
                                .padding(.horizontal, TranscriptLayout.inset)
                        )
                    case nil:
                        return AnyView(EmptyView())
                    case .ownerTurn, .stuckRequest:
                        break
                    }
                    return AnyView(
                        PendingTurnRowView(
                            delivery: delivery,
                            home: transcript.home,
                            holdSentence: holdSentence,
                            canRetry: transcript.canRetry(delivery),
                            onRetry: { Task { await transcript.retryPending() } },
                            canSteer: canSteer,
                            onSteer: { Task { await transcript.steer(delivery) } },
                            onEdit: { Task { await transcript.editPending(delivery) } },
                            onDelete: { transcript.askToDiscard(delivery) }
                        )
                        .messageArrival(transcript.messageArrivals.delivery(delivery.id))
                        .padding(.horizontal, TranscriptLayout.inset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    )
                }
            ))
        }
        out.append(.bottomSpacing(clearance: composerRoom?.clearance ?? 0))
        TranscriptHoldCensus.builtEntries(out.count)
        return out
    }

    private func foldEntry(
        firstSeq: Int,
        hiding: Int,
        showsMore: Bool,
        isFolded: Bool,
        isNested: Bool,
        shows: Bool,
        session: SessionID
    ) -> TranscriptTableEntry {
        TranscriptTableEntry(
            id: .fold(firstSeq),
            contentKey: TranscriptContentKey {
                $0.combine("fold")
                $0.combine(session)
                $0.combine(firstSeq)
                $0.combine(hiding)
                $0.combine(showsMore)
                $0.combine(isFolded)
                $0.combine(isNested)
                $0.combine(shows)
            },
            drawsNothing: !shows,
            shape: .fold,
            content: {
                guard shows else { return AnyView(EmptyView()) }
                return AnyView(
                    TranscriptFoldRowView(
                        hiddenCount: hiding,
                        showsMore: showsMore,
                        isExpanded: !isFolded,
                        isNested: isNested,
                        onToggle: { toggleFold(firstSeq) }
                    )
                    .padding(.horizontal, TranscriptLayout.inset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                )
            }
        )
    }

    var body: some View {
        let _ = SwitchTrace.mark("transcript.body", workspace: transcript.workspace?.id)
        let _ = SwitchTrace.markOnScreen("transcript.body", workspace: transcript.workspace?.id)
        @Bindable var transcript = transcript

        TranscriptTable(
            entries: entries,
            session: transcript.session.id,
            controller: controller,
            scale: fontScale,
            rowEnvironment: rowEnvironment,
            onGeometryChange: { measured($0) },
            onSettled: {
                remember()
                scheduleHistoryPreparation()
            },
            onLiveScrollChange: { hasHold in
                follower.isPaused = hasHold
                isLiveScrolling.value = hasHold
                guard hasHold else { return }
                isGrowing.value = false
                hoverHost.request = nil
                scroller.stop()
                follower.seekLiveEnd(false)
            },
            topInset: topInset
        )
        .ignoresSafeArea(.container, edges: .top)
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        }
        .overlay(alignment: .top) {
            HStack(alignment: .top, spacing: 0) {
                if let pinnedQuestion {
                    PinnedQuestionView(
                        question: pinnedQuestion,
                        onOpen: { show(seq: pinnedQuestion.seq) }
                    )
                    .transition(.opacity)
                } else {
                    Spacer(minLength: 0)
                }
                if !transcript.chapters.isEmpty {
                    TranscriptChaptersMenu(chapters: transcript.chapters, onOpen: show(seq:))
                        .padding(.top, Metrics.spacingWide)
                        .padding(.trailing, Metrics.spacingWide)
                }
            }
        }
        .animation(reduceMotion ? nil : Motion.hover, value: pinnedQuestion?.seq)
        .overlay { TranscriptHoverOverlay(host: hoverHost) }
        .overlay {
            SelectionActionOverlay(
                reader: selection,
                onSideChat: sideChatModel.map { model in
                    { [transcript] in _ = model.openSideConversation(from: transcript, quoting: $0.text) }
                },
                agent: transcript.session.agentKind.label,
                onReply: { transcript.reply(with: $0.text, from: $0.seq, typed: $1) }
            )
        }
        .overlay {
            if showsPlaceholder {
                TranscriptPlaceholderView(isRunningSetup: isRunningSetup, emptyState: emptyState)
                    .padding(.bottom, composerRoom?.clearance ?? 0)
            }
        }
        .onAppear { isVisible.value = true }
        .task(id: SuggestionsToRead(
            session: transcript.session.id, revision: app.workSuggestionsRevision
        )) {
            let read = await app.workSuggestions(in: transcript.session.id)
            guard !Task.isCancelled, read != suggestions else { return }
            suggestions = read
        }
        .onDisappear {
            selection.stop()
            remember()
            scroller.stop()
            follower.stop()
            isVisible.value = false
            isGrowing.value = false
        }
        .onChange(of: transcript.presentationRevision, initial: true) { _, _ in
            updatePinnedQuestion()
            position()
            growWindowDown()
            trackArrivals()
            let rescanned = transcript.presentationFolds()
            if rescanned != folds { folds = rescanned }
            foldSession = transcript.session.id
            foldRevision = transcript.presentationRevision
            if atLiveEnd.value {
                let refolded = TranscriptFold.refoldedAtLiveEnd(unfolded, in: rescanned)
                if refolded != unfolded { unfolded = refolded }
            }
            follower.nudge()
        }
        .background {
            TranscriptStreamingSignal(transcript: transcript) { follower.isStreaming = $0 }
        }
        .onChange(of: activeState, initial: true) { _, state in
            follower.isFrontmost = state != .inactive
        }
        .onChange(of: reduceMotion, initial: true) { _, reduced in
            follower.travels = TranscriptFollow.travels(reduceMotion: reduced)
        }
        .onChange(of: transcript.liveEndRequests, initial: true) { _, _ in
            honourLiveEndRequest()
        }
        .onChange(of: transcript.messageRevealRequests) { _, _ in
            if let seq = transcript.messageRevealSeq { show(seq: seq) }
        }
        .onChange(of: transcript.session.id) { left, _ in
            remember()
            _ = app.takeTranscriptTarget(for: left)
            scroller.stop()
            follower.stop()
            controller.releaseEnd()
            didPosition = false
            placeReady = nil
            isLiveScrolling.value = false
            opening = nil
            pinnedQuestion = nil
            selection.endReply()
            let remembered = memory?.remembered(session: transcript.session.id)
            liveEndRequest = TranscriptLiveEndRequest(handled: remembered?.liveEndRequest ?? 0)
            expanded = remembered?.expanded ?? []
            unfolded = remembered?.unfolded ?? []
            folds = transcript.presentationFolds()
            foldSession = transcript.session.id
            foldRevision = transcript.presentationRevision
            geometry.isNearBottom = true
            geometry.isFarFromEnd = false
            onScrolledUpChange?(false)
            drawn = Drawn(
                session: transcript.session.id,
                window: TranscriptResume.window(
                    remembered,
                    tailStart: TranscriptTail.start(in: transcript.rows.lazy.map(\.kind)),
                    seqs: transcript.rows.lazy.map(\.seq)
                )
            )
            writingTo = memory.map { WriteTarget(memory: $0, session: transcript.session.id) }
            isGrowing.value = false
            topPlace.value = nil
            seen.value = nil
            atLiveEnd.value = true
            arrivalSession = nil
        }
        .task(id: ObjectIdentifier(transcript)) { [transcript] in
            transcript.beginShowing()
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3_600)) }
            transcript.endShowing()
        }
        .task(id: transcript.session.id) {
            follower.onStart = { [controller] in controller.followerTookOver() }
            follower.onStop = { [controller] in controller.followerHandedBack() }
            follower.onRest = { [controller] in controller.goToEnd() }
            await transcript.load()
            let session = transcript.session.id
            await memory?.restorePlace(session: session)
            guard !Task.isCancelled else { return }
            resumed = TranscriptResume.isResuming(memory?.remembered(session: session)) ? session : nil
            placeReady = session
            drawn = Drawn(
                session: transcript.session.id,
                window: TranscriptResume.window(
                    memory?.remembered(session: transcript.session.id),
                    tailStart: TranscriptTail.start(in: transcript.rows.lazy.map(\.kind)),
                    seqs: transcript.rows.lazy.map(\.seq)
                )
            )
            TranscriptDrawn.note(drawn.window.count)
            writingTo = memory.map { WriteTarget(memory: $0, session: transcript.session.id) }
            didPosition = false
            arrivals.adopt(transcript.rows.suffix(TranscriptArrivals.window).map(\.seq))
            await Task.yield()
            guard !Task.isCancelled else { return }
            adoptScrollView()
            position()
            await Task.yield()
            guard !Task.isCancelled else { return }
            controller.arrived()

            guard resumed != transcript.session.id else {
                arrivalSession = transcript.session.id
                notePlace(controller.geometry)
                honourLiveEndRequest()
                scheduleHistoryPreparation()
                SwitchTrace.mark("transcript.window", workspace: transcript.workspace?.id)
                SwitchTrace.markOnScreen("transcript.window", workspace: transcript.workspace?.id)
                return
            }

            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            let settled = TranscriptWindow.settling(
                from: drawn.window, rowCount: transcript.rows.count
            )
            drawn = Drawn(session: transcript.session.id, window: settled)
            TranscriptDrawn.note(settled.count)
            SwitchTrace.mark("transcript.window", workspace: transcript.workspace?.id)
            SwitchTrace.markOnScreen("transcript.window", workspace: transcript.workspace?.id)
            follower.forget()
            await Task.yield()
            guard !Task.isCancelled else { return }
            open(opening)
            arrivalSession = transcript.session.id
            notePlace(controller.geometry)
            honourLiveEndRequest()
            scheduleHistoryPreparation()
            SwitchTrace.mark("transcript.history", workspace: transcript.workspace?.id)
            SwitchTrace.markOnScreen("transcript.history", workspace: transcript.workspace?.id)
        }
        .confirmation($transcript.discarding) { delivery in
            let question = PendingMessageDiscard.question(for: delivery, composerDraft: transcript.draft)
            return Confirmation(
                title: question.title,
                message: question.message,
                confirmLabel: question.confirmLabel,
                cancelLabel: question.cancelLabel
            )
        } onConfirm: { delivery in
            Task { await transcript.confirmDiscard(delivery) }
        }
    }

    private func measured(_ table: TranscriptTableGeometry) {
        adoptScrollView()

        let cap = TranscriptGeometry.cap(
            width: table.viewportWidth,
            share: Self.bubbleShare,
            gutter: Metrics.gutter,
            floor: Self.bubbleFloor
        )
        if bubbleWidth.cap != cap { bubbleWidth.cap = cap }
        reachToEnd.value = TranscriptGeometry.reach(
            contentHeight: table.contentHeight,
            viewportHeight: table.viewportHeight,
            offset: table.offset
        )
        notePlace(table)
        updatePinnedQuestion()

        var measured = TranscriptGeometry(
            paneHeight: TranscriptGeometry.height(table.viewportHeight),
            isNearBottom: ScrollEnd.isAtEnd(
                contentHeight: table.contentHeight,
                viewportHeight: table.viewportHeight,
                offset: table.offset
            ),
            isFarFromEnd: ScrollEnd.isWorthOffering(
                contentHeight: table.contentHeight,
                viewportHeight: table.viewportHeight,
                offset: table.offset
            )
        )
        if drawn.session == transcript.session.id,
           drawn.window.canGrowDown(rowCount: transcript.rows.count) {
            measured.isNearBottom = false
            measured.isFarFromEnd = true
        }
        if measured != geometry {
            geometry = measured
            onScrolledUpChange?(measured.isFarFromEnd)
        }

        if table.offset < table.viewportHeight { growWindow() }
        if measured.isNearBottom || table.contentHeight - table.viewportHeight - table.offset < 1 {
            growWindowDown()
        }
    }

    private var sideChatModel: WorkspaceModel? {
        Self.branchingModel(of: transcript, in: app)
    }

    private static func branchingModel(of transcript: TranscriptModel, in app: AppModel) -> WorkspaceModel? {
        let model = transcript.workspace.flatMap { app.existingModel(for: $0.id) }
        let canBranch = SelectionActions.canBranch(
            isAsk: model == nil,
            isSideConversation: transcript.session.sideConversationParentID != nil,
            workspaceIsActive: model?.workspace.state == .active
        )
        return canBranch ? model : nil
    }

    private func adoptScrollView() {
        selection.accepts = { [transcript] seq in
            transcript.rows.last(where: { $0.seq == seq }).map { SelectionActions.accepts($0.kind) } ?? false
        }
        selection.onContextMenu = { [transcript, app] seq, text, event, view in
            guard let row = transcript.rows.last(where: { $0.seq == seq }) else { return }
            let forking = Self.branchingModel(of: transcript, in: app).map { model in
                { (seq: Int) in model.fork(transcript, through: seq) }
            }
            MessageContextMenu.present(
                for: row, selection: text, transcript: transcript, onFork: forking, event: event, in: view
            )
        }
        selection.onAttach = { [transcript] in transcript.reply(with: $0, from: $1) }
        selection.start(controller: controller)
        let found = controller.scrollView
        if scroller.scrollView !== found { scroller.scrollView = found }
        if follower.scrollView !== found { follower.scrollView = found }
    }

    private func showSetupLogEnd(wasAsked: Bool) {
        guard transcript.rows.isEmpty else {
            if wasAsked { controller.scroll(to: .setup, anchor: .bottom) }
            return
        }
        guard wasAsked || geometry.isNearBottom else { return }
        controller.goToEnd()
    }

    private func honourLiveEndRequest() {
        guard liveEndRequest.consume(
            transcript.liveEndRequests, isReady: arrivalSession == transcript.session.id
        ) else { return }
        opening = .liveEnd
        goToLiveEnd()
    }

    private func goToLiveEnd() {
        scroller.stop()
        follower.seekLiveEnd(true)
        if drawn.session == transcript.session.id,
           drawn.window.canGrowDown(rowCount: transcript.rows.count) {
            drawn.window = TranscriptWindow.liveEnd(rowCount: transcript.rows.count)
            TranscriptDrawn.note(drawn.window.count)
            controller.goToEnd()
            follower.seekLiveEnd(false)
            return
        }

        switch TranscriptMotion.liveEndMove(
            distance: reachToEnd.value, reduceMotion: reduceMotion
        ) {
        case .jump:
            controller.goToEnd()
            follower.seekLiveEnd(false)
        case .glide(let seconds):
            controller.releaseEnd()
            guard scroller.glide(
                seconds: seconds, completion: { [controller, follower] in
                    controller.goToEnd()
                    follower.seekLiveEnd(false)
                }
            ) else {
                controller.goToEnd()
                follower.seekLiveEnd(false)
                return
            }
        }
    }

    private func show(seq: Int) {
        let rows = transcript.rows
        guard let index = TranscriptWindow.index(
            ofSeqAtOrAfter: seq, in: rows.lazy.map(\.seq)
        ) else { return }

        scroller.stop()
        follower.stop()
        controller.releaseEnd()

        if drawn.session != transcript.session.id
            || index < drawn.window.start
            || index >= drawn.window.end {
            let tailStart = drawn.session == transcript.session.id ? drawn.window.start : rows.count
            drawn = Drawn(
                session: transcript.session.id,
                window: TranscriptWindow.opening(
                    rowCount: rows.count, tailStart: tailStart, mustReach: index
                )
            )
            TranscriptDrawn.note(drawn.window.count)
        }

        Task { @MainActor in
            await Task.yield()
            controller.scroll(
                to: .row(seq),
                delta: PinnedQuestionView.height + Metrics.spacingWide
            )
        }
    }

    private func updatePinnedQuestion() {
        guard let place = controller.topmostPlace,
              let question = transcript.pinnedQuestion(atOrBefore: place.seq)
        else {
            if pinnedQuestion != nil { pinnedQuestion = nil }
            return
        }

        let isGone = controller.isAboveViewport(.row(question.seq)) ?? (question.seq < place.seq)
        let next = isGone ? question : nil
        if pinnedQuestion != next { pinnedQuestion = next }
    }

    private func position() {
        guard !transcript.rows.isEmpty, !didPosition, placeReady == transcript.session.id else { return }
        didPosition = true

        drawn = Drawn(session: transcript.session.id, window: drawnWindow)
        TranscriptDrawn.note(drawn.window.count)

        switch TranscriptResume.placement(
            for: memory?.remembered(session: transcript.session.id),
            seqs: transcript.rows.lazy.map(\.seq),
            target: app.takeTranscriptTarget(for: transcript.session.id)?.seq
        ) {
        case .liveEnd:
            opening = .liveEnd
        case .offset(let y):
            opening = .offset(y)
        case .row(let seq, let delta):
            opening = .rowOffset(seq, delta)
        case .target(let seq):
            opening = .row(seq, .center)
        case .first:
            opening = firstOpening()
        }
        open(opening)
        Task { await transcript.markAllRead() }
    }

    private func firstOpening() -> Opening {
        if let unread = transcript.firstUnreadSeq, unread != transcript.rows.first?.seq {
            return .row(unread, .top)
        }
        return .liveEnd
    }

    private func open(_ opening: Opening?) {
        switch opening {
        case .row(let seq, let anchor):
            controller.scroll(to: .row(seq), anchor: anchor)
        case .rowOffset(let seq, let delta):
            controller.scroll(to: .row(seq), delta: CGFloat(delta))
        case .liveEnd:
            controller.goToEnd()
        case .offset(let y):
            controller.scroll(toY: y)
        case nil:
            break
        }
    }

    private func windowToRemember(topSeq: Int?, rowCount: Int) -> TranscriptWindow {
        if atLiveEnd.value {
            return .liveEnd(rowCount: rowCount)
        }
        if let topSeq,
           let index = TranscriptWindow.index(
               ofSeqAtOrAfter: topSeq, in: transcript.rows.lazy.map(\.seq)
           ) {
            return .opening(
                rowCount: rowCount,
                tailStart: max(0, rowCount - TranscriptWindow.settled),
                mustReach: index
            )
        }
        return drawn.window
    }

    private func notePlace(_ table: TranscriptTableGeometry) {
        contentOffset.value = table.offset
        if let place = controller.topmostPlace { topPlace.value = place }
        let hasRowsBelow = drawn.session == transcript.session.id
            && drawn.window.canGrowDown(rowCount: transcript.rows.count)
        atLiveEnd.value = !hasRowsBelow && (
            table.isAtEnd || controller.holdsEnd || follower.isFollowing || follower.isSeekingLiveEnd
        )

        let session = transcript.session.id
        guard TranscriptResume.mayNoteSeen(
            arrived: arrivalSession, drawnFor: drawn.session, showing: session
        ) else { return }
        let place = topPlace.value
        let rowCount = transcript.rows.count
        seen.value = (session, TranscriptPaneState(
            expanded: [],
            offset: table.offset,
            anchorSeq: place?.seq,
            anchorDelta: Double(place?.delta ?? 0),
            isAtLiveEnd: atLiveEnd.value,
            rowCount: rowCount,
            drawn: windowToRemember(topSeq: place?.seq, rowCount: rowCount)
        ))
    }

    private func remember() {
        guard let target = writingTo,
              TranscriptResume.mayRemember(
                  arrived: arrivalSession,
                  writingTo: target.session,
                  drawnRows: drawn.window.count,
                  paneHeight: geometry.paneHeight
              ),
              let seen = seen.value, seen.session == target.session
        else { return }
        var state = seen.state
        state.expanded = expanded
        state.unfolded = unfolded
        state.liveEndRequest = liveEndRequest.handled
        target.memory.remember(state, session: target.session)
    }

    private func growWindowDown() {
        guard drawn.session == transcript.session.id,
              drawn.window.canGrowDown(rowCount: transcript.rows.count)
        else { return }
        drawn.window = drawn.window.grownDown(rowCount: transcript.rows.count)
        TranscriptDrawn.note(drawn.window.count)
    }

    private func growWindow() {
        guard arrivalSession == transcript.session.id,
              !geometry.isNearBottom,
              drawn.session == transcript.session.id,
              drawn.window.canGrowUp,
              !isGrowing.value
        else { return }
        isGrowing.value = true
        drawn.window = drawn.window.grownUp()
        TranscriptDrawn.note(drawn.window.count)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            isGrowing.value = false
        }
    }

    private func prepareHistoryWhileIdle() {
        guard drawn.session == transcript.session.id,
              isVisible.value,
              !isGrowing.value,
              !isLiveScrolling.value,
              arrivalSession == transcript.session.id,
              drawn.window.canGrowUp
        else { return }
        isGrowing.value = true
        Task { @MainActor in
            await Task.yield()
            while isGrowing.value,
                  isVisible.value,
                  arrivalSession == transcript.session.id,
                  drawn.session == transcript.session.id,
                  let prepared = drawn.window.preparedHistory(afterArrival: true) {
                drawn.window = prepared
                TranscriptDrawn.note(prepared.count)
                try? await Task.sleep(for: .milliseconds(180))
            }
            isGrowing.value = false
        }
    }

    private func scheduleHistoryPreparation() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            prepareHistoryWhileIdle()
        }
    }

    private func trackArrivals() {
        let seqs = transcript.rows.suffix(TranscriptArrivals.window).map(\.seq)
        guard arrivalSession == transcript.session.id else {
            arrivals.adopt(seqs)
            return
        }
        arrivals.absorb(seqs)
    }

    private func toggleFold(_ firstSeq: Int) {
        scroller.stop()
        follower.stop()
        controller.willChangeFoldRows(.fold(firstSeq))
        if unfolded.contains(firstSeq) {
            unfolded.remove(firstSeq)
        } else {
            unfolded.insert(firstSeq)
        }
        remember()
    }

    private func toggle(_ seq: Int) {
        controller.willUnfold(.row(seq))
        if expanded.contains(seq) {
            expanded.remove(seq)
        } else {
            expanded.insert(seq)
        }
        remember()
    }
}
