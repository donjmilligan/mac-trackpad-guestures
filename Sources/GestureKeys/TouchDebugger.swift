import AppKit
import GestureCore

/// `GestureKeys --debug-touches`: prints finger counts, raw touch states and detected gestures
/// to the terminal. Handy for checking the trackpad is being read and for tuning thresholds.
enum TouchDebugger {
    static func run() -> Never {
        setvbuf(stdout, nil, _IOLBF, 0) // flush each line even when piped
        let settings = ConfigStore().config.engine
        var engines: [UInt: GestureEngine] = [:]
        var lastSummary = ""

        TouchListener.shared.onFrame = { device, touches, timestamp in
            let engine = engines[device] ?? GestureEngine(settings: settings, surfaceMM: TouchListener.shared.surfaceSize(of: device))
            if engines[device] == nil {
                print("device \(String(device, radix: 16)): surface \(engine.surfaceMM.width) × \(engine.surfaceMM.height) mm")
                engines[device] = engine
            }

            let touching = touches.filter(\.isTouching).count
            let states = touches.map { String(format: "#%d(%.2f,%.2f)%@", $0.id, $0.x, $0.y, $0.isTouching ? "" : "·") }
            let summary = "fingers: \(touching)  " + states.joined(separator: " ")
            if summary.prefix(12) != lastSummary.prefix(12) { print(summary) }
            lastSummary = summary

            for event in engine.process(touches: touches, timestamp: timestamp, modifiers: ModifierSet(NSEvent.modifierFlags)) {
                switch event {
                case .drawMoved: break
                case let .drawEnded(stroke): print("→ drawEnded (\(stroke.count) points, \(Int(ShapeRecognizer.pathLength(stroke))) mm)")
                default: print("→ \(event)")
                }
            }
        }

        guard TouchListener.shared.start() else {
            print("Couldn't load MultitouchSupport.framework.")
            exit(1)
        }
        print("Listening to \(TouchListener.shared.deviceCount) device(s). Touch the trackpad; Ctrl-C to quit.")
        print("(· marks contacts that are hovering or lifting rather than touching)")
        dispatchMain()
    }
}
