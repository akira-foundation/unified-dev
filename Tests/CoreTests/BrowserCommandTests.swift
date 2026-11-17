import Testing
@testable import Core

@Suite("Browser commands")
struct BrowserCommandTests {
    private static func state(
        address: String = "http://localhost:3100/",
        canGoBack: Bool = true,
        canGoForward: Bool = true,
        isLoading: Bool = false,
        isCapturing: Bool = false,
        isViewportOn: Bool = false,
        isReviewing: Bool = false,
        isSaving: Bool = false,
        isEditingComment: Bool = false
    ) -> BrowserPaneState {
        var viewport = BrowserViewport()
        viewport.isEnabled = isViewportOn
        return BrowserPaneState(
            toolbar: BrowserToolbar(
                page: BrowserTabTitle.BrowserPage(address: address, title: ""),
                canGoBack: canGoBack,
                canGoForward: canGoForward,
                isLoading: isLoading,
                isCapturing: isCapturing
            ),
            viewport: viewport,
            isReviewing: isReviewing,
            isSaving: isSaving,
            isEditingComment: isEditingComment
        )
    }

    @Test("every tooltip names the key its menu row answers to", arguments: BrowserCommand.allCases)
    func tooltipNamesTheKey(command: BrowserCommand) throws {
        let key = try #require(MenuBarCatalogue[command.menuAction].key)
        #expect(Self.state().control(for: command).help.hasSuffix("(\(key.display))"))
    }

    @Test("the other face of a control names the same key")
    func secondFaceKeepsTheKey() throws {
        let reload = try #require(MenuBarCatalogue[.browserReload].key)
        let comment = try #require(MenuBarCatalogue[.browserComment].key)
        let viewport = try #require(MenuBarCatalogue[.browserResponsivePreview].key)
        #expect(Self.state(isLoading: true).control(for: .reload).help.hasSuffix("(\(reload.display))"))
        #expect(Self.state(isReviewing: true).control(for: .comment).help.hasSuffix("(\(comment.display))"))
        #expect(Self.state(isViewportOn: true).control(for: .responsivePreview).help.hasSuffix("(\(viewport.display))"))
    }

    @Test("the key follows the sentence rather than replacing it")
    func tooltipKeepsItsSentence() {
        #expect(Self.state().control(for: .reload).help == "Reload this page (\u{2318}R)")
        #expect(Self.state(isLoading: true).control(for: .reload).help == "Stop loading this page (\u{2318}R)")
    }

    @Test("Share is the one control with no key")
    func shareHasNoKey() {
        #expect(Self.state().toolbar.share.help == "Share this page")
    }

    @Test("the keys are the ones agreed with the owner")
    func theKeys() {
        let expected: [BrowserCommand: MenuShortcut] = [
            .back: MenuShortcut("[", .command),
            .forward: MenuShortcut("]", .command),
            .reload: MenuShortcut("r", .command),
            .responsivePreview: MenuShortcut("r", .command, .option),
            .fullSize: MenuShortcut("0", .command, .option, .shift),
            .screenshot: MenuShortcut("s", .command, .option),
            .comment: MenuShortcut("c", .command, .option),
            .openInDefaultBrowser: MenuShortcut("o", .command, .option)
        ]
        for command in BrowserCommand.allCases {
            #expect(MenuBarCatalogue[command.menuAction].key == expected[command], "\(command)")
        }
    }

    @Test("back and forward share the file history row, every other command has its own")
    func menuRows() {
        #expect(BrowserCommand.back.menuAction == .fileBack)
        #expect(BrowserCommand.forward.menuAction == .fileForward)
        #expect(Set(BrowserCommand.menuRows) == Set(BrowserCommand.allCases).subtracting([.back, .forward]))
    }

    @Test("a review holds everything that would move the page under it", arguments: [
        BrowserCommand.back, .forward, .reload, .responsivePreview, .fullSize
    ])
    func reviewHoldsThePage(command: BrowserCommand) {
        let quiet = Self.state(isViewportOn: true)
        #expect(quiet.isEnabled(command))
        #expect(!Self.state(isViewportOn: true, isReviewing: true).isEnabled(command))
    }

    @Test("a review can still be finished and the page still opened elsewhere")
    func reviewLeavesItsWayOut() {
        let reviewing = Self.state(isCapturing: true, isReviewing: true)
        #expect(reviewing.isEnabled(.comment))
        #expect(reviewing.isEnabled(.openInDefaultBrowser))
        #expect(!reviewing.isEnabled(.screenshot))
    }

    @Test("a review being saved cannot be finished by the key")
    func savingHoldsTheKey() {
        #expect(!Self.state(isReviewing: true, isSaving: true).isEnabled(.comment))
    }

    @Test("the key cannot throw away a comment being typed")
    func editingHoldsTheKey() {
        #expect(!Self.state(isReviewing: true, isEditingComment: true).isEnabled(.comment))
        #expect(Self.state(isReviewing: true, isEditingComment: true).control(for: .comment).isEnabled)
    }

    @Test("a review holds the screenshot by itself, with no capture in flight")
    func reviewHoldsTheScreenshot() {
        #expect(Self.state().isEnabled(.screenshot))
        #expect(!Self.state(isReviewing: true).isEnabled(.screenshot))
    }

    @Test("the menu row and the page menu call the area comment by one name")
    func commentHasOneName() {
        #expect(MenuBarCatalogue[.browserComment].title == BrowserToolbar().regionCapture.name)
    }

    @Test("the shared history rows read as page history on a browser pane")
    func historyWording() {
        #expect(MenuBarCatalogue[.fileBack].alternateTitle == "Go Back")
        #expect(MenuBarCatalogue[.fileForward].alternateTitle == "Go Forward")
        #expect(Self.state().usesAlternateTitle(.back))
        #expect(Self.state().usesAlternateTitle(.forward))
    }

    @Test("a key follows its button: no history, no page, nothing to restore")
    func keysFollowTheButtons() {
        #expect(!Self.state(canGoBack: false).isEnabled(.back))
        #expect(!Self.state(canGoForward: false).isEnabled(.forward))
        #expect(!Self.state(address: "").isEnabled(.reload))
        #expect(!Self.state(address: "").isEnabled(.screenshot))
        #expect(!Self.state(address: "").isEnabled(.comment))
        #expect(!Self.state(isViewportOn: false).isEnabled(.fullSize))
        #expect(Self.state(address: "").isEnabled(.responsivePreview))
    }

    @Test("the menu row is worded for what the key would do now")
    func alternateWording() {
        #expect(Self.state(isLoading: true).usesAlternateTitle(.reload))
        #expect(!Self.state().usesAlternateTitle(.reload))
        #expect(Self.state(isReviewing: true).usesAlternateTitle(.comment))
        #expect(!Self.state().usesAlternateTitle(.comment))
        #expect(!Self.state(isReviewing: true).usesAlternateTitle(.reload))
        #expect(!Self.state(isLoading: true).usesAlternateTitle(.comment))
        #expect(!Self.state(isLoading: true, isReviewing: true).usesAlternateTitle(.screenshot))
    }
}
