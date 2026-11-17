import SwiftUI

struct DiscardConfirmation: ViewModifier {
    var isPresented: Binding<Bool>
    var title: String
    var message: () -> String
    var canConfirm: () -> Bool = { true }
    var onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.popover(isPresented: isPresented, arrowEdge: .bottom) {
            ConfirmationPopover(
                title: title,
                confirmLabel: "Discard",
                tint: Palette.negative,
                canConfirm: canConfirm(),
                onConfirm: {
                    onConfirm()
                    isPresented.wrappedValue = false
                },
                onCancel: { isPresented.wrappedValue = false }
            ) {
                Text(message())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension View {
    func discardConfirmation(
        isPresented: Binding<Bool>,
        title: String,
        message: @escaping () -> String,
        canConfirm: @escaping () -> Bool = { true },
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(DiscardConfirmation(
            isPresented: isPresented, title: title, message: message,
            canConfirm: canConfirm, onConfirm: onConfirm
        ))
    }
}
