import AppKit
import Core
import QuartzCore
import SwiftUI

struct ComposerBusyRing: NSViewRepresentable {
    var isBusy: Bool

    var cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> ComposerBusyRingView {
        let view = ComposerBusyRingView(frame: .zero)
        configure(view)
        return view
    }

    func updateNSView(_ view: ComposerBusyRingView, context: Context) {
        configure(view)
    }

    private func configure(_ view: ComposerBusyRingView) {
        view.configure(
            isBusy: isBusy,
            isSpinning: ComposerBusyOutline.isSpinning(isBusy: isBusy, reduceMotion: reduceMotion),
            cornerRadius: cornerRadius
        )
    }
}

final class ComposerBusyRingView: BusyPulseLayerView {
    private static let frameRate = CAFrameRateRange(minimum: 24, maximum: 60, preferred: 30)

    private static let turnKey = "turn"

    private let ring = CALayer()
    private let gradient = CAGradientLayer()
    private let stroke = CAShapeLayer()

    private var isConfigured = false
    private var fades = 0
    private var isBusy = false
    private var isSpinning = false
    private var cornerRadius: CGFloat = 0
    private let tint = NSColor(Palette.running)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false

        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.locations = ComposerBusyOutline.stops.map { NSNumber(value: $0.location) }

        stroke.fillColor = nil
        stroke.strokeColor = NSColor.black.cgColor
        stroke.lineWidth = ComposerBusyOutline.width

        ring.opacity = 0
        ring.mask = stroke
        ring.addSublayer(gradient)
        layer?.addSublayer(ring)
        applyColors()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let side = ComposerBusyOutline.gradientSide(width: bounds.width, height: bounds.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        stroke.frame = bounds
        stroke.path = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: bounds).cgPath
        gradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        gradient.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.contentsScale = scale
        stroke.contentsScale = scale
        CATransaction.commit()
    }

    override func applyColors() {
        let colour = resolved(tint)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = ComposerBusyOutline.stops.map {
            colour.copy(alpha: colour.alpha * $0.opacity) ?? colour
        }
        CATransaction.commit()
    }

    func configure(isBusy: Bool, isSpinning: Bool, cornerRadius: CGFloat) {
        adopt(cornerRadius)
        turn(isSpinning, whileBusy: isBusy)
        reveal(isBusy)
    }

    private func adopt(_ cornerRadius: CGFloat) {
        guard cornerRadius != self.cornerRadius else { return }
        self.cornerRadius = cornerRadius
        needsLayout = true
    }

    private func turn(_ isSpinning: Bool, whileBusy isBusy: Bool) {
        let wasSpinning = self.isSpinning
        self.isSpinning = isSpinning
        if isSpinning, !wasSpinning { spin() }
        if wasSpinning, !isSpinning, isBusy { halt() }
    }

    private func reveal(_ isBusy: Bool) {
        let isFirst = !isConfigured
        isConfigured = true
        guard isFirst || isBusy != self.isBusy else { return }
        self.isBusy = isBusy
        show(isBusy, animated: !isFirst)
    }

    private func show(_ shown: Bool, animated: Bool) {
        fades += 1
        let fade = fades
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(ComposerBusyOutline.fade)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            CATransaction.setCompletionBlock { [weak self] in
                Task { @MainActor in self?.settle(after: fade) }
            }
        } else {
            CATransaction.setDisableActions(true)
        }
        ring.opacity = shown ? 1 : 0
        CATransaction.commit()
    }

    private func settle(after fade: Int) {
        guard fade == fades, !isSpinning else { return }
        halt()
    }

    private func spin() {
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = 2 * Double.pi
        turn.duration = ComposerBusyOutline.lap
        turn.timingFunction = CAMediaTimingFunction(name: .linear)
        turn.preferredFrameRateRange = Self.frameRate
        install(turn, on: gradient, key: Self.turnKey, beginAt: CACurrentMediaTime())
    }

    private func halt() {
        gradient.removeAnimation(forKey: Self.turnKey)
    }
}
