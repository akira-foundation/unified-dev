import Foundation

public struct ForgeCheckout: Sendable, Hashable {
    public let base: ForgeRepository?
    public let remotes: [ForgeRepository]

    public init(base: ForgeRepository?, remotes: [ForgeRepository]) {
        self.base = base
        self.remotes = remotes
    }

    init(baseRemote: String?, remotes: [String]) {
        self.init(
            base: baseRemote.flatMap(ForgeRepository.parse(remoteURL:)),
            remotes: remotes.compactMap(ForgeRepository.parse(remoteURL:))
        )
    }
}

public enum Forge {
    private static let checkouts = SharedReadings<String, ForgeCheckout>(retention: .seconds(600))
    private static let rememberedFor = Duration.seconds(300)

    @TaskLocal static var remoteOverride: (@Sendable (String) async -> String?)?
    @TaskLocal static var otherRemotesOverride: [String] = []

    public static func kind(forDirectory directory: String) async -> ForgeKind {
        await repository(forDirectory: directory)?.kind ?? .gitHub
    }

    public static func repository(forDirectory directory: String) async -> ForgeRepository? {
        await checkout(forDirectory: directory)?.base
    }

    public static func checkout(forDirectory directory: String) async -> ForgeCheckout? {
        if let remoteOverride {
            let remote = await remoteOverride(directory)
            return ForgeCheckout(baseRemote: remote, remotes: (remote.map { [$0] } ?? []) + otherRemotesOverride)
        }
        return try? await checkouts.value(for: directory, notOlderThan: rememberedFor) {
            let context = try await Git.repositoryContext(in: directory)
            return ForgeCheckout(baseRemote: context.baseRemoteURL, remotes: context.remoteURLs)
        }
    }
}
