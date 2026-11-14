import Foundation
import Testing
@testable import Core

@Suite("Which web features a document preview turns off", .tags(.security))
struct DocumentPreviewWebFeaturesTests {
    @Test("peer connections are turned off, and read back as off")
    func peerConnectionsAreTurnedOff() {
        let preferences = PreferencesDouble()

        #expect(DocumentPreview.turnOffFeatures(in: preferences))
        #expect(!preferences.peerConnections)
    }

    @Test("preferences that cannot turn peer connections off are refused rather than trusted")
    func preferencesWithoutTheSwitchAreRefused() {
        #expect(!DocumentPreview.turnOffFeatures(in: NSObject()))
    }

    @Test("a switch that does not stay off is refused")
    func switchThatIgnoresTheWriteIsRefused() {
        #expect(!DocumentPreview.turnOffFeatures(in: StuckPreferencesDouble()))
    }
}

private final class PreferencesDouble: NSObject {
    var peerConnections = true

    @objc(_peerConnectionEnabled) var isPeerConnectionEnabled: Bool {
        peerConnections
    }

    @objc(_setPeerConnectionEnabled:) func setPeerConnection(_ enabled: Bool) {
        peerConnections = enabled
    }
}

private final class StuckPreferencesDouble: NSObject {
    @objc(_peerConnectionEnabled) var isPeerConnectionEnabled: Bool {
        true
    }

    @objc(_setPeerConnectionEnabled:) func setPeerConnection(_ enabled: Bool) {}
}
