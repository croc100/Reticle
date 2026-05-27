import AppKit

// MARK: - Tool

public enum AnnotationTool: String, CaseIterable {
    case rect      = "rectangle"
    case arrow     = "arrow"
    case text      = "text"
    case highlight = "highlight"
    case pen       = "pen"
    case step      = "step"
}

// MARK: - Base

/// All coordinates are in flipped view-point space (top-left origin).
class Annotation: NSObject {
    var color: NSColor
    var lineWidth: CGFloat
    var isSelected: Bool = false

    init(color: NSColor, lineWidth: CGFloat) {
        self.color = color
        self.lineWidth = lineWidth
    }

    /// Override to render. `view` is the canvas (isFlipped = true).
    func draw(in rect: NSRect) {}

    /// Returns true if `point` (flipped) is close enough to select this annotation.
    func hitTest(_ point: NSPoint) -> Bool { false }
}

// MARK: - Rect

final class RectAnnotation: Annotation {
    var rect: NSRect

    init(rect: NSRect, color: NSColor, lineWidth: CGFloat) {
        self.rect = rect
        super.init(color: color, lineWidth: lineWidth)
    }

    override func draw(in _: NSRect) {
        color.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = lineWidth
        path.stroke()
    }

    override func hitTest(_ point: NSPoint) -> Bool {
        rect.insetBy(dx: -6, dy: -6).contains(point) &&
        !rect.insetBy(dx: lineWidth + 4, dy: lineWidth + 4).contains(point)
    }
}

// MARK: - Arrow

final class ArrowAnnotation: Annotation {
    var start: NSPoint
    var end: NSPoint

    init(start: NSPoint, end: NSPoint, color: NSColor, lineWidth: CGFloat) {
        self.start = start
        self.end = end
        super.init(color: color, lineWidth: lineWidth)
    }

    override func draw(in _: NSRect) {
        guard hypot(end.x - start.x, end.y - start.y) > 4 else { return }
        color.setStroke()
        color.setFill()

        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.move(to: start)
        path.line(to: end)
        path.stroke()

        // Arrowhead
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLen: CGFloat = max(12, lineWidth * 4)
        let headAngle: CGFloat = .pi / 6
        let p1 = NSPoint(x: end.x - headLen * cos(angle - headAngle),
                         y: end.y - headLen * sin(angle - headAngle))
        let p2 = NSPoint(x: end.x - headLen * cos(angle + headAngle),
                         y: end.y - headLen * sin(angle + headAngle))
        let head = NSBezierPath()
        head.move(to: end); head.line(to: p1); head.line(to: p2); head.close()
        head.fill()
    }

    override func hitTest(_ point: NSPoint) -> Bool {
        distanceToSegment(point, a: start, b: end) < 8
    }
}

// MARK: - Text

final class TextAnnotation: Annotation {
    var origin: NSPoint      // top-left of text block
    var text: String
    var fontSize: CGFloat

    init(origin: NSPoint, text: String, color: NSColor, fontSize: CGFloat) {
        self.origin = origin
        self.text = text
        self.fontSize = fontSize
        super.init(color: color, lineWidth: 1)
    }

    private var attrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
         .foregroundColor: color]
    }

    override func draw(in _: NSRect) {
        guard !text.isEmpty else { return }
        NSAttributedString(string: text, attributes: attrs).draw(at: origin)
    }

    override func hitTest(_ point: NSPoint) -> Bool {
        let sz = (text as NSString).size(withAttributes: attrs)
        return NSRect(origin: origin, size: sz).insetBy(dx: -4, dy: -4).contains(point)
    }
}

// MARK: - Highlight

final class HighlightAnnotation: Annotation {
    var rect: NSRect

    init(rect: NSRect, color: NSColor) {
        self.rect = rect
        super.init(color: color, lineWidth: 0)
    }

    override func draw(in _: NSRect) {
        color.withAlphaComponent(0.35).setFill()
        NSBezierPath(rect: rect).fill()
    }

    override func hitTest(_ point: NSPoint) -> Bool {
        rect.insetBy(dx: -4, dy: -4).contains(point)
    }
}

// MARK: - Pen

final class PenAnnotation: Annotation {
    var points: [NSPoint] = []

    override init(color: NSColor, lineWidth: CGFloat) {
        super.init(color: color, lineWidth: lineWidth)
    }

    func addPoint(_ p: NSPoint) { points.append(p) }

    override func draw(in _: NSRect) {
        guard points.count > 1 else { return }
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: points[0])
        for p in points.dropFirst() { path.line(to: p) }
        path.stroke()
    }

    override func hitTest(_ point: NSPoint) -> Bool {
        guard points.count > 1 else { return false }
        for i in 1..<points.count {
            if distanceToSegment(point, a: points[i-1], b: points[i]) < 8 { return true }
        }
        return false
    }
}

// MARK: - Step

final class StepAnnotation: Annotation {
    var center: NSPoint
    var number: Int

    init(center: NSPoint, number: Int, color: NSColor) {
        self.center = center
        self.number = number
        super.init(color: color, lineWidth: 2)
    }

    private let radius: CGFloat = 12

    override func draw(in _: NSRect) {
        let circle = NSRect(x: center.x - radius, y: center.y - radius,
                            width: radius * 2, height: radius * 2)
        color.setFill()
        NSBezierPath(ovalIn: circle).fill()

        let label = "\(number)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let sz = (label as NSString).size(withAttributes: attrs)
        let pt = NSPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2)
        label.draw(at: pt, withAttributes: attrs)
    }

    override func hitTest(_ point: NSPoint) -> Bool {
        hypot(point.x - center.x, point.y - center.y) <= radius + 6
    }
}

// MARK: - Geometry helper

private func distanceToSegment(_ p: NSPoint, a: NSPoint, b: NSPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let lenSq = dx*dx + dy*dy
    guard lenSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x)*dx + (p.y - a.y)*dy) / lenSq))
    return hypot(p.x - (a.x + t*dx), p.y - (a.y + t*dy))
}
