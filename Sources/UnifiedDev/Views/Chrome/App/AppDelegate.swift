import AppKit
import SwiftUI
import UserNotifications
import Core

extension Notification.Name {
    static let unifieddevHandleURL = Notification.Name("unifieddevHandleURL")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private weak var appModel: AppModel?

    private var isTerminating = false

    private let servicesProvider = ServicesProvider()

    var isInstallingUpdate = false

    private(set) var isAskingBeforeQuitting = false

    func attach(_ model: AppModel) {
        Log.launchStep("window appeared")
        appModel = model
        SwitchProbe.attach(model)
        TabProbe.attach(model)
        StreamProbe.attach(model)
        JumpProbe.attach(model)
        servicesProvider.attach(model)
        RunningApp.attach(model)
        NotificationService.shared.attach(model)
        #if DEBUG
        NotificationBellJumpProbe.attach(model)
        #endif
        WelcomeWindow.attach(model)
        CentreTabCycleShortcut.attach(model)
        SoftwareUpdater.shared.start(app: model, appDelegate: self)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Log.launchStep("will finish launching")
        LoginShellPath.begin()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.launchStep("did finish launching")
        defer { Log.launchStep("did finish launching returned") }
        if NotificationService.isAvailable {
            UNUserNotificationCenter.current().delegate = self
            NotificationService.shared.registerCategories()
        }
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()
        WindowCloseShortcut.apply()
        CentreTabCycleShortcut.apply()

        if !Snapshot.isDrivingTheWindow { WelcomeLaunch.presentIfNeeded() }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text) else { return }

        MainWindow.raise()
        NotificationCenter.default.post(name: .unifieddevHandleURL, object: url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        SoftwareUpdater.shared.launchPendingReplacement()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        isTerminating = true

        Task { @MainActor in
            await appModel?.flushCanvasDocuments()
            guard let question = appModel?.canvasQuitQuestion else {
                askAboutAgentsThenQuit()
                return
            }
            ask(canvasAlert(question)) { self.askAboutAgentsThenQuit() }
        }
        return .terminateLater
    }

    @MainActor
    private func askAboutAgentsThenQuit() {
        if !isInstallingUpdate, let running = appModel?.runningAgentCount, running > 0 {
            ask(quitAlert(running: running)) { self.beginTeardown() }
            return
        }
        beginTeardown()
    }

    private func beginTeardown() {
        isTerminating = true

        Task { @MainActor in
            await appModel?.shutdownEverything()
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    @MainActor
    private func ask(_ alert: NSAlert, thenQuit quit: @escaping @MainActor () -> Void) {
        isAskingBeforeQuitting = true
        let answer: @MainActor (NSApplication.ModalResponse) -> Void = { response in
            self.isAskingBeforeQuitting = false
            if response == .alertFirstButtonReturn {
                quit()
                return
            }
            self.isTerminating = false
            SoftwareUpdater.shared.terminationWasCancelled()
            NSApp.reply(toApplicationShouldTerminate: false)
        }
        NSApp.activate()
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else {
            answer(alert.runModal())
            return
        }
        window.makeKeyAndOrderFront(nil)
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated { answer(response) }
        }
    }

    @MainActor
    private func canvasAlert(_ question: CanvasQuitQuestion) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = question.title
        alert.informativeText = question.detail
        alert.addButton(withTitle: "Quit anyway")
        alert.addButton(withTitle: "Keep working")
        alert.buttons.last?.keyEquivalent = "\r"
        alert.buttons.first?.keyEquivalent = ""
        return alert
    }

    @MainActor
    private func quitAlert(running: Int) -> NSAlert {
        let names = appModel?.runningAgentWorkspaceNames ?? []

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = running == 1
            ? "An agent is still running"
            : "\(running) agents are still running"

        var detail = running == 1
            ? "Quitting stops it. The turn it is in the middle of will not be finished, and it cannot be resumed."
            : "Quitting stops them. The turns they are in the middle of will not be finished, and they cannot be resumed."
        let shown = names.prefix(5)
        if !shown.isEmpty {
            detail += "\n\n" + shown.map { "\u{2022} \($0)" }.joined(separator: "\n")
            if names.count > shown.count {
                detail += "\n\u{2022} and \(names.count - shown.count) more"
            }
        }
        alert.informativeText = detail

        alert.addButton(withTitle: "Quit anyway")
        alert.addButton(withTitle: "Keep working")
        alert.buttons.last?.keyEquivalent = "\r"
        alert.buttons.first?.keyEquivalent = ""

        return alert
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let appModel else { return nil }
        let running = appModel.workspaces.filter(appModel.isRunning)
        guard !running.isEmpty else { return nil }

        let menu = NSMenu()
        for workspace in running {
            let item = NSMenuItem(
                title: workspace.name,
                action: #selector(openWorkspaceFromDock(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.represent(workspace.id)
            item.image = NSImage(
                systemSymbolName: "circle.fill",
                accessibilityDescription: "Agent running"
            )
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openWorkspaceFromDock(_ sender: NSMenuItem) {
        guard let id = sender.represented(WorkspaceID.self) else { return }
        MainWindow.raise()
        OpenWorkspaceNotification.post(id)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainWindow.raise()
        } else {
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let workspaceID = NotificationService.workspaceID(from: response)
        let sessionID = NotificationService.sessionID(from: response)
        let reply = (response as? UNTextInputNotificationResponse)?.userText

        Task { @MainActor in
            if let reply, let workspaceID, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await NotificationService.shared.reply(reply, toWorkspace: workspaceID, session: sessionID)
                completionHandler()
                return
            }

            MainWindow.raise()
            if let workspaceID {
                if let appModel {
                    await appModel.notificationInbox.openBanner(workspaceID: workspaceID, sessionID: sessionID)
                } else {
                    OpenWorkspaceNotification.post(workspaceID)
                }
            }
            completionHandler()
        }
    }
}
