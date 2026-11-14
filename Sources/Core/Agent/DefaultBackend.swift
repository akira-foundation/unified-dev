import Foundation

public struct DefaultBackend: Equatable, Sendable {
    public var kind: AgentKind
    public var model: String
    public var effort: String

    public init(kind: AgentKind, model: String, effort: String) {
        self.kind = kind
        self.model = model
        self.effort = effort
    }

    public static func resolve(
        model: String,
        effort: String,
        app: AppDefaults,
        running: AgentKind = .claudeCode,
        models: [AgentKind: [AgentModel]] = [:]
    ) -> DefaultBackend {
        let identity = ModelIdentifier.resolve(model, models: models)
        let kind: AgentKind
        if identity.namesBackend, let named = identity.kind {
            kind = named
        } else if model == app.model {
            kind = app.backend
        } else {
            kind = offers(identity.model, on: running, models: models) ? running : identity.kind ?? running
        }
        return DefaultBackend(
            kind: kind,
            model: identity.model,
            effort: self.effort(
                effort,
                on: kind,
                model: identity.model,
                models: models
            )
        )
    }

    public static func kind(
        ofModel model: String,
        running: AgentKind,
        models: [AgentKind: [AgentModel]] = [:]
    ) -> AgentKind {
        let identity = ModelIdentifier.resolve(model, models: models)
        guard !identity.namesBackend, offers(identity.model, on: running, models: models) else {
            return identity.kind ?? running
        }
        return running
    }

    private static func offers(_ model: String, on kind: AgentKind, models: [AgentKind: [AgentModel]]) -> Bool {
        models[kind]?.contains { $0.id == model } == true
    }

    public static func effort(
        _ wanted: String,
        on kind: AgentKind,
        model: String,
        models: [AgentKind: [AgentModel]] = [:]
    ) -> String {
        guard !ComposerEffort.isUnset(wanted) else { return ComposerEffort.unsetID }
        guard kind.announcesModelEfforts else { return wanted }
        guard let found = models[kind]?.first(where: { $0.id == model }) else { return wanted }
        return found.resolvedEffort(preferring: wanted)
    }
}
