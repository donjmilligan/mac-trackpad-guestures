import CoreGraphics
import Foundation

/// Single-stroke recognizer based on the $1 Unistroke Recognizer (Wobbrock et al.), with two changes:
/// it is rotation-sensitive (only ±20° of tilt is forgiven, so "V" and "^" stay distinct) and it
/// scales uniformly so straight lines and thin shapes keep their proportions.
public struct ShapeRecognizer: Sendable {
    public static let sampleCount = 64
    private static let angleRange = 20.0 * .pi / 180
    private static let anglePrecision = 2.0 * .pi / 180
    private static let halfDiagonal = 0.5 * 2.0.squareRoot()

    private let templates: [(name: String, points: [CGPoint])]

    public init(templates: [ShapeTemplate]) {
        self.templates = templates.flatMap { template in
            template.samples.compactMap { sample in
                Self.normalize(sample).map { (template.name, $0) }
            }
        }
    }

    public struct Match: Sendable {
        public var name: String
        /// 1 is a perfect match; anything under ~0.75 is usually a different shape.
        public var score: Double
    }

    public func recognize(_ stroke: [CGPoint]) -> Match? {
        guard let candidate = Self.normalize(stroke) else { return nil }
        var best: Match?
        for template in templates {
            let distance = Self.distanceAtBestAngle(candidate, template.points)
            let score = max(0, 1 - distance / Self.halfDiagonal)
            if score > (best?.score ?? -1) {
                best = Match(name: template.name, score: score)
            }
        }
        return best
    }

    /// Resampled, scaled to a unit box and centred on the origin. Nil for degenerate strokes.
    public static func normalize(_ points: [CGPoint]) -> [CGPoint]? {
        guard points.count >= 2, pathLength(points) > 0 else { return nil }
        let resampled = resample(points, count: sampleCount)
        let box = boundingBox(resampled)
        let size = max(box.width, box.height)
        guard size > 0 else { return nil }
        let c = centroid(resampled)
        return resampled.map { CGPoint(x: ($0.x - c.x) / size, y: ($0.y - c.y) / size) }
    }

    public static func pathLength(_ points: [CGPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        let interval = pathLength(points) / Double(count - 1)
        var pts = points
        var result = [pts[0]]
        var accumulated = 0.0
        var i = 1
        while i < pts.count {
            let d = distance(pts[i - 1], pts[i])
            if d > 0, accumulated + d >= interval {
                let t = (interval - accumulated) / d
                let q = CGPoint(x: pts[i - 1].x + t * (pts[i].x - pts[i - 1].x),
                                y: pts[i - 1].y + t * (pts[i].y - pts[i - 1].y))
                result.append(q)
                pts.insert(q, at: i)
                accumulated = 0
            } else {
                accumulated += d
            }
            i += 1
        }
        while result.count < count { result.append(points[points.count - 1]) }
        return Array(result.prefix(count))
    }

    private static func distanceAtBestAngle(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        // Golden-section search over the allowed tilt.
        let phi = 0.5 * (-1 + 5.0.squareRoot())
        var lo = -angleRange, hi = angleRange
        var x1 = phi * lo + (1 - phi) * hi
        var f1 = pathDistance(rotate(a, by: x1), b)
        var x2 = (1 - phi) * lo + phi * hi
        var f2 = pathDistance(rotate(a, by: x2), b)
        while abs(hi - lo) > anglePrecision {
            if f1 < f2 {
                hi = x2; x2 = x1; f2 = f1
                x1 = phi * lo + (1 - phi) * hi
                f1 = pathDistance(rotate(a, by: x1), b)
            } else {
                lo = x1; x1 = x2; f1 = f2
                x2 = (1 - phi) * lo + phi * hi
                f2 = pathDistance(rotate(a, by: x2), b)
            }
        }
        return min(f1, f2, pathDistance(a, b))
    }

    private static func pathDistance(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        zip(a, b).reduce(0) { $0 + distance($1.0, $1.1) } / Double(min(a.count, b.count))
    }

    private static func rotate(_ points: [CGPoint], by angle: Double) -> [CGPoint] {
        let c = centroid(points), cosA = cos(angle), sinA = sin(angle)
        return points.map {
            let dx = $0.x - c.x, dy = $0.y - c.y
            return CGPoint(x: dx * cosA - dy * sinA + c.x, y: dx * sinA + dy * cosA + c.y)
        }
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / Double(points.count), y: sum.y / Double(points.count))
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }
}
