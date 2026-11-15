import Foundation
import Security

enum BitbucketKeychainToken {
    static let service = "bkt"
    static let quietPeriod: TimeInterval = 60 * 60

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
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            return .declined
        default:
            return .missing
        }
    }

    static var declineMarker: URL {
        FileManager.default.temporaryDirectory.appending(path: "unified-dev-bitbucket-keychain-declined")
    }

    static func recentlyDeclined(at now: Date, marker: URL = declineMarker) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: marker.path),
              let written = attributes[.modificationDate] as? Date
        else { return false }
        return now.timeIntervalSince(written) < quietPeriod
    }

    static func rememberDecline(marker: URL = declineMarker) {
        FileManager.default.createFile(atPath: marker.path, contents: Data(), attributes: [.posixPermissions: 0o600])
    }

    static func forgetDecline(marker: URL = declineMarker) {
        try? FileManager.default.removeItem(at: marker)
    }
}
