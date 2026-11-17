import ImageIO
import AppKit
import SwiftUI
import Core

#if DEBUG
@MainActor
enum CanvasImageProbe {
    private static let frame = CanvasFrame(id: CanvasFrameID("f"), name: "Pictures", rect: CanvasRect(x: 0, y: 0, width: 400, height: 200))

    static func run(in directory: String) -> [String] {
        let root = directory + "/image-probe"
        if let failure = ProbeFolder.failureToRenew(root) { return ["images: \(failure)"] }
        var failures: [String] = []
        failures += aPictureIsWhole(root: root)
        failures += picturesReachTheScreen(root: root)
        failures += fiftyElementsDoNotStall(root: root)
        failures += playbackDrawsAPictureSharp(root: root)
        failures += aRenderOverItsCapDrawsAndNamesAPlaceholder(root: root)
        ProbeFolder.discard(URL(filePath: root, directoryHint: .isDirectory))
        return failures
    }

    private static func aPictureIsWhole(root: String) -> [String] {
        guard write(red: root + "/fresh.png", side: 64) else { return ["images: could not write the picture"] }
        let path = root + "/doc.udcanvas"
        let document = CanvasDocument(frames: [frame], elements: [element("fresh", x: 0, file: "fresh.png", size: 100)])
        guard let png = CanvasFrameRenderer.png(frame: frame, document: document, documentPath: path, worktree: root),
              let picture = NSBitmapImageRep(data: png) else { return ["images: no picture was rendered"] }
        return isRed(picture, 50, 50) ? [] : ["images: an exported picture holds the placeholder and not the image"]
    }

    private static func picturesReachTheScreen(root: String) -> [String] {
        guard write(red: root + "/red.png", side: 64) else { return ["images: could not write the picture"] }
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
        let elements = [
            element("r", x: 0, file: "red.png", size: 100),
            element("g", x: 100, file: "green.svg", size: 100),
            element("m", x: 200, file: "magenta.pdf", size: 100),
            element("n", x: 300, file: "not-there.png", size: 100),
        ]
        let view = CanvasFrameView(frame: frame, elements: elements, worktree: root, documentPath: root + "/doc.udcanvas")
        let shot = root + "/screen.png"
        let shootFailures = CanvasEditorProbe.shoot(view, appearance: .aqua, to: shot, size: NSSize(width: 400, height: 200))
        guard shootFailures.isEmpty, let data = try? Data(contentsOf: URL(filePath: shot)), let picture = NSBitmapImageRep(data: data) else {
            return shootFailures + ["images: no screen picture"]
        }
        var failures: [String] = []
        let ratio = picture.pixelsWide / 400
        if !isRed(picture, 50 * ratio, 100 * ratio) { failures.append("images: the PNG did not reach the screen") }
        if !isColour(picture, 150 * ratio, 100 * ratio, { $1 > 0.5 && $0 < 0.45 && $2 < 0.4 }) { failures.append("images: the SVG did not reach the screen") }
        if !isColour(picture, 250 * ratio, 100 * ratio, { $0 > 0.7 && $2 > 0.7 && $1 < 0.4 }) { failures.append("images: the PDF did not reach the screen") }
        return failures
    }

    private static func fiftyElementsDoNotStall(root: String) -> [String] {
        guard write(red: root + "/huge.png", side: 10_000) else { return ["images: could not write the huge picture"] }
        let path = root + "/doc.udcanvas"
        let wide = CanvasFrame(id: CanvasFrameID("w"), name: "Wide", rect: CanvasRect(x: 0, y: 0, width: 1_000, height: 200))
        let elements = (0..<50).map { element("h\($0)", frame: wide, x: Double($0) * 20, file: "huge.png", size: 20) }
        let clock = ContinuousClock()
        let view = CanvasFrameView(frame: wide, elements: elements, worktree: root, documentPath: path)
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.borderless]
        window.setContentSize(NSSize(width: 1_000, height: 200))
        window.setFrameOrigin(NSPoint(x: -9_000, y: -9_000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let firstDraw = clock.measure {
            controller.view.layoutSubtreeIfNeeded()
            if let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) {
                controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
            }
        }
        var longestTurn = Duration.zero
        var arrived: Duration?
        let start = clock.now
        while arrived == nil, clock.now - start < .seconds(60) {
            let turn = clock.measure { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
            longestTurn = max(longestTurn, turn)
            controller.view.layoutSubtreeIfNeeded()
            guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else { continue }
            controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
            let ratio = bitmap.pixelsWide / 1_000
            if isRed(bitmap, 990 * ratio, 60 * ratio) { arrived = clock.now - start }
        }
        let synchronous = clock.measure {
            _ = CanvasFrameRenderer.png(frame: wide, document: CanvasDocument(frames: [wide], elements: elements), documentPath: path, worktree: root)
        }
        print("MEASURE fifty elements on a 100 MP picture: first draw \(firstDraw), longest run loop turn \(longestTurn), arrived \(arrived.map(String.init(describing:)) ?? "never"), one export render \(synchronous)")
        var failures: [String] = []
        if arrived == nil { failures.append("images: the huge picture never reached the screen") }
        if firstDraw > .seconds(1) { failures.append("images: the first draw took \(firstDraw)") }
        if longestTurn > .seconds(1) { failures.append("images: the main actor stalled for \(longestTurn)") }
        return failures
    }

    private static func aRenderOverItsCapDrawsAndNamesAPlaceholder(root: String) -> [String] {
        guard write(red: root + "/first.png", side: 1_024), write(red: root + "/second.png", side: 1_024) else {
            return ["images: could not write the capped pictures"]
        }
        let document = CanvasDocument(frames: [frame], elements: [
            element("first", x: 0, file: "first.png", size: 100), element("second", x: 200, file: "second.png", size: 100),
        ])
        let picture = CanvasFrameRenderer.picture(
            frame: frame, document: document, documentPath: root + "/doc.udcanvas", worktree: root, byteLimit: 128 * 128 * 4 * 3 / 2
        )
        guard let png = picture.png, let bitmap = NSBitmapImageRep(data: png) else { return ["images: the capped render drew nothing"] }
        var failures: [String] = []
        if !isRed(bitmap, 50, 100) { failures.append("images: a picture within the cap was not drawn") }
        if isRed(bitmap, 250, 100) { failures.append("images: a picture over the cap was drawn anyway") }
        if picture.skippedImages != ["second.png"] { failures.append("images: the skipped picture was named as \(picture.skippedImages)") }
        return failures
    }

    private static func playbackDrawsAPictureSharp(root: String) -> [String] {
        guard write(stripes: root + "/stripes.png", side: 1_024) else { return ["images: could not write the striped picture"] }
        let small = CanvasFrame(id: CanvasFrameID("s"), name: "Small", rect: CanvasRect(x: 0, y: 0, width: 100, height: 60))
        let striped = CanvasElement(
            id: CanvasElementID("stripes"), frameID: small.id, rect: CanvasRect(x: 0, y: 0, width: 100, height: 60), kind: .image(path: "stripes.png")
        )
        let view = CanvasPlaybackView(
            document: CanvasDocument(frames: [small], elements: [striped]), worktree: root, documentPath: root + "/doc.udcanvas", close: {}
        )
        let shot = root + "/playback.png"
        var failures = CanvasEditorProbe.shoot(view, appearance: .aqua, to: shot, size: NSSize(width: 1_000, height: 700))
        for _ in 0..<20 where failures.isEmpty && contrast(atCentreOf: shot) < 0.5 {
            failures = CanvasEditorProbe.shoot(view, appearance: .aqua, to: shot, size: NSSize(width: 1_000, height: 700))
        }
        guard failures.isEmpty else { return failures }
        let measured = contrast(atCentreOf: shot)
        print("MEASURE playback stripes contrast \(measured)")
        return measured < 0.5 ? ["images: a picture in playback is drawn from too few pixels and blurs (contrast \(measured))"] : []
    }

    private static func contrast(atCentreOf path: String) -> Double {
        guard let data = try? Data(contentsOf: URL(filePath: path)), let picture = NSBitmapImageRep(data: data) else { return 0 }
        let y = picture.pixelsHigh / 2 - picture.pixelsHigh / 20
        let middle = picture.pixelsWide / 2
        let reds = (middle - 20..<middle + 20).compactMap { picture.colorAt(x: $0, y: y)?.usingColorSpace(.sRGB)?.redComponent }
        guard let lowest = reds.min(), let highest = reds.max() else { return 0 }
        return highest - lowest
    }

    private static func write(stripes path: String, side: Int) -> Bool {
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        for column in stride(from: 0, to: side, by: 2) { context.fill(CGRect(x: column, y: 0, width: 1, height: side)) }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(URL(filePath: path) as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func element(_ id: String, frame: CanvasFrame = frame, x: Double, file: String, size: Double) -> CanvasElement {
        CanvasElement(id: CanvasElementID(id), frameID: frame.id, rect: CanvasRect(x: x, y: 50, width: size, height: size), kind: .image(path: file))
    }

    private static func write(red path: String, side: Int) -> Bool {
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(URL(filePath: path) as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func isRed(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> Bool {
        isColour(bitmap, x, y) { $0 > 0.7 && $1 < 0.4 && $2 < 0.4 }
    }

    private static func isColour(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int, _ matches: (Double, Double, Double) -> Bool) -> Bool {
        guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
        return matches(colour.redComponent, colour.greenComponent, colour.blueComponent)
    }
}
#endif
