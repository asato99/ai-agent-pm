// UITests/Feature/Feature10_InternalAuditTests.swift
// Feature10: Internal Audit機能
//
// プロジェクト横断でプロセス遵守を自動監視する機能
// 参照: docs/requirements/AUDIT.md
// 参照: docs/ui/07_audit_team.md
//
// ⚠️ テスト実行ルール:
// 修正対象のテストクラス/メソッドのみを実行すること
// 例: xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
//       -only-testing:AIAgentPMUITests/Feature10_InternalAuditTests

import XCTest

/// Feature10: Internal Audit機能テスト
/// 詳細な機能テスト（PRD07は基本テスト、こちらは詳細テスト）
final class Feature10_InternalAuditTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-UITestScenario:InternalAudit",
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

    // MARK: - F10-01: Internal Audit CRUD

    /// F10-01: Internal Audit一覧からの新規作成
    func testCreateInternalAudit() throws {
        guard navigateToInternalAudits() else {
            throw XCTSkip("Internal Audit機能は未実装")
        }

        // 新規作成ボタンをクリック
        let newButton = app.buttons["NewInternalAuditButton"]
        guard newButton.waitForExistence(timeout: 3) else {
            XCTFail("NewInternalAuditButton not found")
            return
        }
        newButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        // フォームに入力
        let nameField = app.textFields["AuditNameField"]
        guard nameField.waitForExistence(timeout: 3) else {
            XCTFail("AuditNameField not found")
            return
        }
        nameField.click()
        nameField.typeText("Test QA Audit")

        // 説明を入力
        let descField = app.textViews["AuditDescriptionField"]
        if descField.waitForExistence(timeout: 2) {
            descField.click()
            descField.typeText("Quality assurance audit for testing")
        }

        // 保存
        let saveButton = app.buttons["SaveAuditButton"]
        guard saveButton.waitForExistence(timeout: 3) else {
            XCTFail("SaveAuditButton not found")
            return
        }
        saveButton.click()

        // シートが閉じる
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5),
                      "Form sheet should close after save")

        // 一覧に表示される
        let auditRow = app.staticTexts["Test QA Audit"]
        XCTAssertTrue(auditRow.waitForExistence(timeout: 3),
                      "Created audit should appear in list")
    }

    /// F10-02: Internal Auditの名前が必須
    func testAuditNameRequired() throws {
        guard navigateToInternalAudits() else {
            throw XCTSkip("Internal Audit機能は未実装")
        }

        openNewAuditForm()

        // 名前を入力せずに保存を試みる
        let saveButton = app.buttons["SaveAuditButton"]
        guard saveButton.waitForExistence(timeout: 3) else {
            XCTFail("SaveAuditButton not found")
            return
        }

        // 保存ボタンが無効化されているか確認
        XCTAssertFalse(saveButton.isEnabled,
                       "Save button should be disabled when name is empty")
    }

    /// F10-03: Internal Auditステータスを変更できる
    func testChangeAuditStatus() throws {
        guard navigateToAuditDetail() else {
            throw XCTSkip("Internal Audit機能は未実装")
        }

        // 編集ボタンをクリック
        let editButton = app.buttons["EditInternalAuditButton"]
        guard editButton.waitForExistence(timeout: 3) else {
            XCTFail("EditInternalAuditButton not found")
            return
        }
        editButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        // ステータスピッカーを変更
        let statusPicker = app.popUpButtons["AuditStatusPicker"]
        guard statusPicker.waitForExistence(timeout: 3) else {
            XCTFail("AuditStatusPicker not found")
            return
        }
        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        // Suspendedを選択
        let suspendedOption = app.menuItems["suspended"]
        if suspendedOption.waitForExistence(timeout: 2) {
            suspendedOption.click()
        }

        // 保存
        let saveButton = app.buttons["SaveAuditButton"]
        if saveButton.waitForExistence(timeout: 2) {
            saveButton.click()
        }

        // ステータスが更新されていることを確認
        let statusText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Suspended'")
        ).firstMatch
        XCTAssertTrue(statusText.waitForExistence(timeout: 3),
                      "Status should be updated to Suspended")
    }

    // MARK: - F10-02: Audit Rule CRUD

    /// F10-04: Audit Ruleを作成できる
    func testCreateAuditRule() throws {
        guard navigateToAuditDetail() else {
            throw XCTSkip("Internal Audit機能は未実装")
        }

        // 新規ルールボタンをクリック
        let newRuleButton = app.buttons["NewAuditRuleButton"]
        guard newRuleButton.waitForExistence(timeout: 3) else {
            XCTFail("NewAuditRuleButton not found")
            return
        }
        newRuleButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        // ルール名を入力
        let nameField = app.textFields["AuditRuleNameField"]
        guard nameField.waitForExistence(timeout: 3) else {
            XCTFail("AuditRuleNameField not found")
            return
        }
        nameField.click()
        nameField.typeText("Task Completion Check")

        // トリガーを選択
        let triggerPicker = app.popUpButtons["TriggerTypePicker"]
        if triggerPicker.waitForExistence(timeout: 2) {
            triggerPicker.click()
            Thread.sleep(forTimeInterval: 0.3)

            let taskCompleted = app.menuItems["task_completed"]
            if taskCompleted.waitForExistence(timeout: 2) {
                taskCompleted.click()
            }
        }

        // テンプレートを選択
        let templatePicker = app.popUpButtons["WorkflowTemplatePicker"]
        if templatePicker.waitForExistence(timeout: 2) {
            templatePicker.click()
            Thread.sleep(forTimeInterval: 0.3)

            let templateOption = app.menuItems.element(boundBy: 1)
            if templateOption.waitForExistence(timeout: 2) {
                templateOption.click()
                Thread.sleep(forTimeInterval: 0.3)
            }
        }

        // エージェントを割り当て（テンプレートにタスクがある場合）
        let agentPickers = app.popUpButtons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'TaskAgentPicker_'")
        ).allElementsBoundByIndex

        for picker in agentPickers where picker.exists {
            picker.click()
            Thread.sleep(forTimeInterval: 0.2)

            let agentOption = app.menuItems.element(boundBy: 1)
            if agentOption.waitForExistence(timeout: 2) {
                agentOption.click()
            }
        }

        // 保存
        let saveButton = app.buttons["SaveAuditRuleButton"]
        guard saveButton.waitForExistence(timeout: 3) else {
            XCTFail("SaveAuditRuleButton not found")
            return
        }
        saveButton.click()

        // 詳細画面に戻る
        let detailView = app.descendants(matching: .any)
            .matching(identifier: "InternalAuditDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "Should return to detail view after save")

        // ルールが一覧に表示される
        let ruleRow = app.staticTexts["Task Completion Check"]
        XCTAssertTrue(ruleRow.waitForExistence(timeout: 3),
                      "Created rule should appear in list")
    }

    /// F10-05: Audit Ruleの有効/無効を切り替えできる
    func testToggleAuditRuleEnabled() throws {
        guard navigateToAuditDetail() else {
            throw XCTSkip("Internal Audit機能は未実装")
        }

        // 既存のルールをクリック
        let ruleRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'AuditRuleRow_'"))
            .firstMatch

        guard ruleRow.waitForExistence(timeout: 5) else {
            throw XCTSkip("No Audit Rules available for testing")
        }
        ruleRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // 有効トグルを操作
        let enabledToggle = app.checkBoxes["AuditRuleEnabledToggle"]
        guard enabledToggle.waitForExistence(timeout: 3) else {
            XCTFail("AuditRuleEnabledToggle not found")
            return
        }

        let initialState = enabledToggle.value as? Bool ?? true
        enabledToggle.click()
        Thread.sleep(forTimeInterval: 0.3)

        // 状態が変わったことを確認
        let newState = enabledToggle.value as? Bool ?? true
        XCTAssertNotEqual(initialState, newState,
                          "Toggle state should change")
    }

    /// F10-06: Audit Ruleのルール名が必須
    func testAuditRuleNameRequired() throws {
        guard openAuditRuleEditView() else {
            throw XCTSkip("Internal Audit機能は未実装")
        }

        // テンプレートを選択（名前以外を入力）
        let templatePicker = app.popUpButtons["WorkflowTemplatePicker"]
        if templatePicker.waitForExistence(timeout: 2) {
            templatePicker.click()
            Thread.sleep(forTimeInterval: 0.3)

            let templateOption = app.menuItems.element(boundBy: 1)
            if templateOption.waitForExistence(timeout: 2) {
                templateOption.click()
            }
        }

        // 名前が空のまま保存を試みる
        let saveButton = app.buttons["SaveAuditRuleButton"]
        guard saveButton.waitForExistence(timeout: 3) else {
            XCTFail("SaveAuditRuleButton not found")
            return
        }

        // 保存ボタンが無効化されているか確認
        XCTAssertFalse(saveButton.isEnabled,
                       "Save button should be disabled when name is empty")
    }

    /// F10-07: 全タスクにエージェント割り当てが必須
    func testAllTasksMustHaveAgentAssigned() throws {
        guard openAuditRuleEditView() else {
            throw XCTSkip("Internal Audit機能は未実装")
        }

        // ルール名を入力
        let nameField = app.textFields["AuditRuleNameField"]
        if nameField.waitForExistence(timeout: 2) {
            nameField.click()
            nameField.typeText("Test Rule")
        }

        // テンプレートを選択
        let templatePicker = app.popUpButtons["WorkflowTemplatePicker"]
        if templatePicker.waitForExistence(timeout: 2) {
            templatePicker.click()
            Thread.sleep(forTimeInterval: 0.3)

            let templateOption = app.menuItems.element(boundBy: 1)
            if templateOption.waitForExistence(timeout: 2) {
                templateOption.click()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        // エージェントを割り当てない状態で保存を試みる
        let saveButton = app.buttons["SaveAuditRuleButton"]
        guard saveButton.waitForExistence(timeout: 3) else {
            XCTFail("SaveAuditRuleButton not found")
            return
        }

        // 保存ボタンが無効化されているか、エラーが表示されるか確認
        // 実装方法によって検証が異なる
        if !saveButton.isEnabled {
            XCTAssertFalse(saveButton.isEnabled,
                           "Save should be disabled without agent assignments")
        } else {
            saveButton.click()
            Thread.sleep(forTimeInterval: 0.5)

            // エラーメッセージが表示されるか確認
            let errorText = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'agent'")
            ).firstMatch
            XCTAssertTrue(errorText.waitForExistence(timeout: 2),
                          "Error message about agent assignment should appear")
        }
    }

    // MARK: - F10-03: Trigger Configuration

    /// F10-08: status_changedトリガーで対象ステータスを選択できる
    func testStatusChangedTriggerConfiguration() throws {
        guard openAuditRuleEditView() else {
            throw XCTSkip("Internal Audit機能は未実装")
        }

        // status_changedトリガーを選択
        let triggerPicker = app.popUpButtons["TriggerTypePicker"]
        guard triggerPicker.waitForExistence(timeout: 3) else {
            XCTFail("TriggerTypePicker not found")
            return
        }
        triggerPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        let statusChanged = app.menuItems["status_changed"]
        guard statusChanged.waitForExistence(timeout: 2) else {
            XCTFail("status_changed option not found")
            return
        }
        statusChanged.click()
        Thread.sleep(forTimeInterval: 0.5)

        // 追加設定（対象ステータス選択）が表示される
        let statusConfigPicker = app.popUpButtons["TriggerStatusPicker"]
        XCTAssertTrue(statusConfigPicker.waitForExistence(timeout: 3),
                      "Status configuration picker should appear for status_changed trigger")
    }

    /// F10-09: deadline_exceededトリガーで猶予時間を設定できる
    func testDeadlineExceededTriggerConfiguration() throws {
        guard openAuditRuleEditView() else {
            throw XCTSkip("Internal Audit機能は未実装")
        }

        // deadline_exceededトリガーを選択
        let triggerPicker = app.popUpButtons["TriggerTypePicker"]
        guard triggerPicker.waitForExistence(timeout: 3) else {
            XCTFail("TriggerTypePicker not found")
            return
        }
        triggerPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        let deadlineExceeded = app.menuItems["deadline_exceeded"]
        guard deadlineExceeded.waitForExistence(timeout: 2) else {
            XCTFail("deadline_exceeded option not found")
            return
        }
        deadlineExceeded.click()
        Thread.sleep(forTimeInterval: 0.5)

        // 追加設定（猶予時間）が表示される
        let graceField = app.textFields["TriggerGraceMinutesField"]
        XCTAssertTrue(graceField.waitForExistence(timeout: 3),
                      "Grace minutes field should appear for deadline_exceeded trigger")
    }

    // MARK: - F10-04: Template Selection & Task Assignment

    /// F10-10: テンプレート変更でタスク割り当てがリセットされる
    func testTemplateChangeResetsAssignments() throws {
        guard openAuditRuleEditView() else {
            throw XCTSkip("Internal Audit機能は未実装")
        }

        // 最初のテンプレートを選択
        let templatePicker = app.popUpButtons["WorkflowTemplatePicker"]
        guard templatePicker.waitForExistence(timeout: 3) else {
            XCTFail("WorkflowTemplatePicker not found")
            return
        }
        templatePicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        let firstTemplate = app.menuItems.element(boundBy: 1)
        if firstTemplate.waitForExistence(timeout: 2) {
            firstTemplate.click()
            Thread.sleep(forTimeInterval: 0.5)
        }

        // エージェントを割り当て
        let agentPicker = app.popUpButtons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'TaskAgentPicker_'")
        ).firstMatch

        if agentPicker.waitForExistence(timeout: 3) {
            agentPicker.click()
            Thread.sleep(forTimeInterval: 0.2)

            let agentOption = app.menuItems.element(boundBy: 1)
            if agentOption.waitForExistence(timeout: 2) {
                agentOption.click()
            }
        }

        // 別のテンプレートに変更
        templatePicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        let secondTemplate = app.menuItems.element(boundBy: 2)
        if secondTemplate.waitForExistence(timeout: 2) {
            secondTemplate.click()
            Thread.sleep(forTimeInterval: 0.5)
        }

        // タスク割り当てが更新される（新しいテンプレートのタスクが表示）
        let newAgentPicker = app.popUpButtons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'TaskAgentPicker_'")
        ).firstMatch

        XCTAssertTrue(newAgentPicker.exists,
                      "Task assignment pickers should be updated for new template")
    }

    // MARK: - Helper Methods

    /// Internal Auditsナビゲーションに移動
    @discardableResult
    private func navigateToInternalAudits() -> Bool {
        let auditsNavItem = app.staticTexts["Internal Audits"]
        if auditsNavItem.waitForExistence(timeout: 5) {
            auditsNavItem.click()
            Thread.sleep(forTimeInterval: 0.5)
            return true
        }
        return false
    }

    /// Internal Audit詳細画面に移動
    @discardableResult
    private func navigateToAuditDetail() -> Bool {
        guard navigateToInternalAudits() else { return false }

        let auditRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'InternalAuditRow_'"))
            .firstMatch

        guard auditRow.waitForExistence(timeout: 5) else { return false }
        auditRow.click()
        Thread.sleep(forTimeInterval: 1.0)

        // Wait for detail view to load
        let detailView = app.descendants(matching: .any)
            .matching(identifier: "InternalAuditDetailView").firstMatch
        return detailView.waitForExistence(timeout: 5)
    }

    /// 新規Auditフォームを開く
    private func openNewAuditForm() {
        let newButton = app.buttons["NewInternalAuditButton"]
        if newButton.waitForExistence(timeout: 3) {
            newButton.click()
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// Audit Rule編集画面を開く
    @discardableResult
    private func openAuditRuleEditView() -> Bool {
        guard navigateToAuditDetail() else { return false }

        let newRuleButton = app.buttons["NewAuditRuleButton"]
        if newRuleButton.waitForExistence(timeout: 3) {
            newRuleButton.click()
            Thread.sleep(forTimeInterval: 0.5)
            return true
        }
        return false
    }
}
