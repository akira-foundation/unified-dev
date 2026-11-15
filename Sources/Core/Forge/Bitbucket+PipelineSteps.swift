import Foundation

extension BitbucketPipelineStep {
    var conclusion: (status: String, conclusion: String?)? {
        switch state?.name?.uppercased() {
        case "PENDING", "READY": return ("QUEUED", nil)
        case "IN_PROGRESS": return ("IN_PROGRESS", nil)
        case "COMPLETED":
            let outcome: String? = switch state?.result?.name?.uppercased() {
            case "SUCCESSFUL": "SUCCESS"
            case "FAILED", "ERROR": "FAILURE"
            case "STOPPED": "CANCELLED"
            case "NOT_RUN", "SKIPPED": "SKIPPED"
            default: nil
            }
            return outcome.map { ("COMPLETED", $0) }
        default: return nil
        }
    }

    var isFinished: Bool { conclusion?.status == "COMPLETED" }

    func checkRun(in target: BitbucketPipelineTarget, pipeline: CheckRun) -> CheckRun? {
        guard let conclusion, let uuid = uuid.flatMap(Self.canonicalUUID) else { return nil }
        let encoded = uuid.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(["-"])) ?? uuid
        return CheckRun(
            name: name.flatMap { $0.isEmpty ? nil : $0 } ?? "Step",
            status: conclusion.status,
            conclusion: conclusion.conclusion,
            detailsURL: "https://bitbucket.org/\(target.repository)/pipelines/results/\(target.buildNumber)/steps/\(encoded)",
            startedAt: BitbucketDates.parse(startedOn),
            completedAt: conclusion.status == "COMPLETED" ? BitbucketDates.parse(completedOn) : nil,
            workflowName: pipeline.name
        )
    }

    static func rows(_ steps: [Self], of pipeline: CheckRun, in target: BitbucketPipelineTarget) -> [CheckRun]? {
        let rows = steps.compactMap { $0.checkRun(in: target, pipeline: pipeline) }
        guard !rows.isEmpty, rows.count == steps.count else { return nil }
        return rows
    }
}

actor BitbucketFinishedSteps {
    struct Key: Hashable {
        let target: BitbucketPipelineTarget
        let finishedAt: Date
    }

    private var kept: [Key: [BitbucketPipelineStep]] = [:]
    private let limit = 128

    func steps(for key: Key?) -> [BitbucketPipelineStep]? { key.flatMap { kept[$0] } }

    func keep(_ steps: [BitbucketPipelineStep], for key: Key?) {
        guard let key, !steps.isEmpty, steps.allSatisfy(\.isFinished) else { return }
        if kept.count >= limit { kept.removeAll() }
        kept[key] = steps
    }
}

extension Bitbucket {
    static let pipelinesExpanded = 5
    static let finishedSteps = BitbucketFinishedSteps()

    static func pipelineTargets(of runs: [CheckRun], in repository: ForgeRepository) -> [Int: BitbucketPipelineTarget] {
        var targets: [Int: BitbucketPipelineTarget] = [:]
        for (index, run) in runs.enumerated() where targets.count < pipelinesExpanded {
            guard let parsed = BitbucketPipelineTarget.parse(detailsURL: run.detailsURL), parsed.belongs(to: repository)
            else { continue }
            targets[index] = BitbucketPipelineTarget(repository: parsed.repository, buildNumber: parsed.buildNumber)
        }
        return targets
    }

    static func expanding(
        _ runs: [CheckRun], with steps: [Int: [BitbucketPipelineStep]], targets: [Int: BitbucketPipelineTarget]
    ) -> [CheckRun] {
        runs.enumerated().flatMap { index, run -> [CheckRun] in
            guard let target = targets[index], let found = steps[index],
                  let rows = BitbucketPipelineStep.rows(found, of: run, in: target)
            else { return [run] }
            return rows
        }
    }

    static func withPipelineSteps(
        _ runs: [CheckRun], in repository: ForgeRepository, context: String, directory: String
    ) async -> [CheckRun] {
        let targets = pipelineTargets(of: runs, in: repository)
        var steps: [Int: [BitbucketPipelineStep]] = [:]
        for (index, target) in targets {
            let finished = runs[index].completedAt.map { BitbucketFinishedSteps.Key(target: target, finishedAt: $0) }
            steps[index] = await pipelineSteps(
                of: target, finished: finished, in: repository, context: context, directory: directory
            )
        }
        return expanding(runs, with: steps, targets: targets)
    }

    private static func pipelineSteps(
        of target: BitbucketPipelineTarget, finished: BitbucketFinishedSteps.Key?,
        in repository: ForgeRepository, context: String, directory: String
    ) async -> [BitbucketPipelineStep]? {
        if let kept = await finishedSteps.steps(for: finished) { return kept }
        let arguments = stepsArguments(build: target.buildNumber, in: repository, context: context)
        guard let result = try? await run(arguments, directory: directory), result.ok,
              let page = try? decode(BitbucketPage<BitbucketPipelineStep>.self, from: result.stdout),
              page.next == nil
        else { return nil }
        await finishedSteps.keep(page.values, for: finished)
        return page.values
    }
}
