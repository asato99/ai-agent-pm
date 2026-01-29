// Tests/InfrastructureTests/Logging/LogUtilsTests.swift

import XCTest
@testable import Infrastructure

final class LogUtilsTests: XCTestCase {

    // MARK: - String Truncation Tests

    func testTruncateShortString() {
        let result = LogUtils.truncate("short", maxLength: 100)
        XCTAssertEqual(result, "short")
        XCTAssertFalse(result.contains("truncated"))
    }

    func testTruncateLongString() {
        let longString = String(repeating: "a", count: 3000)
        let result = LogUtils.truncate(longString, maxLength: 2000)
        XCTAssertLessThanOrEqual(result.count, 2100)  // maxLength + marker
        XCTAssertTrue(result.contains("...[truncated]"))
    }

    func testTruncateExactLength() {
        let exactString = String(repeating: "b", count: 100)
        let result = LogUtils.truncate(exactString, maxLength: 100)
        XCTAssertEqual(result, exactString)
        XCTAssertFalse(result.contains("truncated"))
    }

    func testTruncateEmptyString() {
        let result = LogUtils.truncate("", maxLength: 100)
        XCTAssertEqual(result, "")
    }

    // MARK: - Dictionary Truncation Tests

    func testTruncateDictionaryShort() {
        let dict: [String: Any] = ["key": "value"]
        let result = LogUtils.truncate(dict, maxLength: 1000)
        XCTAssertTrue(result.contains("key"))
        XCTAssertTrue(result.contains("value"))
        XCTAssertFalse(result.contains("truncated"))
    }

    func testTruncateDictionaryLong() {
        let dict: [String: Any] = ["key": String(repeating: "x", count: 3000)]
        let result = LogUtils.truncate(dict, maxLength: 2000)
        XCTAssertTrue(result.contains("...[truncated]"))
    }

    func testTruncateDictionaryWithNestedObjects() {
        let dict: [String: Any] = [
            "outer": [
                "inner": String(repeating: "y", count: 2000)
            ]
        ]
        let result = LogUtils.truncate(dict, maxLength: 1000)
        XCTAssertTrue(result.contains("...[truncated]"))
    }

    // MARK: - Any Value Truncation Tests

    func testTruncateAnyInteger() {
        let result = LogUtils.truncateAny(12345, maxLength: 100)
        XCTAssertEqual(result as? Int, 12345)
    }

    func testTruncateAnyString() {
        let longString = String(repeating: "z", count: 200)
        let result = LogUtils.truncateAny(longString, maxLength: 100) as? String
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("...[truncated]"))
    }

    func testTruncateAnyArray() {
        let array: [Any] = ["short", String(repeating: "w", count: 200)]
        let result = LogUtils.truncateAny(array, maxLength: 100)
        XCTAssertNotNil(result as? [Any])
    }
}
