import Foundation

public struct InjectedInstruction: Equatable, Sendable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum SentTurn {
    public enum Segment: Equatable, Sendable {
        case text(String)
        case file(String)
        case instructions(InjectedInstruction)

        public var text: String {
            switch self {
            case .text(let words): words
            case .file(let path): AttachmentDraft.token(for: path)
            case .instructions(let block): block.body
            }
        }
    }

    public static let mergeTitle = "Merge instructions"
    public static let pullRequestTitle = "Pull request instructions"
    public static let conflictTitle = "Conflict instructions"
    public static let projectTitle = "Project instructions"

    public static func title(forFile path: String) -> String? {
        switch path {
        case PullRequestInstructions.projectPath, PullRequestInstructions.scratchPath:
            return pullRequestTitle
        case ConflictInstructions.scratchPath:
            return conflictTitle
        default:
            let projectPaths = ProjectInstructions.Subject.allCases.flatMap {
                [ProjectInstructions.projectPath(for: $0), ProjectInstructions.scratchPath(for: $0)]
            }
            return projectPaths.contains(path) ? projectTitle : nil
        }
    }

    public static func segments(in text: String) -> [Segment] {
        var out: [Segment] = []
        var start = text.startIndex

        while let found = firstBlock(in: text, from: start) {
            out += words(String(text[start..<found.range.lowerBound]))
            out.append(.instructions(found.block))
            start = found.range.upperBound
        }
        out += words(String(text[start...]))
        return out
    }

    public static func withoutInstructions(_ text: String) -> String {
        segments(in: text)
            .compactMap { segment -> String? in
                if case .instructions = segment { return nil }
                return segment.text
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let constants: [InjectedInstruction] = {
        var found = [
            InjectedInstruction(title: mergeTitle, body: MergeInstructions.canonical),
            InjectedInstruction(
                title: pullRequestTitle, body: PullRequestInstructions.defaultMarkdown
            ),
            InjectedInstruction(title: conflictTitle, body: ConflictInstructions.defaultMarkdown),
            InjectedInstruction(title: mergeTitle, body: MergeInstructions.appOnly),
            InjectedInstruction(
                title: pullRequestTitle, body: PullRequestInstructions.appOnlyMarkdown
            ),
            InjectedInstruction(title: conflictTitle, body: ConflictInstructions.appOnlyMarkdown),
            InjectedInstruction(title: mergeTitle, body: MergeInstructions.bitbucketCanonical),
            InjectedInstruction(title: mergeTitle, body: MergeInstructions.bitbucketAppOnly),
            InjectedInstruction(title: pullRequestTitle, body: PullRequestInstructions.bitbucketMarkdown),
            InjectedInstruction(title: pullRequestTitle, body: PullRequestInstructions.bitbucketAppOnlyMarkdown),
        ]
        found += PullRequestInstructions.retiredDefaults.map {
            InjectedInstruction(title: pullRequestTitle, body: $0)
        }
        return found
    }()

    private struct Found {
        var range: Range<String.Index>
        var block: InjectedInstruction
    }

    private static func firstBlock(in text: String, from start: String.Index) -> Found? {
        var best: Found?
        func keep(_ candidate: Found) {
            guard let current = best else {
                best = candidate
                return
            }
            if candidate.range.lowerBound < current.range.lowerBound { best = candidate }
        }

        for block in constants {
            guard let range = text.range(of: block.body, range: start..<text.endIndex),
                  startsABlock(range.lowerBound, in: text)
            else { continue }
            keep(Found(range: range, block: block))
        }

        for subject in ProjectInstructions.Subject.allCases {
            let lead = ProjectInstructions.inlineLead(for: subject) + "\n\n"
            guard let range = text.range(of: lead, range: start..<text.endIndex),
                  startsABlock(range.lowerBound, in: text)
            else { continue }
            let body = String(text[range.upperBound...])
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            keep(Found(
                range: range.upperBound..<text.endIndex,
                block: InjectedInstruction(title: projectTitle, body: body)
            ))
        }

        return best
    }

    private static func startsABlock(_ index: String.Index, in text: String) -> Bool {
        guard index != text.startIndex else { return true }
        guard let breakStart = text.index(index, offsetBy: -2, limitedBy: text.startIndex),
              breakStart < index
        else { return false }
        return text[breakStart..<index] == "\n\n"
    }

    private static func words(_ run: String) -> [Segment] {
        guard !run.isEmpty else { return [] }
        return FileMention.segments(in: run).map { segment in
            switch segment {
            case .text(let words): .text(words)
            case .attachment(let path): .file(path)
            }
        }
    }
}
