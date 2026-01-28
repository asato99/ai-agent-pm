// Tests/InfrastructureTests/Logging/LogOutputTests.swift

import XCTest
@testable import Infrastructure

final class LogOutputTests: XCTestCase {

    // MARK: - StderrLogOutput Tests

    func testStderrLogOutput() {
        // stderrへの出力が例外なく完了することを確認
        let output = StderrLogOutput()
        let entry = LogEntry(timestamp: Date(), level: .info, category: .system, message: "Test")

        XCTAssertNoThrow(output.write(entry))
    }

    func testStderrLogOutputWithAllLevels() {
        let output = StderrLogOutput()

        for level in LogLevel.allCases {
            let entry = LogEntry(timestamp: Date(), level: level, category: .system, message: "Test \(level)")
            XCTAssertNoThrow(output.write(entry))
        }
    }

    // MARK: - FileLogOutput Tests

    func testFileLogOutput() throws {
        let tempPath = NSTemporaryDirectory() + "test_log_\(UUID().uuidString).log"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let output = FileLogOutput(filePath: tempPath)
        let entry = LogEntry(timestamp: Date(), level: .info, category: .system, message: "Test message")

        output.write(entry)

        let content = try String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertTrue(content.contains("Test message"))
    }

    func testFileLogOutputAppendsToExisting() throws {
        let tempPath = NSTemporaryDirectory() + "test_log_\(UUID().uuidString).log"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let output = FileLogOutput(filePath: tempPath)

        output.write(LogEntry(timestamp: Date(), level: .info, category: .system, message: "First"))
        output.write(LogEntry(timestamp: Date(), level: .info, category: .system, message: "Second"))

        let content = try String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertTrue(content.contains("First"))
        XCTAssertTrue(content.contains("Second"))
    }

    func testFileLogOutputCreatesDirectory() throws {
        let tempDir = NSTemporaryDirectory() + "test_logs_\(UUID().uuidString)/"
        let tempPath = tempDir + "nested.log"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let output = FileLogOutput(filePath: tempPath)
        let entry = LogEntry(timestamp: Date(), level: .info, category: .system, message: "Nested")

        output.write(entry)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))
        let content = try String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertTrue(content.contains("Nested"))
    }

    // MARK: - FileLogOutput JSON Format Tests

    func testFileLogOutputJSONFormat() throws {
        let tempPath = NSTemporaryDirectory() + "test_log_\(UUID().uuidString).log"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let output = FileLogOutput(filePath: tempPath, format: .json)
        let entry = LogEntry(
            timestamp: Date(),
            level: .error,
            category: .agent,
            message: "JSON test"
        )

        output.write(entry)

        let content = try String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertTrue(content.contains("\"level\":\"ERROR\""))
        XCTAssertTrue(content.contains("\"category\":\"agent\""))
        XCTAssertTrue(content.contains("\"message\":\"JSON test\""))
    }

    func testFileLogOutputTextFormat() throws {
        let tempPath = NSTemporaryDirectory() + "test_log_\(UUID().uuidString).log"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let output = FileLogOutput(filePath: tempPath, format: .text)
        let entry = LogEntry(
            timestamp: Date(),
            level: .warn,
            category: .task,
            message: "Text test"
        )

        output.write(entry)

        let content = try String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertTrue(content.contains("[WARN]"))
        XCTAssertTrue(content.contains("[task]"))
        XCTAssertTrue(content.contains("Text test"))
    }

    // MARK: - CompositeLogOutput Tests

    func testCompositeLogOutput() throws {
        let tempPath1 = NSTemporaryDirectory() + "test_log_1_\(UUID().uuidString).log"
        let tempPath2 = NSTemporaryDirectory() + "test_log_2_\(UUID().uuidString).log"
        defer {
            try? FileManager.default.removeItem(atPath: tempPath1)
            try? FileManager.default.removeItem(atPath: tempPath2)
        }

        let output1 = FileLogOutput(filePath: tempPath1)
        let output2 = FileLogOutput(filePath: tempPath2)
        let composite = CompositeLogOutput(outputs: [output1, output2])

        let entry = LogEntry(timestamp: Date(), level: .info, category: .system, message: "Composite test")
        composite.write(entry)

        let content1 = try String(contentsOfFile: tempPath1, encoding: .utf8)
        let content2 = try String(contentsOfFile: tempPath2, encoding: .utf8)

        XCTAssertTrue(content1.contains("Composite test"))
        XCTAssertTrue(content2.contains("Composite test"))
    }
}
