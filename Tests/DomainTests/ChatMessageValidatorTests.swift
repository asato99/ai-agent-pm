// Tests/DomainTests/ChatMessageValidatorTests.swift
// Phase 0: チャットメッセージバリデーションのユニットテスト

import XCTest
@testable import Domain

final class ChatMessageValidatorTests: XCTestCase {

    // MARK: - コンテンツ長バリデーション

    func testValidate_EmptyContent_ReturnsError() {
        // Given: 空のコンテンツ
        let result = ChatMessageValidator.validate(content: "")

        // Then: エラー
        XCTAssertEqual(result, .invalid(.emptyContent))
    }

    func testValidate_WhitespaceOnly_ReturnsError() {
        // Given: 空白のみ
        let result = ChatMessageValidator.validate(content: "   \n\t  ")

        // Then: エラー
        XCTAssertEqual(result, .invalid(.emptyContent))
    }

    func testValidate_ValidContent_ReturnsValid() {
        // Given: 有効なコンテンツ
        let result = ChatMessageValidator.validate(content: "Hello, World!")

        // Then: 有効
        XCTAssertEqual(result, .valid)
    }

    func testValidate_ContentAtLimit_ReturnsValid() {
        // Given: ちょうど4,000文字
        let content = String(repeating: "あ", count: 4000)

        // When: バリデーション
        let result = ChatMessageValidator.validate(content: content)

        // Then: 有効
        XCTAssertEqual(result, .valid)
    }

    func testValidate_ContentOverLimit_ReturnsError() {
        // Given: 4,001文字
        let content = String(repeating: "あ", count: 4001)

        // When: バリデーション
        let result = ChatMessageValidator.validate(content: content)

        // Then: エラー
        XCTAssertEqual(result, .invalid(.contentTooLong(maxLength: 4000, actualLength: 4001)))
    }

    func testValidate_ContentWithLeadingWhitespace_TrimsAndValidates() {
        // Given: 先頭に空白があるコンテンツ
        let result = ChatMessageValidator.validate(content: "   Hello")

        // Then: 有効（トリム後に内容があるため）
        XCTAssertEqual(result, .valid)
    }

    // MARK: - limit パラメータバリデーション

    func testValidateLimit_WithinRange_ReturnsValid() {
        XCTAssertEqual(ChatMessageValidator.validateLimit(50), .valid(50))
        XCTAssertEqual(ChatMessageValidator.validateLimit(200), .valid(200))
        XCTAssertEqual(ChatMessageValidator.validateLimit(1), .valid(1))
    }

    func testValidateLimit_ExceedsMax_ReturnsClamped() {
        // Given: 300（最大200を超える）
        let result = ChatMessageValidator.validateLimit(300)

        // Then: 200に制限される
        XCTAssertEqual(result, .clamped(200))
    }

    func testValidateLimit_Zero_ReturnsDefault() {
        // Given: 0
        let result = ChatMessageValidator.validateLimit(0)

        // Then: デフォルト50
        XCTAssertEqual(result, .useDefault(50))
    }

    func testValidateLimit_Negative_ReturnsDefault() {
        // Given: 負の値
        let result = ChatMessageValidator.validateLimit(-10)

        // Then: デフォルト50
        XCTAssertEqual(result, .useDefault(50))
    }

    func testValidateLimit_Nil_ReturnsDefault() {
        // Given: nil
        let result = ChatMessageValidator.validateLimit(nil)

        // Then: デフォルト50
        XCTAssertEqual(result, .useDefault(50))
    }

    // MARK: - 定数の確認

    func testConstants() {
        XCTAssertEqual(ChatMessageValidator.maxContentLength, 4000)
        XCTAssertEqual(ChatMessageValidator.defaultLimit, 50)
        XCTAssertEqual(ChatMessageValidator.maxLimit, 200)
    }
}
