import AppKit
import ApplicationServices
import Combine
import GestureCore

/// Glue between the touch listener, the per-device gesture engines and the actions.
final class GestureController: ObservableObject {
    /// Most recent multi-finger gesture or shape, bound or not. Lets the editor offer "use last gesture".
    @Published private(set) var lastTrigger: Trigger?
    /// Human-readable result of the last drawing (shown on the Shapes tab).
    @Published private(set) var lastRecognition = ""
    /// Name of the shape whose next stroke will be recorded as a sample.
    @Published private(set) var recordingShapeName: String?
    @Published private(set) var deviceCount = 0
    @Published private(set) var listenerFailed = false
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()

    let store: ConfigStore
    private var engines: [UInt: GestureEngine] = [:]
    private var recognizer: ShapeRecognizer
    private let overlay = DrawingOverlay()
    private let hud = HUD()
    private var cursorAnchor: CGPoint?
    /// Taps counted so far that may still become a double/triple tap.
    private var pendingTap: (fingers: Int, taps: Int)?
    private var pendingTapTimeout: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    init(store: ConfigStore) {
        self.store = store
        recognizer = ShapeRecognizer(templates: store.shapes)

        store.$shapes
            .sink { [weak self] in self?.recognizer = ShapeRecognizer(templates: $0) }
            .store(in: &cancellables)
        store.$config
            .map(\.engine)
            .removeDuplicates()
            .sink { [weak self] settings in self?.engines.values.forEach { $0.settings = settings } }
            .store(in: &cancellables)

        // Trackpads stop reporting after sleep; restart once the machine is awake again.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .delay(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.restartListener() }
            .store(in: &cancellables)

        Timer.publish(every: 2, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                let trusted = AXIsProcessTrusted()
                if self?.accessibilityTrusted != trusted { self?.accessibilityTrusted = trusted }
            }
            .store(in: &cancellables)
    }

    func start() {
        TouchListener.shared.onFrame = { [weak self] device, touches, timestamp in
            self?.handleFrame(device: device, touches: touches, timestamp: timestamp)
        }
        restartListener()
    }

    func restartListener() {
        TouchListener.shared.stop()
        engines = [:]
        listenerFailed = !TouchListener.shared.start()
        deviceCount = TouchListener.shared.deviceCount
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Shape recording

    func beginRecording(shapeName: String) {
        recordingShapeName = shapeName
        lastRecognition = ""
    }

    func cancelRecording() {
        recordingShapeName = nil
    }

    // MARK: Frame handling

    private func handleFrame(device: UInt, touches: [TouchPoint], timestamp: Double) {
        guard store.config.enabled || recordingShapeName != nil else { return }

        let engine = engines[device] ?? {
            let engine = GestureEngine(settings: store.config.engine, surfaceMM: TouchListener.shared.surfaceSize(of: device))
            engines[device] = engine
            return engine
        }()

        let modifiers = ModifierSet(NSEvent.modifierFlags)
        for event in engine.process(touches: touches, timestamp: timestamp, modifiers: modifiers) {
            handle(event, from: engine)
        }
    }

    private func handle(_ event: GestureEngine.Event, from engine: GestureEngine) {
        switch event {
        case let .swipe(fingers, direction):
            flushPendingTap()
            if fingers >= 2 { fire(.swipe(fingers: fingers, direction: direction)) }
        case let .rotateRecognized(fingers, direction):
            flushPendingTap()
            // Two-step gesture: confirm the turn so you know a drag will now pick a command.
            if fingers >= 3, store.config.showHUD { hud.show("\(direction.arrow)  drag ↑ ↓ ← → or lift") }
        case let .rotate(fingers, direction, then):
            if fingers >= 2 { fire(.rotate(fingers: fingers, direction: direction, then: then)) }
        case let .tap(fingers):
            if fingers >= 2 { countTap(fingers: fingers) }
        case .drawBegan:
            flushPendingTap()
            overlay.begin(aspect: engine.surfaceMM.width / engine.surfaceMM.height)
            freezeCursor()
        case let .drawMoved(point):
            overlay.add(point)
            holdCursor()
        case .drawCancelled:
            overlay.end()
            releaseCursor()
        case let .drawEnded(stroke):
            overlay.end()
            releaseCursor()
            finishStroke(stroke)
        }
    }

    // MARK: Multi-taps

    /// Fires as soon as no bound tap needs more taps; otherwise waits `multiTapInterval` for the next one.
    private func countTap(fingers: Int) {
        pendingTapTimeout?.cancel()
        var taps = 1
        if let pending = pendingTap {
            if pending.fingers == fingers { taps = pending.taps + 1 } else { flushPendingTap() }
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if taps >= store.config.maxTaps(fingers: fingers, frontmostApp: frontmost) {
            pendingTap = nil
            fire(.tap(fingers: fingers, taps: taps))
        } else {
            pendingTap = (fingers, taps)
            let timeout = DispatchWorkItem { [weak self] in self?.flushPendingTap() }
            pendingTapTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + store.config.engine.multiTapInterval, execute: timeout)
        }
    }

    private func flushPendingTap() {
        pendingTapTimeout?.cancel()
        pendingTapTimeout = nil
        guard let pending = pendingTap else { return }
        pendingTap = nil
        fire(.tap(fingers: pending.fingers, taps: pending.taps))
    }

    private func finishStroke(_ stroke: [CGPoint]) {
        guard ShapeRecognizer.pathLength(stroke) >= 10 else { return } // a nudge, not a drawing

        if let name = recordingShapeName {
            recordingShapeName = nil
            store.addSample(stroke, toShapeNamed: name)
            lastRecognition = "Recorded a sample for “\(name)”."
            hud.show("Recorded “\(name)”")
            return
        }

        guard let match = recognizer.recognize(stroke) else { return }
        let score = String(format: "%.0f%%", match.score * 100)
        guard match.score >= store.config.engine.minimumShapeScore else {
            lastRecognition = "No match (closest: “\(match.name)” at \(score))"
            if store.config.showHUD { hud.show("Unrecognized shape") }
            return
        }
        lastRecognition = "“\(match.name)” (\(score))"
        // The activator modifier is often still held when the finger lifts; wait so it doesn't leak into the shortcut.
        whenModifiersReleased(store.config.engine.drawModifiers) { [weak self] in
            self?.fire(.shape(name: match.name))
        }
    }

    private func fire(_ trigger: Trigger) {
        // 2-finger swipes/taps happen constantly (scrolling, right-click) and would drown out the gesture you just tried.
        switch trigger {
        case .swipe(fingers: 2, _), .rotate(fingers: 2, _, _), .tap(fingers: 2, _): break
        default: lastTrigger = trigger
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let binding = store.config.binding(for: trigger, frontmostApp: frontmost) else { return }
        var result = binding.action.displayName
        if binding.action == .system(action: .nextProfile) {
            store.config.activateNextProfile()
            result = "Profile: \(store.config.activeProfile.name)"
        } else {
            ActionRunner.run(binding.action)
        }
        if store.config.showHUD {
            hud.show("\(trigger.displayName)  →  \(result)")
        }
    }

    private func whenModifiersReleased(_ modifiers: ModifierSet, deadline: Date = Date() + 1.5, _ work: @escaping () -> Void) {
        if ModifierSet(NSEvent.modifierFlags).isDisjoint(with: modifiers) || Date() > deadline {
            work()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.whenModifiersReleased(modifiers, deadline: deadline, work)
            }
        }
    }

    // MARK: Cursor

    // While drawing, the finger would otherwise drag the pointer across the screen.
    private func freezeCursor() {
        cursorAnchor = CGEvent(source: nil)?.location
        CGAssociateMouseAndMouseCursorPosition(0)
    }

    private func holdCursor() {
        // Disassociating only works reliably for the frontmost app, so also pin the pointer in place.
        if let anchor = cursorAnchor { CGWarpMouseCursorPosition(anchor) }
    }

    private func releaseCursor() {
        CGAssociateMouseAndMouseCursorPosition(1)
        cursorAnchor = nil
    }
}
