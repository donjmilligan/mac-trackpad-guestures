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

/// Turns raw touch frames from one trackpad into swipe, tap and drawing events.
///
/// A "session" runs from the first finger landing until the last one lifts. Each session
/// produces at most one swipe or one tap, or a single drawing stroke.
public final class GestureEngine {
    public enum Event: Equatable, Sendable {
        case swipe(fingers: Int, direction: SwipeDirection)
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

        guard hypot(dx, dy) >= settings.swipeDistanceMM else { return events }

        let direction: SwipeDirection
        if abs(dx) >= abs(dy) * 1.5 {
            direction = dx > 0 ? .right : .left
        } else if abs(dy) >= abs(dx) * 1.5 {
            direction = dy > 0 ? .up : .down
        } else {
            return events // diagonal: wait until one axis clearly dominates
        }

        consumed = true
        events.append(.swipe(fingers: down.count, direction: direction))
        return events
    }

    private func finishSession(at timestamp: Double) -> [Event] {
        defer {
            active = false
            stroke = nil
        }
        if let stroke { return [.drawEnded(stroke)] }
        if !consumed,
           timestamp - startTime <= settings.tapMaxDuration,
           maxTravel <= settings.tapMaxMovementMM
        {
            return [.tap(fingers: maxFingers)]
        }
        return []
    }
}
