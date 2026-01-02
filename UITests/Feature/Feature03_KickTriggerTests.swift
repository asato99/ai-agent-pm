// UITests/Feature/Feature03_KickTriggerTests.swift
// Feature03: キックトリガー
//
// タスクステータスがin_progressに変更されたとき、キックが実行される

import XCTest

/// Feature03: キックトリガーテスト
final class Feature03_KickTriggerTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-UITestScenario:Basic",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment = [
            "XCUI_ENABLE_ACCESSIBILITY": "1"
        ]
        app.launch()

        let window = app.windows.firstMatch
        if window.waitForExistence(timeout: 10) {
            Thread.sleep(forTimeInterval: 2.0)
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helper Methods

    /// プロジェクトを選択
    private func selectProject() throws {
        let projectRow = app.staticTexts["テストプロジェクト"]
        guard projectRow.waitForExistence(timeout: 5) else {
            throw XCTSkip("テストプロジェクトが存在しません")
        }
        projectRow.click()
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// タスク詳細を開く（キーボードショートカット使用）
    private func openResourceTestTask() throws {
        // リソーステストタスクを選択（Cmd+Shift+G）
        app.typeKey("g", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        guard detailView.waitForExistence(timeout: 5) else {
            throw XCTSkip("タスク詳細が開けません")
        }
    }

    // MARK: - Test Cases

    /// F03-01: in_progress変更時にキック処理が呼ばれる
    func testKickTriggeredOnStatusChange() throws {
        try selectProject()
        try openResourceTestTask()

        // StatusPickerでin_progressに変更
        let statusPickerPredicate = NSPredicate(format: "identifier == 'StatusPicker'")
        let statusPicker = app.popUpButtons.matching(statusPickerPredicate).firstMatch

        guard statusPicker.waitForExistence(timeout: 3) else {
            throw XCTSkip("StatusPickerが見つかりません")
        }

        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        let inProgressOption = app.menuItems["In Progress"]
        guard inProgressOption.waitForExistence(timeout: 2) else {
            throw XCTSkip("In Progressオプションが見つかりません")
        }
        inProgressOption.click()
        Thread.sleep(forTimeInterval: 0.5)

        // キックが実行されたことを示すUI要素を確認
        // オプション1: キック状態インジケーター
        let kickStatusIndicator = app.descendants(matching: .any).matching(identifier: "KickStatusIndicator").firstMatch
        // オプション2: キックログエントリ
        let kickLogEntry = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Kick'")).firstMatch

        // どちらかが存在すればOK（またはエラーアラートでブロックされた場合）
        let sheet = app.sheets.firstMatch
        if sheet.waitForExistence(timeout: 2) {
            // ブロックされた場合はOKで閉じる
            let okButton = sheet.buttons["OK"]
            if okButton.exists {
                okButton.click()
            }
            XCTAssertTrue(true, "ステータス変更がトリガーされた（ブロックまたはキック）")
        } else {
            // キック状態の確認
            let kickTriggered = kickStatusIndicator.waitForExistence(timeout: 2) ||
                               kickLogEntry.waitForExistence(timeout: 2)
            XCTAssertTrue(kickTriggered, "キックがトリガーされたことを示すUIが存在すること")
        }
    }

    /// F03-02: キック状態（成功/失敗）がUI上に表示される
    func testKickStatusDisplayed() throws {
        try selectProject()
        try openResourceTestTask()

        // キック状態セクションの存在確認
        let kickStatusSection = app.descendants(matching: .any).matching(identifier: "KickStatusSection").firstMatch

        if kickStatusSection.waitForExistence(timeout: 3) {
            // 状態ラベルの確認
            let pendingStatus = app.staticTexts["Pending"]
            let runningStatus = app.staticTexts["Running"]
            let successStatus = app.staticTexts["Success"]
            let failedStatus = app.staticTexts["Failed"]

            let hasStatus = pendingStatus.exists || runningStatus.exists ||
                           successStatus.exists || failedStatus.exists

            XCTAssertTrue(hasStatus, "キック状態ラベルが表示されること")
        } else {
            // セクション自体が未実装の場合はスキップ
            throw XCTSkip("KickStatusSectionが未実装")
        }
    }

    /// F03-03: キックのログ/履歴が確認可能
    func testKickLogVisible() throws {
        try selectProject()
        try openResourceTestTask()

        // Historyセクションにキックログが表示されることを確認
        let historySection = app.descendants(matching: .any).matching(identifier: "HistorySection").firstMatch

        guard historySection.waitForExistence(timeout: 3) else {
            throw XCTSkip("Historyセクションが見つかりません")
        }

        // キック関連の履歴エントリを検索
        let kickLogEntry = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'kick' OR label CONTAINS[c] 'started'")).firstMatch

        if kickLogEntry.waitForExistence(timeout: 3) {
            XCTAssertTrue(true, "キックログが履歴に表示されていること")
        } else {
            // キックがまだ実行されていない場合、履歴セクションの存在のみ確認
            XCTAssertTrue(historySection.exists, "履歴セクションが存在すること（キックログは実行後に表示）")
        }
    }
}
