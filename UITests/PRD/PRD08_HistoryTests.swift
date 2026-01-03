// UITests/PRD/PRD08_HistoryTests.swift
// PRD 08: 履歴UIテスト
//
// ⚠️ テスト実行ルール:
// 修正対象のテストクラス/メソッドのみを実行すること
// 例: xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
//       -only-testing:AIAgentPMUITests/HistoryTests

import XCTest

// MARK: - PRD 08: History Tests (履歴)

/// 履歴表示・フィルタリング機能のテスト
/// 要件: HISTORY.md - 履歴の表示とフィルタリング
final class HistoryTests: BasicDataUITestCase {

    /// ヘルパー: タスク詳細を開く
    private func openTaskDetail() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクカード選択
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        let firstCard = taskCards.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "タスクが存在すること")
        firstCard.click()
    }

    /// TS-HIST-001: 履歴画面が表示される
    /// 要件: タスク詳細に履歴セクションが表示される
    func testHistoryViewDisplay() throws {
        try openTaskDetail()

        // 履歴セクションの存在確認
        let historySection = app.descendants(matching: .any).matching(identifier: "HistorySection").firstMatch
        XCTAssertTrue(historySection.waitForExistence(timeout: 5), "履歴セクションが表示されること")

        // 履歴ヘッダーの存在確認
        let historyHeader = app.staticTexts["History"]
        XCTAssertTrue(historyHeader.exists, "履歴ヘッダーが表示されること")
    }

    /// TS-HIST-002: エージェント別フィルターが機能する
    /// 要件: 操作したエージェントでフィルタリング可能
    func testHistoryAgentFilter() throws {
        // 履歴フィルター機能は未実装
        // 実装後: エージェント別フィルターUIが存在し、フィルタリングが機能することを確認
        XCTFail("履歴のエージェント別フィルターは未実装")
        throw TestError.failedPrecondition("履歴のエージェント別フィルターは未実装")
    }

    /// TS-HIST-003: タスク別フィルターが機能する
    /// 要件: 対象タスクでフィルタリング可能
    func testHistoryTaskFilter() throws {
        // 履歴フィルター機能は未実装
        // 実装後: タスク別フィルターUIが存在し、フィルタリングが機能することを確認
        XCTFail("履歴のタスク別フィルターは未実装")
        throw TestError.failedPrecondition("履歴のタスク別フィルターは未実装")
    }

    /// TS-HIST-004: 操作種別フィルターが機能する
    /// 要件: 操作種別（ステータス変更、コメント追加等）でフィルタリング可能
    func testHistoryOperationTypeFilter() throws {
        // 履歴フィルター機能は未実装
        // 実装後: 操作種別フィルターUIが存在し、フィルタリングが機能することを確認
        XCTFail("履歴の操作種別フィルターは未実装")
        throw TestError.failedPrecondition("履歴の操作種別フィルターは未実装")
    }
}
