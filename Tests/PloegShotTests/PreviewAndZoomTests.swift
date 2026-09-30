import AppKit
import XCTest
@testable import PloegShot

final class PreviewAndZoomTests: XCTestCase {
    func testEveryPreviewCanBeReachedWithoutGoingOffScreen() {
        for height: CGFloat in [400, 768, 900, 1440] {
            var reached: [Int] = []
            var offset = 0
            repeat {
                let page = PreviewStackPage(total: 17, offset: offset, visibleHeight: height)
                reached.append(contentsOf: page.range)
                let top = 18 + CGFloat(page.range.count - 1) * (PreviewPanelController.panelSize.height + PreviewPanelController.stackSpacing) + PreviewPanelController.panelSize.height
                XCTAssertLessThanOrEqual(top, height - 18)
                offset = page.range.upperBound
                if !page.hasOlder { break }
            } while true
            XCTAssertEqual(reached, Array(0..<17))
        }
    }

    func testClosingLastItemOnLastPageReturnsToReachablePage() {
        let before = PreviewStackPage(total: 9, offset: 8, visibleHeight: 900)
        XCTAssertEqual(before.range, 8..<9)
        let after = PreviewStackPage(total: 8, offset: before.range.lowerBound, visibleHeight: 900)
        XCTAssertEqual(after.range, 4..<8)
        XCTAssertTrue(after.hasNewer)
        XCTAssertFalse(after.hasOlder)
        let newest = PreviewStackPage(total: 8, offset: -4, visibleHeight: 900)
        XCTAssertEqual(newest.range, 0..<4)
    }

    @MainActor
    func testZoomAndFitKeepAnnotationsInImageCoordinates() {
        _ = NSApplication.shared
        let document = EditorDocument(image: NSImage(size: CGSize(width: 1000, height: 800)))
        document.add(.redact(CGRect(x: 50, y: 60, width: 100, height: 80)))
        let viewport = AnnotationViewportView(document: document)
        viewport.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
        viewport.needsLayout = true
        viewport.layoutSubtreeIfNeeded()
        var actualZoom: CGFloat = 0
        viewport.onActualZoom = { actualZoom = $0 }
        viewport.setZoom(nil)
        XCTAssertGreaterThan(actualZoom, 0)
        XCTAssertLessThan(actualZoom, 0.5)
        viewport.setZoom(2)
        XCTAssertEqual(actualZoom, 2, accuracy: 0.001)
        XCTAssertEqual(viewport.canvas.viewportScale, 2, accuracy: 0.001)
        XCTAssertEqual(document.annotations[0].bounds, CGRect(x: 50, y: 60, width: 100, height: 80))
        viewport.setZoom(100)
        XCTAssertEqual(actualZoom, 8, accuracy: 0.001)
        viewport.setZoom(nil)
        XCTAssertLessThan(actualZoom, 0.5)
    }

    @MainActor
    func testDrawingAfterZoomAndPanUsesOriginalImageCoordinates() throws {
        _ = NSApplication.shared
        let document = EditorDocument(image: NSImage(size: CGSize(width: 1000, height: 800)))
        document.selectedTool = .redact
        let viewport = AnnotationViewportView(document: document)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = viewport
        viewport.needsLayout = true
        viewport.layoutSubtreeIfNeeded()
        viewport.setZoom(2)
        let scrollView = try XCTUnwrap(viewport.subviews.first as? NSScrollView)
        scrollView.contentView.scroll(to: CGPoint(x: 250, y: 250))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        let start = viewport.canvas.convert(CGPoint(x: 318, y: 318), to: nil)
        let end = viewport.canvas.convert(CGPoint(x: 398, y: 378), to: nil)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: start, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: end, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        viewport.canvas.mouseDown(with: down)
        viewport.canvas.mouseUp(with: up)
        XCTAssertEqual(document.annotations.count, 1)
        let bounds = try XCTUnwrap(document.annotations.first?.bounds)
        XCTAssertEqual(bounds.minX, 300, accuracy: 0.001)
        XCTAssertEqual(bounds.minY, 300, accuracy: 0.001)
        XCTAssertEqual(bounds.width, 80, accuracy: 0.001)
        XCTAssertEqual(bounds.height, 60, accuracy: 0.001)
    }
}
