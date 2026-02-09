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

    // MARK: - タスク調整マーカー検出テスト

    /// 半角@@タスク調整マーカーを検出できる
    func testDetectsHalfWidthTaskAdjustMarker() {
        let content = "@@タスク調整: タスクXXXの説明を更新"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskAdjustMarker(content),
            "Should detect half-width @@ task adjust marker"
        )
    }

    /// 全角＠＠タスク調整マーカーを検出できる
    func testDetectsFullWidthTaskAdjustMarker() {
        let content = "＠＠タスク調整: タスクXXXを削除"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskAdjustMarker(content),
            "Should detect full-width ＠＠ task adjust marker"
        )
    }

    /// 混合マーカーを検出できる（調整）
    func testDetectsMixedWidthTaskAdjustMarker() {
        let content = "@＠タスク調整: 優先度を変更"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskAdjustMarker(content),
            "Should detect mixed width task adjust marker"
        )
    }

    /// タスク作成マーカーをタスク調整として誤検出しない
    func testDoesNotConfuseCreateWithAdjust() {
        let content = "@@タスク作成: ログイン機能を実装"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskAdjustMarker(content),
            "Should not confuse task create marker with adjust marker"
        )
    }

    /// タスク通知マーカーをタスク調整として誤検出しない
    func testDoesNotConfuseNotifyWithAdjust() {
        let content = "@@タスク通知: レビュー完了"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskAdjustMarker(content),
            "Should not confuse task notify marker with adjust marker"
        )
    }

    // MARK: - 調整内容抽出テスト

    /// タスク調整マーカーから内容を抽出できる
    func testExtractsAdjustContent() {
        let content = "@@タスク調整: タスクXXXの説明を「認証機能の改善」に変更"
        let extracted = ChatCommandMarker.extractAdjustContent(from: content)
        XCTAssertEqual(extracted, "タスクXXXの説明を「認証機能の改善」に変更")
    }

    /// 調整マーカーがない場合はnilを返す
    func testReturnsNilForMessageWithoutAdjustMarker() {
        let content = "タスクの説明を変更してください"
        let extracted = ChatCommandMarker.extractAdjustContent(from: content)
        XCTAssertNil(extracted)
    }

    // MARK: - タスク開始マーカー検出テスト

    /// 半角@@タスク開始マーカーを検出できる
    func testDetectsHalfWidthTaskStartMarker() {
        let content = "@@タスク開始: task_001"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskStartMarker(content),
            "Should detect half-width @@ task start marker"
        )
    }

    /// 全角＠＠タスク開始マーカーを検出できる
    func testDetectsFullWidthTaskStartMarker() {
        let content = "＠＠タスク開始: task_001"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskStartMarker(content),
            "Should detect full-width ＠＠ task start marker"
        )
    }

    /// 混合マーカーを検出できる（開始）
    func testDetectsMixedWidthTaskStartMarker() {
        let content = "@＠タスク開始: task_001"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskStartMarker(content),
            "Should detect mixed width task start marker"
        )
    }

    /// タスク作成マーカーをタスク開始として誤検出しない
    func testDoesNotConfuseCreateWithStart() {
        let content = "@@タスク作成: ログイン機能を実装"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskStartMarker(content),
            "Should not confuse task create marker with start marker"
        )
    }

    /// タスク通知マーカーをタスク開始として誤検出しない
    func testDoesNotConfuseNotifyWithStart() {
        let content = "@@タスク通知: レビュー完了"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskStartMarker(content),
            "Should not confuse task notify marker with start marker"
        )
    }

    /// タスク調整マーカーをタスク開始として誤検出しない
    func testDoesNotConfuseAdjustWithStart() {
        let content = "@@タスク調整: 優先度を変更"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskStartMarker(content),
            "Should not confuse task adjust marker with start marker"
        )
    }

    // MARK: - 開始内容抽出テスト

    /// タスク開始マーカーからタスクIDを抽出できる
    func testExtractsStartContent() {
        let content = "@@タスク開始: task_001"
        let extracted = ChatCommandMarker.extractStartContent(from: content)
        XCTAssertEqual(extracted, "task_001")
    }

    /// 開始マーカーがない場合はnilを返す
    func testReturnsNilForMessageWithoutStartMarker() {
        let content = "タスクを開始してください"
        let extracted = ChatCommandMarker.extractStartContent(from: content)
        XCTAssertNil(extracted)
    }
}
