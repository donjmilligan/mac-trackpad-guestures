import CoreGraphics
import Foundation

public struct TouchPoint: Sendable {
    public var id: Int32
    /// Normalized 0...1, origin bottom-left.
    public var x: Double
    public var y: Double
    public var isTouching: Bool

    public init(id: Int32, x: Double, y: Double, isTouching: Bool = true) {
        self.id = id
        self.x = x
        self.y = y
        self.isTouching = isTouching
    }
}

/// Turns raw touch frames from one trackpad into swipe, rotate, tap and drawing events.
///
/// A "session" runs from the first finger landing until the last one lifts. Each session
/// produces at most one swipe, rotation or tap, or a single drawing stroke. A rotation can be
/// followed by a drag in the same session, which turns it into a rotate-then-swipe.
public final class GestureEngine {
    public enum Event: Equatable, Sendable {
        case swipe(fingers: Int, direction: SwipeDirection)
        /// The fingers turned far enough; a drag may still follow before they lift.
        case rotateRecognized(fingers: Int, direction: RotateDirection)
        /// Sent on lift (`then` nil) or as soon as a drag after the rotation is recognized.
        case rotate(fingers: Int, direction: RotateDirection, then: SwipeDirection?)
        case tap(fingers: Int)
        case drawBegan
        /// Normalized position of the drawing finger, for live feedback.
        case drawMoved(CGPoint)
        /// The finished stroke in millimetres (aspect-correct), for recognition.
        case drawEnded([CGPoint])
        case drawCancelled
    }

    public var settings: EngineSettings
    /// Physical size of the touch surface in millimetres.
    public let surfaceMM: CGSize

    private var active = false
    private var startTime = 0.0
    private var maxFingers = 0
    private var consumed = false
    private var origins: [Int32: CGPoint] = [:]
    private var baseline: [Int32: CGPoint] = [:]
    private var maxTravel = 0.0
    private var rotated: (fingers: Int, direction: RotateDirection)?
    private var stroke: [CGPoint]?

    public init(settings: EngineSettings, surfaceMM: CGSize) {
        self.settings = settings
        self.surfaceMM = surfaceMM
    }

    public var isDrawing: Bool { stroke != nil }

    public func reset() {
        active = false
        stroke = nil
    }

    public func process(touches: [TouchPoint], timestamp: Double, modifiers: ModifierSet) -> [Event] {
        let down = touches.filter(\.isTouching)
        var events: [Event] = []

        if down.isEmpty {
            if active { events += finishSession(at: timestamp) }
            return events
        }

        if !active {
            active = true
            startTime = timestamp
            maxFingers = 0
            consumed = false
            origins = [:]
            baseline = [:]
            maxTravel = 0
            rotated = nil
            if down.count == 1, !settings.drawModifiers.isEmpty, modifiers.isSuperset(of: settings.drawModifiers) {
                stroke = []
                events.append(.drawBegan)
            }
        }

        maxFingers = max(maxFingers, down.count)

        var positions: [Int32: CGPoint] = [:]
        for touch in down {
            let p = CGPoint(x: touch.x * surfaceMM.width, y: touch.y * surfaceMM.height)
            positions[touch.id] = p
            let origin = origins[touch.id] ?? p
            origins[touch.id] = origin
            maxTravel = max(maxTravel, hypot(p.x - origin.x, p.y - origin.y))
        }

        if stroke != nil {
            if down.count > 1 {
                // A second finger landed: this isn't a drawing after all.
                stroke = nil
                consumed = true
                events.append(.drawCancelled)
                return events
            }
            stroke!.append(positions[down[0].id]!)
            events.append(.drawMoved(CGPoint(x: down[0].x, y: down[0].y)))
            return events
        }

        if consumed { return events }

        // Fingers rarely land or lift at the same instant, so measure movement from the
        // moment the current set of fingers became stable.
        if Set(positions.keys) != Set(baseline.keys) {
            baseline = positions
            return events
        }

        var dx = 0.0, dy = 0.0
        for (id, p) in positions {
            let b = baseline[id]!
            dx += p.x - b.x
            dy += p.y - b.y
        }
        dx /= Double(positions.count)
        dy /= Double(positions.count)

        if let rotated {
            // Hands keep turning past the threshold, which shifts the fingers' centre. Restart the drag
            // measurement while the turn continues so that isn't mistaken for a drag.
            if abs(Self.rotationDegrees(from: baseline, to: positions)) >= settings.rotateAngleDegrees / 3 {
                baseline = positions
                return events
            }
            guard let direction = swipeDirection(dx: dx, dy: dy) else { return events }
            consumed = true
            events.append(.rotate(fingers: rotated.fingers, direction: rotated.direction, then: direction))
            return events
        }

        let rotation = positions.count >= 2 ? Self.rotationDegrees(from: baseline, to: positions) : 0
        if abs(rotation) >= settings.rotateAngleDegrees {
            // Positions are y-up, so a clockwise turn is a negative angle.
            let recognized = (fingers: down.count, direction: rotation < 0 ? RotateDirection.right : .left)
            rotated = recognized
            baseline = positions // measure any drag from here
            events.append(.rotateRecognized(fingers: recognized.fingers, direction: recognized.direction))
            return events
        }
        // A twisting hand also drifts; don't let that drift fire a swipe before the rotation is recognized.
        guard abs(rotation) < settings.rotateAngleDegrees * 0.4, let direction = swipeDirection(dx: dx, dy: dy)
        else { return events }

        consumed = true
        events.append(.swipe(fingers: down.count, direction: direction))
        return events
    }

    /// The direction of an average movement, or nil while it's too short or too diagonal to tell.
    private func swipeDirection(dx: Double, dy: Double) -> SwipeDirection? {
        guard hypot(dx, dy) >= settings.swipeDistanceMM else { return nil }
        if abs(dx) >= abs(dy) * 1.5 { return dx > 0 ? .right : .left }
        if abs(dy) >= abs(dx) * 1.5 { return dy > 0 ? .up : .down }
        return nil // diagonal: wait until one axis clearly dominates
    }

    /// Average angle (degrees, counterclockwise positive) each finger turned around the fingers' centre.
    /// Unaffected by the hand sliding or spreading, so swipes and pinches read as ~0.
    static func rotationDegrees(from start: [Int32: CGPoint], to end: [Int32: CGPoint]) -> Double {
        func centroid(_ points: [Int32: CGPoint]) -> CGPoint {
            let sum = points.values.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            return CGPoint(x: sum.x / Double(points.count), y: sum.y / Double(points.count))
        }
        let c0 = centroid(start), c1 = centroid(end)
        var total = 0.0, count = 0
        for (id, p1) in end {
            guard let p0 = start[id] else { continue }
            let v0 = CGPoint(x: p0.x - c0.x, y: p0.y - c0.y), v1 = CGPoint(x: p1.x - c1.x, y: p1.y - c1.y)
            // A finger right at the centre has no meaningful angle.
            guard hypot(v0.x, v0.y) > 5, hypot(v1.x, v1.y) > 5 else { continue }
            var delta = atan2(v1.y, v1.x) - atan2(v0.y, v0.x)
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            total += delta
            count += 1
        }
        return count == 0 ? 0 : total / Double(count) * 180 / .pi
    }

    private func finishSession(at timestamp: Double) -> [Event] {
        defer {
            active = false
            stroke = nil
        }
        if let stroke { return [.drawEnded(stroke)] }
        if let rotated, !consumed { return [.rotate(fingers: rotated.fingers, direction: rotated.direction, then: nil)] }
        if !consumed,
           timestamp - startTime <= settings.tapMaxDuration,
           maxTravel <= settings.tapMaxMovementMM
        {
            return [.tap(fingers: maxFingers)]
        }
        return []
    }
}
