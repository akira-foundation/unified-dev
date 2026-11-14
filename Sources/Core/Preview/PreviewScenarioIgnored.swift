import Foundation

public enum PreviewScenarioIgnored {
    public static func notice(scenarioPath: String, projects: [String]) -> Notice {
        let scenario = (scenarioPath as NSString).lastPathComponent
        return Notice(
            message: "\(scenario) was not applied, because this preview already holds \(listed(projects)). "
                + "Run `make preview-clean` in the worktree, build the preview again and open it with the "
                + "scenario to see it.",
            tone: .warning,
            dismissal: .untilDismissed
        )
    }

    static func listed(_ projects: [String]) -> String {
        projects.isEmpty ? "projects" : ProseList.joined(projects)
    }
}
