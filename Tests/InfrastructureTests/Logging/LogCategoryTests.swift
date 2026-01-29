// Tests/InfrastructureTests/Logging/LogCategoryTests.swift

import XCTest
@testable import Infrastructure

final class LogCategoryTests: XCTestCase {

    // MARK: - Raw Value Tests

    func testLogCategoryRawValue() {
        XCTAssertEqual(LogCategory.system.rawValue, "system")
        XCTAssertEqual(LogCategory.health.rawValue, "health")
        XCTAssertEqual(LogCategory.auth.rawValue, "auth")
        XCTAssertEqual(LogCategory.agent.rawValue, "agent")
        XCTAssertEqual(LogCategory.task.rawValue, "task")
        XCTAssertEqual(LogCategory.chat.rawValue, "chat")
        XCTAssertEqual(LogCategory.project.rawValue, "project")
        XCTAssertEqual(LogCategory.mcp.rawValue, "mcp")
        XCTAssertEqual(LogCategory.transport.rawValue, "transport")
    }

    // MARK: - All Cases Tests

    func testAllCategories() {
        // 全カテゴリが定義されていることを確認
        let expected: Set<LogCategory> = [
            .system, .health, .auth, .agent, .task, .chat, .project, .mcp, .transport
        ]
        XCTAssertEqual(Set(LogCategory.allCases), expected)
    }

    func testAllCasesCount() {
        XCTAssertEqual(LogCategory.allCases.count, 9)
    }

    // MARK: - Codable Tests

    func testLogCategoryEncodeDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for category in LogCategory.allCases {
            let data = try encoder.encode(category)
            let decoded = try decoder.decode(LogCategory.self, from: data)
            XCTAssertEqual(decoded, category)
        }
    }

    // MARK: - String Conversion Tests

    func testLogCategoryFromString() {
        XCTAssertEqual(LogCategory(rawValue: "system"), .system)
        XCTAssertEqual(LogCategory(rawValue: "health"), .health)
        XCTAssertEqual(LogCategory(rawValue: "auth"), .auth)
        XCTAssertEqual(LogCategory(rawValue: "agent"), .agent)
        XCTAssertEqual(LogCategory(rawValue: "task"), .task)
        XCTAssertEqual(LogCategory(rawValue: "chat"), .chat)
        XCTAssertEqual(LogCategory(rawValue: "project"), .project)
        XCTAssertEqual(LogCategory(rawValue: "mcp"), .mcp)
        XCTAssertEqual(LogCategory(rawValue: "transport"), .transport)
    }

    func testLogCategoryFromInvalidString() {
        XCTAssertNil(LogCategory(rawValue: "invalid"))
        XCTAssertNil(LogCategory(rawValue: ""))
        XCTAssertNil(LogCategory(rawValue: "SYSTEM"))  // case-sensitive
    }

    // MARK: - Display String Tests

    func testLogCategoryDisplayString() {
        XCTAssertEqual(LogCategory.system.displayString, "SYSTEM")
        XCTAssertEqual(LogCategory.health.displayString, "HEALTH")
        XCTAssertEqual(LogCategory.auth.displayString, "AUTH")
        XCTAssertEqual(LogCategory.agent.displayString, "AGENT")
        XCTAssertEqual(LogCategory.task.displayString, "TASK")
        XCTAssertEqual(LogCategory.chat.displayString, "CHAT")
        XCTAssertEqual(LogCategory.project.displayString, "PROJECT")
        XCTAssertEqual(LogCategory.mcp.displayString, "MCP")
        XCTAssertEqual(LogCategory.transport.displayString, "TRANSPORT")
    }
}
