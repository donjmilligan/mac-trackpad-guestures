import AppKit
import GestureCore
import SwiftUI

/// Click, then press the key combination to capture. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { recording ? stop() : start() }) {
                Text(recording ? "Type shortcut…" : combo?.displayString ?? "Click to record")
                    .frame(minWidth: 140)
                    .foregroundStyle(recording ? Color.accentColor : .primary)
            }
            if combo != nil, !recording {
                Button { combo = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = ModifierSet(event.modifierFlags).subtracting(.function) // fn is implied by arrows/F-keys
            if event.keyCode == 53, modifiers.isEmpty {
                stop()
            } else {
                combo = KeyCombo(keyCode: event.keyCode, modifiers: modifiers)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
