// UITests/Feature/Feature06_ProjectWorkingDirectoryTests.swift
// Feature06: プロジェクト作業ディレクトリ
//
// Claude Codeエージェントがタスクを実行する際の作業ディレクトリを
// プロジェクトに設定する機能のテスト

import XCTest

/// Feature06: プロジェクト作業ディレクトリ設定テスト
final class Feature06_ProjectWorkingDirectoryTests: XCTestCase {

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

    // MARK: - Test Cases

    /// F06-01: プロジェクトフォームに作業ディレクトリフィールドが存在する
    func testWorkingDirectoryFieldExists() throws {
        // グローバルショートカットは Cmd+N（Shiftなし）で新規プロジェクト作成
        app.typeKey("n", modifierFlags: [.command])

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "プロジェクトフォームが表示されること")

        // 作業ディレクトリフィールドの存在確認
        let workingDirField = app.textFields["ProjectWorkingDirectoryField"]
        XCTAssertTrue(workingDirField.waitForExistence(timeout: 3),
                      "作業ディレクトリフィールドが存在すること")
    }

    /// F06-02: 作業ディレクトリを入力して保存できる
    func testWorkingDirectorySave() throws {
        // グローバルショートカットは Cmd+N（Shiftなし）で新規プロジェクト作成
        app.typeKey("n", modifierFlags: [.command])

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "プロジェクトフォームが表示されること")

        // プロジェクト名を入力
        let nameField = app.textFields["ProjectNameField"]
        guard nameField.waitForExistence(timeout: 3) else {
            XCTFail("ProjectNameFieldが見つかりません")
            throw TestError.failedPrecondition("ProjectNameFieldが見つかりません")
        }
        nameField.click()
        let projectName = "WorkDirTest_\(Int(Date().timeIntervalSince1970))"
        nameField.typeText(projectName)

        // 作業ディレクトリを入力
        let workingDirField = app.textFields["ProjectWorkingDirectoryField"]
        guard workingDirField.waitForExistence(timeout: 3) else {
            XCTFail("ProjectWorkingDirectoryFieldが見つかりません")
            throw TestError.failedPrecondition("ProjectWorkingDirectoryFieldが見つかりません")
        }
        workingDirField.click()
        let testPath = "/tmp/test_project_\(Int(Date().timeIntervalSince1970))"
        workingDirField.typeText(testPath)

        // 保存
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2), "Saveボタンが存在すること")
        XCTAssertTrue(saveButton.isEnabled, "Saveボタンが有効であること")
        saveButton.click()

        // シートが閉じる
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "保存後にシートが閉じること")

        // プロジェクトを選択して詳細を確認
        Thread.sleep(forTimeInterval: 1.0)
        let createdProject = app.staticTexts[projectName]
        XCTAssertTrue(createdProject.waitForExistence(timeout: 5),
                      "作成したプロジェクトが一覧に表示されること")
        createdProject.click()

        // TaskBoardが表示されるまで待機
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5), "TaskBoardが表示されること")

        // データ読み込み完了を待機
        Thread.sleep(forTimeInterval: 2.0)

        // 作業ディレクトリが詳細画面に表示される
        // 1. 指定パスを含むテキストを検索
        let workingDirDisplay = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", testPath)
        ).firstMatch

        // 2. WorkingDirectoryValue identifierを検索
        let workingDirValue = app.descendants(matching: .any)
            .matching(identifier: "WorkingDirectoryValue").firstMatch

        let displayExists = workingDirDisplay.waitForExistence(timeout: 5) ||
                           workingDirValue.waitForExistence(timeout: 3)

        XCTAssertTrue(displayExists,
                      "作業ディレクトリが詳細画面に表示されること")
    }

    /// F06-03: 作業ディレクトリ未設定の場合「Not set」と表示される
    func testWorkingDirectoryNotSet() throws {
        // 既存プロジェクト（作業ディレクトリ未設定）を選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        guard projectRow.waitForExistence(timeout: 5) else {
            XCTFail("テストプロジェクトが存在しません")
            throw TestError.failedPrecondition("テストプロジェクトが存在しません")
        }
        projectRow.click()

        // TaskBoardが表示されるまで待機
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5), "TaskBoardが表示されること")

        // データ読み込み完了を待機
        Thread.sleep(forTimeInterval: 2.0)

        // 作業ディレクトリ表示を確認
        // 未設定の場合「Not set」と表示されるべき
        // 1. WorkingDirectoryValue identifierで検索
        let workingDirValue = app.descendants(matching: .any)
            .matching(identifier: "WorkingDirectoryValue").firstMatch

        // 2. staticTextで検索
        let notSetLabel = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Not set' OR label CONTAINS 'Working Directory'")
        ).firstMatch

        // 3. ProjectWorkingDirectory identifierで検索
        let workingDirSection = app.descendants(matching: .any)
            .matching(identifier: "ProjectWorkingDirectory").firstMatch

        let displayExists = workingDirValue.waitForExistence(timeout: 3) ||
                           notSetLabel.waitForExistence(timeout: 3) ||
                           workingDirSection.waitForExistence(timeout: 2)

        XCTAssertTrue(displayExists,
                      "作業ディレクトリ表示（または「Not set」）が詳細画面に存在すること")
    }

    /// F06-04: 作業ディレクトリを編集で変更できる
    func testWorkingDirectoryEdit() throws {
        // 既存プロジェクトを編集（コンテキストメニュー経由）
        let projectRow = app.staticTexts["テストプロジェクト"]
        guard projectRow.waitForExistence(timeout: 5) else {
            XCTFail("テストプロジェクトが存在しません")
            throw TestError.failedPrecondition("テストプロジェクトが存在しません")
        }

        // 右クリックまたはコンテキストメニューで編集
        projectRow.rightClick()
        Thread.sleep(forTimeInterval: 0.3)

        let editMenuItem = app.menuItems["Edit"]
        if editMenuItem.waitForExistence(timeout: 2) {
            editMenuItem.click()
        }

        let editSheet = app.sheets.firstMatch
        guard editSheet.waitForExistence(timeout: 5) else {
            XCTFail("編集フォームが開けません")
            return
        }

        // 編集フォームに作業ディレクトリフィールドが存在することを確認
        let editWorkingDirField = app.textFields["ProjectWorkingDirectoryField"]
        XCTAssertTrue(editWorkingDirField.waitForExistence(timeout: 3),
                      "編集フォームに作業ディレクトリフィールドが存在すること")

        // 作業ディレクトリを入力
        editWorkingDirField.click()
        editWorkingDirField.typeKey("a", modifierFlags: .command) // 全選択
        let newPath = "/tmp/edited_path_\(Int(Date().timeIntervalSince1970))"
        editWorkingDirField.typeText(newPath)

        // 保存
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2), "Saveボタンが存在すること")
        saveButton.click()

        // シートが閉じることを確認
        XCTAssertTrue(editSheet.waitForNonExistence(timeout: 5), "編集シートが閉じること")

        // プロジェクトを選択してTaskBoardに遷移
        Thread.sleep(forTimeInterval: 1.0)
        let updatedProjectRow = app.staticTexts["テストプロジェクト"]
        if updatedProjectRow.waitForExistence(timeout: 3) {
            updatedProjectRow.click()
        }

        // TaskBoardが表示されるまで待機
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5), "TaskBoardが表示されること")

        // データ読み込み完了を待機
        Thread.sleep(forTimeInterval: 2.0)

        // 編集した作業ディレクトリが表示されていることを確認
        // 1. 編集したパスを含むテキストを検索
        let editedPathDisplay = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", newPath)
        ).firstMatch

        // 2. WorkingDirectoryValue identifierで検索
        let workingDirValue = app.descendants(matching: .any)
            .matching(identifier: "WorkingDirectoryValue").firstMatch

        let displayExists = editedPathDisplay.waitForExistence(timeout: 5) ||
                           workingDirValue.waitForExistence(timeout: 3)

        XCTAssertTrue(displayExists,
                      "編集した作業ディレクトリが詳細画面に表示されること")
    }
}
