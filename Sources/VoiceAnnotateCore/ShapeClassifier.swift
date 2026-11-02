import CoreGraphics
import Foundation

/// Turns raw stroke geometry into a semantic shape ("circled", "line", …).
public enum ShapeClassifier {
    public static func defaultShape(for tool: AnnotationTool) -> AnnotationShape {
        switch tool {
        case .pen: return .freehand
        case .arrow: return .arrow
        case .rectangle: return .box
        case .ellipse: return .ellipse
        case .highlighter: return .highlight
        case .pin: return .pin
        }
    }

    public static func shape(for tool: AnnotationTool, points: [CGPoint]) -> AnnotationShape {
        tool == .pen ? classifyStroke(points) : defaultShape(for: tool)
    }

    /// Classifies a freehand stroke.
    /// - closed-ish loop that winds ≥ ~300° around its centroid → `.circled`
    /// - nearly straight → `.line`
    /// - anything else → `.freehand`
    public static func classifyStroke(_ pts: [CGPoint]) -> AnnotationShape {
        guard pts.count >= 3 else { return .freehand }
        let length = pathLength(pts)
        let box = boundingBox(pts)
        let diag = hypot(box.width, box.height)
        guard length > 8, diag > 4 else { return .freehand }

        let endGap = distance(pts[0], pts[pts.count - 1])
        let sweep = abs(windingAngle(pts))
        // A real loop encloses a good part of its bounding box (an ellipse covers ~78%);
        // a back-and-forth scribble winds around its centroid too but encloses little.
        let fill = enclosedArea(pts) / max(Double(box.width * box.height), 1)
        if sweep >= 1.65 * .pi && endGap < 0.6 * diag && fill >= 0.45 {
            return .circled
        }
        if endGap / length > 0.9 {
            return .line
        }
        return .freehand
    }

    /// Total signed angle swept around the stroke's centroid. Points very close to the
    /// centroid are skipped to avoid angle jumps.
    public static func windingAngle(_ pts: [CGPoint]) -> Double {
        let c = centroid(pts)
        let diag = hypot(boundingBox(pts).width, boundingBox(pts).height)
        let minRadius = 0.05 * diag
        var sweep = 0.0
        var prevAngle: Double?
        for p in pts {
            let dx = p.x - c.x, dy = p.y - c.y
            guard hypot(dx, dy) >= minRadius else { continue }
            let angle = atan2(dy, dx)
            if let prev = prevAngle {
                var d = angle - prev
                while d > .pi { d -= 2 * .pi }
                while d < -.pi { d += 2 * .pi }
                sweep += d
            }
            prevAngle = angle
        }
        return sweep
    }

    /// Absolute area of the polygon formed by the stroke, closed from last to first point.
    public static func enclosedArea(_ pts: [CGPoint]) -> Double {
        guard pts.count >= 3 else { return 0 }
        var twice = 0.0
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            twice += a.x * b.y - b.x * a.y
        }
        return abs(twice) / 2
    }

    public static func pathLength(_ pts: [CGPoint]) -> Double {
        guard pts.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<pts.count {
            total += distance(pts[i - 1], pts[i])
        }
        return total
    }

    public static func boundingBox(_ pts: [CGPoint]) -> CGRect {
        guard let first = pts.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func centroid(_ pts: [CGPoint]) -> CGPoint {
        let n = Double(pts.count)
        let sx = pts.reduce(0.0) { $0 + $1.x }
        let sy = pts.reduce(0.0) { $0 + $1.y }
        return CGPoint(x: sx / n, y: sy / n)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }
}
