// Tests/DomainTests/ChatCommandMarkerTests.swift
// チャットコマンドマーカーのパース・バリデーションテスト
// 参照: docs/design/CHAT_COMMAND_MARKER.md

import XCTest
@testable import Domain

/// チャットコマンドマーカーのテスト
final class ChatCommandMarkerTests: XCTestCase {

    // MARK: - タスク作成マーカー検出テスト

    /// 半角@@タスク作成マーカーを検出できる
    func testDetectsHalfWidthTaskCreateMarker() {
        let content = "@@タスク作成: ログイン機能を実装"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should detect half-width @@ task create marker"
        )
    }

    /// 全角＠＠タスク作成マーカーを検出できる
    func testDetectsFullWidthTaskCreateMarker() {
        let content = "＠＠タスク作成: ログイン機能を実装"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should detect full-width ＠＠ task create marker"
        )
    }

    /// 混合@＠タスク作成マーカーを検出できる
    func testDetectsMixedWidthTaskCreateMarker1() {
        let content = "@＠タスク作成: ログイン機能を実装"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should detect mixed @＠ task create marker"
        )
    }

    /// 混合＠@タスク作成マーカーを検出できる
    func testDetectsMixedWidthTaskCreateMarker2() {
        let content = "＠@タスク作成: ログイン機能を実装"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should detect mixed ＠@ task create marker"
        )
    }

    /// マーカーなしの通常メッセージはfalseを返す
    func testRejectsMessageWithoutMarker() {
        let content = "ログイン機能を実装してください"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should reject message without marker"
        )
    }

    /// @が1つだけの場合はfalseを返す
    func testRejectsSingleAtSign() {
        let content = "@タスク作成: ログイン機能を実装"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should reject single @ sign"
        )
    }

    /// コロンがない場合はfalseを返す
    func testRejectsMarkerWithoutColon() {
        let content = "@@タスク作成 ログイン機能を実装"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should reject marker without colon"
        )
    }

    /// メッセージ途中のマーカーも検出できる
    func testDetectsMarkerInMiddleOfMessage() {
        let content = "お願いします @@タスク作成: ログイン機能を実装 よろしく"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should detect marker in middle of message"
        )
    }

    // MARK: - タスク通知マーカー検出テスト

    /// 半角@@タスク通知マーカーを検出できる
    func testDetectsHalfWidthTaskNotifyMarker() {
        let content = "@@タスク通知: レビュー完了しました"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskNotifyMarker(content),
            "Should detect half-width @@ task notify marker"
        )
    }

    /// 全角＠＠タスク通知マーカーを検出できる
    func testDetectsFullWidthTaskNotifyMarker() {
        let content = "＠＠タスク通知: レビュー完了しました"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskNotifyMarker(content),
            "Should detect full-width ＠＠ task notify marker"
        )
    }

    /// 混合マーカーを検出できる（通知）
    func testDetectsMixedWidthTaskNotifyMarker() {
        let content = "@＠タスク通知: 仕様変更があります"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskNotifyMarker(content),
            "Should detect mixed width task notify marker"
        )
    }

    /// タスク作成マーカーをタスク通知として誤検出しない
    func testDoesNotConfuseCreateWithNotify() {
        let content = "@@タスク作成: ログイン機能を実装"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskNotifyMarker(content),
            "Should not confuse task create marker with notify marker"
        )
    }

    /// タスク通知マーカーをタスク作成として誤検出しない
    func testDoesNotConfuseNotifyWithCreate() {
        let content = "@@タスク通知: レビュー完了しました"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should not confuse task notify marker with create marker"
        )
    }

    // MARK: - タイトル抽出テスト

    /// タスク作成マーカーからタイトルを抽出できる
    func testExtractsTaskTitleFromCreateMarker() {
        let content = "@@タスク作成: ログイン機能を実装"
        let title = ChatCommandMarker.extractTaskTitle(from: content)
        XCTAssertEqual(title, "ログイン機能を実装")
    }

    /// 全角マーカーからもタイトルを抽出できる
    func testExtractsTaskTitleFromFullWidthMarker() {
        let content = "＠＠タスク作成: 決済機能のバグ修正"
        let title = ChatCommandMarker.extractTaskTitle(from: content)
        XCTAssertEqual(title, "決済機能のバグ修正")
    }

    /// マーカーなしの場合はnilを返す
    func testReturnsNilForMessageWithoutMarker() {
        let content = "ログイン機能を実装してください"
        let title = ChatCommandMarker.extractTaskTitle(from: content)
        XCTAssertNil(title)
    }

    /// 前後の空白をトリムする
    func testTrimsWhitespaceFromTitle() {
        let content = "@@タスク作成:   ログイン機能を実装   "
        let title = ChatCommandMarker.extractTaskTitle(from: content)
        XCTAssertEqual(title, "ログイン機能を実装")
    }

    /// メッセージ途中のマーカーからもタイトルを抽出できる
    func testExtractsTitleFromMiddleOfMessage() {
        let content = "お願いします @@タスク作成: ログイン機能を実装 よろしく"
        let title = ChatCommandMarker.extractTaskTitle(from: content)
        // マーカー以降を抽出（後続テキストも含まれる可能性あり）
        XCTAssertTrue(title?.hasPrefix("ログイン機能を実装") ?? false)
    }

    // MARK: - 通知メッセージ抽出テスト

    /// タスク通知マーカーからメッセージを抽出できる
    func testExtractsNotifyMessage() {
        let content = "@@タスク通知: レビュー完了しました"
        let message = ChatCommandMarker.extractNotifyMessage(from: content)
        XCTAssertEqual(message, "レビュー完了しました")
    }

    /// 通知マーカーがない場合はnilを返す
    func testReturnsNilForMessageWithoutNotifyMarker() {
        let content = "レビュー完了しました"
        let message = ChatCommandMarker.extractNotifyMessage(from: content)
        XCTAssertNil(message)
    }
}
