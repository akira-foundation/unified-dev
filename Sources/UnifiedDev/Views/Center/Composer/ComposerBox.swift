import SwiftUI
import Core

struct ComposerBox: ViewModifier {
    @Binding var isFocused: Bool
    var isFloating = false
    var isDropTarget = false
    var isBusy = false

    @Environment(\.controlActiveState) private var activeState
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    private var isRingVisible: Bool { isFocused && activeState.showsFocusRing }

    private var insetShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
    }

    private var shape: AnyShape {
        isFloating
            ? AnyShape(RoundedRectangle(cornerRadius: Self.floatingCorner, style: .continuous))
            : AnyShape(insetShape)
    }

    private var wash: Double { scheme == .dark ? 0.22 : 0.04 }

    func body(content: Content) -> some View {
        let padded = content
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, Metrics.gutter)
            .padding(.bottom, isFloating ? Metrics.spacingWide : Metrics.gutter)
            .background {
                shape
                    .fill(isFloating ? Palette.surfaceRaised : Palette.surfaceSunken)
                    .overlay {
                        if isFloating {
                            shape.fill(.black.opacity(wash))
                        }
                    }
                    .contentShape(shape)
                    .onTapGesture { isFocused = true }
                    .accessibilityHidden(true)
            }

        if isFloating {
            padded
                    .overlay {
                        shape.stroke(Palette.border, lineWidth: Metrics.outline)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .overlay {
                        shape.stroke(Palette.controlAccent, lineWidth: 2)
                            .opacity(isDropTarget ? 1 : 0)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .overlay {
                        ComposerBusyRing(isBusy: isBusy, cornerRadius: Self.floatingCorner)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
        } else {
            padded
                .overlay {
                    insetShape.strokeBorder(
                        isDropTarget ? Palette.accent : Palette.border,
                        lineWidth: isDropTarget ? Metrics.outline * 2 : Metrics.outline
                    )
                    .allowsHitTesting(false)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.corner + 1.5)
                        .strokeBorder(Palette.focusRing, lineWidth: 3)
                        .padding(-1.5)
                        .opacity(isRingVisible ? 1 : 0)
                        .allowsHitTesting(false)
                }
        }
    }

    static let floatingCorner: CGFloat = 16

    private var focusColour: Color {
        contrast == .increased ? Palette.focusRing : Palette.textSecondary
    }

    private var focusOpacity: Double { contrast == .increased ? 1 : 0.2 }
}

extension View {
    func composerBox(
        isFocused: Binding<Bool>,
        isDropTarget: Bool = false,
        isFloating: Bool = false,
        isBusy: Bool = false
    ) -> some View {
        modifier(ComposerBox(
            isFocused: isFocused, isFloating: isFloating, isDropTarget: isDropTarget, isBusy: isBusy
        ))
    }
}
