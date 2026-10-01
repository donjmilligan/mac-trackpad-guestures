import GestureCore
import SwiftUI

struct ShapesView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var controller: GestureController
    @State private var selection: ShapeTemplate.ID?
    @State private var newName = ""
    @State private var renaming: ShapeTemplate?
    @State private var renameText = ""

    private var selected: ShapeTemplate? { store.shapes.first { $0.id == selection } }
    private var activator: String {
        let symbols = store.config.engine.drawModifiers.symbols
        return symbols.isEmpty ? "(set an activator key in Preferences)" : symbols
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading) {
                List(store.shapes, selection: $selection) { shape in
                    HStack {
                        ShapePreview(points: shape.samples.first ?? [])
                            .frame(width: 34, height: 34)
                        VStack(alignment: .leading) {
                            Text(shape.name)
                            Text("\(shape.samples.count) sample\(shape.samples.count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("Rename…") { renaming = shape; renameText = shape.name }
                        Button("Delete") { delete(shape.id) }
                    }
                }
                HStack {
                    Button { if let id = selection { delete(id) } } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Button("Rename…") {
                        if let selected { renaming = selected; renameText = selected.name }
                    }
                    .disabled(selection == nil)
                    Spacer()
                    Button("Restore Built-ins") { restoreBuiltIns() }
                }
            }
            .frame(width: 260)

            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Try it") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hold **\(activator)** and draw a shape with one finger.")
                        Text(controller.lastRecognition.isEmpty ? "Last drawing: —" : "Last drawing: \(controller.lastRecognition)")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox("Record") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let name = controller.recordingShapeName {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Hold **\(activator)** and draw “\(name)” on the trackpad…")
                            }
                            Button("Cancel") { controller.cancelRecording() }
                        } else {
                            if let selected {
                                Button("Add Sample to “\(selected.name)”") { controller.beginRecording(shapeName: selected.name) }
                                Text("Adding 2–3 samples drawn the way you naturally draw it makes recognition much more reliable.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Divider()
                            }
                            HStack {
                                TextField("New shape name", text: $newName)
                                Button("Record New Shape") {
                                    controller.beginRecording(shapeName: newName.trimmingCharacters(in: .whitespaces))
                                    newName = ""
                                }
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                if let selected, selected.samples.count > 1 {
                    GroupBox("Samples of “\(selected.name)”") {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(selected.samples.indices, id: \.self) { index in
                                    ShapePreview(points: selected.samples[index])
                                        .frame(width: 54, height: 54)
                                        .contextMenu { Button("Delete Sample") { deleteSample(index, of: selected.id) } }
                                }
                            }
                            .padding(6)
                        }
                    }
                }
                Spacer()
            }
        }
        .sheet(item: $renaming) { shape in
            VStack(alignment: .leading) {
                Text("Rename Shape").font(.headline)
                TextField("Name", text: $renameText)
                Text("Gestures bound to this shape are updated too.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { renaming = nil }.keyboardShortcut(.cancelAction)
                    Button("Rename") {
                        store.renameShape(id: shape.id, to: renameText.trimmingCharacters(in: .whitespaces))
                        renaming = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
            .frame(width: 320)
        }
    }

    private func delete(_ id: ShapeTemplate.ID) {
        store.shapes.removeAll { $0.id == id }
        if selection == id { selection = nil }
    }

    private func deleteSample(_ index: Int, of id: ShapeTemplate.ID) {
        guard let i = store.shapes.firstIndex(where: { $0.id == id }) else { return }
        store.shapes[i].samples.remove(at: index)
    }

    private func restoreBuiltIns() {
        let existing = Set(store.shapes.map(\.name))
        store.shapes += BuiltInShapes.all.filter { !existing.contains($0.name) }
    }
}

/// Small drawing of a sample; a dot marks where the stroke starts.
struct ShapePreview: View {
    let points: [CGPoint]

    var body: some View {
        Canvas { context, size in
            guard let normalized = ShapeRecognizer.normalize(points), let first = normalized.first else { return }
            let inset: CGFloat = 5
            let scale = min(size.width, size.height) - inset * 2
            // normalize() centres on the centroid in a unit box; flip y for screen coordinates.
            let map = { (p: CGPoint) in CGPoint(x: size.width / 2 + p.x * scale, y: size.height / 2 - p.y * scale) }
            var path = Path()
            path.move(to: map(first))
            normalized.dropFirst().forEach { path.addLine(to: map($0)) }
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            let start = map(first)
            context.fill(Path(ellipseIn: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6)), with: .color(.green))
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }
}
