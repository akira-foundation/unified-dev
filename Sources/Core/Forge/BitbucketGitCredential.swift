import Foundation

public struct BitbucketGitCredential: Sendable, Equatable {
    public static let username = "x-token-auth"
    static let tokenKey = "host/\(BitbucketAuthStatus.cloudHostKey)/token"
    static let refreshMargin: TimeInterval = 120

    let password: String
    let expiresAt: Date?

    init(password: String, expiresAt: Date?) {
        self.password = password
        self.expiresAt = expiresAt
    }

    private struct StoredItem: Decodable {
        let data: Data

        enum CodingKeys: String, CodingKey { case data = "Data" }
    }

    private struct OAuthToken: Decodable {
        let accessToken: String
        let expiresAt: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresAt = "expires_at"
        }
    }

    static func fileName(of key: String) -> String {
        key.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "/", with: "%2F")
    }

    static func read(secrets folder: URL, passphrase: String) -> BitbucketGitCredential? {
        let file = folder.appending(path: fileName(of: tokenKey))
        guard let sealed = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return read(sealed: sealed, passphrase: passphrase)
    }

    static func read(sealed: String, passphrase: String) -> BitbucketGitCredential? {
        guard let opened = try? PassphraseEnvelope.open(sealed, passphrase: passphrase),
              let item = try? JSONDecoder().decode(StoredItem.self, from: opened),
              let value = String(data: item.data, encoding: .utf8)
        else { return nil }
        return credential(storedValue: value)
    }

    static func credential(storedValue value: String) -> BitbucketGitCredential? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("bkt.chunked.") else { return nil }
        guard trimmed.hasPrefix("{") else { return BitbucketGitCredential(password: trimmed, expiresAt: nil) }
        guard let token = try? JSONDecoder().decode(OAuthToken.self, from: Data(trimmed.utf8)),
              !token.accessToken.isEmpty
        else { return nil }
        return BitbucketGitCredential(password: token.accessToken, expiresAt: BitbucketDates.parse(token.expiresAt))
    }

    func isStale(at now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) < Self.refreshMargin
    }

    var answer: String {
        "username=\(Self.username)\npassword=\(password)\n"
    }
}
