import Foundation

public enum AntigravityModelList {
    public static let arguments = ["models"]

    public static let timeout = Duration.seconds(20)

    public enum Reading: Sendable, Hashable {
        case models([AgentModel])
        case signedOut
        case failed(String)
    }

    public static func read(_ result: ShellResult) -> Reading {
        guard result.ok else {
            let message = result.stderr
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .last { !$0.isEmpty } ?? ""
            return message.localizedCaseInsensitiveContains("sign in") ? .signedOut : .failed(message)
        }
        return .models(parse(result.stdout))
    }

    public static func parse(_ stdout: String) -> [AgentModel] {
        let pairs: [(String, String)] = stdout.components(separatedBy: .newlines).compactMap { line in
            let columns = line.split(separator: "\t", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard let id = columns.first, !id.isEmpty, !id.contains(" ") else { return nil }
            let name = columns.count > 1 && !columns[1].isEmpty ? columns[1] : id
            return (id, name)
        }
        return pairs.enumerated().map { index, pair in
            AgentModel(id: pair.0, displayName: pair.1, isDefault: index == 0)
        }
    }
}

public struct AntigravityModelListError: Error, Sendable, Hashable {
    public let message: String
}

public actor AntigravityModelCatalog {
    private let cache: AgentModelCache<AgentModel>

    public init(
        fetch: @escaping @Sendable () async throws -> [AgentModel],
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        cache = AgentModelCache(fetch: fetch, now: now)
    }

    public static func live(store: Store? = nil) -> AntigravityModelCatalog {
        AntigravityModelCatalog(fetch: {
            await LoginShellPath.ready()
            let stored = try await store?.setting(AgentCatalog.executablePathSettingKey(.antigravity))
            let executable = AgentCatalog.executable(for: .antigravity, override: stored)
            let result = try await Shell.run(
                executable,
                AntigravityModelList.arguments,
                cwd: AgentScratchDirectory.current(),
                env: ACPDialect.antigravity.quietEnvironment,
                timeout: AntigravityModelList.timeout
            )
            switch AntigravityModelList.read(result) {
            case .models(let models): return models
            case .signedOut: throw AntigravityModelListError(message: "Antigravity is not signed in")
            case .failed(let message): throw AntigravityModelListError(message: message)
            }
        })
    }

    public func models() async throws -> [AgentModel] {
        try await cache.models()
    }

    public func invalidate() async {
        await cache.invalidate()
    }
}
