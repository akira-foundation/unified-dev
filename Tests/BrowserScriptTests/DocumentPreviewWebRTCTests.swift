@testable import Core
import Foundation
import Network
import Testing
import WebKit

@MainActor
@Suite("What a previewed document reaches through a peer connection", .serialized, .tags(.security))
struct DocumentPreviewWebRTCTests {
    @Test("ICE gathering against a local STUN listener sends nothing, and local files still load")
    func iceGatheringSendsNothing() async throws {
        let listener = try await LoopbackListener.start(.udp)
        defer { listener.stop() }

        let page = try await Self.open(gatheringAgainst: listener.port, featuresOff: true)
        try await Task.sleep(for: .seconds(3))

        #expect(try await page.evaluate("document.body.dataset.script") == "ran")
        #expect(try await page.evaluate("getComputedStyle(document.body).color") == "rgb(1, 2, 3)")
        #expect(try await page.evaluate("document.body.dataset.peer") == "undefined")
        #expect(try await page.evaluate("document.body.dataset.framePeer") == "undefined")
        #expect(listener.arrivals == 0)
    }

    @Test("with peer connections left on, the network rules alone let the same page reach the listener")
    func iceGatheringIsSeenWithFeaturesOn() async throws {
        let listener = try await LoopbackListener.start(.udp)
        defer { listener.stop() }

        let page = try await Self.open(gatheringAgainst: listener.port, featuresOff: false)
        let deadline = ContinuousClock.now + .seconds(10)
        while listener.arrivals == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(try await page.evaluate("document.body.dataset.framePeer") == "function")
        #expect(listener.arrivals > 0)
    }

    private static func open(gatheringAgainst port: UInt16, featuresOff: Bool) async throws -> PreviewWebPage {
        let files = [
            "index.html": """
            <!doctype html>
            <html><head><meta charset="utf-8"><link rel="stylesheet" href="style.css"></head>
            <body>loaded<script src="gather.js"></script></body></html>
            """,
            "style.css": "body { color: rgb(1, 2, 3); }",
            "gather.js": """
            document.body.dataset.script = "ran";
            const frame = document.body.appendChild(document.createElement("iframe"));
            document.body.dataset.peer = typeof RTCPeerConnection;
            document.body.dataset.framePeer = typeof frame.contentWindow.RTCPeerConnection;
            for (const scope of [window, frame.contentWindow]) {
                if (typeof scope.RTCPeerConnection !== "function") continue;
                const peer = new scope.RTCPeerConnection({ iceServers: [{ urls: "stun:127.0.0.1:\(port)" }] });
                peer.createDataChannel("probe");
                peer.createOffer().then((offer) => peer.setLocalDescription(offer));
            }
            """,
        ]
        return try await PreviewWebPage.open(files: files) { configuration in
            try await PreviewWebPage.blockNetwork(in: configuration)
            if featuresOff {
                try #require(DocumentPreview.turnOffFeatures(in: configuration.preferences))
            }
        }
    }
}
