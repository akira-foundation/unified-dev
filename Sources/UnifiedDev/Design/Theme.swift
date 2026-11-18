import SwiftUI
import AppKit
import Core

enum Palette {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)

    static let controlStrip = Color(nsColor: .windowBackgroundColor)

    static let surface = Color(nsColor: .windowBackgroundColor)

    static let surfaceRaised = Color(nsColor: .controlBackgroundColor)

    static let surfaceSunken = Color(nsColor: .controlBackgroundColor)

    static let hover = Color(nsColor: hoverNSColor)

    static let hoverNSColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.055)
            : NSColor(white: 0, alpha: 0.04)
    }

    static let panelScrim = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(white: 0, alpha: SearchPanelLayout.dim(isDark: isDark))
    })

    static let floatingCard = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.2, alpha: 1)
            : NSColor(white: 1, alpha: 1)
    })
    static let selected = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let controlAccent = Color(nsColor: .controlAccentColor)
    static let selectedEmphasized = controlAccent
    static let selectedEmphasizedText = onAccentFill

    static let border = Color(nsColor: .separatorColor)

    static let paneDivider = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.name == .darkAqua || appearance.name == .vibrantDark
            ? NSColor.black
            : NSColor.black.withAlphaComponent(0.10)
    })

    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    static let textTertiaryOnGlass = textTertiary

    static let textInverted = selectedEmphasizedText

    static let textPlaceholder = Color(nsColor: .placeholderTextColor)

    static let textDisabled = Color(nsColor: .disabledControlTextColor)

    static let focusRing = Color(nsColor: .keyboardFocusIndicatorColor)
    static let caret = Color(nsColor: .textInsertionPointColor)
    static let textSelection = Color(nsColor: .selectedTextBackgroundColor)

    static let link = accent

    static let linkNSColor = accentNSColor

    static let positive = dynamic(PaletteInk.positive)

    static let questionWash = accent.opacity(0.06)
    static let questionBorder = accent.opacity(0.4)
    static let questionWashSettled = accent.opacity(0.03)

    static let cautionWash = warning.opacity(0.07)
    static let cautionBorder = warning.opacity(0.4)
    static let cautionWashSettled = warning.opacity(0.03)

    static let negative = dynamic(PaletteInk.negative)

    static let stop = Color(nsColor: .systemRed).opacity(0.85)

    static let warning = dynamic(PaletteInk.warning)
    static let running = dynamic(PaletteInk.running)

    static let runningNSColor = dynamicNSColor(
        light: PaletteInk.running.light, dark: PaletteInk.running.dark
    )

    static let merged = dynamic(PaletteInk.merged)

    static let mergedFill = dynamic(PaletteInk.mergedFill)

    static let workspaceMessage = dynamic(PaletteInk.workspaceMessage)
    static let workspaceMessageFill = dynamic(PaletteInk.workspaceMessageFill)

    static let diffPositive = dynamic(PaletteInk.diffPositive)

    static let diffAddBackground = diffPositive.opacity(0.13)
    static let diffAddEmphasis = diffPositive.opacity(0.28)
    static let diffDeleteBackground = negative.opacity(0.14)
    static let diffDeleteEmphasis = negative.opacity(0.30)

    static let reviewLine = warning.opacity(0.14)
    static let reviewBand = warning.opacity(0.07)

    static let synKeyword = dynamic(PaletteInk.synKeyword)
    static let synType = dynamic(PaletteInk.synType)
    static let synString = dynamic(PaletteInk.synString)
    static let synNumber = dynamic(PaletteInk.synNumber)
    static let synComment = dynamic(PaletteInk.synComment)
    static let synFunction = dynamic(PaletteInk.synFunction)
    static let synVariable = dynamic(PaletteInk.synVariable)
    static let synAttribute = dynamic(PaletteInk.synAttribute)
    static let synOperator = dynamic(PaletteInk.synOperator)
    static let synConstant = synNumber

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: dynamicNSColor(light: light, dark: dark))
    }

    static func dynamic(_ ink: PaletteInk.Pair) -> Color {
        dynamic(light: ink.light, dark: ink.dark)
    }

    static func dynamicNSColor(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        }
    }
}

extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hexString: String) {
        guard let parsed = HexColor(hex: hexString) else {
            self.init(nsColor: NSColor(rgb: 0x4C8DF6))
            return
        }
        self.init(nsColor: NSColor(
            srgbRed: CGFloat(parsed.red) / 255,
            green: CGFloat(parsed.green) / 255,
            blue: CGFloat(parsed.blue) / 255,
            alpha: 1
        ))
    }

    var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return [color.redComponent, color.greenComponent, color.blueComponent]
            .map { component in
                let byte = String(Int((component * 255).rounded()), radix: 16, uppercase: true)
                return byte.count == 1 ? "0" + byte : byte
            }
            .joined()
    }
}

enum Typo {
    static let display = ScaledFont(.largeTitle, weight: .light)
    static let displayHeading = ScaledFont(.title2, weight: .medium)
    static let displayTracking: CGFloat = -0.6
    static let heading = ScaledFont(.title3, weight: .bold)
    static let title = ScaledFont(.headline)
    static let body = ScaledFont(.body)
    static let bodyEmphasis = ScaledFont(.body, weight: .medium)
    static let label = ScaledFont(.callout)
    static let labelEmphasis = ScaledFont(.callout, weight: .medium)
    static let caption = ScaledFont(.subheadline)
    static let captionEmphasis = ScaledFont(.subheadline, weight: .medium)
    static let micro = ScaledFont(.footnote, weight: .medium)

    static let microTracking: CGFloat = 0.6

    static let code = ScaledFont(.callout, design: .monospaced)
    static let codeSmall = ScaledFont(.subheadline, design: .monospaced)
    static let codeTiny = ScaledFont(.footnote, design: .monospaced)
}

enum Metrics {
    static let sidebarWidth: CGFloat = 260
    static let inspectorWidth: CGFloat = 380

    static let centreColumnMinimum: CGFloat = 420

    static let centreColumnIdeal: CGFloat = 520

    static let inspectorMinimum: CGFloat = 280

    static let inspectorMaximum: CGFloat = 760
    static let rowHeight: CGFloat = 28
    static let cornerLarge: CGFloat = 16
    static let corner: CGFloat = 12
    static let cornerSmall: CGFloat = 8

    static let gutter: CGFloat = 12

    static let hairline: CGFloat = 1
    static let outline: CGFloat = 0.5

    static let spacingHair: CGFloat = 1

    static let spacingTight: CGFloat = 2
    static let spacingSmall: CGFloat = 4
    static let spacing: CGFloat = 6
    static let spacingWide: CGFloat = 8
    static let inset: CGFloat = 10
    static let pane: CGFloat = 24

    static let repoIcon: CGFloat = 16
    static let repoIconSmall: CGFloat = 13
    static let glyph: CGFloat = 13

    static let glyphInk: CGFloat = 11.25

    static let glyphDisc: CGFloat = glyphInk * 10 / 11

    static let dot: CGFloat = glyphDisc * 0.9 / CGFloat(BusyDot.peakScale)
    static let chipInsetH: CGFloat = 5
    static let chipInsetV: CGFloat = 2
    static let barHeight: CGFloat = 32
    static let controlHeight: CGFloat = 22
}

enum Elevation {
    case resting
    case lifted

    var opacity: Double {
        switch self {
        case .resting: 0.18
        case .lifted: 0.24
        }
    }

    var radius: CGFloat {
        switch self {
        case .resting: Metrics.spacingSmall
        case .lifted: Metrics.gutter
        }
    }

    var offset: CGFloat {
        switch self {
        case .resting: Metrics.spacingTight
        case .lifted: Metrics.spacingSmall
        }
    }
}

extension View {
    func elevation(_ level: Elevation) -> some View {
        shadow(color: .black.opacity(level.opacity), radius: level.radius, y: level.offset)
    }
}

enum Motion {
    static let pane: Animation = .easeOut(duration: 0.18)

    static let inspectorSeconds: TimeInterval = 0.25

    static let hoverSeconds: TimeInterval = 0.12
    static let hover: Animation = .easeInOut(duration: hoverSeconds)

    static let arrival: Animation = .easeOut(duration: 0.18)

    static let revealSeconds: TimeInterval = 0.18

    static let hoverCardDelay: Duration = .milliseconds(350)
}

extension View {
    func tabStripMaterial() -> some View { self }
}

struct Hairline: View {
    var axis: Axis = .horizontal
    var ink: Color = Palette.border

    var body: some View {
        Rectangle()
            .fill(ink)
            .frame(
                width: axis == .vertical ? Metrics.hairline : nil,
                height: axis == .horizontal ? Metrics.hairline : nil
            )
    }
}

struct Callout: View {
    enum Tone {
        case warning
        case negative

        var color: Color {
            switch self {
            case .warning: Palette.warning
            case .negative: Palette.negative
            }
        }
    }

    let text: String
    let symbol: String
    let tone: Tone

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.spacingWide) {
            Image(systemName: symbol)
                .font(Typo.caption)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            Text(text)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Metrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: Metrics.corner))
    }
}

enum Figures {
    static let count = IntegerFormatStyle<Int>.number.grouping(.never)
}

struct Chip: View {
    var text: String
    var systemImage: String?
    var tint: Color = Palette.textSecondary
    var background: Color = Palette.hover
    var monospaced: Bool = false

    @Environment(\.isOnEmphasizedSelection) private var isOnSelection

    var body: some View {
        HStack(spacing: Metrics.spacingSmall) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Typo.micro)
                    .imageScale(.small)
            }
            Text(text)
                .font(monospaced ? Typo.codeSmall : Typo.caption)
                .lineLimit(1)
        }
        .foregroundStyle(isOnSelection ? Palette.selectedEmphasizedText : tint)
        .padding(.horizontal, Metrics.chipInsetH)
        .padding(.vertical, Metrics.chipInsetV)
        .background(
            isOnSelection ? Palette.selectedEmphasizedText.opacity(0.2) : background,
            in: RoundedRectangle(cornerRadius: Metrics.cornerSmall)
        )
    }
}

struct DiffStatLabel: View {
    var additions: Int
    var deletions: Int
    var compact: Bool = false

    @Environment(\.isOnEmphasizedSelection) private var isOnSelection

    var body: some View {
        HStack(spacing: Metrics.spacingSmall) {
            if additions > 0 {
                Text("+\(Self.abbreviate(additions))")
                    .foregroundStyle(isOnSelection ? Palette.selectedEmphasizedText : Palette.positive)
            }
            if deletions > 0 {
                Text("-\(Self.abbreviate(deletions))")
                    .foregroundStyle(
                        isOnSelection
                            ? Palette.selectedEmphasizedText.opacity(0.75)
                            : Palette.negative
                    )
            }
        }
        .font(compact ? Typo.codeSmall : Typo.caption)
        .monospacedDigit()
    }

    private static let thousandsStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(1))
    private static let wholeThousandsStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0))
        .grouping(.never)

    static func abbreviate(_ value: Int) -> String {
        if value < 1_000 { return value.formatted(Figures.count) }
        let thousands = Double(value) / 1_000
        return thousands < 10
            ? "\(thousands.formatted(thousandsStyle))k"
            : "\(thousands.formatted(wholeThousandsStyle))k"
    }
}

private struct OnEmphasizedSelectionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isOnEmphasizedSelection: Bool {
        get { self[OnEmphasizedSelectionKey.self] }
        set { self[OnEmphasizedSelectionKey.self] = newValue }
    }
}

struct RowBackground: ViewModifier {
    var isSelected: Bool
    var isHovered: Bool
    var isFocused: Bool = false
    var isConcentric: Bool = false

    @Environment(\.controlActiveState) private var activeState

    func body(content: Content) -> some View {
        content
            .background {
                plate
            }
            .foregroundStyle(isEmphasized ? Palette.selectedEmphasizedText : Palette.textPrimary)
            .environment(\.isOnEmphasizedSelection, isEmphasized)
    }

    private var plate: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill)
            .padding(.horizontal, inset)
            .padding(.vertical, isConcentric ? 1 : 0)
    }

    private var inset: CGFloat { isConcentric ? Metrics.spacingSmall : 0 }

    private var radius: CGFloat {
        isConcentric ? Metrics.corner - inset : Metrics.corner
    }

    private var isEmphasized: Bool {
        isSelected && isFocused && activeState != .inactive
    }

    private var fill: Color {
        if isSelected {
            return isEmphasized ? Palette.selectedEmphasized : Palette.selected
        }
        return isHovered ? Palette.hover : .clear
    }
}

extension View {
    func rowBackground(
        isSelected: Bool, isHovered: Bool, isFocused: Bool = false, isConcentric: Bool = false
    ) -> some View {
        modifier(
            RowBackground(
                isSelected: isSelected, isHovered: isHovered,
                isFocused: isFocused, isConcentric: isConcentric
            )
        )
    }

    func onHoverChange(_ handler: @escaping (Bool) -> Void) -> some View {
        onHover(perform: handler)
    }
}

extension View {
    func linkButton() -> some View {
        buttonStyle(.link).foregroundStyle(Palette.link)
    }
}

extension ControlActiveState {
    var showsFocusRing: Bool { self != .inactive }
}
