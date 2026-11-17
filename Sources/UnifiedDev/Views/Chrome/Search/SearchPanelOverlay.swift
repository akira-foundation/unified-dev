import AppKit
import SwiftUI
import Core

struct SearchPanelOverlay: ViewModifier {
    let app: AppModel
    @Bindable var panel: SearchPanelModel

    @State private var window: NSWindow?
    @State private var host: SearchPanelOverlayHost?

    func body(content: Content) -> some View {
        content
            .background(WindowAccessor(window: $window))
            .onChange(of: window, initial: true) { _, _ in install() }
            .onChange(of: panel.isOpen) { _, open in
                if open { raise() }
            }
            .onChange(of: app.profileWorkspaces) { _, _ in panel.rebuild(app: app) }
            .onChange(of: app.profileRepos) { _, _ in panel.rebuild(app: app) }
            .onChange(of: app.transcriptResults) { _, _ in panel.rebuild(app: app) }
            .onChange(of: app.runningWorkspaceIDs) { _, _ in panel.rebuild(app: app) }
            .onChange(of: app.waitingWorkspaceIDs) { _, _ in panel.rebuild(app: app) }
            .onChange(of: app.profiles) { _, _ in panel.rebuild(app: app) }
            .onChange(of: app.activeProfileID) { _, _ in panel.rebuild(app: app) }
    }

    private func install() {
        guard host == nil, let window, let frame = window.contentView?.superview else { return }
        let view = SearchPanelOverlayHost(
            rootView: SearchPanelWindowOverlay(app: app, panel: panel)
        )
        view.frame = frame.bounds
        view.autoresizingMask = [.width, .height]
        frame.addSubview(view, positioned: .above, relativeTo: nil)
        host = view
    }

    private func raise() {
        guard let host, let frame = host.superview else { return }
        frame.addSubview(host, positioned: .above, relativeTo: nil)
    }
}

extension View {
    func searchPanel(app: AppModel) -> some View {
        modifier(SearchPanelOverlay(app: app, panel: SearchPanelModel.shared))
    }
}
