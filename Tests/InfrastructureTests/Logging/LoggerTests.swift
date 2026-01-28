// Tests/InfrastructureTests/Logging/LoggerTests.swift

import XCTest
@testable import Infrastructure

// MARK: - Mock LogOutput for Testing

final class MockLogOutput: LogOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [LogEntry] = []

    var entries: [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    func write(_ entry: LogEntry) {
        lock.lock()
        defer { lock.unlock() }
        _entries.append(entry)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        _entries.removeAll()
    }
}

// MARK: - Logger Tests

final class LoggerTests: XCTestCase {

    // MARK: - Basic Output Tests

    func testLoggerWritesToOutput() {
        let mockOutput = MockLogOutput()
        let logger = MCPLogger()
        logger.addOutput(mockOutput)

        logger.info("Test message", category: .system)

        XCTAssertEqual(mockOutput.entries.count, 1)
        XCTAssertEqual(mockOutput.entries[0].message, "Test message")
        XCTAssertEqual(mockOutput.entries[0].level, .info)
        XCTAssertEqual(mockOutput.entries[0].category, .system)
    }

    func testLoggerMultipleOutputs() {
        let output1 = MockLogOutput()
        let output2 = MockLogOutput()
        let logger = MCPLogger()
        logger.addOutput(output1)
        logger.addOutput(output2)

        logger.info("Test", category: .system)

        XCTAssertEqual(output1.entries.count, 1)
        XCTAssertEqual(output2.entries.count, 1)
    }

    // MARK: - Minimum Level Tests

    func testLoggerRespectsMinimumLevel() {
        let mockOutput = MockLogOutput()
        let logger = MCPLogger()
        logger.addOutput(mockOutput)
        logger.setMinimumLevel(.warn)

        logger.debug("Should not appear", category: .system)
        logger.info("Should not appear", category: .system)
        logger.warn("Should appear", category: .system)
        logger.error("Should appear", category: .system)

        XCTAssertEqual(mockOutput.entries.count, 2)
        XCTAssertEqual(mockOutput.entries[0].level, .warn)
        XCTAssertEqual(mockOutput.entries[1].level, .error)
    }

    func testLoggerDefaultLevelIsInfo() {
        let mockOutput = MockLogOutput()
        let logger = MCPLogger()
        logger.addOutput(mockOutput)

        logger.trace("Should not appear", category: .system)
        logger.debug("Should not appear", category: .system)
        logger.info("Should appear", category: .system)

        XCTAssertEqual(mockOutput.entries.count, 1)
        XCTAssertEqual(mockOutput.entries[0].level, .info)
    }

    // MARK: - Context Fields Tests

    func testLoggerWithContextFields() {
        let mockOutput = MockLogOutput()
        let logger = MCPLogger()
        logger.addOutput(mockOutput)

        logger.log(
            .info,
            category: .agent,
            message: "Action",
            operation: "getAgentAction",
            agentId: "agt_123",
            projectId: "prj_456"
        )

        let entry = mockOutput.entries[0]
        XCTAssertEqual(entry.operation, "getAgentAction")
        XCTAssertEqual(entry.agentId, "agt_123")
        XCTAssertEqual(entry.projectId, "prj_456")
    }

    func testLoggerWithDetails() {
        let mockOutput = MockLogOutput()
        let logger = MCPLogger()
        logger.addOutput(mockOutput)

        // Use info level (default minimum level is info)
        logger.log(
            .info,
            category: .task,
            message: "Task details",
            details: ["taskId": "task_001", "status": "completed"]
        )

        XCTAssertEqual(mockOutput.entries.count, 1)
        let entry = mockOutput.entries[0]
        XCTAssertEqual(entry.details?["taskId"] as? String, "task_001")
        XCTAssertEqual(entry.details?["status"] as? String, "completed")
    }

    // MARK: - Convenience Method Tests

    func testLoggerTraceMethod() {
        let mockOutput = MockLogOutput()
        let logger = MCPLogger()
        logger.addOutput(mockOutput)
        logger.setMinimumLevel(.trace)

        logger.trace("Trace message", category: .health)

        XCTAssertEqual(mockOutput.entries.count, 1)
        XCTAssertEqual(mockOutput.entries[0].level, .trace)
        XCTAssertEqual(mockOutput.entries[0].category, .health)
    }

    func testLoggerDebugMethod() {
        let mockOutput = MockLogOutput()
        let logger = MCPLogger()
        logger.addOutput(mockOutput)
        logger.setMinimumLevel(.debug)

        logger.debug("Debug message", category: .transport)

        XCTAssertEqual(mockOutput.entries.count, 1)
        XCTAssertEqual(mockOutput.entries[0].level, .debug)
        XCTAssertEqual(mockOutput.entries[0].category, .transport)
    }

    func testLoggerWarnMethod() {
        let mockOutput = MockLogOutput()
        let logger = MCPLogger()
        logger.addOutput(mockOutput)

        logger.warn("Warning message", category: .auth)

        XCTAssertEqual(mockOutput.entries.count, 1)
        XCTAssertEqual(mockOutput.entries[0].level, .warn)
        XCTAssertEqual(mockOutput.entries[0].category, .auth)
    }

    func testLoggerErrorMethod() {
        let mockOutput = MockLogOutput()
        let logger = MCPLogger()
        logger.addOutput(mockOutput)

        logger.error("Error message", category: .chat)

        XCTAssertEqual(mockOutput.entries.count, 1)
        XCTAssertEqual(mockOutput.entries[0].level, .error)
        XCTAssertEqual(mockOutput.entries[0].category, .chat)
    }

    // MARK: - Remove Output Tests

    func testLoggerRemoveOutput() {
        let output1 = MockLogOutput()
        let output2 = MockLogOutput()
        let logger = MCPLogger()
        logger.addOutput(output1)
        logger.addOutput(output2)

        logger.info("First", category: .system)

        logger.removeOutput(output1)

        logger.info("Second", category: .system)

        XCTAssertEqual(output1.entries.count, 1)
        XCTAssertEqual(output2.entries.count, 2)
    }
}
