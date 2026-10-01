import CoreGraphics
import Foundation

/// Starter shapes, y pointing up. Each assumes a particular stroke order (noted below);
/// record your own samples on the Shapes tab if you draw them differently.
public enum BuiltInShapes {
    public static var all: [ShapeTemplate] {
        [
            ShapeTemplate(name: "Circle ↻", samples: [circle(clockwise: true)]),     // start at top
            ShapeTemplate(name: "Circle ↺", samples: [circle(clockwise: false)]),    // start at top
            ShapeTemplate(name: "Check ✓", samples: [[p(0, 0.5), p(0.35, 0), p(1, 1)]]),
            ShapeTemplate(name: "V", samples: [[p(0, 1), p(0.5, 0), p(1, 1)]]),
            ShapeTemplate(name: "Caret ^", samples: [[p(0, 0), p(0.5, 1), p(1, 0)]]),
            ShapeTemplate(name: "Z", samples: [[p(0, 1), p(1, 1), p(0, 0), p(1, 0)]]),
            ShapeTemplate(name: "N", samples: [[p(0, 0), p(0, 1), p(1, 0), p(1, 1)]]),
            ShapeTemplate(name: "L", samples: [[p(0, 1), p(0, 0), p(0.7, 0)]]),
            ShapeTemplate(name: "Triangle", samples: [[p(0.5, 1), p(0, 0), p(1, 0), p(0.5, 1)]]), // apex, counter-clockwise
            ShapeTemplate(name: "Square", samples: [[p(0, 1), p(0, 0), p(1, 0), p(1, 1), p(0, 1)]]), // top-left, counter-clockwise
        ]
    }

    private static func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private static func circle(clockwise: Bool) -> [CGPoint] {
        (0...48).map { i in
            let t = Double(i) / 48 * 2 * .pi
            let angle = .pi / 2 + (clockwise ? -t : t)
            return CGPoint(x: 0.5 + 0.5 * cos(angle), y: 0.5 + 0.5 * sin(angle))
        }
    }
}
