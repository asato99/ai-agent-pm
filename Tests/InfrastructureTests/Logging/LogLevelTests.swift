// Tests/InfrastructureTests/Logging/LogLevelTests.swift

import XCTest
@testable import Infrastructure

final class LogLevelTests: XCTestCase {

    // MARK: - Ordering Tests

    func testLogLevelOrdering() {
        XCTAssertTrue(LogLevel.trace < LogLevel.debug)
        XCTAssertTrue(LogLevel.debug < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.warn)
        XCTAssertTrue(LogLevel.warn < LogLevel.error)
    }

    func testLogLevelEquality() {
        XCTAssertEqual(LogLevel.info, LogLevel.info)
        XCTAssertNotEqual(LogLevel.info, LogLevel.debug)
    }

    // MARK: - String Conversion Tests

    func testLogLevelFromStringLowercase() {
        XCTAssertEqual(LogLevel(rawString: "trace"), .trace)
        XCTAssertEqual(LogLevel(rawString: "debug"), .debug)
        XCTAssertEqual(LogLevel(rawString: "info"), .info)
        XCTAssertEqual(LogLevel(rawString: "warn"), .warn)
        XCTAssertEqual(LogLevel(rawString: "error"), .error)
    }

    func testLogLevelFromStringUppercase() {
        XCTAssertEqual(LogLevel(rawString: "TRACE"), .trace)
        XCTAssertEqual(LogLevel(rawString: "DEBUG"), .debug)
        XCTAssertEqual(LogLevel(rawString: "INFO"), .info)
        XCTAssertEqual(LogLevel(rawString: "WARN"), .warn)
        XCTAssertEqual(LogLevel(rawString: "ERROR"), .error)
    }

    func testLogLevelFromInvalidString() {
        XCTAssertNil(LogLevel(rawString: "invalid"))
        XCTAssertNil(LogLevel(rawString: ""))
        XCTAssertNil(LogLevel(rawString: "warning"))  // "warn" is correct
    }

    // MARK: - Display String Tests

    func testLogLevelDisplayString() {
        XCTAssertEqual(LogLevel.trace.displayString, "TRACE")
        XCTAssertEqual(LogLevel.debug.displayString, "DEBUG")
        XCTAssertEqual(LogLevel.info.displayString, "INFO")
        XCTAssertEqual(LogLevel.warn.displayString, "WARN")
        XCTAssertEqual(LogLevel.error.displayString, "ERROR")
    }

    // MARK: - Codable Tests

    func testLogLevelEncodeDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for level in [LogLevel.trace, .debug, .info, .warn, .error] {
            let data = try encoder.encode(level)
            let decoded = try decoder.decode(LogLevel.self, from: data)
            XCTAssertEqual(decoded, level)
        }
    }
}
