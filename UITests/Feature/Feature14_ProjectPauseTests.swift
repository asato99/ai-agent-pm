// UITests/Feature/Feature14_ProjectPauseTests.swift
// Feature 14: プロジェクト一時停止機能テスト
//
// 要件: docs/plan/PROJECT_PAUSE_FEATURE.md
// - active ↔ paused の状態遷移
// - 一時停止中もUI操作は可能
//
// TDDサイクル:
// - RED: 機能未実装のためボタンが存在しない → テスト失敗
// - GREEN: 実装後、同じテストが成功

import XCTest

final class ProjectPauseTests: BasicDataUITestCase {

    /// シナリオ1: 基本フロー（一時停止→再開）
    /// 前提: アクティブなプロジェクトが存在
    func testPauseAndResumeProject() throws {
        // プロジェクト行を右クリックしてコンテキストメニューを開く
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "プロジェクトが表示されること")
        projectRow.rightClick()

        // === 一時停止 ===
        let pauseMenuItem = app.menuItems["PauseProjectMenuItem"]
        XCTAssertTrue(pauseMenuItem.waitForExistence(timeout: 3),
                      "コンテキストメニューに「一時停止」が存在すること")
        pauseMenuItem.click()

        // 確認ダイアログ（オプション：実装次第）
        let confirmButton = app.buttons["ConfirmPauseButton"]
        if confirmButton.waitForExistence(timeout: 2) {
            confirmButton.click()
        }

        // ステータスがPausedに変わることを確認
        // （実装方法によってはバッジ、アイコン、テキストなど）
        let pausedIndicator = app.staticTexts["Paused"]
        XCTAssertTrue(pausedIndicator.waitForExistence(timeout: 3),
                      "プロジェクトステータスが「Paused」と表示されること")

        // === 再開 ===
        // 再度コンテキストメニューを開く
        projectRow.rightClick()

        let resumeMenuItem = app.menuItems["ResumeProjectMenuItem"]
        XCTAssertTrue(resumeMenuItem.waitForExistence(timeout: 3),
                      "一時停止中は「再開」メニューが存在すること")
        resumeMenuItem.click()

        // ステータスがActiveに戻ることを確認
        Thread.sleep(forTimeInterval: 0.5)
        let activeIndicator = app.staticTexts["Active"]
        XCTAssertTrue(activeIndicator.waitForExistence(timeout: 3),
                      "プロジェクトステータスが「Active」に戻ること")

        // Pausedインジケータが消えていることを確認
        XCTAssertFalse(pausedIndicator.exists,
                       "「Paused」表示が消えていること")
    }
}
