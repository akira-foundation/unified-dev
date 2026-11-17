import Core
import Foundation
import Observation

@MainActor
@Observable
final class SideConversationState {
    var lifecycle = SideConversationLifecycle()
    var transcript: TranscriptModel?
    var snapshot: SideConversation.Snapshot?
    var error: String?
    var isKeeping = false
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var closing: Task<Void, Never>?

    var isVisible: Bool { lifecycle.isShown }
    var isBusy: Bool { lifecycle.isOpening || isKeeping }
}
