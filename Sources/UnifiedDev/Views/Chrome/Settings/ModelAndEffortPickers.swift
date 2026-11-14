import SwiftUI
import Core

struct ModelAndEffortPickers: View {
    @Binding var model: String
    @Binding var effort: String
    @Binding var backend: AgentKind
    var offersAgentDefault = false

    private var catalog: ComposerModelCatalog { .shared }

    var body: some View {
        HStack(spacing: Metrics.gutter) {
            Picker("Model", selection: chosenModel) {
                ForEach(catalog.sections(includingCurrent: model, on: backend)) { section in
                    Section(section.title) {
                        ForEach(section.options) { option in
                            Text(option.menuLabel).tag(option.id)
                        }
                    }
                }
            }
            .labelsHidden()
            .fixedSize()

            Picker("Effort", selection: $effort) {
                ForEach(ComposerOption.adding([effort], to: efforts)) { option in
                    Text(option.label).tag(option.id)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var efforts: [ComposerOption] {
        catalog.efforts(for: backend, model: model, offeringAgentDefault: offersAgentDefault)
    }

    private var chosenModel: Binding<String> {
        Binding(get: { model }, set: { id in MainActor.assumeIsolated { choose(id) } })
    }

    private func choose(_ tag: String) {
        let (kind, id) = catalog.choice(tag, current: backend)
        model = id
        backend = kind
        effort = catalog.resolvedEffort(effort, for: kind, model: id)
    }
}
