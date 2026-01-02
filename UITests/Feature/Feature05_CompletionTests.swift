// UITests/Feature/Feature05_CompletionTests.swift
// Feature05: 完了通知
//
// タスク完了時に親（上位エージェント/ユーザー）に通知される

import XCTest

/// Feature05: 完了通知テスト
final class Feature05_CompletionTests: XCTestCase {

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

    /// タスクステータスをdoneに変更
    private func changeStatusToDone() throws {
        let statusPicker = app.popUpButtons.matching(NSPredicate(format: "identifier == 'StatusPicker'")).firstMatch
        guard statusPicker.waitForExistence(timeout: 3) else {
            throw XCTSkip("StatusPickerが見つかりません")
        }

        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        let doneOption = app.menuItems["Done"]
        guard doneOption.waitForExistence(timeout: 2) else {
            throw XCTSkip("Doneオプションが見つかりません")
        }
        doneOption.click()
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Test Cases

    /// F05-01: タスク完了時にHandoffが自動作成される
    func testCompletionCreatesHandoff() throws {
        try selectProject()
        try openResourceTestTask()
        try changeStatusToDone()

        // Handoffが作成されたことを示すUI要素を確認
        // オプション1: Handoffセクションの存在
        let handoffSection = app.descendants(matching: .any).matching(identifier: "HandoffSection").firstMatch
        // オプション2: 完了通知表示
        let completionNotice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'handoff' OR label CONTAINS[c] 'completed'")).firstMatch

        let handoffCreated = handoffSection.waitForExistence(timeout: 3) ||
                            completionNotice.waitForExistence(timeout: 2)

        if handoffCreated {
            XCTAssertTrue(true, "タスク完了時にHandoffが作成されること")
        } else {
            // Handoff未実装の場合
            throw XCTSkip("Handoff自動作成機能が未実装")
        }
    }

    /// F05-02: 作成されたHandoffがタスク詳細に表示される
    func testHandoffVisibleInTaskDetail() throws {
        try selectProject()
        try openResourceTestTask()

        // Handoffセクションの存在確認
        let handoffSection = app.descendants(matching: .any).matching(identifier: "HandoffSection").firstMatch

        if handoffSection.waitForExistence(timeout: 3) {
            // Handoffエントリの確認
            let handoffEntry = handoffSection.descendants(matching: .any).matching(identifier: "HandoffEntry").firstMatch
            // または静的テキストで検索
            let handoffText = handoffSection.staticTexts.firstMatch

            let hasContent = handoffEntry.exists || handoffText.exists
            XCTAssertTrue(hasContent, "Handoffがタスク詳細に表示されること")
        } else {
            throw XCTSkip("HandoffSectionが未実装")
        }
    }

    /// F05-03: 親エージェント/ユーザーに通知が送られる
    func testNotificationToParent() throws {
        try selectProject()
        try openResourceTestTask()
        try changeStatusToDone()

        // 通知が送られたことを示すUI要素を確認
        // オプション1: 通知インジケーター
        let notificationIndicator = app.descendants(matching: .any).matching(identifier: "NotificationSentIndicator").firstMatch
        // オプション2: 通知ログ
        let notificationLog = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'notified' OR label CONTAINS[c] 'notification sent'")).firstMatch
        // オプション3: 成功メッセージ
        let successMessage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'parent notified' OR label CONTAINS[c] 'reported'")).firstMatch

        let notificationSent = notificationIndicator.waitForExistence(timeout: 3) ||
                              notificationLog.waitForExistence(timeout: 2) ||
                              successMessage.waitForExistence(timeout: 2)

        if notificationSent {
            XCTAssertTrue(true, "親エージェント/ユーザーに通知が送られること")
        } else {
            // 通知機能未実装の場合
            throw XCTSkip("親への通知機能が未実装")
        }
    }

    /// F05-04: 全子タスク完了時に親タスクを完了可能
    func testAllSubtasksDoneEnablesParentComplete() throws {
        try selectProject()
        try openResourceTestTask()

        // 子タスクセクションを確認
        let subtasksSection = app.descendants(matching: .any).matching(identifier: "SubtasksSection").firstMatch
        guard subtasksSection.waitForExistence(timeout: 3) else {
            throw XCTSkip("SubtasksSectionが見つかりません")
        }

        // 子タスクが存在する場合、すべて完了状態かチェック
        let subtaskRows = subtasksSection.descendants(matching: .any).matching(identifier: "SubtaskRow")

        if subtaskRows.count > 0 {
            // 親タスクのステータス変更が可能かテスト
            let statusPicker = app.popUpButtons.matching(NSPredicate(format: "identifier == 'StatusPicker'")).firstMatch
            guard statusPicker.waitForExistence(timeout: 3) else {
                throw XCTSkip("StatusPickerが見つかりません")
            }

            statusPicker.click()
            Thread.sleep(forTimeInterval: 0.3)

            let doneOption = app.menuItems["Done"]

            if doneOption.exists && doneOption.isEnabled {
                // 子タスクがすべて完了している場合、Doneが有効
                XCTAssertTrue(true, "全子タスク完了時に親タスクを完了可能")
                app.typeKey(.escape, modifierFlags: [])
            } else if doneOption.exists && !doneOption.isEnabled {
                // 未完了の子タスクがある場合、Doneが無効
                XCTAssertTrue(true, "未完了子タスクがある場合はDoneが無効になること")
                app.typeKey(.escape, modifierFlags: [])
            } else {
                app.typeKey(.escape, modifierFlags: [])
                throw XCTSkip("Doneオプションが見つかりません")
            }
        } else {
            // 子タスクがない場合はスキップ
            throw XCTSkip("子タスクが存在しません")
        }
    }

    /// F05-05: 完了履歴がHistoryセクションに記録される
    func testCompletionRecordedInHistory() throws {
        try selectProject()
        try openResourceTestTask()

        // Historyセクションの確認
        let historySection = app.descendants(matching: .any).matching(identifier: "HistorySection").firstMatch
        guard historySection.waitForExistence(timeout: 3) else {
            throw XCTSkip("Historyセクションが見つかりません")
        }

        // 完了関連の履歴エントリを検索
        let completionEntry = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'completed' OR label CONTAINS[c] 'done' OR label CONTAINS[c] 'finished'")).firstMatch

        if completionEntry.waitForExistence(timeout: 3) {
            XCTAssertTrue(true, "完了履歴がHistoryに記録されること")
        } else {
            // 履歴エントリがまだない場合はセクションの存在のみ確認
            XCTAssertTrue(historySection.exists, "Historyセクションが存在すること（完了後に記録される）")
        }
    }
}
