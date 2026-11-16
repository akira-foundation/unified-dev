import Foundation

public enum RemoteFailure: Sendable, Equatable {
    case hostKeyChanged
    case unknownHostKey
    case sshKeyRefused
    case httpsNeedsCredential
    case httpsCredentialRefused
    case noAccess
    case other

    public static func of(_ output: String) -> RemoteFailure {
        let text = output.lowercased()
        if text.contains("remote host identification has changed") { return .hostKeyChanged }
        if text.contains("host key verification failed") { return .unknownHostKey }
        if text.contains("permission denied (publickey") { return .sshKeyRefused }
        if text.contains("could not read username for 'https://")
            || text.contains("could not read password for 'https://") {
            return .httpsNeedsCredential
        }
        if text.contains("authentication failed for 'https://") || text.contains("invalid credentials") {
            return .httpsCredentialRefused
        }
        if text.contains("may not have access to this repository") || text.contains("repository not found")
            || text.contains("repository does not exist") {
            return .noAccess
        }
        return .other
    }

    public func advice(host: String?, isBitbucket: Bool) -> String? {
        let named = host ?? "The server"
        switch self {
        case .hostKeyChanged:
            return "\(named) presented a key that is not the one this Mac recorded for it. That is what "
                + "a server being impersonated looks like, and it also happens when a host replaces its "
                + "key. Check with whoever runs the host; Unified Dev does not change known_hosts for this."

        case .unknownHostKey:
            return "\(named) is not among the ssh hosts this Mac knows, and git cannot ask whether to "
                + "trust it without a terminal. Compare the fingerprint below with the one the host "
                + "publishes before you trust it."

        case .sshKeyRefused:
            let place = isBitbucket ? " (on Bitbucket, Personal settings and then SSH keys)" : ""
            return "\(named) did not accept this Mac's ssh key. Add the public key to your account "
                + "there\(place), or clone over https."

        case .httpsNeedsCredential:
            guard isBitbucket else {
                return "git has no credential for \(named), and it cannot ask for one without a "
                    + "terminal. Clone over ssh, or store a credential for git with a credential helper."
            }
            return "git has no credential for bitbucket.org. Sign in to Bitbucket in this project's "
                + "profile and Unified Dev hands that sign-in to git; for a profile that uses this Mac's "
                + "sign-in, macOS asks whether bridge, inside Unified Dev, may read it from the Keychain, and "
                + "declining keeps it quiet for an hour. Or clone over ssh with a key added to your "
                + "Bitbucket account."

        case .httpsCredentialRefused:
            return "\(named) refused the credential git sent, or the account it belongs to cannot reach "
                + "that repository. Check the address, that the account has been given access, and sign "
                + "in again if the sign-in has lapsed."

        case .noAccess:
            return "\(named) answered that the account git signed in with cannot reach that repository, "
                + "or that it does not exist under that name. Check the address and that the account "
                + "has been given access."

        case .other:
            return nil
        }
    }
}
