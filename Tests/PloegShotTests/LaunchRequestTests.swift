import XCTest
@testable import PloegShot

final class LaunchRequestTests: XCTestCase {
    func testBackgroundLaunchDoesNotRequestAWindow() {
        XCTAssertEqual(PloegShotLaunchRequest(arguments: ["PloegShot"]), .menuBarOnly)
    }

    func testToolboxColdOpenRequestsSettings() {
        XCTAssertEqual(PloegShotLaunchRequest(arguments: ["PloegShot", "--show-settings"]), .showSettings)
        XCTAssertEqual(PloegShotLaunchRequest(arguments: ["PloegShot", "--show-settings-extra"]), .menuBarOnly)
    }

    func testPreviewArgumentsTakePriorityOverToolboxOpen() {
        for preview in ["--design-preview", "--design-preview-settings", "--design-preview-dark"] {
            XCTAssertEqual(
                PloegShotLaunchRequest(arguments: ["PloegShot", "--show-settings", preview]),
                .designPreview
            )
        }
    }

    func testReviewBundleStaysInPreviewWhenOpenedByToolbox() {
        XCTAssertEqual(
            PloegShotLaunchRequest(arguments: ["PloegShot", "--show-settings"], bundleDesignPreview: true),
            .designPreview
        )
    }
}
