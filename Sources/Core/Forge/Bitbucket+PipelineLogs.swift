import Foundation

public struct BitbucketPipelineTarget: Sendable, Hashable {
    public let repository: String
    public let buildNumber: Int
    public let step: String?

    public init(repository: String, buildNumber: Int, step: String? = nil) {
        self.repository = repository.lowercased()
        self.buildNumber = buildNumber
        self.step = step
    }

    public func belongs(to checkout: ForgeRepository) -> Bool {
        checkout.kind == .bitbucket && checkout.fullName == repository
    }

    public static func parse(detailsURL: String?) -> BitbucketPipelineTarget? {
        guard let detailsURL, let url = URL(string: detailsURL),
              let host = url.host?.lowercased(), ForgeRepository.kind(ofHost: host) == .bitbucket
        else { return nil }
        let path = url.path.split(separator: "/").map(String.init)
        guard path.count >= 2 else { return nil }
        let parts = Array(path.dropFirst(2)) + (url.fragment ?? "").split(separator: "/").map(String.init)
        guard let results = parts.firstIndex(of: "results"), results + 1 < parts.count,
              let number = Int(parts[results + 1]), number > 0
        else { return nil }
        var step: String?
        if let steps = parts.firstIndex(of: "steps"), steps + 1 < parts.count {
            step = BitbucketPipelineStep.canonicalUUID(parts[steps + 1].removingPercentEncoding ?? parts[steps + 1])
        }
        return BitbucketPipelineTarget(repository: "\(path[0])/\(path[1])", buildNumber: number, step: step)
    }
}

struct BitbucketPipelineStep: Decodable, Sendable, Hashable {
    struct State: Decodable, Sendable, Hashable {
        struct Result: Decodable, Sendable, Hashable { let name: String? }
        let name: String?
        let result: Result?
    }

    let uuid: String?
    let name: String?
    let state: State?
    var startedOn: String?
    var completedOn: String?

    enum CodingKeys: String, CodingKey {
        case uuid, name, state
        case startedOn = "started_on"
        case completedOn = "completed_on"
    }

    var hasFailed: Bool {
        ["FAILED", "ERROR"].contains(state?.result?.name?.uppercased() ?? "")
    }

    static func canonicalUUID(_ value: String) -> String? {
        let bare = value.trimmingCharacters(in: CharacterSet(charactersIn: "{} "))
        guard UUID(uuidString: bare) != nil else { return nil }
        return "{\(bare.lowercased())}"
    }

    static func failing(_ steps: [BitbucketPipelineStep], named wanted: String?) -> [BitbucketPipelineStep] {
        if let wanted, let chosen = steps.first(where: { $0.uuid.flatMap(canonicalUUID) == wanted }) {
            return [chosen]
        }
        return steps.filter(\.hasFailed)
    }
}

extension Bitbucket {
    static let stepsLogged = 3

    static func stepsArguments(build: Int, in repository: ForgeRepository, context: String) -> [String] {
        ["api", "\(path(of: repository))/pipelines/\(build)/steps/", "--param", "pagelen=100", "--context", context]
    }

    static func logArguments(build: Int, step: String, in repository: ForgeRepository, context: String) -> [String] {
        [
            "pipeline", "logs", String(build), "--step", step,
            "--workspace", repository.owner, "--repo", repository.name, "--context", context,
        ]
    }

    static func joinedLog(_ logs: [(name: String, text: String)], unread: [String] = []) -> String {
        guard logs.count > 1 || !unread.isEmpty else { return logs.first?.text ?? "" }
        let joined = logs.map { "== \($0.name) ==\n\($0.text)" }.joined(separator: "\n\n")
        guard !unread.isEmpty else { return joined }
        return joined + "\n\n== Not read ==\nBitbucket did not return the log of these failed steps: "
            + unread.joined(separator: ", ") + "."
    }

    public static func pipelineLog(_ target: BitbucketPipelineTarget, worktree: String) async throws -> String {
        let (repository, context) = try await connection(in: worktree)
        guard target.belongs(to: repository) else {
            throw GitHubReadFailure(
                reason: .unavailable,
                message: "That pipeline belongs to \(target.repository), not to \(repository.fullName), so its log was not read."
            )
        }
        let listing = stepsArguments(build: target.buildNumber, in: repository, context: context)
        let listed = try await run(listing, directory: worktree)
        guard listed.ok else { throw shellError(listing, result: listed) }
        let steps = try decode(BitbucketPage<BitbucketPipelineStep>.self, from: listed.stdout).values
        let chosen = BitbucketPipelineStep.failing(steps, named: target.step).prefix(stepsLogged)

        var logs: [(name: String, text: String)] = []
        var unread: [String] = []
        var refusal: (any Error)?
        for step in chosen {
            guard let uuid = step.uuid.flatMap(BitbucketPipelineStep.canonicalUUID) else { continue }
            let arguments = logArguments(build: target.buildNumber, step: uuid, in: repository, context: context)
            let result = try await run(arguments, directory: worktree, timeout: .seconds(90))
            guard result.ok else {
                refusal = refusal ?? shellError(arguments, result: result)
                unread.append(step.name ?? uuid)
                continue
            }
            logs.append((step.name ?? uuid, result.stdout))
        }
        if logs.isEmpty, let refusal { throw refusal }
        let log = joinedLog(logs, unread: unread)
        guard !log.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubReadFailure(reason: .unavailable, message: "Bitbucket returned no log for that pipeline.")
        }
        return log
    }
}
