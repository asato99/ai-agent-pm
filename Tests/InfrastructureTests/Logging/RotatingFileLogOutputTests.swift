// Tests/InfrastructureTests/Logging/RotatingFileLogOutputTests.swift

import XCTest
@testable import Infrastructure

final class RotatingFileLogOutputTests: XCTestCase {

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "rotating_log_test_\(UUID().uuidString)/"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func fileExists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: tempDir + fileName)
    }

    private func readFile(_ fileName: String) -> String? {
        try? String(contentsOfFile: tempDir + fileName, encoding: .utf8)
    }

    // MARK: - Basic Tests

    func testRotatingFileLogOutputCreatesDateFile() {
        let output = RotatingFileLogOutput(directory: tempDir, prefix: "mcp-server")
        let entry = LogEntry(timestamp: Date(), level: .info, category: .system, message: "Test message")

        output.write(entry)

        let expectedFileName = "mcp-server-\(formatDate(Date())).log"
        XCTAssertTrue(fileExists(expectedFileName), "日付付きログファイルが作成されるべき")
    }

    func testRotatingFileLogOutputAppendsToExistingFile() {
        let output = RotatingFileLogOutput(directory: tempDir, prefix: "mcp-server")

        output.write(LogEntry(timestamp: Date(), level: .info, category: .system, message: "First"))
        output.write(LogEntry(timestamp: Date(), level: .info, category: .system, message: "Second"))

        let fileName = "mcp-server-\(formatDate(Date())).log"
        let content = readFile(fileName)

        XCTAssertNotNil(content)
        XCTAssertTrue(content!.contains("First"))
        XCTAssertTrue(content!.contains("Second"))
    }

    func testRotatingFileLogOutputCreatesDirectory() {
        let nestedDir = tempDir + "nested/logs/"
        let output = RotatingFileLogOutput(directory: nestedDir, prefix: "mcp-server")

        let entry = LogEntry(timestamp: Date(), level: .info, category: .system, message: "Test")
        output.write(entry)

        let expectedPath = nestedDir + "mcp-server-\(formatDate(Date())).log"
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath))
    }

    // MARK: - Format Tests

    func testRotatingFileLogOutputTextFormat() {
        let output = RotatingFileLogOutput(directory: tempDir, prefix: "app", format: .text)

        let entry = LogEntry(timestamp: Date(), level: .warn, category: .agent, message: "Warning message")
        output.write(entry)

        let fileName = "app-\(formatDate(Date())).log"
        let content = readFile(fileName)

        XCTAssertNotNil(content)
        XCTAssertTrue(content!.contains("[WARN]"))
        XCTAssertTrue(content!.contains("[agent]"))
        XCTAssertTrue(content!.contains("Warning message"))
    }

    func testRotatingFileLogOutputJSONFormat() {
        let output = RotatingFileLogOutput(directory: tempDir, prefix: "app", format: .json)

        let entry = LogEntry(timestamp: Date(), level: .error, category: .task, message: "Error message")
        output.write(entry)

        let fileName = "app-\(formatDate(Date())).log"
        let content = readFile(fileName)

        XCTAssertNotNil(content)
        XCTAssertTrue(content!.contains("\"level\":\"ERROR\""))
        XCTAssertTrue(content!.contains("\"category\":\"task\""))
    }

    // MARK: - Multiple Writers

    func testRotatingFileLogOutputFromMultipleInstances() {
        let output1 = RotatingFileLogOutput(directory: tempDir, prefix: "mcp-server")
        let output2 = RotatingFileLogOutput(directory: tempDir, prefix: "mcp-server")

        output1.write(LogEntry(timestamp: Date(), level: .info, category: .system, message: "From output1"))
        output2.write(LogEntry(timestamp: Date(), level: .info, category: .system, message: "From output2"))

        let fileName = "mcp-server-\(formatDate(Date())).log"
        let content = readFile(fileName)

        XCTAssertNotNil(content)
        XCTAssertTrue(content!.contains("From output1"))
        XCTAssertTrue(content!.contains("From output2"))
    }

    // MARK: - MinimumLevel Tests

    func testRotatingFileLogOutputHasNoMinimumLevel() {
        let output = RotatingFileLogOutput(directory: tempDir, prefix: "test")

        // minimumLevelはnil（全レベル記録）
        XCTAssertNil(output.minimumLevel)

        // 全レベルがshouldWriteをパス
        for level in LogLevel.allCases {
            let entry = LogEntry(timestamp: Date(), level: level, category: .system, message: "Test")
            XCTAssertTrue(output.shouldWrite(entry), "All levels should be writable")
        }
    }

    // MARK: - Custom Prefix Tests

    func testRotatingFileLogOutputCustomPrefix() {
        let output = RotatingFileLogOutput(directory: tempDir, prefix: "custom-app")

        let entry = LogEntry(timestamp: Date(), level: .info, category: .system, message: "Test")
        output.write(entry)

        let expectedFileName = "custom-app-\(formatDate(Date())).log"
        XCTAssertTrue(fileExists(expectedFileName))
    }

    // MARK: - Date Change Simulation (Integration)

    func testRotatingFileLogOutputUsesEntryTimestamp() {
        let output = RotatingFileLogOutput(directory: tempDir, prefix: "mcp-server")

        // 過去の日付のエントリを作成
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let entryYesterday = LogEntry(timestamp: yesterday, level: .info, category: .system, message: "Yesterday log")

        let today = Date()
        let entryToday = LogEntry(timestamp: today, level: .info, category: .system, message: "Today log")

        output.write(entryYesterday)
        output.write(entryToday)

        let yesterdayFileName = "mcp-server-\(formatDate(yesterday)).log"
        let todayFileName = "mcp-server-\(formatDate(today)).log"

        XCTAssertTrue(fileExists(yesterdayFileName), "昨日の日付のファイルが作成されるべき")
        XCTAssertTrue(fileExists(todayFileName), "今日の日付のファイルが作成されるべき")

        let yesterdayContent = readFile(yesterdayFileName)
        let todayContent = readFile(todayFileName)

        XCTAssertTrue(yesterdayContent?.contains("Yesterday log") ?? false)
        XCTAssertTrue(todayContent?.contains("Today log") ?? false)
    }
}
