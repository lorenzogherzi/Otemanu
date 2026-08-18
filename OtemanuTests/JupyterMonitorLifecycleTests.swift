import XCTest

@testable import Otemanu

@MainActor
final class JupyterMonitorLifecycleTests: XCTestCase {
    func testCompletedExecutionIsRetainedUntilNotificationDismissal() throws {
        let monitor = JupyterMonitor(startAutomatically: false)

        monitor.handle(
            try message(type: "status", parentID: "cell-1", content: ["execution_state": "busy"]),
            kernelID: "kernel-1"
        )
        monitor.handle(
            try message(
                type: "execute_input",
                parentID: "cell-1",
                content: ["code": "long_running_work()", "execution_count": 1]
            ),
            kernelID: "kernel-1"
        )

        XCTAssertEqual(monitor.activeExecutionCount, 1)
        XCTAssertEqual(monitor.busyKernelCount, 1)
        XCTAssertNotNil(monitor.currentExecution)

        monitor.handle(
            try message(type: "status", parentID: "cell-1", content: ["execution_state": "idle"]),
            kernelID: "kernel-1"
        )

        XCTAssertEqual(monitor.activeExecutionCount, 0)
        XCTAssertEqual(monitor.busyKernelCount, 0)
        XCTAssertEqual(monitor.currentExecution?.phase, .completed)
        XCTAssertEqual(monitor.currentExecution?.codeSummary, "long_running_work()")
        XCTAssertNotNil(monitor.currentExecution?.finishedAt)

        monitor.discardCompletedExecution()

        XCTAssertNil(monitor.currentExecution)
    }

    func testFinishingOneKernelKeepsOnlyTheOtherActiveExecution() throws {
        let monitor = JupyterMonitor(startAutomatically: false)

        try startExecution(id: "cell-a", kernelID: "kernel-a", monitor: monitor)
        try startExecution(id: "cell-b", kernelID: "kernel-b", monitor: monitor)

        XCTAssertEqual(monitor.activeExecutionCount, 2)
        XCTAssertEqual(monitor.busyKernelCount, 2)
        XCTAssertEqual(monitor.currentExecution?.kernelID, "kernel-b")

        monitor.handle(
            try message(type: "status", parentID: "cell-a", content: ["execution_state": "idle"]),
            kernelID: "kernel-a"
        )

        XCTAssertEqual(monitor.activeExecutionCount, 1)
        XCTAssertEqual(monitor.busyKernelCount, 1)
        XCTAssertEqual(monitor.currentExecution?.kernelID, "kernel-b")

        monitor.handle(
            try message(type: "status", parentID: "cell-b", content: ["execution_state": "idle"]),
            kernelID: "kernel-b"
        )

        XCTAssertEqual(monitor.activeExecutionCount, 0)
        XCTAssertEqual(monitor.busyKernelCount, 0)
        XCTAssertEqual(monitor.currentExecution?.kernelID, "kernel-b")
        XCTAssertEqual(monitor.currentExecution?.phase, .completed)

        monitor.discardCompletedExecution()

        XCTAssertNil(monitor.currentExecution)
    }

    private func startExecution(
        id: String,
        kernelID: String,
        monitor: JupyterMonitor
    ) throws {
        monitor.handle(
            try message(type: "status", parentID: id, content: ["execution_state": "busy"]),
            kernelID: kernelID
        )
        monitor.handle(
            try message(
                type: "execute_input",
                parentID: id,
                content: ["code": "work()", "execution_count": 1]
            ),
            kernelID: kernelID
        )
    }

    private func message(
        type: String,
        parentID: String,
        content: [String: Any]
    ) throws -> JupyterKernelMessage {
        let data = try JSONSerialization.data(withJSONObject: [
            "channel": "iopub",
            "header": ["msg_type": type],
            "parent_header": ["msg_id": parentID],
            "content": content,
        ])
        return try XCTUnwrap(JupyterKernelMessage(data: data))
    }
}
