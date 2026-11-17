import Foundation

extension DocumentPreview {
    static let featuresTurnedOff = ["peerConnectionEnabled"]

    public static func turnOffFeatures(in preferences: NSObject) -> Bool {
        featuresTurnedOff.allSatisfy { key in
            let setter = "_set" + key.prefix(1).uppercased() + key.dropFirst() + ":"
            guard preferences.responds(to: NSSelectorFromString(setter)),
                  preferences.responds(to: NSSelectorFromString("_" + key))
            else { return false }
            preferences.setValue(false, forKey: key)
            return (preferences.value(forKey: key) as? Bool) == false
        }
    }
}
