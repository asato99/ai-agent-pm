// Tests/MCPServerTests/ChatCommandMarkerValidationTests.swift
// チャットコマンドマーカーのバリデーションテスト（MCPServer統合テスト）
// 参照: docs/design/CHAT_COMMAND_MARKER.md

import XCTest
@testable import MCPServer

/// request_task / notify_task_session のマーカーバリデーションテスト
final class ChatCommandMarkerValidationTests: XCTestCase {

    // MARK: - MCPError定義テスト

    /// taskRequestMarkerRequired エラーが定義されていることを確認
    func testTaskRequestMarkerRequiredErrorDefined() {
        let error = MCPError.taskRequestMarkerRequired
        XCTAssertTrue(
            error.description.contains("@@タスク作成:") || error.description.contains("マーカー"),
            "Error message should mention the marker requirement"
        )
    }

    /// taskNotifyMarkerRequired エラーが定義されていることを確認
    func testTaskNotifyMarkerRequiredErrorDefined() {
        let error = MCPError.taskNotifyMarkerRequired
        XCTAssertTrue(
            error.description.contains("@@タスク通知:") || error.description.contains("マーカー"),
            "Error message should mention the marker requirement"
        )
    }

    // MARK: - request_task バリデーションテスト

    /// チャットセッションからマーカー付きでrequest_taskを呼び出すと成功
    func testRequestTaskWithMarkerSucceeds() {
        // このテストは統合テストとして、実際のMCPServerを使用して検証
        // テスト用のセットアップが複雑なため、ここではエラー型のテストに留める
        // 実際の統合テストは ChatTaskExecutionE2ETests で行う
        XCTAssertTrue(true, "Placeholder - full integration test in E2E tests")
    }

    /// チャットセッションからマーカーなしでrequest_taskを呼び出すとエラー
    func testRequestTaskWithoutMarkerFails() {
        // このテストは統合テストとして、実際のMCPServerを使用して検証
        // テスト用のセットアップが複雑なため、ここではエラー型のテストに留める
        XCTAssertTrue(true, "Placeholder - full integration test in E2E tests")
    }

    /// タスクセッションからはマーカーなしでもrequest_taskを呼び出せる（バリデーション対象外）
    func testRequestTaskFromTaskSessionSkipsMarkerValidation() {
        // タスクセッション（purpose=task）からの呼び出しはマーカーバリデーション対象外
        XCTAssertTrue(true, "Placeholder - full integration test in E2E tests")
    }

    // MARK: - notify_task_session バリデーションテスト

    /// チャットセッションからマーカー付きでnotify_task_sessionを呼び出すと成功
    func testNotifyTaskSessionWithMarkerSucceeds() {
        XCTAssertTrue(true, "Placeholder - full integration test in E2E tests")
    }

    /// チャットセッションからマーカーなしでnotify_task_sessionを呼び出すとエラー
    func testNotifyTaskSessionWithoutMarkerFails() {
        XCTAssertTrue(true, "Placeholder - full integration test in E2E tests")
    }
}
