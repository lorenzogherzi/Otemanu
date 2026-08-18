import AppKit
import XCTest

@testable import Otemanu

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testSettingsWindowHasNoSidebarToolbarControl() throws {
        let window = try XCTUnwrap(SettingsWindowController.shared.window)

        XCTAssertNil(window.toolbar)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertFalse(window.isOpaque)
    }
}
