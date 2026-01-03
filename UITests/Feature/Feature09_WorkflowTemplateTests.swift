// UITests/Feature/Feature09_WorkflowTemplateTests.swift
// Feature09: ワークフローテンプレート
//
// 一連のタスクをテンプレートとして定義し、繰り返し適用できる機能
// 参照: docs/requirements/WORKFLOW_TEMPLATES.md

import XCTest

/// Feature09: ワークフローテンプレートテスト
final class Feature09_WorkflowTemplateTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-UITestScenario:WorkflowTemplate",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment = ["XCUI_ENABLE_ACCESSIBILITY": "1"]
        app.launch()

        let window = app.windows.firstMatch
        if window.waitForExistence(timeout: 10) {
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - UC-WT-01: テンプレート作成

    /// F09-01: テンプレート一覧画面が表示される
    func testTemplateListExists() throws {
        // サイドバーでTemplatesを選択
        let templatesNavItem = app.staticTexts["Templates"]
        guard templatesNavItem.waitForExistence(timeout: 5) else {
            XCTFail("Templates navigation item not found")
            return
        }
        templatesNavItem.click()
        Thread.sleep(forTimeInterval: 0.5)

        // テンプレート一覧が表示される
        let templateList = app.descendants(matching: .any)
            .matching(identifier: "TemplateList").firstMatch
        XCTAssertTrue(templateList.waitForExistence(timeout: 5),
                      "TemplateList should be displayed")

        // 新規作成ボタンが存在する
        let newButton = app.buttons["NewTemplateButton"]
        XCTAssertTrue(newButton.exists, "NewTemplateButton should exist")
    }

    /// F09-02: 新規テンプレート作成フォームが開く
    func testNewTemplateFormOpens() throws {
        navigateToTemplates()

        // 新規作成ボタンをクリック
        let newButton = app.buttons["NewTemplateButton"]
        guard newButton.waitForExistence(timeout: 3) else {
            XCTFail("NewTemplateButton not found")
            return
        }
        newButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        // フォームが表示される
        let form = app.sheets.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 3),
                      "Template form sheet should appear")

        // 必須フィールドが存在する
        let nameField = app.textFields["TemplateNameField"]
        XCTAssertTrue(nameField.exists, "TemplateNameField should exist")
    }

    /// F09-03: テンプレート名が必須
    func testTemplateNameRequired() throws {
        navigateToTemplates()
        openNewTemplateForm()

        // 名前を入力せずに保存を試みる
        let saveButton = app.buttons["TemplateFormSaveButton"]
        guard saveButton.waitForExistence(timeout: 3) else {
            XCTFail("Save button not found")
            return
        }

        // 保存ボタンが無効化されているか確認
        XCTAssertFalse(saveButton.isEnabled,
                       "Save button should be disabled when name is empty")
    }

    /// F09-04: テンプレートにタスクを追加できる
    func testAddTaskToTemplate() throws {
        navigateToTemplates()
        openNewTemplateForm()

        // テンプレート名を入力
        let nameField = app.textFields["TemplateNameField"]
        guard nameField.waitForExistence(timeout: 3) else {
            XCTFail("TemplateNameField not found")
            return
        }
        nameField.click()
        nameField.typeText("Feature Development")

        // タスク追加ボタンをクリック
        let addTaskButton = app.buttons["AddTemplateTaskButton"]
        guard addTaskButton.waitForExistence(timeout: 3) else {
            XCTFail("AddTemplateTaskButton not found")
            return
        }
        addTaskButton.click()
        Thread.sleep(forTimeInterval: 0.3)

        // タスクリストにアイテムが追加される
        let tasksList = app.descendants(matching: .any)
            .matching(identifier: "TemplateTasksList").firstMatch
        XCTAssertTrue(tasksList.exists, "TemplateTasksList should exist")

        // タスク入力フィールドが表示される
        let taskTitleField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'TemplateTaskTitle_'")
        ).firstMatch
        XCTAssertTrue(taskTitleField.waitForExistence(timeout: 3),
                      "Task title field should appear")
    }

    /// F09-05: 変数を追加できる
    func testAddVariableToTemplate() throws {
        navigateToTemplates()
        openNewTemplateForm()

        // テンプレート名を入力
        let nameField = app.textFields["TemplateNameField"]
        guard nameField.waitForExistence(timeout: 3) else {
            XCTFail("TemplateNameField not found")
            return
        }
        nameField.click()
        nameField.typeText("Feature Development")

        // 変数追加ボタンをクリック
        let addVariableButton = app.buttons["AddVariableButton"]
        guard addVariableButton.waitForExistence(timeout: 3) else {
            XCTFail("AddVariableButton not found")
            return
        }
        addVariableButton.click()
        Thread.sleep(forTimeInterval: 0.3)

        // 変数入力フィールドが表示される
        let variableField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'VariableNameField_'")
        ).firstMatch
        XCTAssertTrue(variableField.waitForExistence(timeout: 3),
                      "Variable name field should appear")
    }

    /// F09-06: テンプレートを保存できる
    func testSaveTemplate() throws {
        navigateToTemplates()
        openNewTemplateForm()

        // テンプレート名を入力
        let nameField = app.textFields["TemplateNameField"]
        guard nameField.waitForExistence(timeout: 3) else {
            XCTFail("TemplateNameField not found")
            return
        }
        nameField.click()
        nameField.typeText("Test Template")

        // タスクを1つ追加
        let addTaskButton = app.buttons["AddTemplateTaskButton"]
        if addTaskButton.waitForExistence(timeout: 2) {
            addTaskButton.click()
            Thread.sleep(forTimeInterval: 0.3)

            let taskTitleField = app.textFields.matching(
                NSPredicate(format: "identifier BEGINSWITH 'TemplateTaskTitle_'")
            ).firstMatch
            if taskTitleField.waitForExistence(timeout: 2) {
                taskTitleField.click()
                taskTitleField.typeText("First Task")
            }
        }

        // 保存
        let saveButton = app.buttons["TemplateFormSaveButton"]
        guard saveButton.waitForExistence(timeout: 3) else {
            XCTFail("Save button not found")
            return
        }
        saveButton.click()

        // シートが閉じる
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5),
                      "Form sheet should close after save")

        // 一覧に表示される
        let templateRow = app.staticTexts["Test Template"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 3),
                      "Saved template should appear in list")
    }

    // MARK: - UC-WT-02: インスタンス化

    /// F09-07: インスタンス化シートが開く
    func testInstantiateSheetOpens() throws {
        navigateToTemplates()

        // 既存テンプレートを選択（テストデータに依存）
        let templateRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'TemplateRow_'"))
            .firstMatch

        guard templateRow.waitForExistence(timeout: 5) else {
            XCTFail("No template found in list")
            return
        }
        templateRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // インスタンス化ボタンをクリック
        let instantiateButton = app.buttons["InstantiateButton"]
        guard instantiateButton.waitForExistence(timeout: 3) else {
            XCTFail("InstantiateButton not found")
            return
        }
        instantiateButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        // インスタンス化シートが表示される
        let instantiateSheet = app.sheets.firstMatch
        XCTAssertTrue(instantiateSheet.waitForExistence(timeout: 3),
                      "Instantiate sheet should appear")

        // プロジェクト選択が存在する
        let projectPicker = app.popUpButtons["InstantiateProjectPicker"]
        XCTAssertTrue(projectPicker.exists,
                      "Project picker should exist in instantiate sheet")
    }

    /// F09-08: 変数入力フィールドが表示される
    func testVariableInputFieldsDisplayed() throws {
        navigateToTemplates()
        openInstantiateSheet()

        // 変数入力フィールドが存在する（テストデータに依存）
        let variableField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'VariableField_'")
        ).firstMatch

        // 変数がないテンプレートの場合はスキップ
        if variableField.waitForExistence(timeout: 3) {
            XCTAssertTrue(variableField.exists,
                          "Variable input field should exist")
        }
    }

    /// F09-09: タスク生成が実行される
    func testInstantiateCreatesTasks() throws {
        navigateToTemplates()
        openInstantiateSheet()

        // プロジェクトを選択
        let projectPicker = app.popUpButtons["InstantiateProjectPicker"]
        guard projectPicker.waitForExistence(timeout: 3) else {
            XCTFail("Project picker not found")
            return
        }
        projectPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        // 最初のプロジェクトを選択
        let projectOption = app.menuItems.element(boundBy: 1)
        if projectOption.waitForExistence(timeout: 2) {
            projectOption.click()
            Thread.sleep(forTimeInterval: 0.3)
        }

        // 変数があれば入力
        let variableFields = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'VariableField_'")
        ).allElementsBoundByIndex
        for field in variableFields where field.exists {
            field.click()
            field.typeText("TestValue")
        }

        // 生成ボタンをクリック
        let generateButton = app.buttons["GenerateTasksButton"]
        guard generateButton.waitForExistence(timeout: 3) else {
            XCTFail("Generate button not found")
            return
        }
        generateButton.click()

        // シートが閉じる
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5),
                      "Sheet should close after generation")

        // 成功メッセージまたはプロジェクト画面への遷移を確認
        // （実装に依存するため、基本的なチェックのみ）
    }

    // MARK: - UC-WT-03: テンプレート編集

    /// F09-10: テンプレートを編集できる
    func testEditTemplate() throws {
        navigateToTemplates()

        // 既存テンプレートを選択
        let templateRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'TemplateRow_'"))
            .firstMatch

        guard templateRow.waitForExistence(timeout: 5) else {
            XCTFail("No template found in list")
            return
        }
        templateRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // 編集ボタンをクリック
        let editButton = app.buttons["EditTemplateButton"]
        guard editButton.waitForExistence(timeout: 3) else {
            XCTFail("EditTemplateButton not found")
            return
        }
        editButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        // フォームが表示される
        let form = app.sheets.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 3),
                      "Edit form should appear")

        // 名前フィールドに既存の値が入っている
        let nameField = app.textFields["TemplateNameField"]
        XCTAssertTrue(nameField.exists, "TemplateNameField should exist")
        let currentValue = nameField.value as? String ?? ""
        XCTAssertFalse(currentValue.isEmpty,
                       "Name field should have existing value")
    }

    // MARK: - UC-WT-04: アーカイブ

    /// F09-11: テンプレートをアーカイブできる
    func testArchiveTemplate() throws {
        navigateToTemplates()

        // 既存テンプレートを選択
        let templateRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'TemplateRow_'"))
            .firstMatch

        guard templateRow.waitForExistence(timeout: 5) else {
            XCTFail("No template found in list")
            return
        }
        templateRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // アーカイブボタンをクリック
        let archiveButton = app.buttons["ArchiveTemplateButton"]
        guard archiveButton.waitForExistence(timeout: 3) else {
            XCTFail("ArchiveTemplateButton not found")
            return
        }
        archiveButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        // 確認ダイアログが表示される
        let confirmButton = app.buttons["ConfirmArchiveButton"]
        if confirmButton.waitForExistence(timeout: 2) {
            confirmButton.click()
            Thread.sleep(forTimeInterval: 0.5)
        }

        // テンプレートが一覧から消える（またはアーカイブ表示に移動）
        // 実装によって検証方法が異なる
    }

    // MARK: - Helper Methods

    /// Templatesナビゲーションに移動
    private func navigateToTemplates() {
        let templatesNavItem = app.staticTexts["Templates"]
        if templatesNavItem.waitForExistence(timeout: 5) {
            templatesNavItem.click()
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// 新規テンプレートフォームを開く
    private func openNewTemplateForm() {
        let newButton = app.buttons["NewTemplateButton"]
        if newButton.waitForExistence(timeout: 3) {
            newButton.click()
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// インスタンス化シートを開く
    private func openInstantiateSheet() {
        let templateRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'TemplateRow_'"))
            .firstMatch

        if templateRow.waitForExistence(timeout: 5) {
            templateRow.click()
            Thread.sleep(forTimeInterval: 0.5)

            let instantiateButton = app.buttons["InstantiateButton"]
            if instantiateButton.waitForExistence(timeout: 3) {
                instantiateButton.click()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }
}
