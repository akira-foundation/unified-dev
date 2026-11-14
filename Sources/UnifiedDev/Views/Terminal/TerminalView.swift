import SwiftUI
import AppKit
import SwiftTerm
import Core

struct TerminalLaunch: Sendable, Hashable {
    var executable: String
    var execName: String
    var arguments: [String]
    var environment: [String]
    var directory: String

    static func loginShell(directory: String, extra: [String: String]) -> TerminalLaunch {
        let shell = LoginShell.path()

        let variables = Shell.terminalEnvironment(inheriting: Shell.environment(), extra: extra)

        return TerminalLaunch(
            executable: shell,
            execName: LoginShell.argumentZero(for: shell),
            arguments: [],
            environment: variables.map { "\($0.key)=\($0.value)" }.sorted(),
            directory: directory
        )
    }

    static func tmux(
        command: TmuxCommand,
        session: String,
        directory: String,
        extra: [String: String]
    ) -> TerminalLaunch {
        let variables = Shell.terminalEnvironment(inheriting: Shell.environment())

        var sessionVariables = extra
        sessionVariables["COLORTERM"] = "truecolor"
        sessionVariables["TERM_PROGRAM"] = "Unified Dev"

        return TerminalLaunch(
            executable: command.executable,
            execName: "tmux",
            arguments: command.attachOrCreate(
                session: session, directory: directory, environment: sessionVariables
            ),
            environment: variables.map { "\($0.key)=\($0.value)" }.sorted(),
            directory: directory
        )
    }
}

final class AppTerminalView: LocalProcessTerminalView {
    private(set) var hasExited = false

    private var isStopping = false

    var onFocus: (@MainActor () -> Void)?

    var onExit: (@MainActor (TerminalExit) -> Void)?

    var onCommand: (@MainActor (TerminalPaneCommand) -> Bool)?

    var onContextMenu: (@MainActor () -> NSMenu?)?

    var onOpenLink: (@MainActor (URL, Bool) -> Bool)?

    private let processObserver = TerminalProcessObserver()

    var usesGhosttyTheme = true {
        didSet {
            guard usesGhosttyTheme != oldValue else { return }
            applyFont()
            applyAppearanceColors()
        }
    }

    var fontSizeOverride: CGFloat? {
        didSet {
            guard fontSizeOverride != oldValue else { return }
            applyFont()
        }
    }

    var fontSize: CGFloat { fontSizeOverride ?? defaultFontSize }

    private var defaultFontSize: CGFloat {
        ghostty?.fontSize.map { CGFloat($0) } ?? TerminalTextSize.systemDefault
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        processObserver.owner = self
        processDelegate = processObserver
        applyFont()
        applyAppearanceColors()
    }

    private func applyFont() {
        font = terminalFont(size: fontSize)
    }

    private func terminalFont(size: CGFloat) -> NSFont {
        TerminalGhostty.font(family: ghostty?.fontFamily, size: size)
    }

    private(set) var hasStarted = false
    private var displayedOutput = ""

    func showOutput(_ text: String) {
        guard !hasStarted, text != displayedOutput else { return }
        let addition: String
        if text.hasPrefix(displayedOutput) {
            addition = String(text.dropFirst(displayedOutput.count))
        } else {
            clearScreen()
            addition = text
        }
        feed(text: addition.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n"))
        displayedOutput = text
    }

    func start(_ launch: TerminalLaunch) {
        guard !process.running else { return }
        hasExited = false
        hasStarted = true
        displayedOutput = ""
        startProcess(
            executable: launch.executable,
            args: launch.arguments,
            environment: launch.environment,
            execName: launch.execName,
            currentDirectory: launch.directory
        )
    }

    func willStop() {
        isStopping = true
    }

    func shutdown() {
        isStopping = true
        guard process.running else { return }
        terminate()
    }

    fileprivate func handleProcessExit(_ status: Int32?) {
        guard !hasExited else { return }
        hasExited = true
        guard !isStopping else { return }

        let exit = TerminalExit(waitStatus: status)
        if !exit.closesPane {
            feed(text: "\r\n\u{1b}[2m\(exit.paneMessage)\u{1b}[0m\r\n")
        }
        onExit?(exit)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onFocus?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onFocus?()
        return onContextMenu?() ?? super.menu(for: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard onContextMenu != nil, let menu = menu(for: event) else {
            super.rightMouseDown(with: event)
            return
        }
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }

    override func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        guard !hasExited else { return }
        super.send(source: source, data: data)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        applyAppearanceColors()
    }

    private var ghostty: GhosttyTheme? {
        usesGhosttyTheme ? TerminalGhostty.theme(for: effectiveAppearance) : nil
    }

    func applyAppearanceColors() {
        if let ghostty {
            applyGhosttyColors(ghostty)
        } else {
            applyAppColors()
        }
        needsDisplay = true
    }

    private func applyGhosttyColors(_ theme: GhosttyTheme) {
        installColors(theme.ansiColors().map(SwiftTerm.Color.init))

        let foreground = theme.foreground.map(NSColor.init)
        let background = theme.background.map(NSColor.init)
        nativeForegroundColor = foreground ?? resolved(Palette.textPrimary).withAlphaComponent(1)
        nativeBackgroundColor = background ?? resolved(Palette.surfaceSunken)
        caretColor = theme.cursorColor.map(NSColor.init) ?? foreground ?? .textInsertionPointColor
        if let cursorText = theme.cursorTextColor {
            caretTextColor = NSColor(cursorText)
        }
        selectedTextBackgroundColor = theme.selectionBackground.map(NSColor.init)
            ?? .selectedTextBackgroundColor
        if let selectionForeground = theme.selectionForeground {
            selectedTextForegroundColor = NSColor(selectionForeground)
        }
    }

    private func applyAppColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        installColors(TerminalPalette.colours(dark: isDark).map(SwiftTerm.Color.init(rgb:)))
        nativeForegroundColor = resolved(Palette.textPrimary).withAlphaComponent(1)
        nativeBackgroundColor = .clear
        caretColor = .textInsertionPointColor
        selectedTextBackgroundColor = .selectedTextBackgroundColor
    }

    private func resolved(_ color: SwiftUI.Color) -> NSColor {
        var native = NSColor(color)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            native = NSColor(color).usingColorSpace(.sRGB) ?? native
        }
        return native
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control),
              window?.firstResponder === self,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        if let command = TerminalPaneCommand(key: key, modifiers: event.modifierFlags),
           onCommand?(command) == true {
            return true
        }

        let shift = event.modifierFlags.contains(.shift)
        guard !event.modifierFlags.contains(.option) else {
            return super.performKeyEquivalent(with: event)
        }

        if let input = TerminalEditingShortcut.input(
            key: key,
            isPlainCommand: !shift,
            usesEnhancedKeyboard: !getTerminal().keyboardEnhancementFlags.isEmpty
        ) {
            switch input {
            case .text(let text): send(txt: text)
            case .keyEvent: keyDown(with: event)
            }
            return true
        }

        switch key {
        case "k" where !shift:
            clearScreen()
        case "c" where !shift:
            copy(self)
        case "v" where !shift:
            paste(self)
        case "+", "=":
            TerminalTextSize.adjust(from: fontSize, by: TerminalTextSize.step)
        case "-":
            TerminalTextSize.adjust(from: fontSize, by: -TerminalTextSize.step)
        case "0":
            TerminalTextSize.override = nil
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link), onOpenLink?(url, NSEvent.modifierFlags.contains(.shift)) == true { return }
        super.requestOpenLink(source: source, link: link, params: params)
    }

    func clearScreen() {
        getTerminal().clearScrollback()
        feed(text: "\u{1b}[3J\u{1b}[H\u{1b}[2J")
        if process.running { send(txt: "\u{0C}") }
        needsDisplay = true
    }
}

private final class TerminalProcessObserver: LocalProcessTerminalViewDelegate {
    weak var owner: AppTerminalView?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
        let terminal = owner
        hopToMain {
            terminal?.handleProcessExit(exitCode)
        }
    }
}

final class TerminalHostView: NSView {
    private weak var terminal: AppTerminalView?

    var isFocusedPane = true

    var focusRequest = 0 {
        didSet {
            guard oldValue != focusRequest, isFocusedPane else { return }
            takeKeyboard()
        }
    }

    func attach(_ view: AppTerminalView) {
        guard terminal !== view || view.superview !== self else { return }
        terminal?.removeFromSuperview()
        view.removeFromSuperview()
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        terminal = view
        view.applyAppearanceColors()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        terminal?.frame = bounds
    }

    private func takeKeyboard() {
        guard isFocusedPane, let terminal, let window, window.firstResponder !== terminal,
              AutomaticFocus.mayUpdateResponder(applicationIsActive: NSApp.isActive,
                                                windowIsKey: window.isKeyWindow,
                                                windowIsVisible: window.isVisible) else { return }
        window.makeFirstResponder(terminal)
    }
}

struct TerminalView: NSViewRepresentable {
    var tab: TerminalTab
    var workspace: Workspace
    var repo: Repo?
    var port: Int
    var directory: String = ""
    var output: String?

    var isFocusedPane = true
    var focusRequest = 0
    var onFocus: (@MainActor () -> Void)?
    var onCommand: (@MainActor (TerminalPaneCommand) -> Bool)?
    var onExit: (@MainActor (TerminalExit) -> Void)?
    var onContextMenu: (@MainActor () -> NSMenu?)?
    var onOpenLink: (@MainActor (URL, Bool) -> Bool)?

    @AppStorage(TerminalGhostty.defaultsKey) private var usesGhosttyTheme = true

    @AppStorage(TerminalTextSize.defaultsKey) private var fontSize = 0.0

    func makeNSView(context: Context) -> TerminalHostView {
        let host = TerminalHostView()
        configure(host)
        return host
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        configure(nsView)
    }

    private func configure(_ host: TerminalHostView) {
        let session = self.session
        host.attach(session)
        session.usesGhosttyTheme = usesGhosttyTheme
        session.fontSizeOverride = fontSize > 0 ? CGFloat(fontSize) : nil
        session.onFocus = onFocus
        session.onCommand = onCommand
        session.onContextMenu = onContextMenu
        session.onOpenLink = onOpenLink
        session.onExit = onExit
        host.isFocusedPane = output == nil && isFocusedPane
        host.focusRequest = focusRequest
    }

    @MainActor private var session: AppTerminalView {
        TerminalSessionStore.shared.terminal(
            for: tab, workspace: workspace, repo: repo, port: port, directory: directory, output: output
        )
    }
}
