// Tests/InfrastructureTests/Logging/LogParserTests.swift

import XCTest
@testable import Infrastructure

final class LogParserTests: XCTestCase {

    // MARK: - JSON Log Parsing Tests

    func testParseJsonLogEntry() {
        let json = """
        {"timestamp":"2026-01-28T09:21:35.123Z","level":"INFO","category":"agent","message":"Test"}
        """

        let entry = LogParser.parse(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.level, .info)
        XCTAssertEqual(entry?.category, .agent)
        XCTAssertEqual(entry?.message, "Test")
    }

    func testParseJsonLogEntryWithAllFields() {
        let json = """
        {"timestamp":"2026-01-28T09:21:35.123Z","level":"ERROR","category":"task","message":"Task failed","operation":"completeTask","agent_id":"agt_123","project_id":"prj_456"}
        """

        let entry = LogParser.parse(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.level, .error)
        XCTAssertEqual(entry?.category, .task)
        XCTAssertEqual(entry?.message, "Task failed")
        XCTAssertEqual(entry?.operation, "completeTask")
        XCTAssertEqual(entry?.agentId, "agt_123")
        XCTAssertEqual(entry?.projectId, "prj_456")
    }

    func testParseJsonLogEntryWithLowercaseLevel() {
        let json = """
        {"timestamp":"2026-01-28T09:21:35Z","level":"debug","category":"system","message":"Debug message"}
        """

        let entry = LogParser.parse(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.level, .debug)
    }

    // MARK: - Text Log Parsing Tests

    func testParseTextLogEntry() {
        let line = "[2026-01-28T09:21:35Z] [INFO] [agent] Test message"

        let entry = LogParser.parse(line)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.level, .info)
        XCTAssertEqual(entry?.category, .agent)
        XCTAssertEqual(entry?.message, "Test message")
    }

    func testParseLegacyLogLine() {
        let line = "[2026-01-28T09:21:35Z] [MCP] Test message"

        let entry = LogParser.parse(line)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.message, "[MCP] Test message")
    }

    func testParseTextLogEntryWithWarning() {
        let line = "[2026-01-28T09:21:35Z] [WARN] [health] Health check warning"

        let entry = LogParser.parse(line)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.level, .warn)
        XCTAssertEqual(entry?.category, .health)
    }

    // MARK: - Edge Cases

    func testParseEmptyString() {
        let entry = LogParser.parse("")

        XCTAssertNil(entry)
    }

    func testParseInvalidJson() {
        let invalidJson = "{ invalid json"

        let entry = LogParser.parse(invalidJson)

        // 無効なJSONはレガシー形式としてパース
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.message, "{ invalid json")
    }

    func testParseJsonWithDetails() {
        let json = """
        {"timestamp":"2026-01-28T09:21:35Z","level":"DEBUG","category":"mcp","message":"Tool call","details":{"tool":"health_check","duration_ms":5}}
        """

        let entry = LogParser.parse(json)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.category, .mcp)
        XCTAssertNotNil(entry?.details)
    }

    // MARK: - Batch Parsing Tests

    func testParseMultipleLines() {
        let lines = [
            """
            {"timestamp":"2026-01-28T09:21:35Z","level":"INFO","category":"system","message":"First"}
            """,
            """
            {"timestamp":"2026-01-28T09:21:36Z","level":"DEBUG","category":"agent","message":"Second"}
            """,
            "[2026-01-28T09:21:37Z] [ERROR] [task] Third"
        ]

        let entries = LogParser.parseAll(lines)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].message, "First")
        XCTAssertEqual(entries[1].message, "Second")
        XCTAssertEqual(entries[2].message, "Third")
    }
}
