import SwiftUI
import Core

struct CloneFailureGallery: View {
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            card(unknownHost)
            card(withoutCredential)
            card(refused)
        }
        .padding(18)
    }

    private func card(_ failure: CloneFailure) -> some View {
        VStack(alignment: .leading, spacing: Metrics.gutter) {
            StartProjectFailure(fault: StartProjectFault(failure))
        }
        .padding(Metrics.gutter)
        .frame(width: 420, alignment: .topLeading)
        .background(Palette.hover, in: RoundedRectangle(cornerRadius: 12))
    }

    private var unknownHost: CloneFailure {
        CloneFailure(
            message: "Host key verification failed.",
            folderWasCreated: false,
            advice: RemoteFailure.unknownHostKey.advice(host: "ssh.bitbucket.org", isBitbucket: true),
            detail: "Cloning into 'test'...\nHost key verification failed.\nfatal: Could not read from remote repository.",
            hostOffer: KnownHostOffer(
                host: "ssh.bitbucket.org",
                lines: [],
                fingerprints: [
                    "ED25519 SHA256:exampleEd25519FingerprintNotARealHostKey000",
                    "ECDSA SHA256:exampleEcdsaFingerprintNotARealHostKey00000",
                ]
            )
        )
    }

    private var withoutCredential: CloneFailure {
        CloneFailure(
            message: "fatal: could not read Username for 'https://bitbucket.org': terminal prompts disabled",
            folderWasCreated: false,
            advice: RemoteFailure.httpsNeedsCredential.advice(host: "bitbucket.org", isBitbucket: true),
            detail: "Cloning into 'test'...\nfatal: could not read Username for 'https://bitbucket.org': terminal prompts disabled"
        )
    }

    private var refused: CloneFailure {
        CloneFailure(
            message: "remote: You may not have access to this repository or it no longer exists in this workspace.",
            folderWasCreated: false,
            advice: RemoteFailure.httpsCredentialRefused.advice(host: "bitbucket.org", isBitbucket: true),
            detail: "Cloning into 'test'...\nfatal: Authentication failed for 'https://bitbucket.org/debtges/test.git/'"
        )
    }
}

extension Gallery {
    static let cloneFailure = Gallery(
        name: "clone-failure",
        title: "Clone failure",
        size: CGSize(width: 1340, height: 520),
        needsFocus: false,
        view: { _ in AnyView(CloneFailureGallery()) }
    )
}
