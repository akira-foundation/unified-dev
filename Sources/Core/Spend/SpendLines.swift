import Foundation

public enum SpendLines {
    public static let title = "Agent spend"
    public static let openScreen = "Open the spend screen"
    public static let keepsNoUsage = "keeps no usage on disk"
    public static let notRead = "not read yet"
    public static let nothingYet = "nothing in this window"
    public static let noPublishedPrice = "no published price"
    public static let apiRates = "At API rates, not your bill"
    public static let whereItWent = "Where it went"
    public static let byProvider = "By provider"
    public static let byProject = "By project"
    public static let byAccount = "By account"
    public static let dayAxis = "Day"
    public static let costAxis = "Cost"
    public static let providerAxis = "Provider"

    public static func providerLine(_ provider: SpendBoard.ProviderLine) -> String {
        switch provider.reading {
        case .keepsNoUsage:
            keepsNoUsage
        case .notRead:
            notRead
        case .stillReading(let pending):
            stillReading(pending, of: provider.files)
        case .measured:
            provider.spend.isEmpty
                ? nothingYet
                : SpendFormat.tokens(provider.spend.usage.total) + " tokens, " + cost(provider.spend)
        }
    }

    public static func priceNote(_ date: Date) -> String {
        apiRates + ". " + SpendFormat.pricedOn(date)
    }

    public static func cost(_ spend: Spend) -> String {
        spend.usage == spend.unpriced && !spend.isEmpty
            ? noPublishedPrice
            : SpendFormat.money(spend.cost.total)
    }

    public static func columnCost(_ column: SpendBoard.ColumnLine, in total: Spend) -> String {
        total.usage == total.unpriced && !total.isEmpty
            ? noPublishedPrice
            : SpendFormat.money(column.cost)
    }

    public static func tokensLine(_ count: Int) -> String {
        SpendFormat.tokens(count) + " tokens"
    }

    public static func columnCaption(_ column: SpendBoard.ColumnLine) -> String {
        SpendFormat.share(column.costShare) + " of the cost"
    }

    public static func providerCost(_ provider: SpendBoard.ProviderLine) -> String {
        provider.spend.isEmpty ? "" : cost(provider.spend)
    }

    public static func sessionCaption(_ session: SpendSessionLine) -> String {
        withUnpriced(session.modelLine + ", " + turns(session.turns), session.spend)
    }

    public static func dearestLine(_ board: SpendBoard) -> String {
        daysStatus(board.standing) ?? board.dearestDay.map(dearestDay) ?? SpendBoard.emptyLine
    }

    public static let totalUnknown = "Unknown"

    public static let daysNotRead = "Reading the spend."

    public static let daysFailed = "Could not read the spend. Unified Dev will try again at the next refresh."

    public static let daysBehind = "Could not read the latest spend, so these figures may be behind. Unified Dev will try again at the next refresh."

    public static func daysStatus(_ standing: SpendDaysState.Standing) -> String? {
        switch standing {
        case .notRead: daysNotRead
        case .failed: daysFailed
        case .kept: daysBehind
        case .current: nil
        }
    }

    public static func total(_ board: SpendBoard) -> String {
        board.standing.knowsTheFigures ? cost(board.total) : totalUnknown
    }

    public static func money(_ board: SpendBoard) -> String {
        board.standing.knowsTheFigures ? SpendFormat.money(board.total.cost.total) : totalUnknown
    }

    public static func providerCaption(_ provider: SpendBoard.ProviderLine) -> String {
        provider.spend.isEmpty
            ? providerLine(provider)
            : turns(provider.turns) + ", " + tokensLine(provider.spend.usage.total)
    }

    public static func stillReading(_ pending: Int, of files: Int) -> String {
        files > pending
            ? "still reading \(pending) of \(files) transcripts"
            : "still reading \(pending == 1 ? "1 transcript" : "\(pending) transcripts")"
    }

    public static func turns(_ count: Int) -> String {
        count == 1 ? "1 turn" : "\(count) turns"
    }

    public static func sessions(_ count: Int) -> String {
        count == 1 ? "1 chat" : "\(count) chats"
    }

    public static let accountsNotRead = "Reading the accounts."

    public static let accountsFailed = "Could not read the accounts. Unified Dev will try again at the next refresh."

    public static func accountCaption(_ account: SpendAccountLine) -> String {
        let chats = withUnpriced(sessions(account.sessions.count), account.spend)
        return account.isKnown
            ? account.provider.label + ", " + chats
            : "Not an account Unified Dev knows. Historic " + account.provider.label + " spend, " + chats
    }

    public static func projectCaption(_ project: SpendProjectLine) -> String {
        withUnpriced(sessions(project.sessions.count), project.spend)
    }

    private static func withUnpriced(_ caption: String, _ spend: Spend) -> String {
        spend.hasUnpricedTokens ? caption + ", " + unpricedLine(spend.unpriced) : caption
    }

    public static func savedLine(_ cost: SpendCost) -> String {
        "The cache saved " + SpendFormat.money(cost.saved)
    }

    public static func unpricedLine(_ usage: TokenUsage) -> String {
        SpendFormat.tokens(usage.total) + " tokens had " + noPublishedPrice
    }

    public static func dearestDay(_ bar: SpendBoard.DayBar) -> String {
        "Dearest day: " + SpendFormat.day(bar.day) + ", " + cost(bar.spend)
    }
}
