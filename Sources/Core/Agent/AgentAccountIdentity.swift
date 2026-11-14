import Foundation

public struct AgentAccountIdentity: Sendable, Hashable {
    public var email: String?
    public var displayName: String?
    public var organisationName: String?
    public var plan: String?
    public var expiresAt: Date?

    public init(
        email: String? = nil,
        displayName: String? = nil,
        organisationName: String? = nil,
        plan: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.email = email
        self.displayName = displayName
        self.organisationName = organisationName
        self.plan = plan
        self.expiresAt = expiresAt
    }

    public var isEmpty: Bool {
        email == nil && displayName == nil && organisationName == nil && plan == nil && expiresAt == nil
    }

    public static func read(_ home: AgentAccountHome, identity: Data?, credential: Data?) -> AgentAccountIdentity {
        switch home.provider {
        case .claudeCode: readClaude(identity: identity, credential: credential)
        case .codex: readCodex(credential: credential)
        case .grok, .antigravity, .cursor, .openCode: AgentAccountIdentity()
        }
    }

    private static func readClaude(identity: Data?, credential: Data?) -> AgentAccountIdentity {
        let account = identity.flatMap(JSONValue.parse)?["oauthAccount"]
        let oauth = credential.flatMap(JSONValue.parse)?["claudeAiOauth"]

        return AgentAccountIdentity(
            email: account?["emailAddress"]?.stringValue.flatMap(nonEmpty),
            displayName: account?["displayName"]?.stringValue.flatMap(nonEmpty),
            organisationName: account?["organizationName"]?.stringValue.flatMap(nonEmpty),
            plan: ClaudeAccountFiles(identity: identity, credential: credential).plan,
            expiresAt: oauth?["expiresAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }

    private static func readCodex(credential: Data?) -> AgentAccountIdentity {
        let token = credential.flatMap(JSONValue.parse)?["tokens"]?["id_token"]?.stringValue
        guard let claims = token.flatMap(AgentCatalog.decodeCodexIDToken) else { return AgentAccountIdentity() }
        return AgentAccountIdentity(
            email: claims.email,
            displayName: claims.name,
            plan: claims.planType.flatMap(AgentAccountReader.codexPlan),
            expiresAt: claims.expiresAt
        )
    }

    private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}
