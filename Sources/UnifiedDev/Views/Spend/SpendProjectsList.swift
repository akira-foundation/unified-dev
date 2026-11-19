import SwiftUI
import Core

struct SpendProjectsList: View {
    let projects: [SpendProjectLine]
    let emptyLine: String

    @State private var opened: Set<String> = []

    var body: some View {
        if projects.isEmpty {
            Text(emptyLine).settingsFootnote()
        }
        ForEach(projects) { project in
            DisclosureGroup(isExpanded: binding(for: project)) {
                ForEach(project.sessions) { session in
                    SpendSessionRow(session: session)
                }
            } label: {
                LabeledContent {
                    Text(SpendLines.cost(project.spend)).monospacedDigit()
                } label: {
                    Text(project.name)
                    Text(SpendLines.projectCaption(project))
                }
            }
        }
    }

    private func binding(for project: SpendProjectLine) -> Binding<Bool> {
        Binding(
            get: { opened.contains(project.id) },
            set: { isOpen in
                if isOpen { opened.insert(project.id) } else { opened.remove(project.id) }
            }
        )
    }
}
