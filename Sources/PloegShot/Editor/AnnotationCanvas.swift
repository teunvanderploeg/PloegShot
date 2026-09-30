import AppKit
import SwiftUI

struct AnnotationCanvas: NSViewRepresentable {
    @ObservedObject var document: EditorDocument
    @Binding var zoomScale: CGFloat?
    @Binding var actualZoom: CGFloat

    func makeNSView(context: Context) -> AnnotationViewportView {
        AnnotationViewportView(document: document)
    }

    func updateNSView(_ view: AnnotationViewportView, context: Context) {
        view.canvas.document = document
        view.onActualZoom = { scale in
            DispatchQueue.main.async {
                if abs(actualZoom - scale) > 0.0001 { actualZoom = scale }
            }
        }
        view.onPinchZoom = { scale in zoomScale = scale }
        view.setZoom(zoomScale)
        view.canvas.needsDisplay = true
        view.window?.invalidateCursorRects(for: view.canvas)
    }
}

final class AnnotationViewportView: NSView {
    let canvas: AnnotationCanvasView
    private let scrollView = CanvasScrollView()
    private var requestedZoom: CGFloat?
    var onActualZoom: ((CGFloat) -> Void)?
    var onPinchZoom: ((CGFloat) -> Void)?

    init(document: EditorDocument) {
        canvas = AnnotationCanvasView(document: document)
        super.init(frame: .zero)
        scrollView.contentView = CenteredClipView()
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.01
        scrollView.maxMagnification = 8
        canvas.frame = CGRect(origin: .zero, size: CGSize(width: document.image.size.width + 36, height: document.image.size.height + 36))
        scrollView.documentView = canvas
        scrollView.onMagnify = { [weak self] scale in
            guard let self else { return }
            self.requestedZoom = scale
            self.canvas.viewportScale = scale
            self.onActualZoom?(scale)
            self.onPinchZoom?(scale)
            self.canvas.needsDisplay = true
        }
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        applyZoom()
    }

    func setZoom(_ scale: CGFloat?) {
        requestedZoom = scale
        applyZoom()
    }

    private func applyZoom() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let fit = min(scrollView.contentSize.width / canvas.frame.width, scrollView.contentSize.height / canvas.frame.height)
        let scale = min(8, max(0.01, requestedZoom ?? fit))
        if abs(scrollView.magnification - scale) > 0.0001 {
            let center = requestedZoom == nil
                ? CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
                : CGPoint(x: scrollView.contentView.bounds.midX, y: scrollView.contentView.bounds.midY)
            scrollView.setMagnification(scale, centeredAt: center)
        }
        canvas.viewportScale = scale
        onActualZoom?(scale)
        canvas.needsDisplay = true
    }
}

private final class CanvasScrollView: NSScrollView {
    var onMagnify: ((CGFloat) -> Void)?

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        onMagnify?(magnification)
    }
}

private final class CenteredClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        if let document = documentView {
            if document.frame.width < rect.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
            if document.frame.height < rect.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
        }
        return rect
    }
}

final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    private enum ResizeHandle: CaseIterable, Hashable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    var document: EditorDocument
    var viewportScale: CGFloat = 1
    private var interactionScale: CGFloat { max(0.01, viewportScale * imageRect.width / document.image.size.width) }
    private var interactionTrackingArea: NSTrackingArea?
    private var dragStart: CGPoint?
    private var dragEnd: CGPoint?
    private var dragPoints: [CGPoint] = []
    private var movingAnnotation: Annotation?
    private var didMoveAnnotation = false
    private var resizeHandle: ResizeHandle?
    private var hoveredResizeHandle: ResizeHandle?
    private lazy var diagonalDownCursor = makeDiagonalCursor(symbol: "arrow.up.left.and.arrow.down.right")
    private lazy var diagonalUpCursor = makeDiagonalCursor(symbol: "arrow.up.right.and.arrow.down.left")
    private weak var inlineTextField: NSTextField?
    private var inlineTextPoint: CGPoint?
    private var inlineTextStyle: AnnotationStyle?
    private var inlineEditingIndex: Int?
    private var caretTimer: Timer?
    private var showsInlineCaret = true

    init(document: EditorDocument) {
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    deinit { caretTimer?.invalidate() }

    override func layout() {
        super.layout()
        positionInlineTextField()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let interactionTrackingArea { removeTrackingArea(interactionTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        interactionTrackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(imageRect, cursor: document.selectedTool == .text ? .iBeam : .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateInteractionCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateInteractionCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoveredResizeHandle = nil
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = imageRect
        NSColor.black.withAlphaComponent(0.28).setFill()
        rect.insetBy(dx: -1, dy: -1).fill()
        document.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)

        let scale = rect.width / document.image.size.width
        for (index, annotation) in document.annotations.enumerated() where index != inlineEditingIndex {
            AnnotationRenderer.draw(annotation, transform: viewPoint, scale: scale)
        }
        drawInlineText(scale: scale)
        drawSelection()
        if let previewAnnotation {
            AnnotationRenderer.draw(previewAnnotation, transform: viewPoint, scale: scale)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(location) else { return }
        let point = imagePoint(location)

        if document.selectedTool == .select {
            if let index = document.selectedAnnotationIndex,
               document.annotations.indices.contains(index),
               let handle = resizeHandle(at: location) {
                dragStart = point
                dragEnd = point
                movingAnnotation = document.annotations[index]
                resizeHandle = handle
                didMoveAnnotation = false
                cursor(for: handle).set()
                needsDisplay = true
                return
            }

            let tolerance = 8 / interactionScale
            let index = document.annotationIndex(at: point, tolerance: tolerance)
            document.selectAnnotation(at: index)

            if event.clickCount >= 2,
               let index,
               let text = document.annotations[index].textContent {
                beginInlineText(
                    at: text.point,
                    initialText: text.text,
                    style: text.style,
                    editingIndex: index
                )
                return
            }

            if let index {
                dragStart = point
                dragEnd = point
                movingAnnotation = document.annotations[index]
                didMoveAnnotation = false
                NSCursor.closedHand.set()
            }
            needsDisplay = true
            return
        }

        if document.selectedTool == .text {
            beginInlineText(at: point)
            return
        }

        dragStart = point
        dragEnd = point
        dragPoints = [point]
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        let point = imagePoint(convert(event.locationInWindow, from: nil), clamped: true)
        dragEnd = point

        if document.selectedTool == .select,
           let handle = resizeHandle,
           let original = movingAnnotation,
           let index = document.selectedAnnotationIndex {
            let minimumSize = 12 / interactionScale
            let bounds = resizedBounds(from: original.bounds, handle: handle, to: point, minimumSize: minimumSize)
            document.updateAnnotationTransiently(at: index, to: original.resized(to: bounds))
            didMoveAnnotation = true
            cursor(for: handle).set()
            needsDisplay = true
            return
        }

        if document.selectedTool == .select,
           let start = dragStart,
           let original = movingAnnotation,
           let index = document.selectedAnnotationIndex {
            let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
            document.updateAnnotationTransiently(at: index, to: original.translated(by: delta))
            didMoveAnnotation = true
            needsDisplay = true
            return
        }

        if document.selectedTool == .pen || document.selectedTool == .highlight {
            if let last = dragPoints.last, hypot(point.x - last.x, point.y - last.y) >= 1 {
                dragPoints.append(point)
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }
        let end = imagePoint(convert(event.locationInWindow, from: nil), clamped: true)
        dragEnd = end

        if document.selectedTool == .select {
            if didMoveAnnotation,
               let original = movingAnnotation,
               let index = document.selectedAnnotationIndex {
                document.commitTransientChange(at: index, previousAnnotation: original)
            }
            movingAnnotation = nil
            resetDrag()
            updateInteractionCursor(at: convert(event.locationInWindow, from: nil))
            return
        }

        if document.selectedTool == .pen || document.selectedTool == .highlight {
            dragPoints.append(end)
        }

        if hypot(end.x - start.x, end.y - start.y) >= 2, let annotation = previewAnnotation {
            document.add(annotation)
        }
        resetDrag()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51, document.selectedAnnotationIndex != nil {
            document.deleteSelectedAnnotation()
            needsDisplay = true
        } else {
            super.keyDown(with: event)
        }
    }

    private func resetDrag() {
        dragStart = nil
        dragEnd = nil
        dragPoints.removeAll()
        movingAnnotation = nil
        didMoveAnnotation = false
        resizeHandle = nil
        needsDisplay = true
    }

    private var imageRect: CGRect {
        let imageSize = document.image.size
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        // The scroll view owns magnification. Keep the document in image
        // coordinates, with an 18-point margin, so 100% really is 1:1.
        return CGRect(origin: CGPoint(x: 18, y: 18), size: imageSize)
    }

    private func imagePoint(_ point: CGPoint, clamped: Bool = false) -> CGPoint {
        let rect = imageRect
        var x = (point.x - rect.minX) / rect.width * document.image.size.width
        var y = (point.y - rect.minY) / rect.height * document.image.size.height
        if clamped {
            x = min(max(0, x), document.image.size.width)
            y = min(max(0, y), document.image.size.height)
        }
        return CGPoint(x: x, y: y)
    }

    private func viewPoint(_ point: CGPoint) -> CGPoint {
        let rect = imageRect
        return CGPoint(
            x: rect.minX + point.x / document.image.size.width * rect.width,
            y: rect.minY + point.y / document.image.size.height * rect.height
        )
    }

    private var previewAnnotation: Annotation? {
        guard let start = dragStart, let end = dragEnd else { return nil }
        let style = document.currentStyle
        let rect = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
        switch document.selectedTool {
        case .select: return nil
        case .arrow: return .arrow(start: start, end: end, style: style)
        case .line: return .line(start: start, end: end, style: style)
        case .pen: return .pen(points: dragPoints, style: style)
        case .rectangle: return .rectangle(rect, style: style)
        case .ellipse: return .ellipse(rect, style: style)
        case .highlight: return .highlight(points: dragPoints, style: style)
        case .redact: return .redact(rect)
        case .text: return nil
        }
    }

    private func beginInlineText(
        at point: CGPoint,
        initialText: String = "",
        style: AnnotationStyle? = nil,
        editingIndex: Int? = nil
    ) {
        commitInlineText()

        let style = style ?? document.currentStyle
        let scale = imageRect.width / document.image.size.width
        let field = InlineTextField(frame: .zero)
        field.delegate = self
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        // The native field only receives keyboard input. Text and the caret are
        // drawn by AnnotationRenderer so the live and committed positions match.
        field.textColor = .clear
        field.font = .systemFont(ofSize: max(12, style.fontSize * scale), weight: .semibold)
        field.stringValue = initialText
        field.placeholderString = nil
        field.onCancel = { [weak self] in self?.cancelInlineText() }

        inlineTextPoint = point
        inlineTextStyle = style
        inlineEditingIndex = editingIndex
        inlineTextField = field
        addSubview(field)
        positionInlineTextField()
        window?.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertionPointColor = .clear
        startCaretBlinking()
        if !initialText.isEmpty {
            field.currentEditor()?.selectAll(nil)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        resizeInlineTextField()
        showsInlineCaret = true
        needsDisplay = true
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        showsInlineCaret = true
        needsDisplay = true
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitInlineText()
            window?.makeFirstResponder(self)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelInlineText()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        let movement = (notification.userInfo?["NSTextMovement"] as? NSNumber)?.intValue
        if movement == NSCancelTextMovement {
            cancelInlineText()
        } else {
            commitInlineText()
        }
    }

    private func commitInlineText() {
        guard let field = inlineTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let point = inlineTextPoint
        let style = inlineTextStyle
        let editingIndex = inlineEditingIndex
        clearInlineTextField()
        if !text.isEmpty, let point, let style {
            let annotation = Annotation.text(text, at: point, style: style)
            if let editingIndex {
                document.updateAnnotation(at: editingIndex, to: annotation)
                document.selectAnnotation(at: editingIndex)
            } else {
                document.add(annotation)
            }
            needsDisplay = true
        } else if let editingIndex {
            document.selectAnnotation(at: editingIndex)
        }
    }

    private func cancelInlineText() {
        clearInlineTextField()
        window?.makeFirstResponder(self)
    }

    private func clearInlineTextField() {
        inlineTextField?.delegate = nil
        inlineTextField?.removeFromSuperview()
        inlineTextField = nil
        inlineTextPoint = nil
        inlineTextStyle = nil
        inlineEditingIndex = nil
        caretTimer?.invalidate()
        caretTimer = nil
        showsInlineCaret = false
    }

    private func resizeInlineTextField() {
        guard let field = inlineTextField else { return }
        let text = field.stringValue.isEmpty ? "Type…" : field.stringValue
        let width = (text as NSString).size(withAttributes: [.font: field.font ?? NSFont.systemFont(ofSize: 14)]).width + 14
        let maxWidth = max(80, imageRect.maxX - field.frame.minX)
        field.setFrameSize(CGSize(width: min(max(80, width), maxWidth), height: field.frame.height))
    }

    private func positionInlineTextField() {
        guard let field = inlineTextField, let point = inlineTextPoint else { return }
        let location = viewPoint(point)
        let height = max(24, (field.font?.pointSize ?? 14) + 8)
        let existingWidth = field.frame.width > 0 ? field.frame.width : 100
        field.frame = CGRect(x: location.x - 2, y: location.y - 3, width: existingWidth, height: height)
        resizeInlineTextField()
    }

    private func drawSelection() {
        guard document.selectedTool == .select,
              let index = document.selectedAnnotationIndex,
              document.annotations.indices.contains(index),
              index != inlineEditingIndex else { return }
        let bounds = document.annotations[index].bounds
        let a = viewPoint(bounds.origin)
        let b = viewPoint(CGPoint(x: bounds.maxX, y: bounds.maxY))
        let rect = CGRect(
            x: min(a.x, b.x) - 4 / viewportScale,
            y: min(a.y, b.y) - 4 / viewportScale,
            width: abs(b.x - a.x) + 8 / viewportScale,
            height: abs(b.y - a.y) + 8 / viewportScale
        )
        let path = NSBezierPath(rect: rect)
        path.setLineDash([4 / viewportScale, 3 / viewportScale], count: 2, phase: 0)
        path.lineWidth = 1 / viewportScale
        NSColor.controlAccentColor.setStroke()
        path.stroke()

        for (handle, point) in handlePoints(for: rect) {
            let isActive = handle == hoveredResizeHandle || handle == resizeHandle
            let size: CGFloat = (isActive ? 9 : 7) / viewportScale
            let handleRect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            (isActive ? NSColor.controlAccentColor : NSColor.white).setFill()
            handleRect.fill()
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: handleRect)
            border.lineWidth = 1 / viewportScale
            border.stroke()
        }
    }

    private func selectedAnnotationRect() -> CGRect? {
        guard let index = document.selectedAnnotationIndex,
              document.annotations.indices.contains(index) else { return nil }
        let bounds = document.annotations[index].bounds
        let a = viewPoint(bounds.origin)
        let b = viewPoint(CGPoint(x: bounds.maxX, y: bounds.maxY))
        return CGRect(
            x: min(a.x, b.x) - 4 / viewportScale,
            y: min(a.y, b.y) - 4 / viewportScale,
            width: abs(b.x - a.x) + 8 / viewportScale,
            height: abs(b.y - a.y) + 8 / viewportScale
        )
    }

    private func handlePoints(for rect: CGRect) -> [ResizeHandle: CGPoint] {
        [
            .topLeft: CGPoint(x: rect.minX, y: rect.maxY),
            .top: CGPoint(x: rect.midX, y: rect.maxY),
            .topRight: CGPoint(x: rect.maxX, y: rect.maxY),
            .right: CGPoint(x: rect.maxX, y: rect.midY),
            .bottomRight: CGPoint(x: rect.maxX, y: rect.minY),
            .bottom: CGPoint(x: rect.midX, y: rect.minY),
            .bottomLeft: CGPoint(x: rect.minX, y: rect.minY),
            .left: CGPoint(x: rect.minX, y: rect.midY)
        ]
    }

    private func resizeHandle(at viewPoint: CGPoint) -> ResizeHandle? {
        guard let rect = selectedAnnotationRect() else { return nil }
        return handlePoints(for: rect).first { _, point in
            CGRect(x: point.x - 7 / viewportScale, y: point.y - 7 / viewportScale, width: 14 / viewportScale, height: 14 / viewportScale).contains(viewPoint)
        }?.key
    }

    private func resizedBounds(from original: CGRect, handle: ResizeHandle, to point: CGPoint, minimumSize: CGFloat) -> CGRect {
        var minX = original.minX
        var maxX = original.maxX
        var minY = original.minY
        var maxY = original.maxY

        if [.topLeft, .left, .bottomLeft].contains(handle) { minX = min(point.x, maxX - minimumSize) }
        if [.topRight, .right, .bottomRight].contains(handle) { maxX = max(point.x, minX + minimumSize) }
        if [.bottomLeft, .bottom, .bottomRight].contains(handle) { minY = min(point.y, maxY - minimumSize) }
        if [.topLeft, .top, .topRight].contains(handle) { maxY = max(point.y, minY + minimumSize) }

        minX = max(0, minX)
        minY = max(0, minY)
        maxX = min(document.image.size.width, maxX)
        maxY = min(document.image.size.height, maxY)
        return CGRect(x: minX, y: minY, width: max(minimumSize, maxX - minX), height: max(minimumSize, maxY - minY))
    }

    private func updateInteractionCursor(at location: CGPoint) {
        guard imageRect.contains(location) else {
            hoveredResizeHandle = nil
            NSCursor.arrow.set()
            return
        }
        guard document.selectedTool == .select else {
            hoveredResizeHandle = nil
            (document.selectedTool == .text ? NSCursor.iBeam : NSCursor.crosshair).set()
            return
        }
        if let resizeHandle {
            cursor(for: resizeHandle).set()
            return
        }
        if movingAnnotation != nil {
            NSCursor.closedHand.set()
            return
        }

        let handle = resizeHandle(at: location)
        if hoveredResizeHandle != handle {
            hoveredResizeHandle = handle
            needsDisplay = true
        }
        if let handle {
            cursor(for: handle).set()
            return
        }

        let point = imagePoint(location)
        let tolerance = 8 / interactionScale
        if document.annotationIndex(at: point, tolerance: tolerance) != nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func cursor(for handle: ResizeHandle) -> NSCursor {
        switch handle {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .topLeft, .bottomRight: return diagonalDownCursor
        case .topRight, .bottomLeft: return diagonalUpCursor
        }
    }

    private func makeDiagonalCursor(symbol: String) -> NSCursor {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return .crosshair }
        image.size = CGSize(width: 18, height: 18)
        return NSCursor(image: image, hotSpot: CGPoint(x: 9, y: 9))
    }

    private func drawInlineText(scale: CGFloat) {
        guard let field = inlineTextField,
              let point = inlineTextPoint,
              let style = inlineTextStyle else { return }

        if !field.stringValue.isEmpty {
            AnnotationRenderer.draw(
                .text(field.stringValue, at: point, style: style),
                transform: viewPoint,
                scale: scale
            )
        }

        guard showsInlineCaret else { return }
        let fullText = field.stringValue as NSString
        let insertionIndex = min(
            (field.currentEditor() as? NSTextView)?.selectedRange().location ?? fullText.length,
            fullText.length
        )
        let textBeforeCaret = fullText.substring(to: insertionIndex)
        let textWidth = (textBeforeCaret as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold)
        ]).width
        let caretBottom = viewPoint(CGPoint(x: point.x + textWidth + 1, y: point.y))
        let caretTop = viewPoint(CGPoint(x: point.x + textWidth + 1, y: point.y + style.fontSize))
        let caret = NSBezierPath()
        caret.move(to: caretBottom)
        caret.line(to: caretTop)
        caret.lineWidth = 1.5
        style.color.setStroke()
        caret.stroke()
    }

    private func startCaretBlinking() {
        caretTimer?.invalidate()
        showsInlineCaret = true
        needsDisplay = true

        let timer = Timer(timeInterval: 0.52, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.showsInlineCaret.toggle()
            self.needsDisplay = true
        }
        caretTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}

private final class InlineTextField: NSTextField {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
