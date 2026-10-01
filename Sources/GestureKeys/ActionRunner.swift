import AppKit
import GestureCore
import os

enum ActionRunner {
    private static let log = Logger(subsystem: "com.donjmilligan.GestureKeys", category: "actions")

    static func run(_ action: GestureAction) {
        switch action {
        case let .keyboardShortcut(combo):
            post(combo)
        case let .shellCommand(command):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            do {
                try process.run()
            } catch {
                log.error("Shell command failed to start: \(error.localizedDescription)")
            }
        }
    }

    /// Synthesizes the key press. Needs Accessibility permission; without it macOS silently drops the events.
    static func post(_ combo: KeyCombo) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false)
        else { return }

        var flags = combo.modifiers.cgFlags
        // Match what a real keyboard sends; some system shortcuts (e.g. ⌃← to switch Spaces) require it.
        if KeyNames.functionFlagKeys.contains(combo.keyCode) { flags.insert(.maskSecondaryFn) }
        if KeyNames.arrowKeys.contains(combo.keyCode) { flags.insert(.maskNumericPad) }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
