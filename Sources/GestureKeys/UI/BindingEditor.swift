import GestureCore
import SwiftUI

struct BindingEditor: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var controller: GestureController
    @Environment(\.dismiss) private var dismiss

    let original: GestureBinding
    let onSave: (GestureBinding) -> Void

    private enum Kind: String, CaseIterable { case swipe = "Swipe", rotate = "Rotate", tap = "Tap", shape = "Shape" }
    private enum ActionKind: String, CaseIterable {
        case shortcut = "Keyboard Shortcut", system = "System Action", shell = "Shell Command"
    }

    @State private var kind: Kind
    @State private var fingers: Int
    @State private var taps: Int
    @State private var direction: SwipeDirection
    @State private var rotation: RotateDirection
    @State private var rotateThen: SwipeDirection?
    @State private var shapeName: String
    @State private var actionKind: ActionKind
    @State private var combo: KeyCombo?
    @State private var command: String
    @State private var systemAction: SystemAction
    @State private var appBundleID: String?

    init(original: GestureBinding, onSave: @escaping (GestureBinding) -> Void) {
        self.original = original
        self.onSave = onSave

        var kind = Kind.swipe, fingers = 5, taps = 1, direction = SwipeDirection.up, rotation = RotateDirection.right
        var rotateThen: SwipeDirection?, shapeName = ""
        switch original.trigger {
        case let .swipe(f, d): (kind, fingers, direction) = (.swipe, f, d)
        case let .rotate(f, r, t): (kind, fingers, rotation, rotateThen) = (.rotate, f, r, t)
        case let .tap(f, t): (kind, fingers, taps) = (.tap, f, t)
        case let .shape(name): (kind, shapeName) = (.shape, name)
        }
        _rotateThen = State(initialValue: rotateThen)
        _kind = State(initialValue: kind)
        _fingers = State(initialValue: fingers)
        _taps = State(initialValue: taps)
        _direction = State(initialValue: direction)
        _rotation = State(initialValue: rotation)
        _shapeName = State(initialValue: shapeName)

        var actionKind = ActionKind.shortcut, combo: KeyCombo?, command = "", systemAction = SystemAction.back
        switch original.action {
        case let .keyboardShortcut(c): (actionKind, combo) = (.shortcut, c)
        // New bindings arrive with an empty command; default those to a shortcut.
        case let .shellCommand(c): (actionKind, command) = (c.isEmpty ? .shortcut : .shell, c)
        case let .system(a): (actionKind, systemAction) = (.system, a)
        }
        _actionKind = State(initialValue: actionKind)
        _combo = State(initialValue: combo)
        _command = State(initialValue: command)
        _systemAction = State(initialValue: systemAction)
        _appBundleID = State(initialValue: original.appBundleID)
    }

    private var trigger: Trigger {
        switch kind {
        case .swipe: .swipe(fingers: fingers, direction: direction)
        case .rotate: .rotate(fingers: fingers, direction: rotation, then: rotateThen)
        case .tap: .tap(fingers: fingers, taps: taps)
        case .shape: .shape(name: shapeName)
        }
    }

    private var action: GestureAction? {
        switch actionKind {
        case .shortcut: combo.map { .keyboardShortcut(combo: $0) }
        case .system: .system(action: systemAction)
        case .shell: command.trimmingCharacters(in: .whitespaces).isEmpty ? nil : .shellCommand(command: command)
        }
    }

    private var conflict: GestureBinding? {
        store.config.bindings.first { $0.id != original.id && $0.trigger == trigger && $0.appBundleID == appBundleID }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Gesture") {
                    Picker("Type", selection: $kind) {
                        ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    if kind != .shape {
                        Picker("Fingers", selection: $fingers) {
                            ForEach(2...5, id: \.self) { Text("\($0)") }
                        }
                        .pickerStyle(.segmented)
                    }
                    if kind == .tap {
                        Picker("Taps", selection: $taps) {
                            ForEach(1...4, id: \.self) { Text(Trigger.tapName($0).capitalized) }
                        }
                        .pickerStyle(.segmented)
                        if taps > 1 {
                            Text("Fewer taps with \(fingers) fingers wait \(Int(store.config.engine.multiTapInterval * 1000)) ms to see if another tap follows. Adjust in Preferences.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if kind == .swipe {
                        Picker("Direction", selection: $direction) {
                            ForEach(SwipeDirection.allCases, id: \.self) { Text("\($0.arrow) \($0.rawValue.capitalized)") }
                        }
                        .pickerStyle(.segmented)
                    }
                    if kind == .rotate {
                        Picker("Direction", selection: $rotation) {
                            ForEach(RotateDirection.allCases, id: \.self) {
                                Text("\($0.arrow) \($0 == .right ? "Right (clockwise)" : "Left (counterclockwise)")")
                            }
                        }
                        .pickerStyle(.segmented)
                        Picker("Then", selection: $rotateThen) {
                            Text("Lift").tag(SwipeDirection?.none)
                            ForEach(SwipeDirection.allCases, id: \.self) {
                                Text("\($0.arrow) \($0.rawValue.capitalized)").tag(SwipeDirection?.some($0))
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Rest the fingers on the trackpad and turn your hand like a knob, about \(Int(store.config.engine.rotateAngleDegrees))°. "
                            + (rotateThen == nil ? "Fires when you lift." : "Then, without lifting, drag \(rotateThen!.rawValue)."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if kind == .shape {
                        Picker("Shape", selection: $shapeName) {
                            if shapeName.isEmpty { Text("Choose…").tag("") }
                            ForEach(store.shapes) { Text($0.name).tag($0.name) }
                        }
                        Text("Hold \(store.config.engine.drawModifiers.symbols) and draw with one finger. Add or record shapes on the Shapes tab.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let last = controller.lastTrigger, last != trigger {
                        Button("Use last performed: \(last.displayName)") { apply(last) }
                    }
                    if kind != .shape, fingers <= 2 || (kind == .swipe && fingers <= 4) {
                        Text(systemConflictHint)
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                Section("Action") {
                    Picker("Do", selection: $actionKind) {
                        ForEach(ActionKind.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    switch actionKind {
                    case .shortcut:
                        LabeledContent("Shortcut") { ShortcutRecorder(combo: $combo) }
                    case .system:
                        Picker("Action", selection: $systemAction) {
                            ForEach(SystemAction.groups, id: \.0) { group, actions in
                                Section(group) {
                                    ForEach(actions, id: \.self) { Text($0.title) }
                                }
                            }
                        }
                        if let hint = systemActionHint {
                            Text(hint).font(.caption).foregroundStyle(.secondary)
                        }
                    case .shell:
                        TextField("Command", text: $command, prompt: Text("open -a Safari"))
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Section("Only In") {
                    AppPicker(selection: $appBundleID)
                }

                if let conflict {
                    Text("“\(conflict.action.displayName)” is already bound to this gesture for the same app; only one of them will run.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let action else { return }
                    var binding = original
                    binding.trigger = trigger
                    binding.action = action
                    binding.appBundleID = appBundleID
                    onSave(binding)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(action == nil || (kind == .shape && shapeName.isEmpty))
            }
            .padding()
        }
        .frame(width: 520, height: 560)
    }

    private var systemConflictHint: String {
        if fingers == 2, kind == .rotate { return "2-finger rotation is also macOS’s rotate gesture (Photos, Maps, Preview)." }
        if fingers == 2 { return "2-finger gestures overlap with scrolling and secondary click." }
        if fingers == 3 { return "Turn off 3-finger drag / swipes in System Settings › Trackpad if they’re enabled." }
        return "Turn off macOS 4-finger swipes in System Settings › Trackpad › More Gestures, or both will fire."
    }

    private var systemActionHint: String? {
        switch systemAction {
        case .back, .forward: "Sends the mouse back/forward button; ⌘[ / ⌘] in Safari, Finder and the App Store, which ignore it."
        case .middleClick: "Clicks at the pointer, e.g. to open a link in a new tab or close a tab."
        default: nil
        }
    }

    private func apply(_ trigger: Trigger) {
        switch trigger {
        case let .swipe(f, d): (kind, fingers, direction) = (.swipe, f, d)
        case let .rotate(f, r, t): (kind, fingers, rotation, rotateThen) = (.rotate, f, r, t)
        case let .tap(f, t): (kind, fingers, taps) = (.tap, f, t)
        case let .shape(name): (kind, shapeName) = (.shape, name)
        }
    }
}
