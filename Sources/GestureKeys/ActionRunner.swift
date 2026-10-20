import AppKit
import GestureCore
import IOKit.hidsystem
import os

enum ActionRunner {
    private static let log = Logger(subsystem: "com.donjmilligan.GestureKeys", category: "actions")

    static func run(_ action: GestureAction) {
        switch action {
        case let .keyboardShortcut(combo):
            post(combo)
        case let .shellCommand(command):
            launch("/bin/zsh", ["-lc", command])
        case let .system(action):
            run(action)
        }
    }

    private static func run(_ action: SystemAction) {
        switch action {
        case .back: navigate(button: 3, fallbackKey: 33) // ⌘[
        case .forward: navigate(button: 4, fallbackKey: 30) // ⌘]
        case .middleClick: click(button: 2)
        case .playPause: postMediaKey(NX_KEYTYPE_PLAY)
        case .nextTrack: postMediaKey(NX_KEYTYPE_FAST)
        case .previousTrack: postMediaKey(NX_KEYTYPE_REWIND)
        case .volumeUp: postMediaKey(NX_KEYTYPE_SOUND_UP)
        case .volumeDown: postMediaKey(NX_KEYTYPE_SOUND_DOWN)
        case .mute: postMediaKey(NX_KEYTYPE_MUTE)
        case .brightnessUp: postMediaKey(NX_KEYTYPE_BRIGHTNESS_UP)
        case .brightnessDown: postMediaKey(NX_KEYTYPE_BRIGHTNESS_DOWN)
        case .sleepDisplay: launch("/usr/bin/pmset", ["displaysleepnow"])
        case .missionControl: Dock.send("com.apple.expose.awake")
        case .appExpose: Dock.send("com.apple.expose.front.awake")
        case .showDesktop: Dock.send("com.apple.showdesktop.awake")
        case .nextProfile: break // needs the config; GestureController handles it
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

    /// Apps that ignore the mouse back/forward buttons but take ⌘[ / ⌘].
    private static let sideButtonDeaf: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.apple.finder", "com.apple.AppStore",
    ]

    private static func navigate(button: Int64, fallbackKey: UInt16) {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let frontmost, sideButtonDeaf.contains(frontmost) {
            post(KeyCombo(keyCode: fallbackKey, modifiers: .command))
        } else {
            click(button: button)
        }
    }

    /// Clicks an "other" mouse button (2 = middle, 3 = back, 4 = forward) at the pointer.
    private static func click(button: Int64) {
        let source = CGEventSource(stateID: .hidSystemState)
        let location = CGEvent(source: nil)?.location ?? .zero
        let mouseButton = CGMouseButton(rawValue: UInt32(button)) ?? .center
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                      mouseCursorPosition: location, mouseButton: mouseButton)
            else { return }
            event.setIntegerValueField(.mouseEventButtonNumber, value: button)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Media and brightness keys are "system defined" events, not key codes (see IOKit's ev_keymap.h).
    private static func postMediaKey(_ key: Int32) {
        for (flags, state) in [(0xA00, 0xA), (0xB00, 0xB)] { // key down, key up
            NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: Int(key) << 16 | state << 8, data2: -1
            )?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private static func launch(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            log.error("\(path) failed to start: \(error.localizedDescription)")
        }
    }
}

/// The Dock's private notification hook, which Mission Control and friends listen on. Same approach as
/// BetterTouchTool et al.; loaded lazily so a future macOS removing it only disables these actions.
private enum Dock {
    private typealias SendNotification = @convention(c) (CFString, Int32) -> Void

    private static let sendNotification: SendNotification? = {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        guard let handle = dlopen(path, RTLD_LAZY), let symbol = dlsym(handle, "CoreDockSendNotification")
        else { return nil }
        return unsafeBitCast(symbol, to: SendNotification.self)
    }()

    static func send(_ notification: String) {
        sendNotification?(notification as CFString, 0)
    }
}
