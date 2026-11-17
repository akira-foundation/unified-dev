import AppKit
import SwiftUI

#if DEBUG
@MainActor
enum OffscreenSnapshot {
    static func png(of view: some View, size: CGSize, scheme: ColorScheme, background: Color) async -> Data? {
        let host = NSHostingController(rootView: view
            .frame(width: size.width, height: size.height)
            .background(background)
            .transaction { $0.disablesAnimations = true }
            .environment(\.colorScheme, scheme))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentViewController = host
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(400))
        host.view.displayIfNeeded()
        guard let bitmap = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        if host.view.isFlipped {
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
        }
        host.view.layer?.render(in: context.cgContext)
        context.flushGraphics()
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif
