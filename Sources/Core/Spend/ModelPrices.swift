import Foundation

public struct ModelPrice: Sendable, Hashable {
    public var input: Double
    public var cacheWriteShort: Double
    public var cacheWriteLong: Double
    public var cacheRead: Double
    public var output: Double

    public init(
        input: Double,
        cacheWriteShort: Double,
        cacheWriteLong: Double,
        cacheRead: Double,
        output: Double
    ) {
        self.input = input
        self.cacheWriteShort = cacheWriteShort
        self.cacheWriteLong = cacheWriteLong
        self.cacheRead = cacheRead
        self.output = output
    }

    public static func openAI(input: Double, cachedInput: Double, output: Double) -> ModelPrice {
        ModelPrice(
            input: input,
            cacheWriteShort: 0,
            cacheWriteLong: 0,
            cacheRead: cachedInput,
            output: output
        )
    }

    public func cost(of usage: TokenUsage) -> SpendCost {
        SpendCost(
            freshInput: perMillion(usage.freshInput, input),
            cacheRead: perMillion(usage.cacheRead, cacheRead),
            cacheWrite: perMillion(usage.cacheWriteShort, cacheWriteShort)
                + perMillion(usage.cacheWriteLong, cacheWriteLong),
            output: perMillion(usage.output, output),
            saved: perMillion(usage.cacheRead, input - cacheRead)
        )
    }

    private func perMillion(_ tokens: Int, _ price: Double) -> Double {
        Double(tokens) / 1_000_000 * price
    }
}

public enum PriceTier: Int, Sendable, Hashable {
    case unpriced = -1
    case base = 0
    case longPrompt = 1
}

public struct ModelPricing: Sendable, Hashable {
    public var base: ModelPrice
    public var aboveTokens: Int?
    public var abovePrice: ModelPrice?

    public init(_ base: ModelPrice, aboveTokens: Int? = nil, abovePrice: ModelPrice? = nil) {
        self.base = base
        self.aboveTokens = aboveTokens
        self.abovePrice = abovePrice
    }

    public func tier(forPrompt tokens: Int) -> PriceTier {
        guard let aboveTokens, tokens > aboveTokens else { return .base }
        return abovePrice == nil ? .unpriced : .longPrompt
    }

    public func price(_ tier: PriceTier) -> ModelPrice? {
        switch tier {
        case .base: base
        case .longPrompt: abovePrice
        case .unpriced: nil
        }
    }

    func price(forPrompt tokens: Int) -> ModelPrice? {
        price(tier(forPrompt: tokens))
    }
}

public enum ModelPrices {
    public static let measuredOn = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2026,
        month: 10,
        day: 11
    ).date ?? Date.distantPast

    public static let claude: [String: ModelPricing] = [
        "claude-fable-5-1": ModelPricing(
            ModelPrice(input: 10, cacheWriteShort: 12.50, cacheWriteLong: 20, cacheRead: 0.25, output: 50)
        ),
        "claude-mythos-5-1": ModelPricing(
            ModelPrice(input: 10, cacheWriteShort: 12.50, cacheWriteLong: 20, cacheRead: 0.25, output: 50)
        ),
        "claude-fable-5": ModelPricing(
            ModelPrice(input: 10, cacheWriteShort: 12.50, cacheWriteLong: 20, cacheRead: 1, output: 50)
        ),
        "claude-mythos-5": ModelPricing(
            ModelPrice(input: 10, cacheWriteShort: 12.50, cacheWriteLong: 20, cacheRead: 1, output: 50)
        ),
        "claude-opus-5-5": ModelPricing(
            ModelPrice(input: 4, cacheWriteShort: 5, cacheWriteLong: 8, cacheRead: 0.20, output: 20)
        ),
        "claude-opus-5": ModelPricing(opus4Family),
        "claude-opus-4-8": ModelPricing(opus4Family),
        "claude-opus-4-7": ModelPricing(opus4Family),
        "claude-opus-4-6": ModelPricing(opus4Family),
        "claude-opus-4-5": ModelPricing(opus4Family),
        "claude-sonnet-5-5": ModelPricing(
            ModelPrice(input: 2, cacheWriteShort: 2.50, cacheWriteLong: 4, cacheRead: 0.10, output: 10)
        ),
        "claude-sonnet-5": ModelPricing(
            ModelPrice(input: 2, cacheWriteShort: 2.50, cacheWriteLong: 4, cacheRead: 0.20, output: 10)
        ),
        "claude-sonnet-4-6": ModelPricing(sonnet4Family),
        "claude-sonnet-4-5": ModelPricing(sonnet4Family),
        "claude-haiku-5-5": ModelPricing(
            ModelPrice(input: 0.10, cacheWriteShort: 0.125, cacheWriteLong: 0.20, cacheRead: 0.01, output: 0.50),
            aboveTokens: 100_000,
            abovePrice: ModelPrice(
                input: 0.50, cacheWriteShort: 0.625, cacheWriteLong: 1, cacheRead: 0.05, output: 2.50
            )
        ),
        "claude-haiku-4-5": ModelPricing(
            ModelPrice(input: 1, cacheWriteShort: 1.25, cacheWriteLong: 2, cacheRead: 0.10, output: 5)
        ),
    ]

    public static let openAI: [String: ModelPricing] = [
        "gpt-6-astra": shortContext(.openAI(input: 10, cachedInput: 1, output: 50)),
        "gpt-6.1-sol": shortContext(.openAI(input: 2, cachedInput: 0.10, output: 10)),
        "gpt-6-sol": shortContext(.openAI(input: 2, cachedInput: 0.20, output: 10)),
        "gpt-6-luna": shortContext(.openAI(input: 0.10, cachedInput: 0.01, output: 0.50)),
        "gpt-5.6-sol": shortContext(.openAI(input: 4, cachedInput: 0.40, output: 20)),
        "gpt-5.6-luna": shortContext(.openAI(input: 0.20, cachedInput: 0.02, output: 1.20)),
        "gpt-5.3-codex": shortContext(.openAI(input: 1.75, cachedInput: 0.175, output: 14)),
    ]

    public static let shortContextLimit = 272_000

    private static let opus4Family = ModelPrice(
        input: 5, cacheWriteShort: 6.25, cacheWriteLong: 10, cacheRead: 0.50, output: 25
    )

    private static let sonnet4Family = ModelPrice(
        input: 3, cacheWriteShort: 3.75, cacheWriteLong: 6, cacheRead: 0.30, output: 15
    )

    private static func shortContext(_ price: ModelPrice) -> ModelPricing {
        ModelPricing(price, aboveTokens: shortContextLimit, abovePrice: nil)
    }

    public static func table(for provider: AgentKind) -> [String: ModelPricing] {
        switch provider {
        case .claudeCode: claude
        case .codex: openAI
        case .grok, .antigravity, .cursor, .openCode: [:]
        }
    }

    public static func pricing(for model: String, provider: AgentKind) -> ModelPricing? {
        let table = table(for: provider)
        if let exact = table[model] { return exact }
        return table
            .filter { model.hasPrefix($0.key) }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    public static func tier(for model: String, provider: AgentKind, prompt: Int) -> PriceTier {
        pricing(for: model, provider: provider)?.tier(forPrompt: prompt) ?? .unpriced
    }

    public static func spend(
        of usage: TokenUsage,
        model: String,
        provider: AgentKind,
        tier: PriceTier
    ) -> Spend {
        guard let price = pricing(for: model, provider: provider)?.price(tier) else {
            return Spend(usage: usage, cost: .none, unpriced: usage)
        }
        return Spend(usage: usage, cost: price.cost(of: usage), unpriced: .none)
    }

    static func spend(of usage: TokenUsage, model: String, provider: AgentKind) -> Spend {
        spend(
            of: usage,
            model: model,
            provider: provider,
            tier: tier(for: model, provider: provider, prompt: usage.prompt)
        )
    }
}
