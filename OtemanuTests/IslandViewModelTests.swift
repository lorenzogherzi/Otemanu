import AppKit
import XCTest

@testable import Otemanu

@MainActor
final class IslandViewModelTests: XCTestCase {
    func testExecutionCanStartInCompactBusyMode() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let viewModel = IslandViewModel(screen: screen)

        viewModel.executionDidStart(openAutomatically: false)

        XCTAssertTrue(viewModel.isExecutionPinned)
        XCTAssertEqual(viewModel.state, .minimizedBusy)

        viewModel.executionDidFinish(
            showCompletionNotice: true,
            automaticallyHide: false,
            delay: 2
        )

        XCTAssertFalse(viewModel.isExecutionPinned)
        XCTAssertTrue(viewModel.showsCompletionNotice)
        XCTAssertEqual(viewModel.state, .open)
    }

    func testExecutionStillOpensByDefault() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let viewModel = IslandViewModel(screen: screen)

        viewModel.executionDidStart()

        XCTAssertEqual(viewModel.state, .open)
    }

    func testCompletionNoticeRemainsUntilTheNotificationIsClosed() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let viewModel = IslandViewModel(screen: screen)
        var didDismissNotice = false
        viewModel.onCompletionNoticeDismissed = {
            didDismissNotice = true
        }

        viewModel.executionDidFinish(
            showCompletionNotice: true,
            automaticallyHide: false,
            delay: 2
        )

        XCTAssertTrue(viewModel.showsCompletionNotice)
        XCTAssertEqual(viewModel.state, .open)
        XCTAssertNil(JupyterMonitor(startAutomatically: false).currentExecution)

        viewModel.toggle()

        XCTAssertFalse(viewModel.showsCompletionNotice)
        XCTAssertEqual(viewModel.state, .closed)
        XCTAssertTrue(didDismissNotice)
    }
}
