import SwiftUI
import Core

nonisolated let markdownChromeSpace = "markdownChrome"

struct MarkdownCodeHeader: View {
    var code: String
    var language: Language
    var command: String?
    var canRun: Bool
    var actions: TranscriptLinkActions
    var onControls: (CGRect) -> Void

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            Text(Self.displayName(for: language))
                .font(Typo.caption)
                .foregroundStyle(Palette.textTertiary)
            Spacer(minLength: MarkdownMetrics.blockGap)
            HStack(spacing: Metrics.spacing) {
                if let command, canRun, let run = actions.runCommand {
                    CodeBlockRunButtons(
                        command: command,
                        isRunning: actions.commandRun(command)?.isRunning == true,
                        run: run,
                        stop: actions.stopCommand
                    )
                }
                CopyButton(text: code, title: "Copy code", size: MarkdownMetrics.iconButton)
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(markdownChromeSpace)) }, action: onControls)
        }
        .padding(.horizontal, MarkdownMetrics.blockGap)
        .padding(.vertical, Metrics.spacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(.named(markdownChromeSpace))
    }

    private static func displayName(for language: Language) -> String {
        switch language {
        case .plainText: "Plain text"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .html: "HTML"
        case .css: "CSS"
        case .json: "JSON"
        case .yaml: "YAML"
        case .toml: "TOML"
        case .sql: "SQL"
        case .xml: "XML"
        case .php: "PHP"
        default: language.rawValue.capitalized
        }
    }
}

struct MarkdownCodeFooter: View {
    var lines: Int
    var foldsLines: Bool
    var isExpanded: Bool
    var command: String?
    var actions: TranscriptLinkActions
    var onToggle: () -> Void
    var onHeight: (CGFloat) -> Void
    var onControls: (CGRect) -> Void
    var onOutput: (CGRect) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if foldsLines {
                Button(TextFold.title(isExpanded: isExpanded, lines: lines), action: onToggle)
                    .linkButton()
                    .font(Typo.caption)
                    .padding(.horizontal, MarkdownMetrics.blockGap)
                    .padding(.vertical, Metrics.spacing)
            }
            if let run = command.flatMap(actions.commandRun) {
                CodeBlockRunStatus(run: run, onOutput: onOutput)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height, action: onHeight)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(markdownChromeSpace)) }, action: onControls)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(.named(markdownChromeSpace))
    }
}
