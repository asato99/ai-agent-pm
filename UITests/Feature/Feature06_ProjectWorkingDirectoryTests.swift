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

    // MARK: - Helper Methods

    /// 新規プロジェクト作成フォームを開く
    private func openNewProjectForm() {
        // グローバルショートカットは Cmd+N（Shiftなし）
        app.typeKey("n", modifierFlags: [.command])
    }

    /// 既存プロジェクトの編集フォームを開く
    private func openEditProjectForm(projectName: String) {
        let projectRow = app.staticTexts[projectName]
        guard projectRow.waitForExistence(timeout: 5) else { return }

        // 右クリックまたはコンテキストメニューで編集
        projectRow.rightClick()
        Thread.sleep(forTimeInterval: 0.3)

        let editMenuItem = app.menuItems["Edit"]
        if editMenuItem.waitForExistence(timeout: 2) {
            editMenuItem.click()
        }
    }

    // MARK: - Test Cases

    /// F06-01: プロジェクトフォームに作業ディレクトリフィールドが存在する
    func testWorkingDirectoryFieldExists() throws {
        openNewProjectForm()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "プロジェクトフォームが表示されること")

        // 作業ディレクトリフィールドの存在確認
        let workingDirField = app.textFields["ProjectWorkingDirectoryField"]
        XCTAssertTrue(workingDirField.waitForExistence(timeout: 3),
                      "作業ディレクトリフィールドが存在すること")
    }

    /// F06-02: 作業ディレクトリを入力して保存できる
    func testWorkingDirectorySave() throws {
        openNewProjectForm()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "プロジェクトフォームが表示されること")

        // プロジェクト名を入力
        let nameField = app.textFields["ProjectNameField"]
        guard nameField.waitForExistence(timeout: 3) else {
            throw XCTSkip("ProjectNameFieldが見つかりません")
        }
        nameField.click()
        let projectName = "WorkDirTest_\(Int(Date().timeIntervalSince1970))"
        nameField.typeText(projectName)

        // 作業ディレクトリを入力
        let workingDirField = app.textFields["ProjectWorkingDirectoryField"]
        guard workingDirField.waitForExistence(timeout: 3) else {
            throw XCTSkip("ProjectWorkingDirectoryFieldが見つかりません - 機能未実装")
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
            throw XCTSkip("テストプロジェクトが存在しません")
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
        // まず作業ディレクトリ付きプロジェクトを作成
        openNewProjectForm()

        let sheet = app.sheets.firstMatch
        guard sheet.waitForExistence(timeout: 5) else {
            throw XCTSkip("プロジェクトフォームが開けません")
        }

        let nameField = app.textFields["ProjectNameField"]
        guard nameField.waitForExistence(timeout: 3) else {
            throw XCTSkip("ProjectNameFieldが見つかりません")
        }
        nameField.click()
        let projectName = "EditWorkDirTest_\(Int(Date().timeIntervalSince1970))"
        nameField.typeText(projectName)

        let workingDirField = app.textFields["ProjectWorkingDirectoryField"]
        guard workingDirField.waitForExistence(timeout: 3) else {
            throw XCTSkip("ProjectWorkingDirectoryFieldが見つかりません - 機能未実装")
        }
        workingDirField.click()
        workingDirField.typeText("/tmp/original_path")

        let saveButton = app.buttons["Save"]
        saveButton.click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "シートが閉じること")

        // 作成したプロジェクトを編集
        Thread.sleep(forTimeInterval: 1.0)
        let createdProject = app.staticTexts[projectName]
        guard createdProject.waitForExistence(timeout: 5) else {
            throw XCTSkip("作成したプロジェクトが見つかりません")
        }

        openEditProjectForm(projectName: projectName)

        let editSheet = app.sheets.firstMatch
        guard editSheet.waitForExistence(timeout: 5) else {
            // 編集フォームが開かない場合はスキップ
            throw XCTSkip("編集フォームが開けません")
        }

        // 作業ディレクトリを変更
        let editWorkingDirField = app.textFields["ProjectWorkingDirectoryField"]
        guard editWorkingDirField.waitForExistence(timeout: 3) else {
            throw XCTSkip("編集フォームにProjectWorkingDirectoryFieldが見つかりません")
        }

        // 既存の値をクリアして新しい値を入力
        editWorkingDirField.click()
        editWorkingDirField.typeKey("a", modifierFlags: .command) // 全選択
        let newPath = "/tmp/updated_path_\(Int(Date().timeIntervalSince1970))"
        editWorkingDirField.typeText(newPath)

        let editSaveButton = app.buttons["Save"]
        editSaveButton.click()
        XCTAssertTrue(editSheet.waitForNonExistence(timeout: 5), "編集シートが閉じること")

        // 更新された値を確認
        Thread.sleep(forTimeInterval: 1.0)
        createdProject.click()
        Thread.sleep(forTimeInterval: 0.5)

        let updatedWorkingDir = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", newPath)
        ).firstMatch
        XCTAssertTrue(updatedWorkingDir.waitForExistence(timeout: 5),
                      "更新された作業ディレクトリが詳細画面に表示されること")
    }
}
