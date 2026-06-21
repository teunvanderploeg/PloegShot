import AppKit
import XCTest
@testable import PloegShot

final class EditorDocumentHistoryTests: XCTestCase {
    private var style: AnnotationStyle {
        AnnotationStyle(color: .systemRed, lineWidth: 4, fontSize: 24)
    }

    func testClearCanBeUndoneAsOneAction() {
        let document = makeDocument()
        document.add(.rectangle(CGRect(x: 10, y: 20, width: 100, height: 50), style: style))
        document.add(.ellipse(CGRect(x: 30, y: 40, width: 60, height: 60), style: style))

        document.clear()
        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertTrue(document.canUndo)

        document.undo()
        XCTAssertEqual(document.annotations.count, 2)
    }

    func testDeletingAndUndoingPreservesAnnotationOrder() {
        let document = makeDocument()
        let firstRect = CGRect(x: 10, y: 20, width: 100, height: 50)
        let secondRect = CGRect(x: 200, y: 100, width: 80, height: 40)
        document.add(.rectangle(firstRect, style: style))
        document.add(.rectangle(secondRect, style: style))

        document.selectAnnotation(at: 0)
        document.deleteSelectedAnnotation()
        document.undo()

        XCTAssertEqual(document.annotations.map(\.bounds), [firstRect, secondRect])
    }

    func testMoveIsOneUndoableTransaction() {
        let document = makeDocument()
        let original = Annotation.rectangle(CGRect(x: 10, y: 20, width: 100, height: 50), style: style)
        document.add(original)
        let moved = original.translated(by: CGPoint(x: 40, y: 30))

        document.updateAnnotationTransiently(at: 0, to: moved)
        document.commitTransientChange(at: 0, previousAnnotation: original)
        XCTAssertEqual(document.annotations[0].bounds.origin, CGPoint(x: 50, y: 50))

        document.undo()
        XCTAssertEqual(document.annotations[0].bounds.origin, CGPoint(x: 10, y: 20))
    }

    func testResizeIsOneUndoableTransaction() {
        let document = makeDocument()
        let originalRect = CGRect(x: 10, y: 20, width: 100, height: 50)
        let resizedRect = CGRect(x: 10, y: 20, width: 180, height: 120)
        let original = Annotation.rectangle(originalRect, style: style)
        document.add(original)

        document.updateAnnotationTransiently(at: 0, to: original.resized(to: resizedRect))
        document.commitTransientChange(at: 0, previousAnnotation: original)
        XCTAssertEqual(document.annotations[0].bounds, resizedRect)

        document.undo()
        XCTAssertEqual(document.annotations[0].bounds, originalRect)
    }

    private func makeDocument() -> EditorDocument {
        EditorDocument(image: NSImage(size: CGSize(width: 640, height: 480)))
    }
}
