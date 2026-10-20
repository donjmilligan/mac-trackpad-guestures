import CoreGraphics
import Foundation
import GestureCore

// Run with `swift run SelfTest`. Exits non-zero on failure.

var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition {
        print("  ✓ \(message)")
    } else {
        failures += 1
        print("  ✗ \(message) (line \(line))")
    }
}

let surface = CGSize(width: 160, height: 100)

/// Feeds `fingers` touches that start at `start` and move by `delta` (normalized) over `steps` frames, then lift.
func runGesture(fingers: Int, delta: CGPoint, steps: Int = 20, duration: Double = 0.3,
                modifiers: ModifierSet = [], engine: GestureEngine? = nil) -> [GestureEngine.Event] {
    let engine = engine ?? GestureEngine(settings: EngineSettings(), surfaceMM: surface)
    var events: [GestureEngine.Event] = []
    for step in 0...steps {
        let t = Double(step) / Double(steps)
        let touches = (0..<fingers).map { i in
            TouchPoint(id: Int32(i), x: 0.3 + Double(i) * 0.08 + delta.x * t, y: 0.4 + delta.y * t)
        }
        events += engine.process(touches: touches, timestamp: duration * t, modifiers: modifiers)
    }
    events += engine.process(touches: [], timestamp: duration + 0.01, modifiers: modifiers)
    return events
}

print("GestureEngine")
check(runGesture(fingers: 5, delta: CGPoint(x: 0, y: 0.3)) == [.swipe(fingers: 5, direction: .up)], "5-finger swipe up")
check(runGesture(fingers: 4, delta: CGPoint(x: -0.25, y: 0.02)) == [.swipe(fingers: 4, direction: .left)], "4-finger swipe left")
check(runGesture(fingers: 3, delta: CGPoint(x: 0, y: -0.3)) == [.swipe(fingers: 3, direction: .down)], "3-finger swipe down")
check(runGesture(fingers: 5, delta: CGPoint(x: 0.2, y: 0.32)).isEmpty, "45° diagonal (in mm) is ignored")
check(runGesture(fingers: 3, delta: CGPoint(x: 0.005, y: 0), steps: 4, duration: 0.12) == [.tap(fingers: 3)], "3-finger tap")
check(runGesture(fingers: 3, delta: .zero, steps: 4, duration: 0.6).isEmpty, "long press is not a tap")
check(runGesture(fingers: 5, delta: CGPoint(x: 0, y: 0.05)).isEmpty, "small movement is neither swipe nor tap")

/// Five fingers on a 25 mm circle turning by `degrees` (counterclockwise positive) while the hand drifts by `drift` mm,
/// then, without lifting, dragging by `drag` mm.
func runRotation(degrees: Double, drift: CGPoint = .zero, drag: CGPoint = .zero) -> [GestureEngine.Event] {
    let engine = GestureEngine(settings: EngineSettings(), surfaceMM: surface)
    var events: [GestureEngine.Event] = []
    func frame(angle: Double, center: CGPoint, at time: Double) {
        let touches = (0..<5).map { i -> TouchPoint in
            let a = (Double(i) * 50 + 20 + angle) * .pi / 180
            return TouchPoint(id: Int32(i), x: (center.x + 25 * cos(a)) / surface.width,
                              y: (center.y + 25 * sin(a)) / surface.height)
        }
        events += engine.process(touches: touches, timestamp: time, modifiers: [])
    }
    for step in 0...20 {
        let t = Double(step) / 20
        frame(angle: degrees * t, center: CGPoint(x: 80 + drift.x * t, y: 50 + drift.y * t), at: 0.5 * t)
    }
    for step in 1...15 {
        let t = Double(step) / 15
        frame(angle: degrees, center: CGPoint(x: 80 + drift.x + drag.x * t, y: 50 + drift.y + drag.y * t), at: 0.5 + 0.3 * t)
    }
    events += engine.process(touches: [], timestamp: 0.9, modifiers: [])
    return events
}

check(runRotation(degrees: -40) == [.rotateRecognized(fingers: 5, direction: .right), .rotate(fingers: 5, direction: .right, then: nil)],
      "5-finger clockwise turn, lift → rotate right")
check(runRotation(degrees: 40) == [.rotateRecognized(fingers: 5, direction: .left), .rotate(fingers: 5, direction: .left, then: nil)],
      "5-finger counterclockwise turn, lift → rotate left")
check(runRotation(degrees: -40, drift: CGPoint(x: 18, y: 6)).last == .rotate(fingers: 5, direction: .right, then: nil),
      "a turn that drifts sideways is still a rotation, not a swipe")
check(runRotation(degrees: 7).isEmpty, "a small turn does nothing")

let drags: [(SwipeDirection, CGPoint)] = [(.up, CGPoint(x: 0, y: 25)), (.down, CGPoint(x: 0, y: -25)),
                                          (.left, CGPoint(x: -25, y: 0)), (.right, CGPoint(x: 25, y: 0))]
for (rotation, degrees) in [(RotateDirection.right, -40.0), (.left, 40.0)] {
    for (direction, drag) in drags {
        let events = runRotation(degrees: degrees, drag: drag)
        check(events == [.rotateRecognized(fingers: 5, direction: rotation), .rotate(fingers: 5, direction: rotation, then: direction)],
              "rotate \(rotation.rawValue) then drag \(direction.rawValue)")
    }
}
check(runRotation(degrees: -90, drift: CGPoint(x: 10, y: -10)).last == .rotate(fingers: 5, direction: .right, then: nil),
      "turning well past the threshold isn't read as a drag")
check(runRotation(degrees: -60, drag: CGPoint(x: -25, y: 2)).last == .rotate(fingers: 5, direction: .right, then: .left),
      "overshooting the turn doesn't change the drag")
check(runRotation(degrees: -40, drag: CGPoint(x: 20, y: 20)).last == .rotate(fingers: 5, direction: .right, then: nil),
      "a diagonal drag after a turn falls back to plain rotate")
check(runRotation(degrees: -40, drag: CGPoint(x: 0, y: 8)).last == .rotate(fingers: 5, direction: .right, then: nil),
      "a short drag after a turn falls back to plain rotate")

do {
    // Fingers landing one at a time shouldn't produce a swipe with the wrong count.
    let engine = GestureEngine(settings: EngineSettings(), surfaceMM: surface)
    var events: [GestureEngine.Event] = []
    for n in 1...5 {
        let touches = (0..<n).map { TouchPoint(id: Int32($0), x: 0.3 + Double($0) * 0.08, y: 0.4) }
        events += engine.process(touches: touches, timestamp: Double(n) * 0.01, modifiers: [])
    }
    for step in 1...20 {
        let touches = (0..<5).map { TouchPoint(id: Int32($0), x: 0.3 + Double($0) * 0.08 + Double(step) * 0.015, y: 0.4) }
        events += engine.process(touches: touches, timestamp: 0.05 + Double(step) * 0.01, modifiers: [])
    }
    events += engine.process(touches: [], timestamp: 0.5, modifiers: [])
    check(events == [.swipe(fingers: 5, direction: .right)], "staggered landing → single 5-finger swipe right")
}

do {
    let events = runGesture(fingers: 1, delta: CGPoint(x: 0.3, y: 0.3), modifiers: [.option])
    check(events.first == .drawBegan, "one finger + ⌥ begins a drawing")
    if case let .drawEnded(stroke)? = events.last {
        check(stroke.count == 21, "drawing ends with the full stroke")
    } else {
        check(false, "drawing ends with the full stroke")
    }
    check(!runGesture(fingers: 1, delta: CGPoint(x: 0.3, y: 0.3)).contains(.drawBegan), "no drawing without the activator")
}

print("ShapeRecognizer")
let recognizer = ShapeRecognizer(templates: BuiltInShapes.all)

/// Distorts a built-in shape: scale, offset, slight rotation, jitter and denser sampling, as a real stroke would be.
func wobble(_ name: String, rotation: Double = 8) -> [CGPoint] {
    let base = BuiltInShapes.all.first { $0.name == name }!.samples[0]
    let dense = zip(base, base.dropFirst()).flatMap { a, b in
        (0..<15).map { i -> CGPoint in
            let t = Double(i) / 15
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    } + [base.last!]
    let angle = rotation * .pi / 180
    var seed: UInt64 = 42
    func noise() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 33) / Double(1 << 31) - 0.5
    }
    return dense.map { p in
        let x = (p.x - 0.5) * cos(angle) - (p.y - 0.5) * sin(angle)
        let y = (p.x - 0.5) * sin(angle) + (p.y - 0.5) * cos(angle)
        return CGPoint(x: 30 * x + 70 + noise() * 1.2, y: 30 * y + 40 + noise() * 1.2)
    }
}

for shape in BuiltInShapes.all {
    let match = recognizer.recognize(wobble(shape.name))
    check(match?.name == shape.name && (match?.score ?? 0) >= 0.8,
          "recognizes \(shape.name) (\(match?.name ?? "nil") \(String(format: "%.2f", match?.score ?? 0)))")
}

do {
    let reversedCircle = Array(wobble("Circle ↻").reversed())
    check(recognizer.recognize(reversedCircle)?.name != "Circle ↻", "direction matters for circles")
    let vRotated = wobble("V", rotation: 180)
    check(recognizer.recognize(vRotated)?.name == "Caret ^", "upside-down V reads as ^")
    let line = (0...30).map { CGPoint(x: Double($0), y: 0.0) }
    let lineMatch = recognizer.recognize(line)
    check((lineMatch?.score ?? 1) < 0.8, "a straight line matches nothing well (\(lineMatch?.name ?? "nil") \(String(format: "%.2f", lineMatch?.score ?? 0)))")
}

print("Config")
do {
    var config = AppConfig()
    let global = GestureBinding(trigger: .tap(fingers: 3), action: .shellCommand(command: "global"))
    let safari = GestureBinding(trigger: .tap(fingers: 3), action: .shellCommand(command: "safari"), appBundleID: "com.apple.Safari")
    config.bindings = [global, safari]
    check(config.binding(for: .tap(fingers: 3), frontmostApp: "com.apple.Safari")?.id == safari.id, "app-specific binding wins")
    check(config.binding(for: .tap(fingers: 3), frontmostApp: "com.apple.finder")?.id == global.id, "global binding elsewhere")
    check(config.binding(for: .tap(fingers: 4), frontmostApp: nil) == nil, "no binding for unbound gesture")

    let data = try! JSONEncoder().encode(config)
    let decoded = try! JSONDecoder().decode(AppConfig.self, from: data)
    check(decoded == config, "config round-trips through JSON")
    let back = try! JSONDecoder().decode(GestureAction.self, from: Data(#"{"system": {"action": "back"}}"#.utf8))
    check(back == .system(action: .back), "system action decodes from JSON")
    check(Set(SystemAction.groups.flatMap(\.1)) == Set(SystemAction.allCases), "every system action is in a picker group")
    let partial = try! JSONDecoder().decode(AppConfig.self, from: Data(#"{"enabled": false}"#.utf8))
    check(!partial.enabled && partial.engine == EngineSettings(), "missing keys fall back to defaults")
}

print("Taps & profiles")
do {
    let legacyTap = try! JSONDecoder().decode(Trigger.self, from: Data(#"{"tap": {"fingers": 3}}"#.utf8))
    check(legacyTap == .tap(fingers: 3, taps: 1), "tap without a count decodes as a single tap")
    let double = Trigger.tap(fingers: 4, taps: 2)
    check(try! JSONDecoder().decode(Trigger.self, from: JSONEncoder().encode(double)) == double, "double tap round-trips")
    check(double.displayName == "4-finger double tap", "double tap display name")
    let combo = Trigger.rotate(fingers: 5, direction: .right, then: .up)
    check(try! JSONDecoder().decode(Trigger.self, from: JSONEncoder().encode(combo)) == combo, "rotate-then-swipe round-trips")
    check(combo.displayName == "5-finger rotate right ↻ then swipe up ↑", "rotate-then-swipe display name")
    let plain = try! JSONDecoder().decode(Trigger.self, from: Data(#"{"rotate": {"fingers": 5, "direction": "left"}}"#.utf8))
    check(plain == .rotate(fingers: 5, direction: .left, then: nil), "rotate without a drag decodes")

    let legacy = #"{"bindings": [{"id": "BEF1AB03-B65E-43D0-A577-4EE099956A17", "enabled": true,"#
        + #""trigger": {"tap": {"fingers": 3}}, "action": {"shellCommand": {"command": "x"}}}]}"#
    let migrated = try! JSONDecoder().decode(AppConfig.self, from: Data(legacy.utf8))
    check(migrated.profiles.count == 1 && migrated.activeProfile.name == "Default" && migrated.bindings.count == 1,
          "pre-profile config becomes a Default profile")

    var config = AppConfig()
    config.bindings = [
        GestureBinding(trigger: .tap(fingers: 3), action: .shellCommand(command: "one")),
        GestureBinding(trigger: .tap(fingers: 3, taps: 3), action: .shellCommand(command: "three"), appBundleID: "com.apple.Safari"),
    ]
    check(config.maxTaps(fingers: 3, frontmostApp: "com.apple.Safari") == 3, "max taps counts app-specific bindings")
    check(config.maxTaps(fingers: 3, frontmostApp: "com.apple.finder") == 1, "max taps ignores other apps' bindings")
    check(config.maxTaps(fingers: 4, frontmostApp: nil) == 1, "max taps defaults to 1")

    let first = config.activeProfileID
    config.profiles.append(Profile(name: "Work"))
    config.activateNextProfile()
    check(config.activeProfile.name == "Work" && config.bindings.isEmpty, "next profile switches bindings")
    check(config.binding(for: .tap(fingers: 3), frontmostApp: nil) == nil, "inactive profile's bindings don't fire")
    config.activateNextProfile()
    check(config.activeProfileID == first, "next profile wraps around")
    let decoded = try! JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
    check(decoded == config, "profiles round-trip through JSON")
}

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
