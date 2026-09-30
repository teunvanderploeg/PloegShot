import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import PloegShot

final class CaptureAndExportTests: XCTestCase {
    func testRetinaCropUsesTopLeftPixelsAndScreenLocalCoordinates() throws {
        let bitmap = try makeBitmap(width: 200, height: 160)
        for y in 0..<160 {
            for x in 0..<200 {
                bitmap.setColor(NSColor(deviceRed: CGFloat(x) / 255, green: CGFloat(y) / 255, blue: 0, alpha: 1), atX: x, y: y)
            }
        }
        let cropped = try ScreenCapturer.crop(
            XCTUnwrap(bitmap.cgImage), area: CGRect(x: 10, y: 20, width: 30, height: 15),
            screenSize: CGSize(width: 100, height: 80)
        )
        XCTAssertEqual(cropped.width, 60)
        XCTAssertEqual(cropped.height, 30)
        let result = NSBitmapImageRep(cgImage: cropped)
        let firstPixel = try XCTUnwrap(result.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(firstPixel.redComponent, 20.0 / 255, accuracy: 0.005)
        XCTAssertEqual(firstPixel.greenComponent, 90.0 / 255, accuracy: 0.005)
    }

    func testInvalidAreasFailInsteadOfReturningFullDisplay() throws {
        let image = try XCTUnwrap(makeBitmap(width: 200, height: 160).cgImage)
        let areas = [
            CGRect.zero,
            CGRect(x: -1, y: 0, width: 20, height: 20),
            CGRect(x: 90, y: 0, width: 20, height: 20),
            CGRect(x: 0, y: 70, width: 20, height: 20),
            CGRect(x: CGFloat.nan, y: 0, width: 20, height: 20)
        ]
        for area in areas {
            XCTAssertThrowsError(try ScreenCapturer.crop(image, area: area, screenSize: CGSize(width: 100, height: 80))) { error in
                guard case ScreenCaptureError.invalidSelection = error else {
                    return XCTFail("Expected invalid selection, received \(error)")
                }
            }
        }
    }

    func testCaptureAtDisplayEdgesAndFractionalScale() throws {
        let image = try XCTUnwrap(makeBitmap(width: 250, height: 200).cgImage)
        let full = try ScreenCapturer.crop(image, area: CGRect(x: 0, y: 0, width: 100, height: 80), screenSize: CGSize(width: 100, height: 80))
        XCTAssertEqual(full.width, 250)
        XCTAssertEqual(full.height, 200)
        let corner = try ScreenCapturer.crop(image, area: CGRect(x: 99, y: 79, width: 1, height: 1), screenSize: CGSize(width: 100, height: 80))
        XCTAssertEqual(corner.width, 3)
        XCTAssertEqual(corner.height, 3)
    }

    func testPNGExportPreservesPixelDimensions() throws {
        for size in [CGSize(width: 640, height: 480), CGSize(width: 1280, height: 960), CGSize(width: 257, height: 193)] {
            let document = try makeDocument(size: size)
            document.add(.rectangle(CGRect(x: 5, y: 5, width: 20, height: 20), style: AnnotationStyle(color: .blue, lineWidth: 3, fontSize: 20)))
            let data = try XCTUnwrap(document.renderedImage().pngData)
            let exported = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(exported.pixelsWide, Int(size.width))
            XCTAssertEqual(exported.pixelsHigh, Int(size.height))
        }
    }

    func testRedactionCoversEveryPixelIncludingFractionalCorners() throws {
        let document = try makeDocument(size: CGSize(width: 40, height: 40))
        document.add(.redact(CGRect(x: 5.25, y: 6.25, width: 12.5, height: 10.5)))
        let data = try XCTUnwrap(document.renderedImage().pngData)
        let exported = try XCTUnwrap(NSBitmapImageRep(data: data))
        // Bitmap rows start at the top; annotation coordinates start at the bottom.
        for y in (40 - 17)..<(40 - 6) {
            for x in 5..<18 {
                let color = try XCTUnwrap(exported.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.001)
                XCTAssertLessThan(color.redComponent, 0.2, "Uncovered pixel at \(x), \(y)")
            }
        }
        let outside = try XCTUnwrap(exported.colorAt(x: 4, y: 25)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(outside.redComponent, 0.99)
    }

    func testDragProvidesPNGDataAndAReadableFileURL() async throws {
        let document = try makeDocument(size: CGSize(width: 40, height: 40))
        let image = try document.renderedImage()
        let expected = try XCTUnwrap(image.pngData)
        let provider = try ImageExporter.dragItemProvider(for: image)
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.png.identifier))
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
            }
        }
        XCTAssertEqual(data, expected)
        let fileURL: URL = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { object, error in
                if let error { continuation.resume(throwing: error) }
                else if let url = object as? URL { continuation.resume(returning: url) }
                else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
            }
        }
        defer { try? FileManager.default.removeItem(at: fileURL) }
        XCTAssertEqual(try Data(contentsOf: fileURL), expected)
        let loadedFile = expectation(description: "PNG file representation")
        provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, error in
            XCTAssertNil(error)
            if let url { XCTAssertEqual(try? Data(contentsOf: url), expected) }
            else { XCTFail("Missing PNG file") }
            loadedFile.fulfill()
        }
        await fulfillment(of: [loadedFile], timeout: 5)
    }

    private func makeDocument(size: CGSize) throws -> EditorDocument {
        let bitmap = try makeBitmap(width: Int(size.width), height: Int(size.height))
        let red = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide { bitmap.setColor(red, atX: x, y: y) }
        }
        let image = NSImage(size: size)
        bitmap.size = size
        image.addRepresentation(bitmap)
        return EditorDocument(image: image)
    }

    private func makeBitmap(width: Int, height: Int) throws -> NSBitmapImageRep {
        try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
    }
}
