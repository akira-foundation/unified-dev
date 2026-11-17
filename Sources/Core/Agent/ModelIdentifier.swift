import Foundation

public struct ModelIdentifier: Equatable, Sendable {
    public var model: String
    public var kind: AgentKind?
    public var namesBackend: Bool

    public init(model: String, kind: AgentKind? = nil, namesBackend: Bool = false) {
        self.model = model
        self.kind = kind
        self.namesBackend = namesBackend
    }

    public static func resolve(
        _ raw: String,
        models: [AgentKind: [AgentModel]] = [:]
    ) -> ModelIdentifier {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ModelIdentifier(model: raw) }

        guard let (named, rest) = namespaced(trimmed) else {
            if ClaudeModelRank.recognises(trimmed) {
                return ModelIdentifier(model: trimmed, kind: .claudeCode)
            }
            for kind in AgentKind.runnable where kind != .claudeCode {
                if let match = model(named: trimmed, in: models[kind] ?? []) {
                    return ModelIdentifier(model: match, kind: kind)
                }
            }
            if GrokModelRank.recognises(trimmed) {
                return ModelIdentifier(model: trimmed, kind: .grok)
            }
            return ModelIdentifier(model: trimmed)
        }

        let model = named == .claudeCode ? rest : model(named: rest, in: models[named] ?? []) ?? rest
        return ModelIdentifier(model: model, kind: named, namesBackend: true)
    }

    public static func correction(
        model raw: String,
        on kind: AgentKind,
        hasSpoken: Bool,
        models: [AgentKind: [AgentModel]] = [:]
    ) -> ModelIdentifier? {
        let resolved = resolve(raw, models: models)
        let moved = !hasSpoken && resolved.namesBackend ? resolved.kind : nil
        let settled = moved ?? kind
        guard resolved.model != raw || settled != kind else { return nil }
        return ModelIdentifier(model: resolved.model, kind: settled, namesBackend: resolved.namesBackend)
    }

    private static func namespaced(_ value: String) -> (AgentKind, String)? {
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let head = normalised(String(value[value.startIndex..<colon]))
        guard let kind = AgentKind.runnable.first(where: { names(head, $0) }) else { return nil }
        let rest = value[value.index(after: colon)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return nil }
        return (kind, rest)
    }

    private static func names(_ head: String, _ kind: AgentKind) -> Bool {
        !head.isEmpty && [kind.rawValue, kind.label, kind.executableName]
            .contains { normalised($0) == head }
    }

    private static func model(named value: String, in models: [AgentModel]) -> String? {
        let wanted = normalised(value)
        guard !wanted.isEmpty else { return nil }
        if let exact = models.first(where: { normalised($0.id) == wanted }) { return exact.id }
        return models.first { normalised($0.displayName) == wanted }?.id
    }

    private static func normalised(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
