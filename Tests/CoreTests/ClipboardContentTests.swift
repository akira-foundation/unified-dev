import Foundation
import Testing
@testable import Core

@Suite("Clipboard content")
struct ClipboardContentTests {
    private let attachment = BridgeAttachment(
        shimPath: "/Applications/Unified Dev.app/Contents/MacOS/bridge",
        socketPath: "/tmp/bridge-test.sock",
        token: "fixture-token",
        role: .owner
    )

    @Test("every command that registers the bridge is copied concealed")
    func bridgeCommandsAreConcealed() {
        let commands = [
            BridgeRegistration.ownerAddCommand(attachment),
            BridgeRegistration.ownerCodexAddCommand(attachment),
            BridgeRegistration.ownerGrokAddCommand(attachment),
        ]
        for command in commands {
            let content = ClipboardContent.command(command)
            #expect(content.isConcealed)
            #expect(content.representations.map(\.type).contains(ClipboardContent.concealedType))
        }
    }

    @Test("a command that carries no secret stays in the clipboard history", arguments: [
        "xcode-select --install",
        "env \(BridgeProtocol.socketVariable)=/tmp/bridge.sock claude",
    ])
    func ordinaryCommandsAreNotConcealed(_ command: String) {
        let content = ClipboardContent.command(command)
        #expect(!content.isConcealed)
        #expect(content.representations.map(\.type) == [ClipboardContent.plainTextType])
    }

    @Test("concealed content still carries its text, and marks itself with an empty item")
    func concealedCarriesTheText() {
        let command = BridgeRegistration.ownerAddCommand(attachment)
        let content = ClipboardContent.command(command)
        #expect(content.representations == [
            .init(type: ClipboardContent.plainTextType, data: Data(command.utf8)),
            .init(type: ClipboardContent.concealedType, data: Data()),
        ])
    }
}
