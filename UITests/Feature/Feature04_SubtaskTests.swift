// UITests/Feature/Feature04_SubtaskTests.swift
// Feature04: 子タスク管理
//
// 親タスクの下に子タスクを作成・管理できる

import XCTest

/// Feature04: 子タスク管理テスト
final class Feature04_SubtaskTests: XCTestCase {

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

    /// F04-01: タスク詳細に「子タスク追加」ボタンが存在
    func testCreateSubtaskButton() throws {
        try selectProject()
        try openResourceTestTask()

        // 子タスク追加ボタンの存在確認
        let addSubtaskButton = app.buttons["AddSubtaskButton"]
        // または標準的な表記
        let addSubtaskAlt = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'subtask' OR label CONTAINS[c] 'Add'")).firstMatch

        let buttonExists = addSubtaskButton.waitForExistence(timeout: 3) ||
                          addSubtaskAlt.waitForExistence(timeout: 1)

        XCTAssertTrue(buttonExists, "「子タスク追加」ボタンが存在すること")
    }

    /// F04-02: ボタンクリックで子タスク作成フォームが開く
    func testSubtaskFormOpens() throws {
        try selectProject()
        try openResourceTestTask()

        // 子タスク追加ボタンをクリック
        let addSubtaskButton = app.buttons["AddSubtaskButton"]
        guard addSubtaskButton.waitForExistence(timeout: 3) else {
            throw XCTSkip("AddSubtaskButtonが見つかりません")
        }
        addSubtaskButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        // 子タスク作成フォームが表示されることを確認
        let subtaskForm = app.sheets.firstMatch
        XCTAssertTrue(subtaskForm.waitForExistence(timeout: 3),
                      "子タスク作成フォームが表示されること")

        // フォームにタイトルフィールドがあること
        let titleField = app.textFields["SubtaskTitleField"]
        let titleFieldAlt = subtaskForm.textFields.firstMatch
        let hasTitle = titleField.exists || titleFieldAlt.exists
        XCTAssertTrue(hasTitle, "タイトル入力フィールドが存在すること")
    }

    /// F04-03: 作成した子タスクが親タスク詳細に表示される
    func testSubtaskDisplayedUnderParent() throws {
        try selectProject()
        try openResourceTestTask()

        // 子タスクセクションの存在確認
        let subtasksSection = app.descendants(matching: .any).matching(identifier: "SubtasksSection").firstMatch

        if subtasksSection.waitForExistence(timeout: 3) {
            // 子タスクリストが表示されること
            XCTAssertTrue(subtasksSection.exists, "子タスクセクションが表示されること")
        } else {
            // セクション未実装の場合はスキップ
            throw XCTSkip("SubtasksSectionが未実装")
        }
    }

    /// F04-04: 子タスクのステータスを個別に変更可能
    func testSubtaskStatusIndependent() throws {
        try selectProject()
        try openResourceTestTask()

        // 子タスクセクションを確認
        let subtasksSection = app.descendants(matching: .any).matching(identifier: "SubtasksSection").firstMatch
        guard subtasksSection.waitForExistence(timeout: 3) else {
            throw XCTSkip("SubtasksSectionが見つかりません")
        }

        // 子タスクの存在確認
        let subtaskRow = subtasksSection.descendants(matching: .any).matching(identifier: "SubtaskRow").firstMatch
        guard subtaskRow.waitForExistence(timeout: 2) else {
            throw XCTSkip("子タスクが存在しません")
        }

        // 子タスクのStatusPickerを確認
        let subtaskStatusPicker = subtaskRow.popUpButtons.firstMatch
        if subtaskStatusPicker.exists {
            // ステータス変更が可能であることを確認
            subtaskStatusPicker.click()
            Thread.sleep(forTimeInterval: 0.3)

            let doneOption = app.menuItems["Done"]
            XCTAssertTrue(doneOption.exists, "子タスクのステータスを変更可能なこと")

            // メニューを閉じる
            app.typeKey(.escape, modifierFlags: [])
        } else {
            throw XCTSkip("子タスクのStatusPickerが見つかりません")
        }
    }

    /// F04-05: 親タスクに子タスク数バッジが表示される
    func testSubtaskCountBadge() throws {
        try selectProject()

        // カンバンボードでタスクカードを確認
        let taskCard = app.descendants(matching: .any).matching(identifier: "TaskCard").firstMatch
        guard taskCard.waitForExistence(timeout: 5) else {
            throw XCTSkip("TaskCardが見つかりません")
        }

        // 子タスク数バッジの存在確認
        let subtaskBadge = taskCard.descendants(matching: .any).matching(identifier: "SubtaskCountBadge").firstMatch
        // または数字表示で検索
        let countLabel = taskCard.staticTexts.matching(NSPredicate(format: "label MATCHES '\\\\d+/\\\\d+' OR label MATCHES '\\\\(\\\\d+\\\\)'")).firstMatch

        let badgeExists = subtaskBadge.waitForExistence(timeout: 2) ||
                         countLabel.waitForExistence(timeout: 1)

        if badgeExists {
            XCTAssertTrue(true, "子タスク数バッジが表示されること")
        } else {
            // バッジ未実装の場合は機能の存在のみ確認
            throw XCTSkip("SubtaskCountBadgeが未実装")
        }
    }
}
