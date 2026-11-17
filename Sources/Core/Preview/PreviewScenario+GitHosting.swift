import Foundation

extension PreviewScenario {
    public static let gitHostingKey = "preview.gitHosting"

    public struct GitHosting: Sendable, Equatable, Codable {
        public struct Host: Sendable, Equatable, Codable {
            public var thisMac: String?
            public var profiles: [String: String]
            public var installed: Bool

            public init(thisMac: String? = nil, profiles: [String: String] = [:], installed: Bool = true) {
                self.thisMac = thisMac
                self.profiles = profiles
                self.installed = installed
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                thisMac = try container.decodeIfPresent(String.self, forKey: .thisMac)
                profiles = try container.decodeIfPresent([String: String].self, forKey: .profiles) ?? [:]
                installed = try container.decodeIfPresent(Bool.self, forKey: .installed) ?? true
            }

            public var thisMacAccount: GitHostingAccount {
                GitHostingAccount(user: thisMac, installed: installed)
            }

            public func account(ofProfileNamed name: String) -> GitHostingAccount {
                let user = profiles.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
                return GitHostingAccount(user: user, installed: installed)
            }
        }

        public var gitHub: Host?
        public var bitbucket: Host?

        public init(gitHub: Host? = nil, bitbucket: Host? = nil) {
            self.gitHub = gitHub
            self.bitbucket = bitbucket
        }

        public func host(_ kind: ForgeKind) -> Host? {
            switch kind {
            case .gitHub: gitHub
            case .bitbucket: bitbucket
            }
        }

        public static func seeded(in defaults: UserDefaults = .standard) -> GitHosting? {
            defaults.data(forKey: gitHostingKey).flatMap { try? JSONDecoder().decode(GitHosting.self, from: $0) }
        }

        public static func adopt(_ hosting: GitHosting?, in defaults: UserDefaults = .standard) {
            guard let hosting, let data = try? JSONEncoder().encode(hosting) else {
                return defaults.removeObject(forKey: gitHostingKey)
            }
            defaults.set(data, forKey: gitHostingKey)
        }
    }

    var gitHostingProblems: [String] {
        guard let gitHosting else { return [] }
        let known = Set(([Self.initialProfileName] + profiles.map(\.name)).map { $0.lowercased() })
        return ForgeKind.allCases.flatMap { kind -> [String] in
            guard let host = gitHosting.host(kind) else { return [] }
            return host.profiles.keys.sorted()
                .filter { !known.contains($0.lowercased()) }
                .map { "git hosting for \(kind.displayName) names profile \"\($0)\", which the scenario does not create" }
        }
    }
}
