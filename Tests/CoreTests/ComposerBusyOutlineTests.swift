import Foundation
import Testing
@testable import Core

@Suite("The outline a busy composer wears")
struct ComposerBusyOutlineTests {
    @Test("it turns only while the composer is busy and motion is allowed")
    func turnsOnlyWhenBusyAndMotionAllowed() {
        #expect(ComposerBusyOutline.isSpinning(isBusy: true, reduceMotion: false))
        #expect(!ComposerBusyOutline.isSpinning(isBusy: true, reduceMotion: true))
        #expect(!ComposerBusyOutline.isSpinning(isBusy: false, reduceMotion: false))
        #expect(!ComposerBusyOutline.isSpinning(isBusy: false, reduceMotion: true))
    }

    @Test("the turn closes on the colour it opened with, so a lap has no seam")
    func closesWithoutASeam() throws {
        let first = try #require(ComposerBusyOutline.stops.first)
        let last = try #require(ComposerBusyOutline.stops.last)
        #expect(first.location == 0)
        #expect(last.location == 1)
        #expect(first.opacity == last.opacity)
    }

    @Test("one bright head on a faint ring, with its tail behind it")
    func oneHeadWithItsTailBehind() throws {
        let stops = ComposerBusyOutline.stops
        #expect(stops.map(\.location) == stops.map(\.location).sorted())
        let head = try #require(stops.max { $0.opacity < $1.opacity })
        #expect(head.opacity == 1)
        #expect(stops.count { $0.opacity == 1 } == 1)
        #expect(stops.filter { $0.opacity < 1 }.allSatisfy { $0.opacity == ComposerBusyOutline.faint })
        let rise = try #require(stops.last { $0.location < head.location })
        let fall = try #require(stops.first { $0.location > head.location })
        #expect(head.location - rise.location > fall.location - head.location)
    }

    @Test(
        "the turning square covers the box and its stroke at every angle",
        arguments: [(900.0, 120.0), (340.0, 96.0), (120.0, 120.0), (40.0, 600.0)]
    )
    func coversTheBoxAtEveryAngle(width: Double, height: Double) {
        let side = ComposerBusyOutline.gradientSide(width: width, height: height)
        let reach = hypot(width / 2, height / 2) + ComposerBusyOutline.width / 2
        #expect(side / 2 >= reach)
        #expect(side / 2 < reach + 1)
    }

    @Test("the square is the box's diagonal and the stroke, and nothing more")
    func squareIsTheDiagonalAndTheStroke() {
        #expect(ComposerBusyOutline.gradientSide(width: 300, height: 400) == 503)
    }

    @Test(
        "a box missing either dimension asks for no square",
        arguments: [(0.0, 0.0), (-4.0, 10.0), (10.0, 0.0), (0.0, 10.0), (10.0, -4.0)]
    )
    func noSizeNoSquare(width: Double, height: Double) {
        #expect(ComposerBusyOutline.gradientSide(width: width, height: height) == 0)
    }

    @Test("the ring is the one the composer wore before it moved to the render server")
    func ringIsTheOneTheComposerWore() {
        #expect(ComposerBusyOutline.stops == [
            .init(location: 0, opacity: 0.08),
            .init(location: 0.72, opacity: 0.08),
            .init(location: 0.88, opacity: 1),
            .init(location: 1, opacity: 0.08),
        ])
        #expect(ComposerBusyOutline.lap == 3)
        #expect(ComposerBusyOutline.width == 3)
        #expect(ComposerBusyOutline.fade == 0.25)
    }
}
