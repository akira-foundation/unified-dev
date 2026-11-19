import Testing
import Foundation
@testable import Core

@Suite("Agent account environment")
struct AgentAccountEnvironmentTests {
    private let someone = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
    private let defaultClaude = AgentAccountHome.defaultHome(
        for: .claudeCode, home: URL(filePath: "/Users/someone")
    )!
    private let workClaude = AgentAccountHome(
        provider: .claudeCode,
        id: AgentAccountID("work"),
        directory: URL(filePath: "/support/AgentAccounts/claudeCode/work", directoryHint: .isDirectory),
        isDefault: false
    )
    private let workCodex = AgentAccountHome(
        provider: .codex,
        id: AgentAccountID("work"),
        directory: URL(filePath: "/support/AgentAccounts/codex/work", directoryHint: .isDirectory),
        isDefault: false
    )

    private static let tokens: Set<String> = [
        "CLAUDE_CODE_OAUTH_TOKEN",
        "CLAUDE_CODE_OAUTH_REFRESH_TOKEN",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_IDENTITY_TOKEN",
        "CLAUDE_CODE_API_KEY_FILE_DESCRIPTOR",
        "CLAUDE_CODE_GATEWAY_TOKEN",
        "CLAUDE_TRUSTED_DEVICE_TOKEN",
        "CLAUDE_SECURESTORAGE_CONFIG_DIR",
        "ANTHROPIC_CONFIG_DIR",
        "OPENAI_BASE_URL",
        "XAI_API_KEY",
        "GROK_API_KEY",
        "GROK_AUTH_TOKEN",
        "CODEX_API_KEY",
        "CODEX_ACCESS_TOKEN",
        "CODEX_AUTH",
        "OPENAI_IDENTITY_TOKEN_FILE",
    ]

    private static let measured: Set<String> = [
        "ANTHROPIC_API_KEY",
        "OPENAI_API_KEY",
        "ANTHROPIC_BASE_URL",
        "CLAUDE_CODE_USER_EMAIL",
        "CLAUDE_CODE_ACCOUNT_UUID",
        "CLAUDE_CODE_ORGANIZATION_UUID",
        "CLAUDECODE",
        "CLAUDE_CODE_ENTRYPOINT",
        "CLAUDE_CODE_SDK_HAS_HOST_AUTH_REFRESH",
        "CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH",
        "CLAUDE_CODE_SESSION_ACCESS_TOKEN",
        "CLAUDE_CODE_HOST_AUTH_ENV_VAR",
        "CLAUDE_CODE_HOST_CREDS_FILE",
        "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST",
        "CLAUDE_CODE_MESSAGING_SOCKET",
        "CLAUDE_CODE_MESSAGING_TOKEN",
        "CLAUDE_CODE_EXECPATH",
    ]

    @Test func everyInheritedCredentialAndHostAuthVariableIsStripped() {
        var dirty = Dictionary(uniqueKeysWithValues: Self.measured.union(Self.tokens).map { ($0, "x") })
        dirty["PATH"] = "/usr/bin"
        let clean = AgentAccountEnvironment.apply(launching: workClaude.provider, as: workClaude, to: dirty)
        for key in Self.measured.union(Self.tokens) { #expect(clean[key] == nil, "\(key) survived") }
        #expect(clean["PATH"] == "/usr/bin")
    }

    @Test func everyVariableThatWasMeasuredAndEveryTokenTheCliHonoursMatchesAPrefix() {
        for key in Self.measured.union(Self.tokens) {
            #expect(AgentAccountEnvironment.isStripped(key), "\(key) is not covered by a prefix")
        }
    }

    @Test func theNamesThePrefixesSpareAreTheProviderDirectoriesAndTheExemptions() {
        #expect(AgentAccountEnvironment.directoryVariables == ["CLAUDE_CONFIG_DIR", "CODEX_HOME", "GROK_HOME"])
        #expect(AgentAccountEnvironment.exemptVariables == [
            "CLAUDE_CODE_USE_BEDROCK",
            "CLAUDE_CODE_USE_VERTEX",
            "ANTHROPIC_MODEL",
            "CLAUDE_CODE_MAX_OUTPUT_TOKENS",
            "CLAUDE_CODE_SUBAGENT_MODEL",
        ])
        for name in AgentAccountEnvironment.directoryVariables.union(AgentAccountEnvironment.exemptVariables) {
            #expect(!AgentAccountEnvironment.isStripped(name), "\(name) was stripped")
        }
    }

    @Test func aVariableOnTheExemptionListSurvivesTheStripThatItsPrefixWouldOtherwiseCause() {
        let inherited = Dictionary(
            uniqueKeysWithValues: AgentAccountEnvironment.exemptVariables.map { ($0, "chosen") }
        )
        let clean = AgentAccountEnvironment.apply(launching: workClaude.provider, as: workClaude, to: inherited)
        for name in AgentAccountEnvironment.exemptVariables { #expect(clean[name] == "chosen", "\(name) was dropped") }
    }

    @Test func aRoutingVariableAndAnythingElseWithTheSamePrefixIsStillTaken() {
        for name in ["ANTHROPIC_BASE_URL", "OPENAI_BASE_URL", "CLAUDE_CODE_USE_SOMETHING_ELSE", "ANTHROPIC_MODELS"] {
            #expect(AgentAccountEnvironment.isStripped(name), "\(name) survived its prefix")
        }
    }

    @Test func whatWasClearedIsReportedByNameAndNothingIsSaidWhenNothingWasCleared() {
        let applied = AgentAccountEnvironment.applied(launching: .claudeCode, as: workClaude, to: ["ANTHROPIC_API_KEY": "x", "CLAUDE_CODE_OAUTH_TOKEN": "y", "PATH": "/usr/bin"]
        )
        #expect(applied.stripped == ["ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN"])
        let notice = AgentAccountEnvironment.strippedNotice(applied.stripped)
        #expect(notice?.contains("ANTHROPIC_API_KEY, CLAUDE_CODE_OAUTH_TOKEN") == true)
        #expect(AgentAccountEnvironment.strippedNotice([]) == nil)
        #expect(AgentAccountEnvironment.applied(launching: .claudeCode, as: workClaude, to: ["PATH": "/usr/bin"]).stripped.isEmpty)
    }

    @Test func aNameTheCliHasNotInventedYetIsStrippedByItsPrefix() {
        for prefix in AgentAccountEnvironment.strippedPrefixes {
            #expect(AgentAccountEnvironment.isStripped(prefix + "_SOMETHING_NOBODY_HAS_SHIPPED_YET"))
        }
        #expect(!AgentAccountEnvironment.isStripped("PATH"))
        #expect(AgentAccountEnvironment.isStripped("GEMINI_API_KEY"))
        #expect(AgentAccountEnvironment.isStripped("GOOGLE_API_KEY"))
        #expect(!AgentAccountEnvironment.isStripped("GOOGLE_APPLICATION_CREDENTIALS"))
    }

    @Test(
        """
        the names the listing can emit are only those the eval cannot turn into a command, \
        so a failure here is widened code and not a stale expectation
        """
    )
    func theListedNamesCannotReachTheEvalAsACommand() throws {
        let listable = try NSRegularExpression(
            pattern: "^[\(AgentAccountEnvironment.listableNameCharacters)]+$"
        )
        let dangerous = ";|&<>$`()[]{}*?!#~^=\\\"' \t\n"

        for character in dangerous {
            let name = "CLAUDE_X\(character)Y"
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            #expect(
                listable.firstMatch(in: name, range: range) == nil,
                "a name holding \(String(reflecting: character)) would reach the eval unquoted"
            )
        }
        #expect(AgentAccountEnvironment.shellListing.contains("eval \"set -- "))
        #expect(AgentAccountEnvironment.shellListing
            .contains("[\(AgentAccountEnvironment.listableNameCharacters)]"))
    }

    @Test func eachProviderHasItsDirectorySparedAndItsCredentialsTaken() {
        #expect(!AgentAccountEnvironment.isStripped("CLAUDE_CONFIG_DIR"))
        #expect(AgentAccountEnvironment.isStripped("CLAUDE_CODE_OAUTH_TOKEN"))
        #expect(!AgentAccountEnvironment.isStripped("CODEX_HOME"))
        #expect(AgentAccountEnvironment.isStripped("CODEX_API_KEY"))
        #expect(AgentAccountEnvironment.isStripped("CODEX_ACCESS_TOKEN"))
        #expect(AgentAccountEnvironment.isStripped("CODEX_AUTH"))
        #expect(!AgentAccountEnvironment.isStripped("GROK_HOME"))
        #expect(AgentAccountEnvironment.isStripped("GROK_API_KEY"))
    }

    @Test func aClaudeAccountIsPointedAtByItsConfigDirectory() {
        let clean = AgentAccountEnvironment.apply(launching: workClaude.provider, as: workClaude, to: [:])
        #expect(clean["CLAUDE_CONFIG_DIR"] == workClaude.directory.path)
        #expect(clean["CODEX_HOME"] == nil)
    }

    @Test func aCodexAccountIsPointedAtByItsHome() {
        let clean = AgentAccountEnvironment.apply(launching: workCodex.provider, as: workCodex, to: [:])
        #expect(clean["CODEX_HOME"] == workCodex.directory.path)
        #expect(clean["CLAUDE_CONFIG_DIR"] == nil)
    }

    @Test func theDirectoryTheCliWouldUseAnywayIsLeftUnnamedAndTheOwnersExportIsStillCleared() {
        let clean = AgentAccountEnvironment.apply(
            launching: .claudeCode,
            as: defaultClaude,
            to: ["ANTHROPIC_API_KEY": "x", "CLAUDE_CONFIG_DIR": "/Users/someone/.claude-work"],
            userHome: someone
        )
        #expect(clean["CLAUDE_CONFIG_DIR"] == nil)
        #expect(clean["ANTHROPIC_API_KEY"] == nil)
    }

    @Test func everyProvidersOwnDirectoryIsLeftUnnamed() {
        for provider in [AgentKind.claudeCode, .codex, .grok] {
            let home = AgentAccountHome.defaultHome(for: provider, home: someone)!
            let clean = AgentAccountEnvironment.apply(launching: home.provider, as: home, to: [:], userHome: someone)
            #expect(clean.isEmpty, "\(provider) named \(clean)")
        }
    }

    @Test func aDefaultHomeTheLaunchPointedElsewhereIsStillNamed() {
        let elsewhere = AgentAccountHome(
            provider: .claudeCode,
            id: AgentAccountHome.defaultID(for: .claudeCode),
            directory: URL(filePath: "/Users/someone/.claude-work", directoryHint: .isDirectory),
            isDefault: true
        )
        let clean = AgentAccountEnvironment.apply(launching: elsewhere.provider, as: elsewhere, to: [:], userHome: someone)
        #expect(clean["CLAUDE_CONFIG_DIR"] == elsewhere.directory.path)
    }

    @Test func theShellUnsetsTheDirectoryTheCliWouldUseAnywayRatherThanLeavingTheInheritedOne() {
        #expect(AgentAccountEnvironment.shellArguments(for: defaultClaude, userHome: someone)
            == ["-u", "CLAUDE_CONFIG_DIR"])
        #expect(AgentAccountEnvironment.shellArguments(for: workCodex, userHome: someone)
            == ["CODEX_HOME=\(workCodex.directory.path)"])
        #expect(AgentAccountEnvironment.shellArguments(for: nil, userHome: someone).isEmpty)
    }

    @Test func aLaunchWithNoAccountUnsetsItsOwnProvidersDirectoryAndNoOther() {
        #expect(AgentAccountEnvironment.shellArguments(launching: .claudeCode, as: nil, userHome: someone)
            == ["-u", "CLAUDE_CONFIG_DIR"])
        #expect(AgentAccountEnvironment.shellArguments(launching: .codex, as: nil, userHome: someone)
            == ["-u", "CODEX_HOME"])
        #expect(AgentAccountEnvironment.shellArguments(launching: .grok, as: nil, userHome: someone)
            == ["-u", "GROK_HOME"])
        #expect(AgentAccountEnvironment.shellArguments(launching: .cursor, as: nil, userHome: someone).isEmpty)
    }

    @Test func aLaunchWithAnAccountOfAnotherProviderStillUnsetsItsOwnDirectory() {
        #expect(AgentAccountEnvironment.shellArguments(launching: .claudeCode, as: workCodex, userHome: someone)
            == ["-u", "CLAUDE_CONFIG_DIR"])
    }

    @Test func aLaunchWithAnAccountNamesIt() {
        #expect(AgentAccountEnvironment.shellArguments(launching: .codex, as: workCodex, userHome: someone)
            == ["CODEX_HOME=\(workCodex.directory.path)"])
    }

    @Test func theShellStillNamesADefaultHomeTheLaunchPointedElsewhere() {
        let elsewhere = AgentAccountHome(
            provider: .claudeCode,
            id: AgentAccountHome.defaultID(for: .claudeCode),
            directory: URL(filePath: "/Users/someone/.claude-work", directoryHint: .isDirectory),
            isDefault: true
        )
        #expect(AgentAccountEnvironment.shellArguments(for: elsewhere, userHome: someone)
            == ["CLAUDE_CONFIG_DIR=\(elsewhere.directory.path)"])
    }

    @Test func theRealHomeIsTheOneUsedWhenNoCallerNamesOne() {
        let home = AgentAccountHome.defaultHome(
            for: .claudeCode, home: FileManager.default.homeDirectoryForCurrentUser
        )!
        #expect(AgentAccountEnvironment.apply(launching: home.provider, as: home, to: [:]).isEmpty)
        #expect(AgentAccountEnvironment.shellArguments(for: home) == ["-u", "CLAUDE_CONFIG_DIR"])
    }

    @Test func noAccountStillStripsTheInheritedVariables() {
        let clean = AgentAccountEnvironment.apply(
            launching: .claudeCode, as: nil, to: ["ANTHROPIC_API_KEY": "x", "CLAUDECODE": "1", "PATH": "/usr/bin"]
        )
        #expect(clean["ANTHROPIC_API_KEY"] == nil)
        #expect(clean["CLAUDECODE"] == nil)
        #expect(clean["PATH"] == "/usr/bin")
    }

    @Test func aStaleDirectoryVariableInTheInheritedEnvironmentIsReplacedNotKept() {
        let clean = AgentAccountEnvironment.apply(
            launching: .claudeCode, as: workClaude, to: ["CLAUDE_CONFIG_DIR": "/somewhere/else"]
        )
        #expect(clean["CLAUDE_CONFIG_DIR"] == workClaude.directory.path)
    }

    @Test func variablesThatAreNotCredentialsPassThroughUntouched() {
        let inherited = ["HOME": "/Users/someone", "PATH": "/usr/bin", "LANG": "en_GB.UTF-8"]
        #expect(AgentAccountEnvironment.apply(launching: workClaude.provider, as: workClaude, to: inherited).filter { $0.key != "CLAUDE_CONFIG_DIR" } == inherited)
    }
}

@Suite("Agent account login environment")
struct AgentAccountLoginEnvironmentTests {
    private let work = AgentAccountHome(
        provider: .claudeCode,
        id: AgentAccountID("work"),
        directory: URL(filePath: "/support/AgentAccounts/claudeCode/work", directoryHint: .isDirectory),
        isDefault: false
    )
    private let workCodex = AgentAccountHome(
        provider: .codex,
        id: AgentAccountID("work"),
        directory: URL(filePath: "/support/AgentAccounts/codex/work", directoryHint: .isDirectory),
        isDefault: false
    )
    private let defaultCodex = AgentAccountHome.defaultHome(for: .codex, home: URL(filePath: "/Users/someone"))!

    private static let directoryVariables: Set<String> = ["CLAUDE_CONFIG_DIR", "CODEX_HOME", "GROK_HOME"]

    private static let credentials: Set<String> = [
        "ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_AUTH_TOKEN", "CLAUDECODE",
    ]

    private var dirty: [String: String] {
        var variables = Dictionary(
            uniqueKeysWithValues: Self.credentials.union(Self.directoryVariables).map { ($0, "inherited") }
        )
        variables["PATH"] = "/usr/bin"
        return variables
    }

    @Test func noInheritedCredentialReachesTheLoginOfAnyAccount() {
        for home in [work, workCodex, defaultCodex, nil] {
            let login = AgentAccountEnvironment.login(launching: home?.provider, as: home, inheriting: dirty)
            for key in Self.credentials { #expect(login[key] == nil, "\(key) survived for \(String(describing: home?.id))") }
            #expect(login["PATH"] == "/usr/bin")
        }
    }

    @Test func aChosenAccountsLoginOverridesTheInheritedDirectory() {
        let claude = AgentAccountEnvironment.login(launching: work.provider, as: work, inheriting: dirty)
        let codex = AgentAccountEnvironment.login(launching: workCodex.provider, as: workCodex, inheriting: dirty)
        #expect(claude["CLAUDE_CONFIG_DIR"] == work.directory.path)
        #expect(codex["CODEX_HOME"] == workCodex.directory.path)
    }

    @Test(arguments: [AgentKind.claudeCode, .codex, .grok])
    func theLoginOfNoAccountSignsInToTheCliOwnDirectoryNotTheInheritedOne(provider: AgentKind) throws {
        let variable = try #require(AgentAccountEnvironment.directoryVariable(for: provider))
        let login = AgentAccountEnvironment.login(launching: provider, as: nil, inheriting: dirty)
        #expect(login[variable] == nil)
        for other in Self.directoryVariables.subtracting([variable]) {
            #expect(login[other] == "inherited", "\(other) was dropped")
        }
    }

    @Test func aLoginThatLaunchesNoAgentLeavesEveryDirectoryVariableAlone() {
        let login = AgentAccountEnvironment.login(launching: nil, as: nil, inheriting: dirty)
        for key in Self.directoryVariables { #expect(login[key] == "inherited", "\(key) was dropped") }
    }

    @Test func theLoginOfTheDefaultHomeLeavesTheDirectoryTheCliWouldUseAnywayUnnamed() {
        let login = AgentAccountEnvironment.login(
            launching: .codex, as: defaultCodex, inheriting: dirty, userHome: URL(filePath: "/Users/someone")
        )
        #expect(login["CODEX_HOME"] == nil)
    }

    @Test func theLoginRunsInATerminal() {
        let login = AgentAccountEnvironment.login(launching: work.provider, as: work, inheriting: ["NO_COLOR": "1"])
        #expect(login["TERM"] == "xterm-256color")
        #expect(login["NO_COLOR"] == nil)
    }
    @Test("the app's own directory variable does not take the session away from the files")
    func anInheritedDirectoryVariableLeavesTheFilesDescribingTheSession() {
        #expect(AgentAccountEnvironment.filesDescribeTheSession(["CLAUDE_CONFIG_DIR": "/Users/ada/.claude-work"]))
    }

    @Test("an API key in the environment means the files describe no session")
    func anApiKeyMeansTheFilesDescribeNoSession() {
        #expect(!AgentAccountEnvironment.filesDescribeTheSession(["ANTHROPIC_API_KEY": "sk-test"]))
        #expect(AgentAccountEnvironment.filesDescribeTheSession([:]))
    }

}
