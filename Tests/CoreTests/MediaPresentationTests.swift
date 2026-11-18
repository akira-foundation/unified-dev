import Testing
@testable import Core

@Suite("Media presentation")
struct MediaPresentationTests {
    @Test("A PDF is read page by page, not as one picture", arguments: [
        "docs/report.pdf", "/Users/someone/Desktop/Report.PDF", "three pages.pdf",
    ])
    func pdfIsPaged(path: String) {
        #expect(MediaPresentation.of(path: path) == .pages)
    }

    @Test("Pictures, sound, video, archives and fonts are drawn as a still", arguments: [
        "shot.png", "photo.jpeg", "clip.mov", "song.mp3", "bundle.zip", "Inter.ttf",
    ])
    func othersAreStills(path: String) {
        #expect(MediaPresentation.of(path: path) == .still)
    }

    @Test("Text, source and files with no known type are not media", arguments: [
        "README.md", "main.swift", "notes.txt", "page.html", "data.json", "Makefile", "",
    ])
    func textIsNotMedia(path: String) {
        #expect(MediaPresentation.of(path: path) == nil)
    }

    @Test("An image that is text, like SVG, is read as text")
    func svgIsText() {
        #expect(MediaPresentation.of(path: "icon.svg") == nil)
    }
}

@Suite("Media display")
struct MediaDisplayTests {
    @Test("A PDF waits for its pages to be counted before anything is drawn")
    func pdfWaitsForCount() {
        #expect(MediaDisplay.of(path: "report.pdf", pageCount: nil, hasCounted: false) == .counting)
    }

    @Test("A PDF with pages scrolls through all of them")
    func pdfWithPagesScrolls() {
        #expect(MediaDisplay.of(path: "report.pdf", pageCount: 3, hasCounted: true) == .pages)
    }

    @Test("A PDF with no readable pages falls back to the still and its note")
    func unreadablePdfIsStill() {
        #expect(MediaDisplay.of(path: "report.pdf", pageCount: nil, hasCounted: true) == .still)
    }

    @Test("Anything else is a still, whatever was counted", arguments: [false, true])
    func otherMediaIsStill(hasCounted: Bool) {
        #expect(MediaDisplay.of(path: "shot.png", pageCount: nil, hasCounted: hasCounted) == .still)
    }
}
