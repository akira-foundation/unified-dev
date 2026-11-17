import SwiftUI
import Core

enum UsageScale {
    static var label: Font { Font(NSFont.menuFont(ofSize: 0)).weight(.semibold) }
    static var supporting: Font { Font(NSFont.menuFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize - 1)) }
    static var header: Font { Font(NSFont.menuFont(ofSize: 0)).weight(.semibold) }
    static var plan: Font { Font(NSFont.menuFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize - 2)) }
}

enum MenuInk {
    static var primary: Color { Color(nsColor: .labelColor) }
    static var secondary: Color { Color(nsColor: .secondaryLabelColor) }
    static var tertiary: Color { Color(nsColor: .tertiaryLabelColor) }
    static var track: Color { Color(nsColor: .tertiaryLabelColor) }

    static var normal: Color { Color(nsColor: .systemBlue) }
    static var warning: Color { Color(nsColor: .systemYellow) }
    static var critical: Color { Color(nsColor: .systemRed) }

    static func tone(_ tone: UsageMeterReading.Tone) -> Color {
        switch tone {
        case .normal: normal
        case .warning: warning
        case .critical: critical
        case .empty: .clear
        }
    }
}

struct ProviderMarkShape: Shape {
    let mark: SVGPath
    var inset: CGFloat = 0.04

    func path(in rect: CGRect) -> Path {
        let bounds = mark.bounds
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        let available = rect.insetBy(dx: rect.width * inset, dy: rect.height * inset)
        let scale = min(available.width / bounds.width, available.height / bounds.height)
        let dx = available.midX - bounds.midX * scale
        let dy = available.midY - bounds.midY * scale
        func point(_ source: CGPoint) -> CGPoint {
            CGPoint(x: source.x * scale + dx, y: source.y * scale + dy)
        }
        var path = Path()
        for command in mark.commands {
            switch command {
            case .move(let to): path.move(to: point(to))
            case .line(let to): path.addLine(to: point(to))
            case .curve(let to, let first, let second):
                path.addCurve(to: point(to), control1: point(first), control2: point(second))
            case .quad(let to, let control): path.addQuadCurve(to: point(to), control: point(control))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

struct ProviderMarkView: View {
    let provider: AgentKind

    var body: some View {
        if let mark = ProviderMark.path(for: provider) {
            ProviderMarkShape(mark: mark)
                .accessibilityHidden(true)
        } else {
            Image(systemName: PaneGlyph.agentMark(for: provider))
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        }
    }
}
