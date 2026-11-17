import AppKit
import Combine
import Core
import SwiftUI

struct FullScreenBarReader: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    final class ReaderView: NSView {
        var onChange: ((Bool) -> Void)?
        private var polling: Task<Void, Never>?
        private var fullScreenChanges: AnyCancellable?
        private var barIsHidden = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            fullScreenChanges = nil
            polling?.cancel()
            guard let window else { return }
            let centre = NotificationCenter.default
            fullScreenChanges = centre.publisher(for: NSWindow.didEnterFullScreenNotification, object: window)
                .merge(with: centre.publisher(for: NSWindow.didExitFullScreenNotification, object: window))
                .sink { [weak self] _ in self?.windowChangedFullScreen() }
            windowChangedFullScreen()
        }

        private func windowChangedFullScreen() {
            polling?.cancel()
            guard window?.styleMask.contains(.fullScreen) == true else {
                report()
                return
            }
            polling = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.report()
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }

        private func report() {
            let hidden = ProfileToolbarLabel.barIsHidden(
                isFullScreen: window?.styleMask.contains(.fullScreen) == true,
                trafficLightsOpacity: trafficLightsOpacity
            )
            guard hidden != barIsHidden else { return }
            barIsHidden = hidden
            onChange?(hidden)
        }

        private var trafficLightsOpacity: CGFloat {
            var opacity: CGFloat = 1
            var view: NSView? = window?.standardWindowButton(.closeButton)
            while let current = view {
                opacity *= current.alphaValue
                view = current.superview
            }
            return opacity
        }
    }
}
