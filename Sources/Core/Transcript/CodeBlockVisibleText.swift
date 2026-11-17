import Foundation

enum CodeBlockVisibleText {
    static let blankLetters: Set<UInt32> = [0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800]

    static func shown(_ text: String) -> String {
        var shown = ""
        for scalar in text.unicodeScalars {
            guard hides(scalar) else {
                shown.unicodeScalars.append(scalar)
                continue
            }
            shown += "[U+" + String(scalar.value, radix: 16, uppercase: true) + "]"
        }
        return shown
    }

    static func hiddenCount(in text: String) -> Int {
        text.unicodeScalars.count(where: hides)
    }

    static func hides(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "\n" || scalar == "\t" { return false }
        if scalar.isASCII { return !(0x20...0x7E).contains(scalar.value) }
        if blankLetters.contains(scalar.value) { return true }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber,
             .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol, .spacingMark:
            return false
        default:
            return true
        }
    }
}
