import GestureCore
import SwiftUI

struct BindingsView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var controller: GestureController
    @State private var selection: Set<GestureBinding.ID> = []
    @State private var editing: GestureBinding?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last gesture:").foregroundStyle(.secondary)
                Text(controller.lastTrigger?.displayName ?? "— perform one on the trackpad —")
                Spacer()
                if let last = controller.lastTrigger {
                    Button("Bind Last Gesture…") { editing = newBinding(for: last) }
                }
            }

            Table(store.config.bindings, selection: $selection) {
                TableColumn("On") { binding in
                    Toggle("", isOn: enabledBinding(for: binding.id)).labelsHidden()
                }
                .width(28)
                TableColumn("Gesture") { Text($0.trigger.displayName) }
                TableColumn("Action") { Text($0.action.displayName).lineLimit(1) }
                TableColumn("App") { Text(AppList.name(for: $0.appBundleID)) }
            }
            .contextMenu(forSelectionType: GestureBinding.ID.self) { ids in
                Button("Edit…") { edit(ids) }.disabled(ids.count != 1)
                Button("Delete") { delete(ids) }
            } primaryAction: { ids in
                edit(ids)
            }
            .onDeleteCommand { delete(selection) }

            HStack {
                Button { editing = newBinding(for: controller.lastTrigger ?? .swipe(fingers: 5, direction: .up)) } label: {
                    Image(systemName: "plus")
                }
                Button { delete(selection) } label: { Image(systemName: "minus") }
                    .disabled(selection.isEmpty)
                Button("Edit…") { edit(selection) }
                    .disabled(selection.count != 1)
                Spacer()
                Text("Double-click a row to edit. App-specific gestures win over “All apps”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { binding in
            BindingEditor(original: binding) { store.upsert($0) }
        }
    }

    private func newBinding(for trigger: Trigger) -> GestureBinding {
        GestureBinding(trigger: trigger, action: .shellCommand(command: ""))
    }

    private func edit(_ ids: Set<GestureBinding.ID>) {
        guard ids.count == 1, let binding = store.config.bindings.first(where: { ids.contains($0.id) }) else { return }
        editing = binding
    }

    private func delete(_ ids: Set<GestureBinding.ID>) {
        store.config.bindings.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    private func enabledBinding(for id: GestureBinding.ID) -> Binding<Bool> {
        Binding(
            get: { store.config.bindings.first { $0.id == id }?.enabled ?? false },
            set: { newValue in
                if let index = store.config.bindings.firstIndex(where: { $0.id == id }) {
                    store.config.bindings[index].enabled = newValue
                }
            }
        )
    }
}
