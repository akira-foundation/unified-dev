import Foundation

public extension SetupCheck {
    var fix: SetupFix? {
        switch (tool, outcome) {
        case (_, .pending), (_, .ready):
            return nil

        case (.git, _):
            return SetupFix(
                summary: "Install Apple's command line tools, which include git",
                command: "xcode-select --install",
                url: URL(string: "https://git-scm.com/download/mac")
            )

        case (.claudeCode, .missing):
            return SetupFix(
                summary: "Install Claude Code",
                command: "npm install -g @anthropic-ai/claude-code",
                url: URL(string: "https://docs.claude.com/en/docs/claude-code/setup")
            )

        case (.claudeCode, .needsSignIn):
            return SetupFix(
                summary: "Sign in to Claude Code",
                command: AgentKind.claudeCode.loginCommand,
                url: nil,
                isInteractive: true
            )

        case (.codex, .missing):
            return SetupFix(
                summary: "Install Codex",
                command: "npm install -g @openai/codex",
                url: URL(string: "https://developers.openai.com/codex/cli")
            )

        case (.codex, .needsSignIn):
            return SetupFix(
                summary: "Sign in to Codex",
                command: AgentKind.codex.loginCommand,
                url: nil,
                isInteractive: true
            )

        case (.grok, .missing):
            return SetupFix(
                summary: "Install Grok",
                command: "curl -fsSL https://x.ai/cli/install.sh | bash",
                url: URL(string: "https://x.ai/cli")
            )

        case (.grok, .needsSignIn):
            return SetupFix(
                summary: "Sign in to Grok",
                command: AgentKind.grok.loginCommand,
                url: nil,
                isInteractive: true
            )

        case (.antigravity, .missing):
            return SetupFix(
                summary: "Install Antigravity",
                command: "brew install --cask antigravity-cli",
                url: URL(string: "https://antigravity.google/product/antigravity-cli")
            )

        case (.antigravity, .needsSignIn):
            return SetupFix(
                summary: "Sign in to Antigravity",
                command: AgentKind.antigravity.loginCommand,
                url: nil,
                isInteractive: true
            )

        case (.gitHub, .missing):
            return SetupFix(
                summary: "Install the GitHub CLI",
                command: "brew install gh",
                url: URL(string: "https://cli.github.com")
            )

        case (.gitHub, .needsSignIn):
            return SetupFix(
                summary: "Sign in to GitHub",
                command: "gh auth login",
                url: nil,
                isInteractive: true
            )

        case (.bitbucket, .missing):
            return SetupFix(
                summary: "Install the Bitbucket CLI",
                command: "brew install bitbucket-cli",
                url: URL(string: "https://github.com/avivsinai/bitbucket-cli")
            )

        case (.bitbucket, .needsSignIn):
            return SetupFix(
                summary: "Sign in to Bitbucket",
                command: "bkt auth login https://bitbucket.org --kind cloud --web",
                url: nil,
                isInteractive: true
            )
        }
    }
}
