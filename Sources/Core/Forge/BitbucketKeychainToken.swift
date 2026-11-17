import Foundation
import Security

enum BitbucketKeychainToken {
    static let service = "bkt"
    enum Reading: Equatable {
        case found(String)
        case missing
        case declined
    }

    static func read() -> Reading {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: BitbucketGitCredential.tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var found: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        switch status {
        case errSecSuccess:
            guard let data = found as? Data, let value = String(data: data, encoding: .utf8) else { return .missing }
            return .found(value)
        case errSecUserCanceled, errSecAuthFailed:
            return .declined
        default:
            return .missing
        }
    }

    static func declined(in folder: URL = FileManager.default.temporaryDirectory) -> QuietMarker {
        QuietMarker(named: "unified-dev-bitbucket-keychain-declined", period: 60 * 60, in: folder)
    }
}
