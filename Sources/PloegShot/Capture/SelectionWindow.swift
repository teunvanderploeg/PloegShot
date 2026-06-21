import AppKit

enum CaptureMode { case area, repeatArea, screen }

enum CaptureSelection {
    case area(ScreenSelection)
    case screen(NSScreen)
}

final class ReusableAreaState {
    private(set) var targetScreen: NSScreen
    private(set) var rect: CGRect
    private let observers = NSHashTable<NSView>.weakObjects()

    init(screen: NSScreen, rect: CGRect) {
        targetScreen = screen
        self.rect = rect
    }

    func register(_ view: NSView) { observers.add(view) }

    func move(globalRect: CGRect, pointer: CGPoint) {
        let destination = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? targetScreen
        targetScreen = destination
        let width = min(globalRect.width, destination.frame.width)
        let height = min(globalRect.height, destination.frame.height)
        var x = globalRect.minX - destination.frame.minX
        var y = globalRect.minY - destination.frame.minY
        x = min(max(0, x), destination.frame.width - width)
        y = min(max(0, y), destination.frame.height - height)
        rect = CGRect(x: x, y: y, width: width, height: height)
        notifyObservers()
    }

    func resize(to rect: CGRect) {
        self.rect = rect
        notifyObservers()
    }

    var globalRect: CGRect {
        rect.offsetBy(dx: targetScreen.frame.minX, dy: targetScreen.frame.minY)
    }

    func isActive(on screen: NSScreen) -> Bool {
        targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            == screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }

    private func notifyObservers() {
        observers.allObjects.forEach {
            $0.needsDisplay = true
            $0.window?.invalidateCursorRects(for: $0)
        }
    }
}

final class SelectionWindow: NSWindow {
    let captureScreen: NSScreen
    private let selectionView: SelectionView

    init(
        mode: CaptureMode,
        screen: NSScreen,
        reusableState: ReusableAreaState? = nil,
        onSelection: @escaping (CaptureSelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        captureScreen = screen
        selectionView = SelectionView(mode: mode, screen: screen, reusableState: reusableState, onSelection: onSelection, onCancel: onCancel)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var canConfirmSelection: Bool { selectionView.hasReusableArea }
    func confirmSelection() { selectionView.confirmSelection() }
}

private final class SelectionView: NSView {
    private struct ResizeEdges: OptionSet {
        let rawValue: Int
        static let left = Self(rawValue: 1 << 0)
        static let right = Self(rawValue: 1 << 1)
        static let bottom = Self(rawValue: 1 << 2)
        static let top = Self(rawValue: 1 << 3)
    }

    private enum DragOperation {
        case move(start: CGPoint, original: CGRect)
        case resize(start: CGPoint, original: CGRect, edges: ResizeEdges)
    }

    private let mode: CaptureMode
    private let screen: NSScreen
    private let onSelection: (CaptureSelection) -> Void
    private let onCancel: () -> Void
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private let reusableState: ReusableAreaState?
    fileprivate var hasReusableArea: Bool { reusableState?.isActive(on: screen) == true }
    private var reusableRect: CGRect { reusableState?.rect ?? .zero }
    private var dragOperation: DragOperation?
    private lazy var diagonalDownCursor = makeDiagonalCursor(symbol: "arrow.up.left.and.arrow.down.right")
    private lazy var diagonalUpCursor = makeDiagonalCursor(symbol: "arrow.up.right.and.arrow.down.left")

    init(mode: CaptureMode, screen: NSScreen, reusableState: ReusableAreaState?, onSelection: @escaping (CaptureSelection) -> Void, onCancel: @escaping () -> Void) {
        self.mode = mode
        self.screen = screen
        self.onSelection = onSelection
        self.onCancel = onCancel
        self.reusableState = reusableState
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        reusableState?.register(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func cursorUpdate(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.36).setFill()
        bounds.fill()

        let clearRect: CGRect?
        switch mode {
        case .area: clearRect = selectionRect
        case .repeatArea: clearRect = hasReusableArea ? reusableRect : nil
        case .screen: clearRect = bounds.insetBy(dx: 2, dy: 2)
        }
        if let clearRect { drawSelection(rect: clearRect) }

        switch mode {
        case .area:
            if let selectionRect { drawLabel("\(Int(selectionRect.width)) × \(Int(selectionRect.height))", at: CGPoint(x: selectionRect.minX, y: max(4, selectionRect.minY - 22))) }
        case .repeatArea:
            if hasReusableArea {
                drawHandles(around: reusableRect)
                drawLabel("\(Int(reusableRect.width)) × \(Int(reusableRect.height))  •  Press Enter to capture", at: CGPoint(x: reusableRect.minX, y: max(4, reusableRect.minY - 22)))
            }
        case .screen:
            drawLabel("Click to capture this display", at: CGPoint(x: bounds.midX - 90, y: bounds.midY))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch mode {
        case .area:
            startPoint = point
            currentPoint = point
        case .repeatArea:
            guard hasReusableArea else { break }
            let edges = resizeEdges(at: point)
            if !edges.isEmpty {
                dragOperation = .resize(start: point, original: reusableRect, edges: edges)
                cursor(for: edges).set()
            } else if reusableRect.contains(point) {
                dragOperation = .move(start: NSEvent.mouseLocation, original: reusableState?.globalRect ?? reusableRect)
                NSCursor.closedHand.set()
            }
        case .screen:
            break
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch mode {
        case .area:
            currentPoint = point
        case .repeatArea:
            updateReusableRect(to: point)
            if case .move = dragOperation { NSCursor.closedHand.set() }
        case .screen:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch mode {
        case .area:
            currentPoint = convert(event.locationInWindow, from: nil)
            guard let rect = selectionRect, rect.width >= 2, rect.height >= 2 else { onCancel(); return }
            onSelection(.area(ScreenSelection(screen: screen, rect: rect)))
        case .repeatArea:
            dragOperation = nil
            updateCursor(at: convert(event.locationInWindow, from: nil))
        case .screen:
            onSelection(.screen(screen))
        }
    }

    func confirmSelection() {
        guard case .repeatArea = mode,
              let reusableState,
              reusableRect.width >= 2,
              reusableRect.height >= 2 else { return }
        onSelection(.area(ScreenSelection(screen: reusableState.targetScreen, rect: reusableState.rect)))
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(x: min(startPoint.x, currentPoint.x), y: min(startPoint.y, currentPoint.y), width: abs(currentPoint.x - startPoint.x), height: abs(currentPoint.y - startPoint.y))
    }

    private func resizeEdges(at point: CGPoint) -> ResizeEdges {
        let hit: CGFloat = 10
        guard reusableRect.insetBy(dx: -hit, dy: -hit).contains(point) else { return [] }
        var edges: ResizeEdges = []
        if abs(point.x - reusableRect.minX) <= hit { edges.insert(.left) }
        if abs(point.x - reusableRect.maxX) <= hit { edges.insert(.right) }
        if abs(point.y - reusableRect.minY) <= hit { edges.insert(.bottom) }
        if abs(point.y - reusableRect.maxY) <= hit { edges.insert(.top) }
        return edges
    }

    private func updateReusableRect(to point: CGPoint) {
        guard let dragOperation else { return }
        switch dragOperation {
        case let .move(start, original):
            let globalPoint = NSEvent.mouseLocation
            let rect = original.offsetBy(dx: globalPoint.x - start.x, dy: globalPoint.y - start.y)
            reusableState?.move(globalRect: rect, pointer: globalPoint)
        case let .resize(start, original, edges):
            let dx = point.x - start.x
            let dy = point.y - start.y
            var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
            if edges.contains(.left) { minX = min(max(original.minX + dx, bounds.minX), maxX - 40) }
            if edges.contains(.right) { maxX = max(min(original.maxX + dx, bounds.maxX), minX + 40) }
            if edges.contains(.bottom) { minY = min(max(original.minY + dy, bounds.minY), maxY - 40) }
            if edges.contains(.top) { maxY = max(min(original.maxY + dy, bounds.maxY), minY + 40) }
            reusableState?.resize(to: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
        }
    }

    private func drawSelection(rect: CGRect) {
        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        rect.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    private func drawHandles(around rect: CGRect) {
        let points = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        NSColor.white.setFill()
        points.forEach { CGRect(x: $0.x - 4, y: $0.y - 4, width: 8, height: 8).fill() }
    }

    private func drawLabel(_ text: String, at point: CGPoint) {
        text.draw(at: point, withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.72)])
    }

    private func updateCursor(at point: CGPoint) {
        guard case .repeatArea = mode, hasReusableArea else {
            NSCursor.crosshair.set()
            return
        }
        if case .move = dragOperation {
            NSCursor.closedHand.set()
            return
        }
        if case let .resize(_, _, edges) = dragOperation {
            cursor(for: edges).set()
            return
        }
        let edges = resizeEdges(at: point)
        if !edges.isEmpty {
            cursor(for: edges).set()
        } else if reusableRect.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    private func cursor(for edges: ResizeEdges) -> NSCursor {
        let horizontal = edges.contains(.left) || edges.contains(.right)
        let vertical = edges.contains(.top) || edges.contains(.bottom)
        if horizontal && vertical {
            let downDiagonal = (edges.contains(.left) && edges.contains(.top)) || (edges.contains(.right) && edges.contains(.bottom))
            return downDiagonal ? diagonalDownCursor : diagonalUpCursor
        }
        return horizontal ? .resizeLeftRight : .resizeUpDown
    }

    private func makeDiagonalCursor(symbol: String) -> NSCursor {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return .crosshair }
        image.size = CGSize(width: 18, height: 18)
        return NSCursor(image: image, hotSpot: CGPoint(x: 9, y: 9))
    }
}
