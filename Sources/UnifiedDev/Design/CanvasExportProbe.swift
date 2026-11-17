import AppKit
import SwiftUI
import Core

#if DEBUG
@MainActor
enum CanvasExportProbe {
    static func run(in directory: String) -> [String] {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append("export: \(message)") }
        }
        let root = directory + "/export-probe"
        if let failure = ProbeFolder.failureToRenew(root) { return ["export: \(failure)"] }
        guard writeRed(to: root + "/red.png") else { return ["export: could not seed"] }
        let path = root + "/Spring Launch.udcanvas"
        let cover = CanvasFrame(id: CanvasFrameID("cover"), name: "Cover", rect: CanvasRect(x: 0, y: 0, width: 1_080, height: 1_080))
        let offer = CanvasFrame(id: CanvasFrameID("offer"), name: "Offer / 50%", rect: CanvasRect(x: 1_200, y: 0, width: 1_080, height: 1_350), fill: "#FFF4E0")
        let poster = CanvasFrame(id: CanvasFrameID("poster"), name: "Poster", rect: CanvasRect(x: 2_400, y: 0, width: 9_000, height: 100))
        let elements = [
            text("title", cover, x: 80, y: 80, "Spring launch", "Helvetica", 96),
            shape("box", cover, x: 600, y: 600, "#0000FF"),
            image("pic", cover, x: 80, y: 600),
            text("ghost", offer, x: 80, y: 80, "Missing face", "No Such Font Anywhere", 64),
            text("headline", offer, x: 80, y: 400, "Half price", "Helvetica", 120),
            image("lost", offer, x: 80, y: 900, file: "not-there.png"),
        ]
        var document = CanvasDocument(frames: [offer, poster, cover], elements: elements)
        guard (try? CanvasDocumentFile.write(document, to: path)) != nil else { return ["export: could not write the document"] }

        let model = CanvasDocumentModel(path: path, worktree: root)
        let mark = CanvasComment(
            id: CanvasCommentID("mark"), anchor: CanvasPoint(x: 700, y: 650), frameID: cover.id, text: "Check this",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        model.changeComments { current in
            var changed = current
            changed.comments = [mark]
            return changed
        }
        model.exportFrames()
        let beforeTyping = try? Data(contentsOf: URL(filePath: root + "/spring-launch.export/02-offer-50.png"))
        if case .document(let held) = model.document, let original = held.elements.first(where: { $0.id == CanvasElementID("headline") })?.text {
            var typed = original
            typed.runs[0].text = "Typed anew"
            model.startEditing(CanvasElementID("headline"), text: original)
            model.editing?.text = typed
        }
        model.exportFrames()
        check(model.editing == nil, "the text session was still open after exporting")
        let afterTyping = try? Data(contentsOf: URL(filePath: root + "/spring-launch.export/02-offer-50.png"))
        check(beforeTyping != nil && afterTyping != nil && beforeTyping != afterTyping, "text typed in the overlay is not in the picture")
        if case .document(let held) = model.document {
            check(held.elements.first { $0.id == CanvasElementID("headline") }?.text?.runs.first?.text == "Typed anew", "typed text was not committed")
        }

        let folder = root + "/spring-launch.export"
        let files = pictures(in: folder)
        check(files == ["01-cover.png", "02-offer-50.png"], "the folder holds \(files)")
        let coverPicture = bitmap(folder + "/01-cover.png")
        let offerPicture = bitmap(folder + "/02-offer-50.png")
        check(coverPicture.map { $0.pixelsWide == 1_080 && $0.pixelsHigh == 1_080 } == true, "Cover is not 1080 by 1080 pixels")
        check(offerPicture.map { $0.pixelsWide == 1_080 && $0.pixelsHigh == 1_350 } == true, "Offer is not 1080 by 1350 pixels")
        if let coverPicture {
            check(isNear(coverPicture, 660, 660, .blue), "the shape is missing from Cover")
            check(isNear(coverPicture, 120, 640, .red), "the picture is missing from Cover")
            check(isNear(coverPicture, 700, 650, .blue), "a comment mark is drawn over the shape")
        }
        if let offerPicture {
            check(hasInk(offerPicture, x: 80..<500, y: 400..<520), "the text typed last is missing from Offer")
            check(isNear(offerPicture, 1_070, 1_340, NSColor(red: 1, green: 0.957, blue: 0.878, alpha: 1)), "Offer lost its fill")
        }

        if let notice = model.exportNotice {
            check(notice.tone == .warning, "the notice is \(notice.tone), not a warning: \(notice.lines)")
            let said = ([notice.title] + notice.lines).joined(separator: "\n")
            check(said.contains("export-probe") == false && said.contains("spring-launch.export"), "the notice does not say where: \(said)")
            check(said.contains("Poster") && said.contains("9000 by 100"), "the notice does not name the frame left out")
            check(said.contains("No Such Font Anywhere"), "the notice does not name the missing font")
            check(said.contains("not-there.png"), "the notice does not name the missing picture")
        } else {
            failures.append("export: no notice")
        }

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let editor = CanvasEditorView(model: model, revision: 0, initialViewport: CanvasViewport(zoom: 0.3, offset: CanvasPoint(x: 40, y: 150)))
                .frame(width: 900, height: 700)
            failures += CanvasEditorProbe.shoot(editor, appearance: appearance, to: "\(directory)/export-notice-\(name).png")
        }

        if let notice = model.exportNotice {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let strip = NoticePiece(tone: notice.tone, onDismiss: {}) {
                    VStack(alignment: .leading, spacing: Metrics.spacingSmall) {
                        Text(verbatim: notice.title).font(Typo.labelEmphasis)
                        CanvasNoticeLines(notice: notice)
                    }
                }
                .frame(width: 900, height: 200, alignment: .top)
                failures += CanvasEditorProbe.shoot(strip, appearance: appearance, to: "\(directory)/export-strip-\(name).png", size: NSSize(width: 900, height: 200))
            }
        }

        let withMark = try? Data(contentsOf: URL(filePath: folder + "/01-cover.png"))
        model.changeComments { current in
            var changed = current
            changed.comments = []
            return changed
        }
        model.finishEditing()
        model.exportFrames()
        let without = try? Data(contentsOf: URL(filePath: folder + "/01-cover.png"))
        check(withMark != nil && withMark == without, "a comment changes the picture")

        try? FileManager.default.copyItem(atPath: folder + "/01-cover.png", toPath: directory + "/export-1080x1080.png")
        try? FileManager.default.copyItem(atPath: folder + "/02-offer-50.png", toPath: directory + "/export-1080x1350.png")
        document.frames.removeAll { $0.id == offer.id || $0.id == poster.id }
        failures += vectorImages(in: directory)
        failures += stale(root: root, folder: folder, document: document)
        failures += timing(in: directory)
        return failures
    }

    private static func vectorImages(in directory: String) -> [String] {
        var failures: [String] = []
        let root = directory + "/export-vectors"
        if let failure = ProbeFolder.failureToRenew(root) { return ["export: \(failure)"] }
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\"><rect width=\"100\" height=\"100\" fill=\"#00AA00\"/></svg>"
        try? svg.write(toFile: root + "/green.svg", atomically: true, encoding: .utf8)
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        if let context = CGContext(URL(filePath: root + "/magenta.pdf") as CFURL, mediaBox: &box, nil) {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.magenta.cgColor)
            context.fill(box)
            context.endPDFPage()
            context.closePDF()
        }
        try? Data("not a picture".utf8).write(to: URL(filePath: root + "/corrupt.png"))
        try? FileManager.default.createDirectory(atPath: root + "/folder.png", withIntermediateDirectories: true)
        let frame = CanvasFrame(id: CanvasFrameID("v"), name: "Vectors", rect: CanvasRect(x: 0, y: 0, width: 400, height: 200))
        let files = ["green.svg", "magenta.pdf", "corrupt.png", "folder.png"]
        let elements = files.enumerated().map { index, file in
            CanvasElement(
                id: CanvasElementID("i\(index)"), frameID: frame.id,
                rect: CanvasRect(x: Double(index) * 100, y: 50, width: 100, height: 100), kind: .image(path: file)
            )
        }
        let path = root + "/vectors.udcanvas"
        let document = CanvasDocument(frames: [frame], elements: elements)
        for file in ["green.svg", "magenta.pdf"] {
            let loaded = CanvasImageLoading.image(file, documentPath: path, worktree: root)
            if loaded == nil { failures.append("export: \(file) does not draw on screen") }
        }
        for file in ["corrupt.png", "folder.png"] where CanvasImageLoading.image(file, documentPath: path, worktree: root) != nil {
            failures.append("export: \(file) draws on screen")
        }
        guard let report = try? CanvasExporter.export(document: document, path: path, worktree: root) else { return failures + ["export: vectors did not export"] }
        if report.missingImages != ["corrupt.png", "folder.png"] { failures.append("export: named \(report.missingImages)") }
        let picture = (try? Data(contentsOf: URL(filePath: report.directory + "/01-vectors.png"))).flatMap { NSBitmapImageRep(data: $0) }
        try? FileManager.default.copyItem(atPath: report.directory + "/01-vectors.png", toPath: directory + "/export-vectors.png")
        if let picture {
            if !isGreen(picture, 50, 100) { failures.append("export: the SVG is not in the picture") }
            if !isNear(picture, 150, 100, .magenta) { failures.append("export: the PDF is not in the picture") }
        } else {
            failures.append("export: no vectors picture")
        }
        ProbeFolder.discard(URL(filePath: root, directoryHint: .isDirectory))
        return failures
    }

    private static func stale(root: String, folder: String, document: CanvasDocument) -> [String] {
        let path = root + "/Spring Launch.udcanvas"
        guard (try? CanvasDocumentFile.write(document, to: path)) != nil else { return ["export: could not rewrite"] }
        let model = CanvasDocumentModel(path: path, worktree: root)
        model.exportFrames()
        let files = pictures(in: folder)
        return files == ["01-cover.png"] ? [] : ["export: a deleted frame left \(files)"]
    }

    private static func pictures(in folder: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    private static func timing(in directory: String) -> [String] {
        let root = directory + "/export-timing"
        if let failure = ProbeFolder.failureToRenew(root) { return ["export: \(failure)"] }
        var frames: [CanvasFrame] = []
        var elements: [CanvasElement] = []
        for index in 0..<10 {
            let frame = CanvasFrame(
                id: CanvasFrameID("s\(index)"), name: "Slide \(index)", rect: CanvasRect(x: Double(index) * 1_200, y: 0, width: 1_080, height: 1_350)
            )
            frames.append(frame)
            elements.append(text("t\(index)", frame, x: 80, y: 100, "Slide \(index) headline", "Helvetica", 96))
            elements.append(text("b\(index)", frame, x: 80, y: 400, "Body copy for the slide, long enough to wrap onto a few lines of the frame.", "Helvetica", 48))
            elements.append(shape("x\(index)", frame, x: 600, y: 800, "#FF3366"))
        }
        let document = CanvasDocument(frames: frames, elements: elements)
        let path = root + "/deck.udcanvas"
        let clock = ContinuousClock()
        var report: CanvasExportReport?
        let elapsed = clock.measure { report = try? CanvasExporter.export(document: document, path: path, worktree: root) }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        try? "ten 1080 by 1350 frames: \(seconds) seconds on the main actor, \(report?.written.count ?? 0) written\n"
            .write(toFile: directory + "/export-timing.txt", atomically: true, encoding: .utf8)
        let big = CanvasFrame(id: CanvasFrameID("big"), name: "Big", rect: CanvasRect(x: 0, y: 0, width: 8_192, height: 8_192))
        let bigDocument = CanvasDocument(frames: [big], elements: [text("bt", big, x: 80, y: 100, "Big", "Helvetica", 400)])
        var bigReport: CanvasExportReport?
        let bigElapsed = clock.measure { bigReport = try? CanvasExporter.export(document: bigDocument, path: root + "/big.udcanvas", worktree: root) }
        let bigSeconds = Double(bigElapsed.components.seconds) + Double(bigElapsed.components.attoseconds) / 1e18
        let line = "one 8192 by 8192 frame: \(bigSeconds) seconds, \(bigReport?.written.count ?? 0) written\n"
        if let handle = FileHandle(forWritingAtPath: directory + "/export-timing.txt") {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        }
        ProbeFolder.discard(URL(filePath: root, directoryHint: .isDirectory))
        return report?.written.count == 10 ? [] : ["export: the timing deck wrote \(report?.written.count ?? 0)"]
    }

    private static func text(_ id: String, _ frame: CanvasFrame, x: Double, y: Double, _ string: String, _ font: String, _ size: Double) -> CanvasElement {
        CanvasElement(
            id: CanvasElementID(id), frameID: frame.id, rect: CanvasRect(x: x, y: y, width: 920, height: size * 1.4),
            kind: .text(CanvasText(runs: [CanvasTextRun(text: string, fontName: font, size: size, weight: 700, colour: "#000000")]))
        )
    }

    private static func shape(_ id: String, _ frame: CanvasFrame, x: Double, y: Double, _ fill: String) -> CanvasElement {
        CanvasElement(
            id: CanvasElementID(id), frameID: frame.id, rect: CanvasRect(x: x, y: y, width: 200, height: 200),
            style: CanvasStyle(fill: fill), kind: .shape(CanvasShape(kind: .rectangle))
        )
    }

    private static func image(_ id: String, _ frame: CanvasFrame, x: Double, y: Double, file: String = "red.png") -> CanvasElement {
        CanvasElement(id: CanvasElementID(id), frameID: frame.id, rect: CanvasRect(x: x, y: y, width: 200, height: 200), kind: .image(path: file))
    }

    private static func bitmap(_ path: String) -> NSBitmapImageRep? {
        (try? Data(contentsOf: URL(filePath: path))).flatMap { NSBitmapImageRep(data: $0) }
    }

    private static func writeRed(to path: String) -> Bool {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(filePath: path))) != nil
    }

    private static func isNear(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int, _ expected: NSColor) -> Bool {
        guard let actual = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.genericRGB),
              let wanted = expected.usingColorSpace(.genericRGB) else { return false }
        return abs(actual.redComponent - wanted.redComponent) < 0.08
            && abs(actual.greenComponent - wanted.greenComponent) < 0.08
            && abs(actual.blueComponent - wanted.blueComponent) < 0.08
    }

    private static func isGreen(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> Bool {
        guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.genericRGB) else { return false }
        return colour.greenComponent > 0.5 && colour.redComponent < 0.25 && colour.blueComponent < 0.25
    }

    private static func hasInk(_ bitmap: NSBitmapImageRep, x: Range<Int>, y: Range<Int>) -> Bool {
        for row in y {
            for column in x where !isNear(bitmap, column, row, NSColor(red: 1, green: 0.957, blue: 0.878, alpha: 1)) { return true }
        }
        return false
    }
}
#endif
