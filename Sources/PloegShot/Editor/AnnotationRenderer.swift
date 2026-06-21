import AppKit

enum AnnotationRenderer {
    static func draw(_ annotations: [Annotation], transform: (CGPoint) -> CGPoint, scale: CGFloat) {
        annotations.forEach { draw($0, transform: transform, scale: scale) }
    }

    static func draw(_ annotation: Annotation, transform: (CGPoint) -> CGPoint, scale: CGFloat) {
        switch annotation {
        case let .arrow(start, end, style):
            configure(style, scale: scale)
            drawLine(from: transform(start), to: transform(end), style: style, scale: scale)
            drawArrowHead(from: transform(start), to: transform(end), style: style, scale: scale)

        case let .line(start, end, style):
            configure(style, scale: scale)
            drawLine(from: transform(start), to: transform(end), style: style, scale: scale)

        case let .pen(points, style):
            configure(style, scale: scale)
            drawStroke(points.map(transform), width: displayWidth(style, scale: scale))

        case let .highlight(points, style):
            style.color.withAlphaComponent(0.38).setStroke()
            drawStroke(points.map(transform), width: max(8, style.lineWidth * 4 * scale))

        case let .text(string, point, style):
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            shadow.shadowBlurRadius = 2 * scale
            shadow.shadowOffset = CGSize(width: 0, height: -1 * scale)
            string.draw(at: transform(point), withAttributes: [
                .font: NSFont.systemFont(ofSize: max(10, style.fontSize * scale), weight: .semibold),
                .foregroundColor: style.color,
                .shadow: shadow
            ])

        case let .rectangle(rect, style):
            configure(style, scale: scale)
            let path = NSBezierPath(roundedRect: mapped(rect, transform), xRadius: 5 * scale, yRadius: 5 * scale)
            path.lineWidth = displayWidth(style, scale: scale)
            path.stroke()

        case let .ellipse(rect, style):
            configure(style, scale: scale)
            let path = NSBezierPath(ovalIn: mapped(rect, transform))
            path.lineWidth = displayWidth(style, scale: scale)
            path.stroke()

        case let .redact(rect):
            let rect = mapped(rect, transform)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3 * scale, yRadius: 3 * scale).fill()
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: 3 * scale, yRadius: 3 * scale).addClip()
            NSColor.white.withAlphaComponent(0.14).setStroke()
            let hatch = NSBezierPath()
            var x = rect.minX - rect.height
            while x < rect.maxX {
                hatch.move(to: CGPoint(x: x, y: rect.minY))
                hatch.line(to: CGPoint(x: x + rect.height, y: rect.maxY))
                x += 8 * max(scale, 0.5)
            }
            hatch.lineWidth = max(1, scale)
            hatch.stroke()
            NSGraphicsContext.current?.restoreGraphicsState()
        }
    }

    private static func configure(_ style: AnnotationStyle, scale: CGFloat) {
        style.color.setStroke()
        style.color.setFill()
    }

    private static func displayWidth(_ style: AnnotationStyle, scale: CGFloat) -> CGFloat {
        max(2, style.lineWidth * scale)
    }

    private static func drawLine(from start: CGPoint, to end: CGPoint, style: AnnotationStyle, scale: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = displayWidth(style, scale: scale)
        path.lineCapStyle = .round
        path.stroke()
    }

    private static func drawStroke(_ points: [CGPoint], width: CGFloat) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.move(to: first)
        points.dropFirst().forEach { path.line(to: $0) }
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func mapped(_ rect: CGRect, _ transform: (CGPoint) -> CGPoint) -> CGRect {
        let a = transform(rect.origin)
        let b = transform(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private static func drawArrowHead(from start: CGPoint, to end: CGPoint, style: AnnotationStyle, scale: CGFloat) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(12, (style.lineWidth * 3.5 + 10) * scale)
        let wing = CGFloat.pi / 6
        let p1 = CGPoint(x: end.x - length * cos(angle - wing), y: end.y - length * sin(angle - wing))
        let p2 = CGPoint(x: end.x - length * cos(angle + wing), y: end.y - length * sin(angle + wing))
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: p1)
        head.move(to: end)
        head.line(to: p2)
        head.lineWidth = displayWidth(style, scale: scale)
        head.lineCapStyle = .round
        head.stroke()
    }
}
