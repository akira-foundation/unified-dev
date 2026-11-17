import Foundation

public struct MenuBarPanelContent: Equatable, Sendable {
    public struct Input: Sendable {
        public var workspaces: [Workspace]
        public var running: Set<WorkspaceID>
        public var waiting: Set<WorkspaceID>
        public var agentsByWorkspace: [WorkspaceID: Int]
        public var quotas: [AgentQuota]
        public var accounts: [AgentKind: AgentAccount]
        public var unanswered: Set<AgentKind>
        public var withoutLimits: Set<AgentKind>
        public var lastReported: [AgentKind: Date]
        public var pending: Set<AgentKind>
        public var layout: UsageLayout
        public var hold: KeepAwake.Hold
        public var now: Date
        public var offers: [AgentKind: QuotaAccountOffer]
        public var askIsWorking: Bool
        public var profile: Profile?
        public var hasAgentsElsewhere = false

        public init(
            workspaces: [Workspace],
            running: Set<WorkspaceID>,
            waiting: Set<WorkspaceID>,
            agentsByWorkspace: [WorkspaceID: Int],
            quotas: [AgentQuota],
            accounts: [AgentKind: AgentAccount],
            unanswered: Set<AgentKind>,
            withoutLimits: Set<AgentKind>,
            lastReported: [AgentKind: Date],
            pending: Set<AgentKind> = [],
            layout: UsageLayout,
            hold: KeepAwake.Hold,
            now: Date,
            offers: [AgentKind: QuotaAccountOffer] = [:],
            askIsWorking: Bool = false,
            profile: Profile? = nil
        ) {
            self.workspaces = workspaces
            self.running = running
            self.waiting = waiting
            self.agentsByWorkspace = agentsByWorkspace
            self.quotas = quotas
            self.accounts = accounts
            self.unanswered = unanswered
            self.withoutLimits = withoutLimits
            self.lastReported = lastReported
            self.pending = pending
            self.layout = layout
            self.hold = hold
            self.now = now
            self.offers = offers
            self.askIsWorking = askIsWorking
            self.profile = profile
        }

        public var runningAgents: Int {
            agentsByWorkspace.values.reduce(0, +) + (askIsWorking ? 1 : 0)
        }
    }

    public enum Badge: String, Sendable, Hashable, CaseIterable {
        case running
        case waiting
        case limitReached
        case awake

        public var symbolName: String {
            switch self {
            case .running: MenuBarSummary.runningSymbol
            case .waiting: MenuBarSummary.waitingSymbol
            case .limitReached: "gauge.with.dots.needle.100percent"
            case .awake: KeepAwake.menuBarSymbol
            }
        }

        public var label: String {
            switch self {
            case .running: "Agents running"
            case .waiting: "Agents waiting on you"
            case .limitReached: "A limit is reached"
            case .awake: KeepAwake.onHeadline
            }
        }
    }

    public enum Reading: Equatable, Sendable {
        case measured
        case unavailable
    }

    public struct Provider: Equatable, Sendable, Identifiable {
        public var kind: AgentKind
        public var reading: Reading
        public var section: UsageLayout.Section?
        public var note: String?
        public var offer: QuotaAccountOffer?
        public var id: AgentKind { kind }

        public init(
            kind: AgentKind,
            reading: Reading,
            section: UsageLayout.Section? = nil,
            note: String? = nil,
            offer: QuotaAccountOffer? = nil
        ) {
            self.kind = kind
            self.reading = reading
            self.section = section
            self.note = note
            self.offer = offer
        }

        public var isFoldable: Bool {
            guard reading == .measured, let section else { return false }
            return UsageCompactSection.foldCount(section) > 0
        }
    }

    public struct Agent: Equatable, Sendable, Identifiable {
        public var workspace: Workspace
        public var isWaiting: Bool
        public var id: WorkspaceID { workspace.id }

        public init(workspace: Workspace, isWaiting: Bool) {
            self.workspace = workspace
            self.isWaiting = isWaiting
        }

        public var symbolName: String { isWaiting ? MenuBarSummary.waitingSymbol : MenuBarSummary.runningSymbol }
        public var label: String { isWaiting ? MenuBarSummary.waitingHeading : MenuBarSummary.runningHeading }
    }

    public struct LimitNotice: Equatable, Sendable {
        public var provider: AgentKind
        public var title: String
        public var resetsAt: Date?

        public init(provider: AgentKind, title: String, resetsAt: Date?) {
            self.provider = provider
            self.title = title
            self.resetsAt = resetsAt
        }
    }

    public static let agentLimit = 5
    public static let statusTitle = "What's going on?"
    public static let setupSentence = "Sign in to \(usageAgentNames) and their limits show here."

    static var usageAgentNames: String {
        let names = UsageLayout.defaultProviderOrder.map(\.label)
        return names.dropLast().joined(separator: ", ") + " or " + (names.last ?? "")
    }

    public static let setupAction = "Open Agent Settings\u{2026}"
    public static let agentsTitle = "Agents"
    public static let noAgentsLine = MenuBarSummary.emptyTitle
    public static let retryTitle = "Try again"
    public static let settingsTitle = "Settings\u{2026}"
    public static let quitTitle = "Quit Unified Dev"
    public static let footerTitle = "Unified Dev"

    public static func moreTitle(_ count: Int) -> String { "+\(count) more" }

    public static func unavailableLine(for provider: AgentKind) -> String {
        "\(provider.label) did not report its limits."
    }

    public enum Activity: Equatable, Sendable {
        case running
        case waiting
        case idle
    }

    public var sentence: String
    public var headline = ""
    public var activity = Activity.idle
    public var badges: [Badge]
    public var providers: [Provider]
    public var agents: [Agent]
    public var moreAgents: Int
    public var notices: [LimitNotice]
    public var needsSetup: Bool
    public var profile: Profile?

    public static func make(_ input: Input) -> MenuBarPanelContent {
        let listed = agents(in: input)
        let working = listed.count { !$0.isWaiting }
        let waiting = listed.count - working
        let running = max(input.runningAgents, working)
        let providers = providers(in: input)
        let measured = Set(providers.filter { $0.reading == .measured }.map(\.kind))
        let notices = limitNotices(input.quotas, at: input.now).filter { measured.contains($0.provider) }
        let needsSetup = configuredProviders(in: input).isEmpty

        var badges: [Badge] = []
        if running > 0 { badges.append(.running) }
        if waiting > 0 { badges.append(.waiting) }
        if !notices.isEmpty { badges.append(.limitReached) }
        if input.hold.isOn { badges.append(.awake) }

        return MenuBarPanelContent(
            sentence: sentence(
                running: running,
                workspaces: working,
                waiting: waiting,
                notices: notices,
                hold: input.hold,
                hasAgentsElsewhere: input.hasAgentsElsewhere,
                needsSetup: needsSetup,
                now: input.now
            ),
            headline: headline(
                running: running,
                workspaces: working,
                waiting: waiting,
                hold: input.hold,
                hasAgentsElsewhere: input.hasAgentsElsewhere
            ),
            activity: running > 0 ? .running : (waiting > 0 ? .waiting : .idle),
            badges: badges,
            providers: providers,
            agents: Array(listed.prefix(agentLimit)),
            moreAgents: max(0, listed.count - agentLimit),
            notices: notices,
            needsSetup: needsSetup,
            profile: input.profile
        )
    }

    static func agents(in input: Input) -> [Agent] {
        MenuBarSummary.sections(
            in: input.workspaces,
            isRunning: { input.running.contains($0.id) },
            isAwaitingPermission: { input.waiting.contains($0.id) }
        )
        .filter { $0.heading != MenuBarSummary.unreadHeading }
        .flatMap { section in
            section.workspaces.map { Agent(workspace: $0, isWaiting: section.heading == MenuBarSummary.waitingHeading) }
        }
    }

    static func configuredProviders(in input: Input) -> Set<AgentKind> {
        let reading = input.quotas.filter { !$0.hasExpired(at: input.now) }.map(\.provider)
        return Set(reading).union(input.accounts.keys).filter(\.publishesUsage)
    }

    static func knownProviders(in input: Input) -> Set<AgentKind> {
        configuredProviders(in: input)
            .union(input.unanswered.filter(\.publishesUsage))
            .union(input.pending.filter(\.publishesUsage))
    }

    static func providers(in input: Input) -> [Provider] {
        let known = knownProviders(in: input)
        let metrics = UsageCatalogue.metrics(quotas: input.quotas, accounts: input.accounts, at: input.now)
        let sections = Dictionary(
            input.layout.sections(for: metrics).map { ($0.provider, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return input.layout.orderedProviders()
            .filter { known.contains($0) && input.layout.isEnabled($0) }
            .compactMap { kind -> Provider? in
                let offer = input.offers[kind]
                if input.pending.contains(kind), sections[kind] == nil {
                    return Provider(kind: kind, reading: .unavailable, note: readingLine(for: kind), offer: offer)
                }
                if input.unanswered.contains(kind) {
                    return Provider(kind: kind, reading: .unavailable, note: reason(for: kind, in: input), offer: offer)
                }
                if let section = sections[kind] {
                    return Provider(
                        kind: kind,
                        reading: .measured,
                        section: section,
                        note: note(for: kind, drawing: section, in: input),
                        offer: offer
                    )
                }
                guard metrics[kind]?.isEmpty ?? true else { return nil }
                return Provider(kind: kind, reading: .unavailable, note: reason(for: kind, in: input), offer: offer)
            }
    }

    public static func limitNotices(_ quotas: [AgentQuota], at now: Date) -> [LimitNotice] {
        QuotaBoard.make(from: quotas, at: now).all
            .filter { QuotaSeverity.of($0.fraction) == .spent }
            .map { LimitNotice(provider: $0.provider, title: UsageCatalogue.title(for: $0), resetsAt: $0.resetsAt) }
    }
}
