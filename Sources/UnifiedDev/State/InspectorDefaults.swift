import Foundation
import Core

enum InspectorDefaults {
    private static let hiddenKey = "inspector.isHidden"

    static var stored: InspectorVisibility {
        InspectorVisibility(storedHidden: UserDefaults.standard.bool(forKey: hiddenKey))
    }

    static func remember(_ visibility: InspectorVisibility) {
        UserDefaults.standard.set(visibility.storedHidden, forKey: hiddenKey)
    }
}
