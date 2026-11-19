import SwiftUI
import Core

struct DiscardConfirmation: ViewModifier {
    var isPresented: Binding<Bool>
    var alert: () -> DiscardAlert?
    var onConfirm: () -> Void

    func body(content: Content) -> some View {
        let shown = isPresented.wrappedValue ? alert() : nil
        content.alert(
            shown?.title ?? "",
            isPresented: Binding(
                get: { isPresented.wrappedValue && shown != nil },
                set: { isPresented.wrappedValue = $0 }
            ),
            presenting: shown
        ) { alert in
            ForEach(alert.actions, id: \.label) { action in
                Button(action.label, role: Self.role(action.role)) {
                    if action.confirms { onConfirm() }
                }
                .keyboardShortcut(action == alert.returnKey ? .defaultAction : nil)
            }
        } message: { alert in
            Text(alert.body)
        }
    }

    private static func role(_ role: DiscardAlert.Role) -> ButtonRole {
        switch role {
        case .destructive: .destructive
        case .cancel: .cancel
        }
    }
}

extension View {
    func discardConfirmation(
        isPresented: Binding<Bool>,
        alert: @escaping () -> DiscardAlert?,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(DiscardConfirmation(isPresented: isPresented, alert: alert, onConfirm: onConfirm))
    }
}
