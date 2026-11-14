import Testing
import Foundation
@testable import Core

@Suite("Reading a preview scenario")
struct PreviewScenarioTests {
    @Test("a scenario reads with every optional part left out")
    func readsTheSmallestScenario() throws {
        let scenario = try PreviewScenario.read(Data(#"{"projects":[{"name":"harbour"}]}"#.utf8))
        #expect(scenario.welcome)
        #expect(scenario.projects == [PreviewScenario.Project(name: "harbour")])
    }

    @Test("a project may name branches to leave on its remote and in its clone")
    func readsBranches() throws {
        let scenario = try PreviewScenario.read(Data(#"{"projects":[{"name":"a","branches":["feat/shade"]}]}"#.utf8))
        #expect(scenario.projects[0].branches == ["feat/shade"])
        let bare = try PreviewScenario.read(Data(#"{"projects":[{"name":"a"}]}"#.utf8))
        #expect(bare.projects[0].branches.isEmpty)
    }

    @Test("a project's remote answers promptly unless it is told to answer slowly or never")
    func readsTheRemoteAnswer() throws {
        let scenario = try PreviewScenario.read(Data(
            #"{"projects":[{"name":"a"},{"name":"b","remote":"slowly"},{"name":"c","remote":"never"}]}"#.utf8
        ))
        #expect(scenario.projects.map(\.remote) == [.promptly, .slowly, .never])
        #expect(PreviewScenario.RemoteAnswer.promptly.uploadPack == nil)
        #expect(PreviewScenario.RemoteAnswer.slowly.uploadPack?.hasSuffix("git-upload-pack") == true)
        #expect(throws: PreviewScenarioError.self) {
            try PreviewScenario.read(Data(#"{"projects":[{"name":"a","remote":"sometimes"}]}"#.utf8))
        }
    }

    @Test("a full scenario keeps its projects, workspaces and chats in order")
    func readsAFullScenario() throws {
        let json = """
            {"welcome": false, "projects": [{"name": "harbour", "files": {"src/a.txt": "a"},
             "commits": ["one", "two"], "remoteAhead": ["three"],
             "workspaces": [{"name": "Lighthouse", "branch": "lighthouse",
               "chats": [{"title": "Chat", "messages": [{"from": "user", "text": "hi"},
                                                         {"from": "agent", "text": "hello"}]}]}]}]}
            """
        let scenario = try PreviewScenario.read(Data(json.utf8))
        #expect(!scenario.welcome)
        let project = try #require(scenario.projects.first)
        #expect(project.files == ["src/a.txt": "a"])
        #expect(project.commits == ["one", "two"])
        #expect(project.remoteAhead == ["three"])
        #expect(project.workspaces.first?.chats.first?.messages.map(\.from) == [.user, .agent])
    }

    @Test("a file that is not JSON is unreadable, and says so")
    func refusesGarbage() {
        #expect(throws: PreviewScenarioError.self) { try PreviewScenario.read(Data("projects: []".utf8)) }
    }

    @Test("a scenario that would write outside its own folders is refused", arguments: [
        #"{"projects":[]}"#,
        #"{"projects":[{"name":"../escape"}]}"#,
        #"{"projects":[{"name":".hidden"}]}"#,
        #"{"projects":[{"name":"--bare"}]}"#,
        #"{"projects":[{"name":"-q"}]}"#,
        #"{"projects":[{"name":"a"},{"name":"A"}]}"#,
        #"{"projects":[{"name":"a","files":{"/etc/hosts":"x"}}]}"#,
        #"{"projects":[{"name":"a","files":{"src/../../x":"x"}}]}"#,
        #"{"projects":[{"name":"a","files":{".git/config":"x"}}]}"#,
        #"{"projects":[{"name":"a","files":{".GIT/config":"x"}}]}"#,
        #"{"projects":[{"name":"a","files":{"src/.Git/hooks/x":"x"}}]}"#,
        #"{"projects":[{"name":"caf\u00e9"}]}"#,
        #"{"projects":[{"name":"a/b"}]}"#,
        #"{"projects":[{"name":"a","workspaces":[{"name":"w","branch":"bad..branch"}]}]}"#,
        #"{"projects":[{"name":"a","workspaces":[{"name":"w","branch":"main"}]}]}"#,
        #"{"projects":[{"name":"a","workspaces":[{"name":"w","branch":"x"},{"name":"v","branch":"x"}]}]}"#,
        #"{"projects":[{"name":"a","workspaces":[{"name":" ","branch":"x"}]}]}"#,
        #"{"projects":[{"name":"a","workspaces":[{"name":"w","branch":"ui"},{"name":"v","branch":"ui/panel"}]}]}"#,
        #"{"projects":[{"name":"a","branches":["main"]}]}"#,
        #"{"projects":[{"name":"a","branches":["bad..branch"]}]}"#,
        #"{"projects":[{"name":"a","branches":["x"],"workspaces":[{"name":"w","branch":"x"}]}]}"#,
        #"{"projects":[{"name":"a","branches":["ui","ui/panel"]}]}"#,
    ])
    func refusesUnsafeScenarios(json: String) {
        do {
            _ = try PreviewScenario.read(Data(json.utf8))
            Issue.record("\(json) was accepted")
        } catch PreviewScenarioError.invalid(let problems) {
            #expect(!problems.isEmpty)
        } catch {
            Issue.record("\(json) failed to read rather than being judged: \(error)")
        }
    }

    @Test("a relative scenario path is refused, because an opened app starts in /")
    func refusesARelativePath() {
        #expect(throws: PreviewScenarioError.self) { try PreviewLaunch.scenario(at: "Tools/scenarios/harbour.json") }
    }

    @Test("the launch argument is read only when a path follows it")
    func readsTheArgument() {
        #expect(PreviewLaunch.scenarioPath(arguments: ["app", "--scenario", "/tmp/s.json"]) == "/tmp/s.json")
        #expect(PreviewLaunch.scenarioPath(arguments: ["app", "--scenario"]) == nil)
        #expect(PreviewLaunch.scenarioPath(arguments: ["app", "--scenario", "--snapshot"]) == nil)
        #expect(PreviewLaunch.scenarioPath(arguments: ["app"]) == nil)
    }

    @Test("only a preview with its database, workspaces and transcripts inside its own root may seed")
    func onlyAPreviewMaySeed() throws {
        let root = "/tmp/wt/.build/preview"
        let info: [String: Any] = [
            PreviewIdentity.rootOverride: root,
            Store.databaseOverride: root + "/data/unifieddev.sqlite",
            WorkspacesRoot.override: root + "/workspaces",
            TranscriptHome.override: root + "/transcripts",
        ]
        let preview = PreviewIdentity.bundlePrefix + "wt"
        #expect(try PreviewLaunch.root(bundleIdentifier: preview, environment: [:], info: info) == root)

        for identifier in [Store.primaryBundleIdentifier, Store.devBundleIdentifier, nil] {
            #expect(throws: PreviewScenarioError.notAPreview) {
                try PreviewLaunch.root(bundleIdentifier: identifier, environment: [:], info: info)
            }
        }
        var realDatabase = info
        realDatabase[Store.databaseOverride] = "/Users/tester/Library/Application Support/Unified Dev/unifieddev.sqlite"
        #expect(throws: PreviewScenarioError.notAPreview) {
            try PreviewLaunch.root(bundleIdentifier: preview, environment: [:], info: realDatabase)
        }
        #expect(try PreviewLaunch.root(
            bundleIdentifier: preview,
            environment: [Store.databaseOverride: "/Users/tester/Library/Application Support/Unified Dev (Dev)/unifieddev.sqlite"],
            info: info
        ) == root)
        var relative = info
        relative[PreviewIdentity.rootOverride] = "wt/.build/preview"
        #expect(throws: PreviewScenarioError.notAPreview) {
            try PreviewLaunch.root(bundleIdentifier: preview, environment: [:], info: relative)
        }
        var theirTranscripts = info
        theirTranscripts[TranscriptHome.override] = "/Users/tester/.claude"
        #expect(throws: PreviewScenarioError.notAPreview) {
            try PreviewLaunch.root(bundleIdentifier: preview, environment: [:], info: theirTranscripts)
        }
        var missing = info
        missing[WorkspacesRoot.override] = nil
        #expect(throws: PreviewScenarioError.notAPreview) {
            try PreviewLaunch.root(bundleIdentifier: preview, environment: [:], info: missing)
        }
        var realWorkspaces = info
        realWorkspaces[WorkspacesRoot.override] = "/Users/tester/unifieddev/workspaces.noindex"
        #expect(throws: PreviewScenarioError.notAPreview) {
            try PreviewLaunch.root(bundleIdentifier: preview, environment: [:], info: realWorkspaces)
        }
    }

    @Test("a bundle's own value wins over an inherited environment, and an empty one counts as absent")
    func overridesPreferTheBundle() {
        let info: [String: Any] = ["UD_X": "bundle"]
        #expect(LaunchOverride.value("UD_X", environment: ["UD_X": "env"], info: info) == "bundle")
        #expect(LaunchOverride.value("UD_X", environment: ["UD_X": "env"], info: ["UD_X": ""]) == "env")
        #expect(LaunchOverride.value("UD_X", environment: ["UD_X": "env"], info: nil) == "env")
        #expect(LaunchOverride.value("UD_X", environment: [:], info: nil) == nil)
    }

    @Test("an overridden workspaces root is used as given, whatever is on disk")
    func workspacesRootOverride() {
        let root = WorkspacesRoot.resolve(home: URL(fileURLWithPath: "/Users/tester"), overriddenBy: "/tmp/wt/ws")
        #expect(root.path == "/tmp/wt/ws")
    }

    @Test("the real app never takes its workspaces root from the environment or the bundle")
    func realAppIgnoresTheOverride() {
        let environment = [WorkspacesRoot.override: "/tmp/elsewhere"]
        #expect(WorkspacesRoot.overrideValue(
            bundleIdentifier: Store.primaryBundleIdentifier, environment: environment, info: nil
        ) == nil)
        #expect(WorkspacesRoot.overrideValue(
            bundleIdentifier: PreviewIdentity.bundlePrefix + "wt", environment: environment, info: nil
        ) == "/tmp/elsewhere")
    }

    @Test("the command line prints one line per field, and refuses what it cannot use")
    func commandLine() {
        let printed = PreviewCommand.run(["identity", "--worktree", "/tmp/wt/abc", "--branch", "feat/7-x"])
        #expect(printed.status == 0)
        #expect(printed.output.contains("bundle_id=io.akira.unifieddev.dev.abc\n"))
        #expect(printed.output.contains("app_name=UD #7\n"))
        #expect(PreviewCommand.run(["identity"]).status == 1)
        #expect(PreviewCommand.run(["identity", "--worktree"]).status == 1)
        #expect(PreviewCommand.run(["nonsense"]).status == 1)
        #expect(PreviewCommand.run(["check", "/nonexistent/scenario.json"]).status == 1)
        #expect(PreviewCommand.run(["identity", "--worktree", "/tmp/wt/abc", "--foo", "x"]).status == 1)
    }

    @Test("every field the scripts read is printed, with the title's trailing space kept")
    func commandLinePrintsEveryField() throws {
        let printed = PreviewCommand.run(["identity", "--worktree", "/tmp/wt/abc", "--label", "Try it"])
        let identity = try PreviewIdentity(worktree: "/tmp/wt/abc", branch: nil, label: "Try it")
        let lines = Set(printed.output.split(separator: "\n").map(String.init))
        for field in ["slug", "bundle_id", "app_name", "title_prefix", "url_scheme", "services_item",
                      "root", "app_path", "database", "workspaces", "scratch", "tmux_socket", "bridge_server"] {
            let value = try #require(identity.fields.first { $0.key == field }?.value)
            #expect(lines.contains("\(field)=\(value)"))
        }
        #expect(lines.contains("title_prefix=[DEV \u{00B7} Try it] "))
    }

    @Test("a scenario that reads is summarised by the check command", .scratchDirectory)
    func checkSummarises() throws {
        let path = TestScratch.unique("scenario") + ".json"
        try #"{"projects":[{"name":"a","workspaces":[{"name":"w","branch":"w","chats":[{"title":"c","messages":[]}]}]}]}"#
            .write(toFile: path, atomically: true, encoding: .utf8)
        let checked = PreviewCommand.run(["check", path])
        #expect(checked.status == 0)
        #expect(checked.output == "1 projects, 1 workspaces, 1 chats\n")
    }

    @Test("every scenario shipped in Tools/scenarios reads and is valid")
    func shippedScenariosRead() throws {
        let names = try FileManager.default
            .contentsOfDirectory(atPath: TestScenarios.repositoryRoot + "/Tools/scenarios")
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()

        #expect(names.count > 20)
        for name in names {
            do {
                let scenario = try TestScenarios.shipped(name)
                #expect(!scenario.projects.isEmpty, "\(name)")
            } catch {
                Issue.record("\(name): \(error)")
            }
        }
    }

    @Test("the discard scenario carries a path git has to quote, changed in the workspace")
    func discardHunkAwkwardPath() throws {
        let scenario = try TestScenarios.shipped("discard-hunk")
        let project = try #require(scenario.projects.first)
        let workspace = try #require(project.workspaces.first)
        let awkward = "src/say \"hi\" there.txt"

        #expect(project.files[awkward] != nil)
        #expect(workspace.changes[awkward] != nil)
        #expect(workspace.changes[awkward] != project.files[awkward])
    }

    @Test("the start project card scenario offers a folder that is not a project, and one that is")
    func startProjectCardRecentFolders() throws {
        let scenario = try TestScenarios.shipped("start-project-card")

        #expect(scenario.recentFolders == ["sketches", "harbour", "almanac", "beacon"])
        #expect(scenario.looseRepositories == ["almanac"])
        #expect(scenario.looseFolders == ["sketches"])
        #expect(scenario.projects.map(\.name) == ["harbour", "beacon"])
        #expect(scenario.projects.last?.workspaces.isEmpty == true)
    }

    @Test("the menus and notices scenario declares the run script its steps use")
    func menusAndNoticesRunScript() throws {
        let scenario = try TestScenarios.shipped("menus-and-notices")
        let project = try #require(scenario.projects.first)
        let settings = try TOML.parse(try #require(project.files[".unifieddev/settings.toml"]))
        let clock = settings.tableValue?["scripts"]?.tableValue?["run"]?.tableValue?["clock"]?.tableValue
        #expect(clock?["name"]?.stringValue == "Clock")
        #expect(project.workspaces.map(\.name) == ["Wick", "Oil"])
    }

    @Test("the fast mode scenario puts one project on Codex and leaves the other on Claude Code")
    func composerFastModeBackends() throws {
        let scenario = try TestScenarios.shipped("composer-fast-mode")
        #expect(scenario.projects.map(\.name) == ["kestrel", "merlin"])

        let kestrel = try #require(scenario.projects.first)
        #expect(kestrel.files[".unifieddev/settings.toml"] == nil)

        let merlin = try #require(scenario.projects.last)
        let settings = try TOML.parse(try #require(merlin.files[".unifieddev/settings.toml"]))
        let model = settings["models.default"]?.stringValue
        #expect(model == "codex:" + TestScenarios.codexModel)
        #expect(ModelIdentifier.resolve(try #require(model)).kind == .codex)
    }
}
