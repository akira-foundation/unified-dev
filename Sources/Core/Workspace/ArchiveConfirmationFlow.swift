import Foundation

public enum ArchiveConfirmationFlow {
    public enum Update: Sendable, Equatable {
        case offer(ArchiveRequest)
        case replace(ArchiveRequest)
        case withdraw(WorkspaceID)

        public var request: ArchiveRequest? {
            switch self {
            case .offer(let request), .replace(let request): request
            case .withdraw: nil
            }
        }

        public var workspaceID: WorkspaceID {
            switch self {
            case .offer(let request), .replace(let request): request.id
            case .withdraw(let id): id
            }
        }
    }

    public static func shows(
        _ update: Update, while shown: ArchiveRequest?, replacesInPlace: Bool
    ) -> ArchiveRequest? {
        switch update {
        case .offer(let request):
            guard !request.isChecking || replacesInPlace else { return shown }
            guard let shown, shown.id != request.id else { return request }
            return shown
        case .replace(let request):
            guard let shown else { return replacesInPlace ? nil : request }
            return shown.id == request.id ? request : shown
        case .withdraw(let id):
            return shown?.id == id ? nil : shown
        }
    }
}
