import Foundation

public struct ClonedRepository: Sendable, Equatable {
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

public struct CloneFailure: Error, Sendable, Equatable {
    public var message: String
    public var folderWasCreated: Bool
    public var advice: String?
    public var detail: String?
    public var hostOffer: KnownHostOffer?

    public init(
        message: String,
        folderWasCreated: Bool,
        advice: String? = nil,
        detail: String? = nil,
        hostOffer: KnownHostOffer? = nil
    ) {
        self.message = message
        self.folderWasCreated = folderWasCreated
        self.advice = advice
        self.detail = detail
        self.hostOffer = hostOffer
    }

    public var title: String { "Could not clone the repository" }
}

public enum RepositoryCloner {
    public static let patience = Duration.seconds(30)

    public static let slowNotice = """
        git clone has not finished. A large repository takes a while, and it can also be waiting \
        on the network or on a key your agent has to approve. Stopping now leaves nothing behind.
        """

    public static func clone(
        _ remote: String,
        into destination: String
    ) async throws -> ClonedRepository {
        try claim(destination)
        do {
            try await Git.clone(remote, into: destination)
            guard await Git.isRepository(destination) else {
                throw CloneFailure(
                    message: "git clone finished and left no repository at \(destination).",
                    folderWasCreated: true
                )
            }
        } catch let failure as CloneFailure {
            discard(destination, folderWasCreated: true)
            throw CloneFailure(message: failure.message, folderWasCreated: false)
        } catch {
            discard(destination, folderWasCreated: true)
            throw await failure(cloning: remote, error)
        }
        return ClonedRepository(path: destination)
    }

    static func failure(cloning remote: String, _ error: Error) async -> CloneFailure {
        let output = RepositoryStarter.output(of: error)
        let kind = RemoteFailure.of(output)
        let host = ForgeRepository.host(ofRemote: remote)
        let isBitbucket = host.map { ForgeRepository.kind(ofHost: $0) == .bitbucket } ?? false
        var offer: KnownHostOffer?
        if kind == .unknownHostKey, let ssh = SSHRemote(remote: remote) {
            offer = await KnownHosts.offer(for: ssh)
        }
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return CloneFailure(
            message: RepositoryStarter.sentence(from: error),
            folderWasCreated: false,
            advice: kind.advice(host: host, isBitbucket: isBitbucket),
            detail: detail.isEmpty ? nil : detail,
            hostOffer: offer
        )
    }

    public static func discard(_ destination: String, folderWasCreated: Bool) {
        guard folderWasCreated, !destination.isEmpty else { return }
        let folder = FolderPath.normalize((destination as NSString).expandingTildeInPath)
        guard folder.components(separatedBy: "/").count > 2 else { return }
        try? FileManager.default.removeItem(atPath: folder)
    }

    private static func claim(_ destination: String) throws {
        let parent = (destination as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(
                atPath: parent, withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                atPath: destination, withIntermediateDirectories: false
            )
        } catch {
            throw CloneFailure(
                message: CloneRefusal.occupied(destination).sentence,
                folderWasCreated: false
            )
        }
    }
}
