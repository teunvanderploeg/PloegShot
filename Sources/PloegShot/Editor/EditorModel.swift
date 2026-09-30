import AppKit

enum EditorTool: String, CaseIterable, Identifiable {
    case select, arrow, line, pen, text, rectangle, ellipse, highlight, redact

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .pen: "pencil.tip"
        case .text: "textformat"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .highlight: "highlighter"
        case .redact: "eye.slash.fill"
        }
    }
}

enum AnnotationColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, white, black

    var id: Self { self }
    var color: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .white: .white
        case .black: .black
        }
    }
}

struct AnnotationStyle {
    let color: NSColor
    let lineWidth: CGFloat
    let fontSize: CGFloat
}

enum Annotation {
    case arrow(start: CGPoint, end: CGPoint, style: AnnotationStyle)
    case line(start: CGPoint, end: CGPoint, style: AnnotationStyle)
    case pen(points: [CGPoint], style: AnnotationStyle)
    case text(String, at: CGPoint, style: AnnotationStyle)
    case rectangle(CGRect, style: AnnotationStyle)
    case ellipse(CGRect, style: AnnotationStyle)
    case highlight(points: [CGPoint], style: AnnotationStyle)
    case redact(CGRect)

    var bounds: CGRect {
        switch self {
        case let .arrow(start, end, style), let .line(start, end, style):
            return Self.rect(containing: [start, end]).insetBy(dx: -style.lineWidth * 2, dy: -style.lineWidth * 2)
        case let .pen(points, style), let .highlight(points, style):
            return Self.rect(containing: points).insetBy(dx: -style.lineWidth * 2, dy: -style.lineWidth * 2)
        case let .text(text, at: point, style: style):
            let size = (text as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold)
            ])
            return CGRect(origin: point, size: size)
        case let .rectangle(rect, _), let .ellipse(rect, _), let .redact(rect):
            return rect.standardized
        }
    }

    func translated(by delta: CGPoint) -> Annotation {
        let move: (CGPoint) -> CGPoint = { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        switch self {
        case let .arrow(start, end, style): return .arrow(start: move(start), end: move(end), style: style)
        case let .line(start, end, style): return .line(start: move(start), end: move(end), style: style)
        case let .pen(points, style): return .pen(points: points.map(move), style: style)
        case let .highlight(points, style): return .highlight(points: points.map(move), style: style)
        case let .text(text, at: point, style: style): return .text(text, at: move(point), style: style)
        case let .rectangle(rect, style): return .rectangle(rect.offsetBy(dx: delta.x, dy: delta.y), style: style)
        case let .ellipse(rect, style): return .ellipse(rect.offsetBy(dx: delta.x, dy: delta.y), style: style)
        case let .redact(rect): return .redact(rect.offsetBy(dx: delta.x, dy: delta.y))
        }
    }

    func resized(to newBounds: CGRect) -> Annotation {
        let oldBounds = bounds
        let map: (CGPoint) -> CGPoint = { point in
            let xRatio = oldBounds.width > 0 ? (point.x - oldBounds.minX) / oldBounds.width : 0
            let yRatio = oldBounds.height > 0 ? (point.y - oldBounds.minY) / oldBounds.height : 0
            return CGPoint(x: newBounds.minX + xRatio * newBounds.width, y: newBounds.minY + yRatio * newBounds.height)
        }
        switch self {
        case let .arrow(start, end, style): return .arrow(start: map(start), end: map(end), style: style)
        case let .line(start, end, style): return .line(start: map(start), end: map(end), style: style)
        case let .pen(points, style): return .pen(points: points.map(map), style: style)
        case let .highlight(points, style): return .highlight(points: points.map(map), style: style)
        case let .text(text, at: point, style: style):
            let scale = oldBounds.height > 0 ? newBounds.height / oldBounds.height : 1
            let resizedStyle = AnnotationStyle(color: style.color, lineWidth: style.lineWidth, fontSize: max(8, style.fontSize * scale))
            return .text(text, at: map(point), style: resizedStyle)
        case let .rectangle(_, style): return .rectangle(newBounds, style: style)
        case let .ellipse(_, style): return .ellipse(newBounds, style: style)
        case .redact: return .redact(newBounds)
        }
    }

    var textContent: (text: String, point: CGPoint, style: AnnotationStyle)? {
        guard case let .text(text, at: point, style: style) = self else { return nil }
        return (text, point, style)
    }

    private static func rect(containing points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }
    }
}

final class EditorDocument: ObservableObject {
    let image: NSImage
    @Published var selectedTool: EditorTool = .select
    @Published var selectedColor: AnnotationColor = .red
    @Published var strokeWidth: CGFloat = 6
    @Published var fontSize: CGFloat = 32
    @Published private(set) var annotations: [Annotation] = []
    @Published private(set) var selectedAnnotationIndex: Int?
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    init(image: NSImage) { self.image = image }

    var currentStyle: AnnotationStyle {
        AnnotationStyle(color: selectedColor.color, lineWidth: strokeWidth, fontSize: fontSize)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func add(_ annotation: Annotation) {
        recordCurrentState()
        annotations.append(annotation)
        selectedAnnotationIndex = annotations.indices.last
    }

    func selectAnnotation(at index: Int?) { selectedAnnotationIndex = index }

    func annotationIndex(at point: CGPoint, tolerance: CGFloat) -> Int? {
        annotations.indices.reversed().first { annotations[$0].bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
    }

    func updateAnnotation(at index: Int, to annotation: Annotation) {
        guard annotations.indices.contains(index) else { return }
        recordCurrentState()
        annotations[index] = annotation
    }

    func updateAnnotationTransiently(at index: Int, to annotation: Annotation) {
        guard annotations.indices.contains(index) else { return }
        annotations[index] = annotation
    }

    func commitTransientChange(at index: Int, previousAnnotation: Annotation) {
        guard annotations.indices.contains(index) else { return }
        var previousState = annotations
        previousState[index] = previousAnnotation
        undoStack.append(previousState)
        redoStack.removeAll()
        objectWillChange.send()
    }

    func deleteSelectedAnnotation() {
        guard let index = selectedAnnotationIndex, annotations.indices.contains(index) else { return }
        recordCurrentState()
        annotations.remove(at: index)
        selectedAnnotationIndex = nil
    }

    func undo() {
        guard let previousState = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previousState
        selectedAnnotationIndex = nil
    }

    func redo() {
        guard let nextState = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = nextState
        selectedAnnotationIndex = nil
    }

    func clear() {
        guard !annotations.isEmpty else { return }
        recordCurrentState()
        annotations.removeAll()
        selectedAnnotationIndex = nil
    }

    private func recordCurrentState() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    /// Produces a flattened image at the original capture resolution.
    func renderedImage() throws -> NSImage {
        // An explicit bitmap avoids lockFocus choosing the current screen's
        // backing scale and changing the exported screenshot's pixel dimensions.
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(image.size.width), pixelsHigh: Int(image.size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        let output = NSImage(size: image.size)
        context.imageInterpolation = .high
        image.draw(in: CGRect(origin: .zero, size: image.size))
        AnnotationRenderer.draw(annotations, transform: { $0 }, scale: 1)
        context.flushGraphics()
        output.addRepresentation(bitmap)
        return output
    }
}
