import SwiftUI
import Core

enum MenuBarModuleStyle {
    static let gap: CGFloat = 10
    static let edge: CGFloat = 12
    static let panelCorner: CGFloat = 26
    static let shadowRoom: CGFloat = 16
    static let corner: CGFloat = panelCorner - edge
    static let inset: CGFloat = 14
    static let chip: CGFloat = 20
}

struct MenuBarModule: ViewModifier {
    let title: String
    var inset: CGFloat = MenuBarModuleStyle.inset

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: MenuBarModuleStyle.corner, style: .continuous)
        content
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .menuBarSurface(shape)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
    }
}

struct MenuBarSurface<SurfaceShape: InsettableShape>: ViewModifier {
    let shape: SurfaceShape

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                } else {
                    shape.fill(Color.primary.opacity(0.06))
                }
            }
    }
}

struct MenuBarPanelPlatter: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: MenuBarModuleStyle.panelCorner, style: .continuous)
        content
            .clipShape(shape)
            .background {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                }
            }
            .glassEffect(reduceTransparency ? .identity : .regular, in: shape)
    }
}

struct MenuBarPanelFocusRing: ViewModifier {
    let isFocused: Bool

    @Environment(\.menuBarPanelShowsFocus) private var showsFocus

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .overlay {
                if isFocused, showsFocus {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .padding(-3)
                }
            }
    }
}

extension EnvironmentValues {
    @Entry var menuBarPanelShowsFocus = false
}

extension View {
    func menuBarModule(_ title: String, inset: CGFloat = MenuBarModuleStyle.inset) -> some View {
        modifier(MenuBarModule(title: title, inset: inset))
    }

    func menuBarSurface<SurfaceShape: InsettableShape>(_ shape: SurfaceShape) -> some View {
        modifier(MenuBarSurface(shape: shape))
    }

    func menuBarPanelPlatter() -> some View {
        modifier(MenuBarPanelPlatter())
    }

    @ViewBuilder
    func panelFocus(_ focus: FocusState<MenuBarPanelFocus?>.Binding?, _ target: MenuBarPanelFocus) -> some View {
        if let focus {
            focusable()
                .focused(focus, equals: target)
                .modifier(MenuBarPanelFocusRing(isFocused: focus.wrappedValue == target))
        } else {
            self
        }
    }
}

struct MenuBarRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuBarRow(configuration: configuration)
    }
}

private struct MenuBarRow: View {
    let configuration: ButtonStyle.Configuration

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (isHovered ? 0.08 : 0)))
            }
            .onHover { isHovered = $0 }
    }
}
