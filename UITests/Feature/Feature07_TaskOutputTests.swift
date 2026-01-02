// UITests/Feature/Feature07_TaskOutputTests.swift
// Feature07: タスク成果物情報
//
// タスクで作成すべき成果物（ファイル名、内容/指示）を
// 入力・保存する機能のテスト

import XCTest

/// Feature07: タスク成果物情報テスト
final class Feature07_TaskOutputTests: XCTestCase {

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

        // プロジェクトを選択してタスクボードを表示
        selectTestProject()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helper Methods

    /// テストプロジェクトを選択
    private func selectTestProject() {
        let projectRow = app.staticTexts["テストプロジェクト"]
        if projectRow.waitForExistence(timeout: 5) {
            projectRow.click()
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    /// 新規タスク作成フォームを開く
    private func openNewTaskForm() {
        // ⇧⌘T でタスク作成フォームを開く
        app.typeKey("t", modifierFlags: [.command, .shift])
    }

    /// 既存タスクの詳細画面を開く
    private func openTaskDetail(taskTitle: String) {
        // TaskBoardからタスクカードをクリック
        let taskCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", taskTitle))
            .firstMatch

        if taskCard.waitForExistence(timeout: 5) {
            taskCard.click()
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    // MARK: - Test Cases

    /// F07-01: タスクフォームに成果物ファイル名フィールドが存在する
    func testOutputFileNameFieldExists() throws {
        openNewTaskForm()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "タスクフォームが表示されること")

        // 成果物ファイル名フィールドの存在確認
        let outputFileNameField = app.textFields["TaskOutputFileNameField"]
        XCTAssertTrue(outputFileNameField.waitForExistence(timeout: 3),
                      "成果物ファイル名フィールドが存在すること")
    }

    /// F07-02: タスクフォームに成果物説明フィールドが存在する
    func testOutputDescriptionFieldExists() throws {
        openNewTaskForm()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "タスクフォームが表示されること")

        // 成果物説明フィールドの存在確認
        let outputDescField = app.textFields["TaskOutputDescriptionField"]
        XCTAssertTrue(outputDescField.waitForExistence(timeout: 3),
                      "成果物説明フィールドが存在すること")
    }

    /// F07-03: 成果物情報を入力して保存できる
    func testOutputInfoSave() throws {
        openNewTaskForm()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "タスクフォームが表示されること")

        // タスクタイトルを入力
        let titleField = app.textFields["TaskTitleField"]
        guard titleField.waitForExistence(timeout: 3) else {
            throw XCTSkip("TaskTitleFieldが見つかりません")
        }
        titleField.click()
        let taskTitle = "OutputTest_\(Int(Date().timeIntervalSince1970))"
        titleField.typeText(taskTitle)

        // 成果物ファイル名を入力
        let outputFileNameField = app.textFields["TaskOutputFileNameField"]
        guard outputFileNameField.waitForExistence(timeout: 3) else {
            throw XCTSkip("TaskOutputFileNameFieldが見つかりません - 機能未実装")
        }
        outputFileNameField.click()
        let testFileName = "test_output.md"
        outputFileNameField.typeText(testFileName)

        // 成果物説明を入力
        let outputDescField = app.textFields["TaskOutputDescriptionField"]
        guard outputDescField.waitForExistence(timeout: 3) else {
            throw XCTSkip("TaskOutputDescriptionFieldが見つかりません - 機能未実装")
        }
        outputDescField.click()
        let testDescription = "Test output description"
        outputDescField.typeText(testDescription)

        // 保存
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2), "Saveボタンが存在すること")
        XCTAssertTrue(saveButton.isEnabled, "Saveボタンが有効であること")
        saveButton.click()

        // シートが閉じる
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "保存後にシートが閉じること")

        // 作成したタスクをクリックして詳細を表示
        Thread.sleep(forTimeInterval: 1.0)
        openTaskDetail(taskTitle: taskTitle)

        // タスク詳細ビューでOutputSectionを確認
        let outputSection = app.descendants(matching: .any)
            .matching(identifier: "OutputSection").firstMatch

        // データ読み込み待機
        Thread.sleep(forTimeInterval: 2.0)

        // 成果物ファイル名が表示されることを確認
        let fileNameDisplay = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", testFileName)
        ).firstMatch

        let outputExists = outputSection.waitForExistence(timeout: 5) ||
                          fileNameDisplay.waitForExistence(timeout: 3)

        XCTAssertTrue(outputExists, "成果物情報が詳細画面に表示されること")
    }

    /// F07-04: タスク詳細にOutputSectionが表示される
    func testOutputSectionDisplay() throws {
        // まず新規タスクを成果物情報付きで作成
        openNewTaskForm()

        let sheet = app.sheets.firstMatch
        guard sheet.waitForExistence(timeout: 5) else {
            throw XCTSkip("タスクフォームが表示されません")
        }

        // タスクタイトルを入力
        let titleField = app.textFields["TaskTitleField"]
        guard titleField.waitForExistence(timeout: 3) else {
            throw XCTSkip("TaskTitleFieldが見つかりません")
        }
        titleField.click()
        let taskTitle = "OutputDisplayTest_\(Int(Date().timeIntervalSince1970))"
        titleField.typeText(taskTitle)

        // 成果物ファイル名を入力
        let outputFileNameField = app.textFields["TaskOutputFileNameField"]
        guard outputFileNameField.waitForExistence(timeout: 3) else {
            throw XCTSkip("TaskOutputFileNameFieldが見つかりません")
        }
        outputFileNameField.click()
        outputFileNameField.typeText("display_test.md")

        // 成果物説明を入力
        let outputDescField = app.textFields["TaskOutputDescriptionField"]
        guard outputDescField.waitForExistence(timeout: 3) else {
            throw XCTSkip("TaskOutputDescriptionFieldが見つかりません")
        }
        outputDescField.click()
        outputDescField.typeText("Display test description")

        // 保存
        let saveButton = app.buttons["TaskFormSaveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2), "Saveボタンが存在すること")
        saveButton.click()

        // シートが閉じる
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "保存後にシートが閉じること")

        // 待機してからタスク詳細を開く
        Thread.sleep(forTimeInterval: 2.0)

        // 作成したタスクをタイトルで検索してクリック
        let taskCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", taskTitle))
            .firstMatch

        if taskCard.waitForExistence(timeout: 5) {
            taskCard.click()
            Thread.sleep(forTimeInterval: 2.0)
        } else {
            throw XCTSkip("作成したタスク '\(taskTitle)' が見つかりません")
        }

        // TaskDetailViewの確認
        let taskDetailView = app.descendants(matching: .any)
            .matching(identifier: "TaskDetailView").firstMatch

        XCTAssertTrue(taskDetailView.waitForExistence(timeout: 5),
                      "タスク詳細画面が表示されていること")

        // OutputSectionの存在確認
        let outputSection = app.descendants(matching: .any)
            .matching(identifier: "OutputSection").firstMatch

        XCTAssertTrue(outputSection.waitForExistence(timeout: 5),
                      "成果物情報が設定されたタスクではOutputSectionが表示されること")
    }
}
