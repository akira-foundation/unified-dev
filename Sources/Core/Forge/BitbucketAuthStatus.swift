import Foundation

struct BitbucketAuthStatus: Decodable, Sendable {
    struct Host: Decodable, Sendable {
        let key: String
        let kind: String?
        let username: String?
        let authMethod: String?

        enum CodingKeys: String, CodingKey {
            case key, kind, username
            case authMethod = "auth_method"
        }
    }

    struct Context: Decodable, Sendable {
        let name: String
        let host: String
        let active: Bool?
    }

    static let cloudHostKey = "api.bitbucket.org"

    let hosts: [Host]
    let contexts: [Context]

    enum CodingKeys: String, CodingKey { case hosts, contexts }

    init(hosts: [Host], contexts: [Context]) {
        self.hosts = hosts
        self.contexts = contexts
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hosts = try container.decodeIfPresent([Host].self, forKey: .hosts) ?? []
        contexts = try container.decodeIfPresent([Context].self, forKey: .contexts) ?? []
    }

    static func decode(_ output: String) -> BitbucketAuthStatus? {
        try? JSONDecoder().decode(BitbucketAuthStatus.self, from: Data(output.utf8))
    }

    var isSignedInToCloud: Bool { cloudHost != nil }

    var cloudHost: Host? {
        hosts.first { $0.key.caseInsensitiveCompare(Self.cloudHostKey) == .orderedSame }
    }

    var cloudContext: String? {
        let cloud = contexts.filter { $0.host.caseInsensitiveCompare(Self.cloudHostKey) == .orderedSame }
        return (cloud.first { $0.active == true } ?? cloud.first)?.name
    }
}
