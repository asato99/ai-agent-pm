// Tests/InfrastructureTests/Logging/LoggerTests.swift

import XCTest
@testable import Infrastructure

// MARK: - Mock LogOutput for Testing

final class MockLogOutput: LogOutput, @unchecked Sendable {
    /// Mockはフィルタなし（全て記録）
    let minimumLevel: LogLevel? = nil

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

    // MARK: - Category Level Tests

    func testLoggerCategorySpecificLevel() {
        let mockOutput = MockLogOutput()
        let logger = MCPLogger()
        logger.addOutput(mockOutput)
        logger.setMinimumLevel(.info)
        logger.setCategoryLevel(.health, level: .warn)  // healthカテゴリはWARN以上のみ

        logger.log(.info, category: .health, message: "Should not appear")
        logger.log(.warn, category: .health, message: "Should appear")
        logger.log(.info, category: .agent, message: "Should appear")

        XCTAssertEqual(mockOutput.entries.count, 2)
        XCTAssertTrue(mockOutput.entries.allSatisfy { $0.message != "Should not appear" })
    }

    func testLoggerCategoryLevelOverridesGlobalLevel() {
        let mockOutput = MockLogOutput()
        let logger = MCPLogger()
        logger.addOutput(mockOutput)
        logger.setMinimumLevel(.warn)
        logger.setCategoryLevel(.mcp, level: .trace)  // mcpカテゴリはTRACE以上

        logger.log(.info, category: .system, message: "Should not appear")
        logger.log(.trace, category: .mcp, message: "Should appear")

        XCTAssertEqual(mockOutput.entries.count, 1)
        XCTAssertEqual(mockOutput.entries[0].category, .mcp)
    }

    func testLoggerClearCategoryLevel() {
        let mockOutput = MockLogOutput()
        let logger = MCPLogger()
        logger.addOutput(mockOutput)
        logger.setMinimumLevel(.info)
        logger.setCategoryLevel(.health, level: .error)

        logger.log(.warn, category: .health, message: "Should not appear")

        logger.clearCategoryLevel(.health)

        logger.log(.warn, category: .health, message: "Should appear")

        XCTAssertEqual(mockOutput.entries.count, 1)
        XCTAssertEqual(mockOutput.entries[0].message, "Should appear")
    }
}

// MARK: - LogConfig Tests

final class LogConfigTests: XCTestCase {

    override func tearDown() {
        unsetenv("MCP_LOG_LEVEL")
        unsetenv("MCP_LOG_FORMAT")
        super.tearDown()
    }

    // MARK: - Log Level Environment Tests

    func testLogConfigReadsLevelFromEnvironment() {
        setenv("MCP_LOG_LEVEL", "DEBUG", 1)

        let config = LogConfig.fromEnvironment()

        XCTAssertEqual(config.level, .debug)
    }

    func testLogConfigReadsTraceLevelFromEnvironment() {
        setenv("MCP_LOG_LEVEL", "TRACE", 1)

        let config = LogConfig.fromEnvironment()

        XCTAssertEqual(config.level, .trace)
    }

    func testLogConfigUsesDefaultLevelWhenNotSet() {
        unsetenv("MCP_LOG_LEVEL")

        let config = LogConfig.fromEnvironment()

        XCTAssertEqual(config.level, .info)  // デフォルトはINFO
    }

    func testLogConfigUsesDefaultLevelForInvalidValue() {
        setenv("MCP_LOG_LEVEL", "INVALID", 1)

        let config = LogConfig.fromEnvironment()

        XCTAssertEqual(config.level, .info)  // 無効な値はデフォルトを使用
    }

    func testLogConfigIsCaseInsensitive() {
        setenv("MCP_LOG_LEVEL", "debug", 1)

        let config = LogConfig.fromEnvironment()

        XCTAssertEqual(config.level, .debug)
    }

    // MARK: - Log Format Environment Tests

    func testLogConfigReadsFormatFromEnvironment() {
        setenv("MCP_LOG_FORMAT", "json", 1)

        let config = LogConfig.fromEnvironment()

        XCTAssertEqual(config.format, .json)
    }

    func testLogConfigReadsTextFormatFromEnvironment() {
        setenv("MCP_LOG_FORMAT", "text", 1)

        let config = LogConfig.fromEnvironment()

        XCTAssertEqual(config.format, .text)
    }

    func testLogConfigUsesDefaultFormatWhenNotSet() {
        unsetenv("MCP_LOG_FORMAT")

        let config = LogConfig.fromEnvironment()

        XCTAssertEqual(config.format, .json)  // デフォルトはJSON
    }

    func testLogConfigUsesDefaultFormatForInvalidValue() {
        setenv("MCP_LOG_FORMAT", "invalid", 1)

        let config = LogConfig.fromEnvironment()

        XCTAssertEqual(config.format, .json)  // 無効な値はデフォルトを使用
    }

    func testLogConfigFormatIsCaseInsensitive() {
        setenv("MCP_LOG_FORMAT", "JSON", 1)

        let config = LogConfig.fromEnvironment()

        XCTAssertEqual(config.format, .json)
    }
}
