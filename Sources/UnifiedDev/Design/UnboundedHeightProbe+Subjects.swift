import AppKit
import Core
import SwiftUI

extension UnboundedHeightProbe {
    struct Staging {
        var app: AppModel
        var workspace: Workspace?
        var session: Session?
    }

    @ViewBuilder
    static func view(
        for subject: UnboundedHeightSubject, in staging: Staging, saying text: String
    ) -> some View {
        switch subject.key {
        case "inspector-notice":
            InspectorNotice(
                notice: PullRequestNotice(
                    tone: .failure,
                    title: text,
                    message: text,
                    details: nil
                ),
                onDismiss: {}
            )
        case "agent-question-option":
            AgentQuestionCard(ask: longAsk(saying: text), decision: nil, answers: [:], isExpanded: true)
        case "attachment-comment":
            AttachmentCard(
                attachment: PromptAttachment(
                    path: "notes/the-comment.txt",
                    isCopy: false,
                    imageComment: BrowserImageComment(
                        body: text,
                        address: "https://example.com/"
                    )
                ),
                worktree: NSTemporaryDirectory(),
                availableWidth: HoverCardWidth.ceiling
            )
        case "browser-capture-comment":
            browserCapture(in: staging, saying: text)
        case "start-project-consequence":
            StartProjectConsequenceBlock(
                said: ProjectConsequence(
                    lead: text,
                    detail: text,
                    tone: .caution
                ),
                home: NSHomeDirectory()
            )
        case "quick-prompt-toggle":
            QuickPromptFormStand(text: text)
        case "prompt-settings-title":
            PromptSettingsView()
        case "notifications-blocked":
            NotificationSettingsView().environment(staging.app)
        case "approval-provenance":
            ApprovalSettingsStand().environment(staging.app)
        case "menu-bar-provider-note":
            MenuBarProviderModule(
                provider: .init(kind: .claudeCode, reading: .unavailable, note: text),
                plan: nil,
                options: UsageDisplayOptions(),
                now: Date(),
                retry: {},
                toggleFold: {}
            )
        case "welcome-command":
            WelcomeCommandStand(text: text)
        case "workspace-hover-title":
            WorkspaceHoverCardView(card: longHoverCard(saying: text))
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private static func browserCapture(in staging: Staging, saying text: String) -> some View {
        if let capture = longCapture(in: staging, saying: text), let workspace = staging.workspace {
            BrowserRegionCaptureView(
                capture: capture,
                model: staging.app.model(for: workspace),
                viewportFrame: CGRect(x: 0, y: 0, width: 900, height: 600),
                add: {}
            )
        } else {
            EmptyView()
        }
    }

    private static func longCapture(in staging: Staging, saying text: String) -> BrowserRegionCapture? {
        guard let session = staging.session, let data = flatImage(),
              let capture = try? BrowserRegionCapture(
                  data: data, address: "https://example.com/", session: session
              )
        else { return nil }
        let note = BrowserRegionComment(
            path: "captures/region.png",
            selection: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.3),
            address: "https://example.com/",
            body: text
        )
        capture.comments = [note]
        capture.focusedCommentPath = note.id
        return capture
    }

    static func flatImage() -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 32, bitsPerPixel: 32
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.gray.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func longAsk(saying text: String) -> PermissionAsk {
        PermissionAsk(
            requestID: "unbounded-height",
            toolName: AgentQuestionnaire.toolName,
            toolUseID: "toolu_unbounded_height",
            input: .object(["questions": .array([
                .object([
                    "question": .string(text),
                    "header": .string("Storage"),
                    "multiSelect": .bool(false),
                    "unifieddevAnswerID": .string("q1"),
                    "options": .array([
                        .object([
                            "label": .string(text),
                            "description": .string(text),
                        ]),
                        .object([
                            "label": .string("SQLite"),
                            "description": .string("One file beside the worktree."),
                        ]),
                    ]),
                ]),
            ])])
        )
    }

    private static func longHoverCard(saying text: String) -> WorkspaceHoverCard {
        WorkspaceHoverCard(
            title: text,
            branch: "unbounded-height",
            diff: WorkspaceHoverCard.Diff(additions: 120, deletions: 4),
            status: .running,
            state: "Idle",
            detail: text,
            age: "2m"
        )
    }
}

private struct QuickPromptFormStand: View {
    let text: String

    @State private var draft = QuickPromptFormDraft()

    var body: some View {
        QuickPromptForm(draft: $draft, onCancel: {}, onSave: { _ in }, onDelete: {})
            .task { draft.name = text }
    }
}

private struct ApprovalSettingsStand: View {
    @State private var defaults = AppDefaults()

    var body: some View {
        ApprovalSettingsView(defaults: $defaults, isReady: true)
    }
}

private struct WelcomeCommandStand: View {
    let text: String

    var body: some View {
        WelcomeCheckDetailStep(
            subject: WelcomeCheckSubject(
                tool: .gitHub,
                fix: SetupFix(
                    summary: text,
                    command: text,
                    isInteractive: true
                )
            ),
            session: nil,
            footer: WelcomeFooter(
                backTitle: OnboardingFlow.backTitle,
                forwardTitle: OnboardingFlow.forwardTitle,
                progress: OnboardingProgress(position: 2, count: 4),
                canGoBack: true,
                back: {},
                forward: {}
            )
        )
    }
}
