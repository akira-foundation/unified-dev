import Foundation

public enum BackgroundWork {
    static let namedLimit = 3

    public static func note(for roster: SubagentRoster) -> String? {
        note(for: roster.subagents)
    }

    static func note(for subagents: [Subagent]) -> String? {
        let running = subagents.filter { $0.state == .running }
        guard case let (counted, names)? = described(running) else { return nil }
        let verb = running.count == 1 ? "is" : "are"
        return "\(capitalised(counted)) \(verb) still running: \(names)."
    }

    public static func stopped(_ commands: [Subagent]) -> String? {
        guard case let (counted, names)? = described(commands) else { return nil }
        return "It stopped \(counted): \(names)."
    }

    private static func described(_ subagents: [Subagent]) -> (counted: String, names: String)? {
        guard let first = subagents.first else { return nil }

        let noun = subagents.allSatisfy { $0.kind == first.kind } ? first.kind.noun : "background task"
        let counted = subagents.count == 1
            ? "\(article(for: noun)) \(noun)"
            : "\(subagents.count) \(plural(noun))"

        let titles = subagents.map(SubagentRow.title(of:))
        let named = Array(titles.prefix(namedLimit))
        let rest = titles.count - named.count
        let names = rest > 0
            ? named.joined(separator: ", ") + " and \(rest) more"
            : ProseList.joined(named)
        return (counted, names)
    }

    private static func article(for noun: String) -> String {
        noun.first.map { "aeiou".contains($0) } == true ? "an" : "a"
    }

    private static func capitalised(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func plural(_ noun: String) -> String { noun + "s" }
}
