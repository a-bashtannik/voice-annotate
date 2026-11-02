import CoreGraphics
import Foundation

/// Produces the textual reference for an annotation, e.g.
/// `#3 circled (412,230)-(640,310) in frame 2`.
public enum AnnotationDescriber {
    public static func describe(_ a: Annotation, mapper: CoordinateMapper, frame: Int?) -> String {
        let body: String
        switch a.shape {
        case .pin:
            body = "pin at \(pt(mapper.map(a.points.first ?? .zero)))"
        case .arrow:
            let from = a.points.first ?? .zero
            let to = a.points.last ?? from
            body = "arrow from \(pt(mapper.map(from))) pointing at \(pt(mapper.map(to)))"
        case .line:
            let from = a.points.first ?? .zero
            let to = a.points.last ?? from
            let dx = abs(to.x - from.x), dy = abs(to.y - from.y)
            if dy < 0.3 * dx {
                body = "underline \(rect(mapper.map(a.bounds)))"
            } else {
                body = "line from \(pt(mapper.map(from))) to \(pt(mapper.map(to)))"
            }
        case .circled, .ellipse:
            body = "circled \(rect(mapper.map(a.bounds)))"
        case .box:
            body = "box around \(rect(mapper.map(a.bounds)))"
        case .highlight:
            body = "highlighted \(rect(mapper.map(a.bounds)))"
        case .freehand:
            body = "drawing over \(rect(mapper.map(a.bounds)))"
        }
        if let frame {
            return "#\(a.id) \(body) in frame \(frame)"
        }
        return "#\(a.id) \(body)"
    }

    public static func describeClick(_ c: ClickEvent, mapper: CoordinateMapper) -> String {
        "click at \(pt(mapper.map(c.location)))"
    }

    static func pt(_ p: (x: Int, y: Int)) -> String { "(\(p.x),\(p.y))" }

    static func rect(_ r: (x1: Int, y1: Int, x2: Int, y2: Int)) -> String {
        "(\(r.x1),\(r.y1))-(\(r.x2),\(r.y2))"
    }
}
