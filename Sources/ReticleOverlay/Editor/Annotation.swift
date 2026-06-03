import AppKit

// MARK: - RectResizable

/// Annotations that store a single `rect` and can be resized via handle drag.
protocol RectResizable: AnyObject {
    var rect: NSRect { get set }
}

// MARK: - Tool

public enum AnnotationTool: String, CaseIterable {
    case region        = "region"        // crosshair — drag to select capture area (rectangle)
    case freehand      = "freehand"      // freehand / polygon region selection
    case select        = "select"        // move / delete existing annotations
    case rect          = "rectangle"
    case ellipse       = "ellipse"
    case line          = "line"
    case arrow         = "arrow"
    case freehandArrow = "freehandArrow" // curved arrow along a freehand path
    case text          = "text"
    case textOutline   = "textOutline"   // text with stroke outline
    case textBackground = "textBackground" // text with filled background
    case highlight     = "highlight"
    case pen           = "pen"
    case step          = "step"
    case blur          = "blur"          // Gaussian blur (redaction)
    case pixelate      = "pixelate"      // Mosaic / pixelate (redaction)
    case blackout      = "blackout"      // Solid fill
    case speechBalloon = "speechBalloon" // Rounded-rect speech bubble with text
    case spotlight     = "spotlight"     // Darken everything outside this region
    case magnify       = "magnify"       // Zoom loupe showing region at larger scale
    case emoji         = "emoji"         // Place an emoji / text sticker
    case cursor        = "cursor"        // Overlay the system arrow cursor
    case image         = "image"         // Insert an image file
    case crop          = "crop"          // Re-crop the captured area
    case eraser        = "eraser"        // Erase existing annotations
    case ruler         = "ruler"         // Distance measurement ruler
}

// MARK: - Base

/// All coordinates stored in flipped view-point space (top-left origin, points).
class Annotation: NSObject {
    var color: NSColor
    var lineWidth: CGFloat
    /// Stroke dash style for this annotation (only affects stroke-based shapes).
    var lineStyle: LineStyle = .solid

    /// Clockwise rotation in radians (visual, in the flipped NSView coordinate system).
    var rotation: CGFloat = 0

    /// Whether this annotation supports the rotation handle in the selection UI.
    /// Pixel-region annotations (blur, pixelate, spotlight) and freehand paths return false.
    var isRotatable: Bool { true }

    /// The point around which `rotation` is applied.  Defaults to the center of `boundingRect`.
    var rotationCenter: NSPoint {
        guard let r = boundingRect else { return .zero }
        return NSPoint(x: r.midX, y: r.midY)
    }

    /// Axis-aligned bounding rect in view coordinates.  Override in subclasses that store a rect.
    var boundingRect: NSRect? { nil }

    init(color: NSColor, lineWidth: CGFloat) {
        self.color = color
        self.lineWidth = lineWidth
    }

    func draw(in rect: NSRect) {}
    func hitTest(_ point: NSPoint) -> Bool { false }

    /// Applies the annotation's `lineStyle` dash pattern to `path`.
    /// Call this after setting `lineWidth`; it may override `lineCapStyle` for dotted lines.
    func applyLineDash(to path: NSBezierPath) {
        switch lineStyle {
        case .solid:
            break
        case .dashed:
            let dash = max(lineWidth * 4, 6)
            let gap  = max(lineWidth * 2, 4)
            path.setLineDash([dash, gap], count: 2, phase: 0)
        case .dotted:
            path.lineCapStyle = .round
            path.setLineDash([0, max(lineWidth * 2.5, 4)], count: 2, phase: 0)
        }
    }

    /// Draws the annotation with its `rotation` transform applied via NSAffineTransform
    /// (which correctly accounts for the flipped NSView coordinate system).
    func drawRotated(in dirtyRect: NSRect) {
        guard isRotatable, rotation != 0 else { draw(in: dirtyRect); return }
        NSGraphicsContext.saveGraphicsState()
        let c = rotationCenter
        let t = NSAffineTransform()
        t.translateX(by: c.x, yBy: c.y)
        t.rotate(byRadians: rotation)
        t.translateX(by: -c.x, yBy: -c.y)
        t.concat()
        draw(in: dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - Rectangle

final class RectAnnotation: Annotation, RectResizable {
    var rect: NSRect
    override var boundingRect: NSRect? { rect }

    init(rect: NSRect, color: NSColor, lineWidth: CGFloat) {
        self.rect = rect
        super.init(color: color, lineWidth: lineWidth)
    }

    override func draw(in _: NSRect) {
        color.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = lineWidth
        applyLineDash(to: path)
        path.stroke()
    }

    override func hitTest(_ p: NSPoint) -> Bool {
        rect.insetBy(dx: -6, dy: -6).contains(p) &&
        !rect.insetBy(dx: lineWidth + 4, dy: lineWidth + 4).contains(p)
    }
}

// MARK: - Ellipse

final class EllipseAnnotation: Annotation, RectResizable {
    var rect: NSRect
    override var boundingRect: NSRect? { rect }

    init(rect: NSRect, color: NSColor, lineWidth: CGFloat) {
        self.rect = rect
        super.init(color: color, lineWidth: lineWidth)
    }

    override func draw(in _: NSRect) {
        color.setStroke()
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = lineWidth
        applyLineDash(to: path)
        path.stroke()
    }

    override func hitTest(_ p: NSPoint) -> Bool {
        NSBezierPath(ovalIn: rect.insetBy(dx: -6, dy: -6)).contains(p) &&
        !NSBezierPath(ovalIn: rect.insetBy(dx: lineWidth + 4, dy: lineWidth + 4)).contains(p)
    }
}

// MARK: - Line

// Lines and arrows use endpoint handles; rotation is not offered for these.
final class LineAnnotation: Annotation {
    var start: NSPoint
    var end: NSPoint
    override var isRotatable: Bool { false }

    init(start: NSPoint, end: NSPoint, color: NSColor, lineWidth: CGFloat) {
        self.start = start; self.end = end
        super.init(color: color, lineWidth: lineWidth)
    }

    override func draw(in _: NSRect) {
        guard hypot(end.x - start.x, end.y - start.y) > 2 else { return }
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.move(to: start)
        path.line(to: end)
        applyLineDash(to: path)
        path.stroke()
    }

    override func hitTest(_ p: NSPoint) -> Bool { distanceToSegment(p, a: start, b: end) < 8 }
}

// MARK: - Arrow

final class ArrowAnnotation: Annotation {
    var start: NSPoint
    var end: NSPoint
    override var isRotatable: Bool { false }

    init(start: NSPoint, end: NSPoint, color: NSColor, lineWidth: CGFloat) {
        self.start = start; self.end = end
        super.init(color: color, lineWidth: lineWidth)
    }

    override func draw(in _: NSRect) {
        guard hypot(end.x - start.x, end.y - start.y) > 4 else { return }
        color.setStroke(); color.setFill()
        // Shaft — apply dash style
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.move(to: start); path.line(to: end)
        applyLineDash(to: path)
        path.stroke()
        // Arrowhead — always solid regardless of lineStyle
        let angle = atan2(end.y - start.y, end.x - start.x)
        let hl: CGFloat = max(12, lineWidth * 4), ha: CGFloat = .pi / 6
        let p1 = NSPoint(x: end.x - hl * cos(angle - ha), y: end.y - hl * sin(angle - ha))
        let p2 = NSPoint(x: end.x - hl * cos(angle + ha), y: end.y - hl * sin(angle + ha))
        let head = NSBezierPath(); head.move(to: end); head.line(to: p1); head.line(to: p2); head.close()
        head.fill()
    }

    override func hitTest(_ p: NSPoint) -> Bool { distanceToSegment(p, a: start, b: end) < 8 }
}

// MARK: - Freehand Arrow
// A freehand curved path with an arrowhead at the last point.

final class FreehandArrowAnnotation: Annotation {
    var points: [NSPoint] = []
    override var isRotatable: Bool { false }

    override init(color: NSColor, lineWidth: CGFloat) { super.init(color: color, lineWidth: lineWidth) }

    func addPoint(_ p: NSPoint) { points.append(p) }

    override func draw(in _: NSRect) {
        guard points.count > 1 else { return }
        color.setStroke(); color.setFill()
        // Shaft — apply dash style
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round; path.lineJoinStyle = .round

        // Catmull-Rom spline, same as PenAnnotation
        path.move(to: points[0])
        if points.count > 2 {
            for i in 1..<points.count - 1 {
                let p0 = points[max(0, i - 1)]
                let p1 = points[i]
                let p2 = points[min(points.count - 1, i + 1)]
                let cp1 = NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let cp2 = NSPoint(x: p2.x - (points[min(points.count - 1, i + 2)].x - p1.x) / 6,
                                  y: p2.y - (points[min(points.count - 1, i + 2)].y - p1.y) / 6)
                path.curve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
            }
        } else {
            path.line(to: points[1])
        }
        applyLineDash(to: path)
        path.stroke()

        // Arrowhead at last point — always solid regardless of lineStyle
        let last  = points[points.count - 1]
        let prev  = points.count > 3 ? points[points.count - 4] : points[points.count - 2]
        let angle = atan2(last.y - prev.y, last.x - prev.x)
        let hl: CGFloat = max(12, lineWidth * 4), ha: CGFloat = .pi / 6
        let p1 = NSPoint(x: last.x - hl * cos(angle - ha), y: last.y - hl * sin(angle - ha))
        let p2 = NSPoint(x: last.x - hl * cos(angle + ha), y: last.y - hl * sin(angle + ha))
        let head = NSBezierPath(); head.move(to: last); head.line(to: p1); head.line(to: p2); head.close()
        head.fill()
    }

    override func hitTest(_ p: NSPoint) -> Bool {
        guard points.count > 1 else { return false }
        for i in 1..<points.count { if distanceToSegment(p, a: points[i-1], b: points[i]) < 8 { return true } }
        return false
    }
}

// MARK: - Text

final class TextAnnotation: Annotation {
    var origin: NSPoint
    var text: String
    var fontSize: CGFloat

    init(origin: NSPoint, text: String, color: NSColor, fontSize: CGFloat) {
        self.origin = origin; self.text = text; self.fontSize = fontSize
        super.init(color: color, lineWidth: 1)
    }

    private var attrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: color]
    }
    override var boundingRect: NSRect? {
        let sz = (text as NSString).size(withAttributes: attrs)
        return NSRect(origin: origin, size: sz)
    }

    override func draw(in _: NSRect) {
        guard !text.isEmpty else { return }
        NSAttributedString(string: text, attributes: attrs).draw(at: origin)
    }

    override func hitTest(_ p: NSPoint) -> Bool {
        let sz = (text as NSString).size(withAttributes: attrs)
        return NSRect(origin: origin, size: sz).insetBy(dx: -4, dy: -4).contains(p)
    }
}

// MARK: - Text Outline (text with stroke outline for legibility on any background)

final class TextOutlineAnnotation: Annotation {
    var origin: NSPoint
    var text: String
    var fontSize: CGFloat
    /// Outline color drawn via NSStrokeColorAttributeName (defaults to white for dark-on-light scenarios)
    var outlineColor: NSColor

    init(origin: NSPoint, text: String, color: NSColor, fontSize: CGFloat, outlineColor: NSColor = .white) {
        self.origin = origin; self.text = text; self.fontSize = fontSize; self.outlineColor = outlineColor
        super.init(color: color, lineWidth: 1)
    }

    private var attrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
         .foregroundColor: color,
         .strokeColor: outlineColor,
         .strokeWidth: -3.0]   // negative = fill AND stroke
    }
    override var boundingRect: NSRect? {
        let sz = (text as NSString).size(withAttributes: attrs)
        return NSRect(origin: origin, size: sz)
    }

    override func draw(in _: NSRect) {
        guard !text.isEmpty else { return }
        NSAttributedString(string: text, attributes: attrs).draw(at: origin)
    }

    override func hitTest(_ p: NSPoint) -> Bool {
        let sz = (text as NSString).size(withAttributes: attrs)
        return NSRect(origin: origin, size: sz).insetBy(dx: -4, dy: -4).contains(p)
    }
}

// MARK: - Text Background (text with a filled box behind it)

final class TextBackgroundAnnotation: Annotation {
    var origin: NSPoint
    var text: String
    var fontSize: CGFloat
    /// Fill color of the background rect behind the text.
    var backgroundColor: NSColor

    init(origin: NSPoint, text: String, color: NSColor, fontSize: CGFloat, backgroundColor: NSColor = .black) {
        self.origin = origin; self.text = text; self.fontSize = fontSize; self.backgroundColor = backgroundColor
        super.init(color: color, lineWidth: 1)
    }

    private var attrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: color]
    }
    override var boundingRect: NSRect? {
        let sz = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 4
        return NSRect(x: origin.x - pad, y: origin.y - pad / 2,
                      width: sz.width + pad * 2, height: sz.height + pad)
    }

    override func draw(in _: NSRect) {
        guard !text.isEmpty else { return }
        let sz = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 4
        let bgRect = NSRect(x: origin.x - pad, y: origin.y - pad / 2,
                            width: sz.width + pad * 2, height: sz.height + pad)
        backgroundColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3).fill()
        NSAttributedString(string: text, attributes: attrs).draw(at: origin)
    }

    override func hitTest(_ p: NSPoint) -> Bool {
        let sz = (text as NSString).size(withAttributes: attrs)
        return NSRect(origin: origin, size: sz).insetBy(dx: -8, dy: -6).contains(p)
    }
}

// MARK: - Highlight

final class HighlightAnnotation: Annotation, RectResizable {
    var rect: NSRect
    override var boundingRect: NSRect? { rect }
    /// Opacity of the highlight fill (0.1 – 0.85). Default 0.35 matches ShareX.
    var opacity: CGFloat

    init(rect: NSRect, color: NSColor, opacity: CGFloat = 0.35) {
        self.rect = rect; self.opacity = opacity
        super.init(color: color, lineWidth: 0)
    }

    override func draw(in _: NSRect) {
        color.withAlphaComponent(opacity).setFill()
        NSBezierPath(rect: rect).fill()
    }

    override func hitTest(_ p: NSPoint) -> Bool { rect.insetBy(dx: -4, dy: -4).contains(p) }
}

// MARK: - Pen

final class PenAnnotation: Annotation {
    var points: [NSPoint] = []
    override var isRotatable: Bool { false }
    /// 0 = no smoothing, 1-10 = increasing weighted smoothing (matches ShareX FreehandSmoothing)
    var smoothing: Int = 3

    override init(color: NSColor, lineWidth: CGFloat) { super.init(color: color, lineWidth: lineWidth) }

    /// Add point with optional weighted smoothing (ShareX SmoothPoint algorithm).
    func addPoint(_ p: NSPoint) {
        var pt = p
        if smoothing > 0, !points.isEmpty {
            pt = smoothedPoint(p, in: points, smoothing: smoothing)
        }
        points.append(pt)
    }

    override func draw(in _: NSRect) {
        guard points.count > 1 else { return }
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round; path.lineJoinStyle = .round

        if points.count > 2 {
            // Catmull-Rom cardinal spline (tension 0.5) — smoother than raw polyline
            path.move(to: points[0])
            for i in 1..<points.count - 1 {
                let p0 = points[max(0, i - 1)]
                let p1 = points[i]
                let p2 = points[min(points.count - 1, i + 1)]
                let cp1 = NSPoint(x: p1.x + (p2.x - p0.x) / 6,
                                  y: p1.y + (p2.y - p0.y) / 6)
                let cp2 = NSPoint(x: p2.x - (points[min(points.count - 1, i + 2)].x - p1.x) / 6,
                                  y: p2.y - (points[min(points.count - 1, i + 2)].y - p1.y) / 6)
                path.curve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
            }
        } else {
            path.move(to: points[0])
            path.line(to: points[1])
        }
        applyLineDash(to: path)
        path.stroke()
    }

    override func hitTest(_ p: NSPoint) -> Bool {
        guard points.count > 1 else { return false }
        for i in 1..<points.count {
            if distanceToSegment(p, a: points[i-1], b: points[i]) < 8 { return true }
        }
        return false
    }

    // ShareX SmoothPoint: weighted moving average over recent points with exponential decay.
    private func smoothedPoint(_ current: NSPoint, in history: [NSPoint], smoothing: Int) -> NSPoint {
        let s = max(0, min(smoothing, 10))
        let windowSize = min(s * 4, history.count)
        guard windowSize > 0 else { return current }
        var sumX = Double(current.x), sumY = Double(current.y)
        var weight = 1.0, totalWeight = 1.0
        let decay = 0.6 + Double(s) * 0.0175
        for i in 0..<windowSize {
            let pt = history[history.count - 1 - i]
            weight *= decay
            sumX += Double(pt.x) * weight
            sumY += Double(pt.y) * weight
            totalWeight += weight
        }
        return NSPoint(x: sumX / totalWeight, y: sumY / totalWeight)
    }
}

// MARK: - Step

final class StepAnnotation: Annotation {
    var center: NSPoint
    var number: Int
    /// Optional leader line endpoint (set by drag after click-to-place).
    var leaderEnd: NSPoint?
    private let r: CGFloat = 12
    override var boundingRect: NSRect? {
        NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
    }
    override var rotationCenter: NSPoint { center }

    init(center: NSPoint, number: Int, color: NSColor) {
        self.center = center; self.number = number
        super.init(color: color, lineWidth: 2)
    }

    override func draw(in _: NSRect) {
        // Leader line first so circle sits on top
        if let tip = leaderEnd {
            // Find the point on the circle rim closest to the tip
            let angle = atan2(tip.y - center.y, tip.x - center.x)
            let rim   = NSPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            color.setStroke()
            let leader = NSBezierPath()
            leader.lineWidth = lineWidth
            leader.lineCapStyle = .round
            leader.move(to: rim); leader.line(to: tip)
            leader.stroke()
            // Small filled dot at tip
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: tip.x - 3, y: tip.y - 3, width: 6, height: 6)).fill()
        }

        let circle = NSRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2)
        color.setFill(); NSBezierPath(ovalIn: circle).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let label = "\(number)"
        let sz = (label as NSString).size(withAttributes: attrs)
        label.draw(at: NSPoint(x: center.x - sz.width/2, y: center.y - sz.height/2), withAttributes: attrs)
    }

    override func hitTest(_ p: NSPoint) -> Bool {
        if hypot(p.x - center.x, p.y - center.y) <= r + 6 { return true }
        if let tip = leaderEnd { return distanceToSegment(p, a: center, b: tip) < 8 }
        return false
    }
}

// MARK: - Blackout

final class BlackoutAnnotation: Annotation, RectResizable {
    var rect: NSRect
    override var boundingRect: NSRect? { rect }

    init(rect: NSRect) {
        self.rect = rect
        super.init(color: .black, lineWidth: 0)
    }

    override func draw(in _: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(rect: rect).fill()
    }

    override func hitTest(_ p: NSPoint) -> Bool { rect.insetBy(dx: -4, dy: -4).contains(p) }
}

// MARK: - Blur (CoreImage rendering handled by canvas)

final class BlurAnnotation: Annotation, RectResizable {
    var rect: NSRect
    var radius: CGFloat
    override var isRotatable: Bool { false }
    override var boundingRect: NSRect? { rect }

    init(rect: NSRect, radius: CGFloat = 20) {
        self.rect = rect; self.radius = radius
        super.init(color: .clear, lineWidth: 0)
    }

    override func draw(in _: NSRect) {
        // Fallback when CoreImage path is unavailable
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSBezierPath(rect: rect).fill()
    }

    override func hitTest(_ p: NSPoint) -> Bool { rect.insetBy(dx: -4, dy: -4).contains(p) }
}

// MARK: - Pixelate (CoreImage rendering handled by canvas)

final class PixelateAnnotation: Annotation, RectResizable {
    var rect: NSRect
    var pixelSize: CGFloat
    override var isRotatable: Bool { false }
    override var boundingRect: NSRect? { rect }

    init(rect: NSRect, pixelSize: CGFloat = 12) {
        self.rect = rect; self.pixelSize = pixelSize
        super.init(color: .clear, lineWidth: 0)
    }

    override func draw(in _: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSBezierPath(rect: rect).fill()
    }

    override func hitTest(_ p: NSPoint) -> Bool { rect.insetBy(dx: -4, dy: -4).contains(p) }
}

// MARK: - Speech Balloon

/// Where the speech-bubble tail points.
public enum BalloonTailDirection: String, CaseIterable {
    case bottomLeft  = "bottomLeft"
    case bottomRight = "bottomRight"
    case topLeft     = "topLeft"
    case topRight    = "topRight"

    var sfSymbol: String {
        switch self {
        case .bottomLeft:  return "bubble.left"
        case .bottomRight: return "bubble.right"
        case .topLeft:     return "bubble.left.fill"
        case .topRight:    return "bubble.right.fill"
        }
    }
    var label: String {
        switch self {
        case .bottomLeft:  return "Tail bottom-left"
        case .bottomRight: return "Tail bottom-right"
        case .topLeft:     return "Tail top-left"
        case .topRight:    return "Tail top-right"
        }
    }
}

final class SpeechBalloonAnnotation: Annotation, RectResizable {
    var rect: NSRect
    override var boundingRect: NSRect? { rect }
    var text: String
    var fontSize: CGFloat
    var tailDirection: BalloonTailDirection

    init(rect: NSRect, text: String = "", color: NSColor, fontSize: CGFloat,
         tailDirection: BalloonTailDirection = .bottomLeft) {
        self.rect = rect; self.text = text; self.fontSize = fontSize
        self.tailDirection = tailDirection
        super.init(color: color, lineWidth: 2)
    }

    override func draw(in _: NSRect) {
        guard rect.width > 8, rect.height > 8 else { return }
        let fill = NSColor.white.withAlphaComponent(0.92)

        // ── Body ──────────────────────────────────────────────────────────────
        let bodyPath = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        fill.setFill(); bodyPath.fill()

        // ── Tail triangle (direction-aware) ───────────────────────────────────
        // tail length / inset constants
        let tailLen: CGFloat = 18     // how far the tip extends beyond the body edge
        let tailBase: CGFloat = 16    // base width of the triangle on the body edge
        let inset: CGFloat  = 22      // horizontal inset from the nearer corner

        let tailPath = NSBezierPath()

        switch tailDirection {
        case .bottomLeft:
            // Attaches to bottom edge, near left corner; tip points down-left
            let ax = rect.minX + inset
            let ay = rect.maxY
            tailPath.move(to: NSPoint(x: ax,             y: ay))
            tailPath.line(to: NSPoint(x: rect.minX - tailLen * 0.35, y: ay + tailLen))
            tailPath.line(to: NSPoint(x: ax + tailBase,  y: ay))

        case .bottomRight:
            let ax = rect.maxX - inset
            let ay = rect.maxY
            tailPath.move(to: NSPoint(x: ax,             y: ay))
            tailPath.line(to: NSPoint(x: rect.maxX + tailLen * 0.35, y: ay + tailLen))
            tailPath.line(to: NSPoint(x: ax - tailBase,  y: ay))

        case .topLeft:
            let ax = rect.minX + inset
            let ay = rect.minY
            tailPath.move(to: NSPoint(x: ax,             y: ay))
            tailPath.line(to: NSPoint(x: rect.minX - tailLen * 0.35, y: ay - tailLen))
            tailPath.line(to: NSPoint(x: ax + tailBase,  y: ay))

        case .topRight:
            let ax = rect.maxX - inset
            let ay = rect.minY
            tailPath.move(to: NSPoint(x: ax,             y: ay))
            tailPath.line(to: NSPoint(x: rect.maxX + tailLen * 0.35, y: ay - tailLen))
            tailPath.line(to: NSPoint(x: ax - tailBase,  y: ay))
        }
        tailPath.close()
        fill.setFill(); tailPath.fill()

        // ── Stroke body + tail ────────────────────────────────────────────────
        color.setStroke()
        bodyPath.lineWidth = lineWidth; bodyPath.stroke()
        // Stroke only the two outer tail edges (skip the base segment inside the body)
        let tailStroke = NSBezierPath()
        switch tailDirection {
        case .bottomLeft:
            let ax = rect.minX + inset; let ay = rect.maxY
            tailStroke.move(to: NSPoint(x: ax, y: ay))
            tailStroke.line(to: NSPoint(x: rect.minX - tailLen * 0.35, y: ay + tailLen))
            tailStroke.line(to: NSPoint(x: ax + tailBase, y: ay))
        case .bottomRight:
            let ax = rect.maxX - inset; let ay = rect.maxY
            tailStroke.move(to: NSPoint(x: ax, y: ay))
            tailStroke.line(to: NSPoint(x: rect.maxX + tailLen * 0.35, y: ay + tailLen))
            tailStroke.line(to: NSPoint(x: ax - tailBase, y: ay))
        case .topLeft:
            let ax = rect.minX + inset; let ay = rect.minY
            tailStroke.move(to: NSPoint(x: ax, y: ay))
            tailStroke.line(to: NSPoint(x: rect.minX - tailLen * 0.35, y: ay - tailLen))
            tailStroke.line(to: NSPoint(x: ax + tailBase, y: ay))
        case .topRight:
            let ax = rect.maxX - inset; let ay = rect.minY
            tailStroke.move(to: NSPoint(x: ax, y: ay))
            tailStroke.line(to: NSPoint(x: rect.maxX + tailLen * 0.35, y: ay - tailLen))
            tailStroke.line(to: NSPoint(x: ax - tailBase, y: ay))
        }
        tailStroke.lineWidth = lineWidth; color.setStroke(); tailStroke.stroke()

        // ── Text ──────────────────────────────────────────────────────────────
        let pad: CGFloat = 10
        let textRect = rect.insetBy(dx: pad, dy: pad)
        let str = text.isEmpty ? "Type…" : text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: text.isEmpty ? NSColor.placeholderTextColor : color
        ]
        NSAttributedString(string: str, attributes: attrs).draw(in: textRect)
    }

    override func hitTest(_ p: NSPoint) -> Bool { rect.insetBy(dx: -6, dy: -6).contains(p) }
}

// MARK: - Spotlight
// Rendering is handled at the canvas level (unified dark overlay with holes).
// draw() is intentionally empty.

final class SpotlightAnnotation: Annotation, RectResizable {
    var rect: NSRect
    override var isRotatable: Bool { false }
    override var boundingRect: NSRect? { rect }

    init(rect: NSRect, color: NSColor = .white, lineWidth: CGFloat = 2) {
        self.rect = rect
        super.init(color: color, lineWidth: lineWidth)
    }

    // No-op — OverlayView / renderFinalImage draw the composite overlay.
    override func draw(in _: NSRect) {}
    override func hitTest(_ p: NSPoint) -> Bool { rect.insetBy(dx: -6, dy: -6).contains(p) }
}

// MARK: - Magnify (Loupe)
// Actual pixel content is drawn by OverlayView / renderFinalImage (needs base image).

final class MagnifyAnnotation: Annotation, RectResizable {
    var rect: NSRect
    override var isRotatable: Bool { false }   // pixel-space content; rotation is disorienting
    override var boundingRect: NSRect? { rect }
    var scale: CGFloat   // 2 = 2× zoom

    init(rect: NSRect, scale: CGFloat = 2, color: NSColor, lineWidth: CGFloat) {
        self.rect = rect; self.scale = scale
        super.init(color: color, lineWidth: lineWidth)
    }

    // Fallback when base image is unavailable
    override func draw(in _: NSRect) {
        guard rect.width > 4, rect.height > 4 else { return }
        color.setStroke()
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = lineWidth; path.stroke()
        // Draw ×N label
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: color
        ]
        let label = "×\(Int(scale))"
        let sz = (label as NSString).size(withAttributes: attrs)
        label.draw(at: NSPoint(x: rect.midX - sz.width/2, y: rect.midY - sz.height/2),
                   withAttributes: attrs)
    }

    override func hitTest(_ p: NSPoint) -> Bool {
        NSBezierPath(ovalIn: rect.insetBy(dx: -6, dy: -6)).contains(p)
    }
}

// MARK: - Emoji / Sticker

final class EmojiAnnotation: Annotation {
    var origin: NSPoint
    var emoji: String
    var fontSize: CGFloat

    init(origin: NSPoint, emoji: String, fontSize: CGFloat) {
        self.origin = origin; self.emoji = emoji; self.fontSize = fontSize
        super.init(color: .clear, lineWidth: 0)
    }

    private var attrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize)]
    }
    override var boundingRect: NSRect? {
        let sz = (emoji as NSString).size(withAttributes: attrs)
        return NSRect(origin: origin, size: sz)
    }

    override func draw(in _: NSRect) {
        guard !emoji.isEmpty else { return }
        NSAttributedString(string: emoji, attributes: attrs).draw(at: origin)
    }

    override func hitTest(_ p: NSPoint) -> Bool {
        let sz = (emoji as NSString).size(withAttributes: attrs)
        return NSRect(origin: origin, size: sz).insetBy(dx: -6, dy: -6).contains(p)
    }
}

// MARK: - Cursor

final class CursorAnnotation: Annotation {
    var origin: NSPoint
    var size: CGFloat
    override var boundingRect: NSRect? {
        NSRect(x: origin.x, y: origin.y, width: size, height: size)
    }

    init(origin: NSPoint, size: CGFloat = 32) {
        self.origin = origin; self.size = size
        super.init(color: .clear, lineWidth: 0)
    }

    override func draw(in _: NSRect) {
        NSCursor.arrow.image.draw(in: NSRect(x: origin.x, y: origin.y, width: size, height: size))
    }

    override func hitTest(_ p: NSPoint) -> Bool {
        NSRect(x: origin.x, y: origin.y, width: size + 8, height: size + 8).contains(p)
    }
}

// MARK: - Image

final class ImageAnnotation: Annotation {
    var origin: NSPoint
    var nsImage: NSImage
    var size: NSSize
    override var boundingRect: NSRect? { NSRect(origin: origin, size: size) }

    init(origin: NSPoint, image: NSImage) {
        self.origin = origin
        self.nsImage = image
        let maxW: CGFloat = 300
        let w = image.size.width > 0 ? min(image.size.width, maxW) : maxW
        let ratio = image.size.width > 0 ? image.size.height / image.size.width : 1
        self.size = NSSize(width: w, height: w * ratio)
        super.init(color: .clear, lineWidth: 0)
    }

    override func draw(in _: NSRect) {
        nsImage.draw(in: NSRect(origin: origin, size: size))
    }

    override func hitTest(_ p: NSPoint) -> Bool {
        NSRect(origin: origin, size: size).insetBy(dx: -6, dy: -6).contains(p)
    }
}

// MARK: - Ruler

/// Distance measurement ruler.  Shows a line with endpoint caps, distance label,
/// and optional per-100-pixel tick marks.
final class RulerAnnotation: Annotation {
    var start: NSPoint
    var end: NSPoint
    override var isRotatable: Bool { false }
    /// Display scale factor (points → pixels) used to annotate physical pixel count.
    var scaleFactor: CGFloat

    init(start: NSPoint, end: NSPoint, color: NSColor = .systemCyan,
         lineWidth: CGFloat = 1.5, scaleFactor: CGFloat = 2) {
        self.start = start; self.end = end; self.scaleFactor = scaleFactor
        super.init(color: color, lineWidth: lineWidth)
    }

    override func draw(in _: NSRect) {
        guard hypot(end.x - start.x, end.y - start.y) > 4 else { return }
        let len = hypot(end.x - start.x, end.y - start.y)
        let angle = atan2(end.y - start.y, end.x - start.x)

        color.setStroke(); color.setFill()

        // Main line
        let line = NSBezierPath()
        line.lineWidth = lineWidth; line.lineCapStyle = .round
        line.move(to: start); line.line(to: end); line.stroke()

        // Endpoint caps (perpendicular 8pt ticks)
        let capLen: CGFloat = 8
        let perp = angle + .pi / 2
        for pt in [start, end] {
            let cap = NSBezierPath()
            cap.lineWidth = lineWidth
            cap.move(to: NSPoint(x: pt.x - capLen/2 * cos(perp), y: pt.y - capLen/2 * sin(perp)))
            cap.line(to: NSPoint(x: pt.x + capLen/2 * cos(perp), y: pt.y + capLen/2 * sin(perp)))
            cap.stroke()
        }

        // Distance label at midpoint
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        let px = Int((len * scaleFactor).rounded())
        let label = "\(px) px"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let sz = str.size(); let pad: CGFloat = 4
        let bgRect = NSRect(x: midX - sz.width/2 - pad, y: midY - sz.height/2 - pad/2,
                            width: sz.width + pad*2, height: sz.height + pad)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3).fill()
        str.draw(at: NSPoint(x: midX - sz.width/2, y: midY - sz.height/2))
    }

    override func hitTest(_ p: NSPoint) -> Bool { distanceToSegment(p, a: start, b: end) < 8 }
}

// MARK: - Geometry helper

private func distanceToSegment(_ p: NSPoint, a: NSPoint, b: NSPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let lenSq = dx*dx + dy*dy
    guard lenSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x)*dx + (p.y - a.y)*dy) / lenSq))
    return hypot(p.x - (a.x + t*dx), p.y - (a.y + t*dy))
}
