// Tests/InfrastructureTests/Logging/LogEntryTests.swift

import XCTest
@testable import Infrastructure

final class LogEntryTests: XCTestCase {

    // MARK: - Creation Tests

    func testLogEntryCreation() {
        let timestamp = Date()
        let entry = LogEntry(
            timestamp: timestamp,
            level: .info,
            category: .agent,
            message: "Test message"
        )

        XCTAssertEqual(entry.timestamp, timestamp)
        XCTAssertEqual(entry.level, .info)
        XCTAssertEqual(entry.category, .agent)
        XCTAssertEqual(entry.message, "Test message")
        XCTAssertNil(entry.operation)
        XCTAssertNil(entry.agentId)
        XCTAssertNil(entry.projectId)
        XCTAssertNil(entry.details)
    }

    func testLogEntryCreationWithAllFields() {
        let timestamp = Date()
        let entry = LogEntry(
            timestamp: timestamp,
            level: .error,
            category: .task,
            message: "Error occurred",
            operation: "completeTask",
            agentId: "agt_123",
            projectId: "prj_456",
            details: ["key": "value"]
        )

        XCTAssertEqual(entry.timestamp, timestamp)
        XCTAssertEqual(entry.level, .error)
        XCTAssertEqual(entry.category, .task)
        XCTAssertEqual(entry.message, "Error occurred")
        XCTAssertEqual(entry.operation, "completeTask")
        XCTAssertEqual(entry.agentId, "agt_123")
        XCTAssertEqual(entry.projectId, "prj_456")
        XCTAssertEqual(entry.details?["key"] as? String, "value")
    }

    // MARK: - JSON Format Tests

    func testLogEntryToJSON() {
        let entry = LogEntry(
            timestamp: Date(timeIntervalSince1970: 0),
            level: .error,
            category: .task,
            message: "Error occurred",
            operation: "completeTask",
            agentId: "agt_123",
            projectId: "prj_456"
        )

        let json = entry.toJSON()

        XCTAssertTrue(json.contains("\"level\":\"ERROR\""))
        XCTAssertTrue(json.contains("\"category\":\"task\""))
        XCTAssertTrue(json.contains("\"message\":\"Error occurred\""))
        XCTAssertTrue(json.contains("\"operation\":\"completeTask\""))
        XCTAssertTrue(json.contains("\"agent_id\":\"agt_123\""))
        XCTAssertTrue(json.contains("\"project_id\":\"prj_456\""))
        XCTAssertTrue(json.contains("\"timestamp\":"))
    }

    func testLogEntryToJSONWithDetails() {
        let entry = LogEntry(
            timestamp: Date(timeIntervalSince1970: 0),
            level: .info,
            category: .system,
            message: "Test",
            details: ["count": 42, "name": "test"]
        )

        let json = entry.toJSON()

        XCTAssertTrue(json.contains("\"details\":"))
        XCTAssertTrue(json.contains("\"count\":42"))
        XCTAssertTrue(json.contains("\"name\":\"test\""))
    }

    func testLogEntryToJSONMinimal() {
        let entry = LogEntry(
            timestamp: Date(timeIntervalSince1970: 0),
            level: .info,
            category: .system,
            message: "Simple message"
        )

        let json = entry.toJSON()

        // 必須フィールドのみ含まれる
        XCTAssertTrue(json.contains("\"level\":\"INFO\""))
        XCTAssertTrue(json.contains("\"category\":\"system\""))
        XCTAssertTrue(json.contains("\"message\":\"Simple message\""))

        // オプションフィールドはnullまたは含まれない
        // (実装によってはnull: trueでnullを出力する場合もある)
    }

    // MARK: - Text Format Tests

    func testLogEntryToText() {
        let entry = LogEntry(
            timestamp: Date(timeIntervalSince1970: 0),
            level: .info,
            category: .agent,
            message: "Action determined"
        )

        let text = entry.toText()

        XCTAssertTrue(text.contains("[INFO]"))
        XCTAssertTrue(text.contains("[agent]"))
        XCTAssertTrue(text.contains("Action determined"))
    }

    func testLogEntryToTextWithOperation() {
        let entry = LogEntry(
            timestamp: Date(timeIntervalSince1970: 0),
            level: .debug,
            category: .task,
            message: "Task updated",
            operation: "updateStatus"
        )

        let text = entry.toText()

        XCTAssertTrue(text.contains("[DEBUG]"))
        XCTAssertTrue(text.contains("[task]"))
        XCTAssertTrue(text.contains("updateStatus"))
        XCTAssertTrue(text.contains("Task updated"))
    }

    func testLogEntryToTextWithAgentAndProject() {
        let entry = LogEntry(
            timestamp: Date(timeIntervalSince1970: 0),
            level: .warn,
            category: .chat,
            message: "Rate limit approaching",
            agentId: "agt_001",
            projectId: "prj_002"
        )

        let text = entry.toText()

        XCTAssertTrue(text.contains("[WARN]"))
        XCTAssertTrue(text.contains("[chat]"))
        XCTAssertTrue(text.contains("agt_001"))
        XCTAssertTrue(text.contains("prj_002"))
    }

    // MARK: - Codable Tests

    func testLogEntryCodable() throws {
        let original = LogEntry(
            timestamp: Date(timeIntervalSince1970: 1000),
            level: .error,
            category: .auth,
            message: "Authentication failed",
            operation: "login",
            agentId: "agt_test"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(LogEntry.self, from: data)

        XCTAssertEqual(decoded.level, original.level)
        XCTAssertEqual(decoded.category, original.category)
        XCTAssertEqual(decoded.message, original.message)
        XCTAssertEqual(decoded.operation, original.operation)
        XCTAssertEqual(decoded.agentId, original.agentId)
    }
}
