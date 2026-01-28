// Tests/InfrastructureTests/Logging/MockLoggerTests.swift

import XCTest
@testable import Infrastructure

final class MockLoggerTests: XCTestCase {

    // MARK: - Basic Capture Tests

    func testMockLoggerCapturesLogs() {
        let mockLogger = MockLogger()

        mockLogger.info("Test message", category: .system)

        XCTAssertEqual(mockLogger.logs.count, 1)
        XCTAssertTrue(mockLogger.hasLog(level: .info, containing: "Test"))
    }

    func testMockLoggerCapturesAllLevels() {
        let mockLogger = MockLogger()

        mockLogger.trace("Trace", category: .system)
        mockLogger.debug("Debug", category: .system)
        mockLogger.info("Info", category: .system)
        mockLogger.warn("Warn", category: .system)
        mockLogger.error("Error", category: .system)

        XCTAssertEqual(mockLogger.logs.count, 5)
    }

    // MARK: - Filter Tests

    func testMockLoggerFiltersByLevel() {
        let mockLogger = MockLogger()

        mockLogger.debug("Debug message", category: .system)
        mockLogger.error("Error message", category: .system)

        XCTAssertEqual(mockLogger.logs(level: .error).count, 1)
        XCTAssertEqual(mockLogger.logs(level: .debug).count, 1)
    }

    func testMockLoggerFiltersByCategory() {
        let mockLogger = MockLogger()

        mockLogger.info("System log", category: .system)
        mockLogger.info("Agent log", category: .agent)
        mockLogger.info("Task log", category: .task)

        XCTAssertEqual(mockLogger.logs(category: .system).count, 1)
        XCTAssertEqual(mockLogger.logs(category: .agent).count, 1)
        XCTAssertEqual(mockLogger.logs(category: .task).count, 1)
    }

    // MARK: - Search Tests

    func testMockLoggerHasLogWithContaining() {
        let mockLogger = MockLogger()

        mockLogger.info("User authentication successful", category: .auth)

        XCTAssertTrue(mockLogger.hasLog(containing: "authentication"))
        XCTAssertTrue(mockLogger.hasLog(containing: "successful"))
        XCTAssertFalse(mockLogger.hasLog(containing: "failed"))
    }

    func testMockLoggerHasLogWithLevelAndContaining() {
        let mockLogger = MockLogger()

        mockLogger.info("Info message", category: .system)
        mockLogger.error("Error message", category: .system)

        XCTAssertTrue(mockLogger.hasLog(level: .info, containing: "Info"))
        XCTAssertFalse(mockLogger.hasLog(level: .info, containing: "Error"))
        XCTAssertTrue(mockLogger.hasLog(level: .error, containing: "Error"))
    }

    // MARK: - Context Fields Tests

    func testMockLoggerCapturesContextFields() {
        let mockLogger = MockLogger()

        mockLogger.log(
            .info,
            category: .agent,
            message: "Agent action",
            operation: "getAgentAction",
            agentId: "agt_123",
            projectId: "prj_456",
            details: nil
        )

        XCTAssertEqual(mockLogger.logs.count, 1)
        let log = mockLogger.logs[0]
        XCTAssertEqual(log.operation, "getAgentAction")
        XCTAssertEqual(log.agentId, "agt_123")
        XCTAssertEqual(log.projectId, "prj_456")
    }

    // MARK: - Clear Tests

    func testMockLoggerClear() {
        let mockLogger = MockLogger()

        mockLogger.info("Message 1", category: .system)
        mockLogger.info("Message 2", category: .system)

        XCTAssertEqual(mockLogger.logs.count, 2)

        mockLogger.clear()

        XCTAssertEqual(mockLogger.logs.count, 0)
    }

    // MARK: - Minimum Level Tests

    func testMockLoggerRespectsMinimumLevel() {
        let mockLogger = MockLogger()
        mockLogger.setMinimumLevel(.warn)

        mockLogger.debug("Should not appear", category: .system)
        mockLogger.info("Should not appear", category: .system)
        mockLogger.warn("Should appear", category: .system)
        mockLogger.error("Should appear", category: .system)

        XCTAssertEqual(mockLogger.logs.count, 2)
        XCTAssertTrue(mockLogger.hasLog(level: .warn, containing: "Should appear"))
        XCTAssertTrue(mockLogger.hasLog(level: .error, containing: "Should appear"))
    }
}
