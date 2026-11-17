import SwiftUI
import Core

struct CodeBlockRunConfirmation: ViewModifier {
    @Bindable private var runs = CodeBlockRunStore.shared

    func body(content: Content) -> some View {
        content.alert(
            CodeBlockConfirmation.title,
            isPresented: $runs.pending.isPresent(),
            presenting: runs.pending
        ) { request in
            Button(CodeBlockConfirmation.confirmLabel) { runs.answer(request, confirmed: true) }
            Button(CodeBlockConfirmation.cancelLabel, role: .cancel) { runs.answer(request, confirmed: false) }
        } message: { request in
            Text(request.question.message)
        }
    }
}
