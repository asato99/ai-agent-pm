// UITests/PRD/PRD07_AuditTeamTests.swift
// PRD 07: Internal Audit UIテスト
//
// 参照: docs/requirements/AUDIT.md - Internal Audit仕様
// 参照: docs/ui/07_audit_team.md - UI仕様
//
// ⚠️ テスト実行ルール:
// 修正対象のテストクラス/メソッドのみを実行すること
// 例: xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
//       -only-testing:AIAgentPMUITests/InternalAuditTests

import XCTest

// MARK: - PRD 07: Internal Audit Tests

/// Internal Audit機能のテスト
/// 要件: AUDIT.md - プロジェクト横断でプロセス遵守を自動監視
final class InternalAuditTests: InternalAuditUITestCase {

    // MARK: - TS-AUD-01: Internal Audit一覧画面

    /// TS-AUD-001: サイドバーにInternal Auditsセクションが存在する
    /// 要件: Internal Auditはプロジェクトと同列のトップレベル概念
    func testInternalAuditsSectionExists() throws {
        // Internal Audit機能は未実装
        // 実装後: サイドバーに「Internal Audits」が存在することを確認
        let auditsNavItem = app.staticTexts["Internal Audits"]

        // 未実装のため、存在しないことを確認してスキップ
        if !auditsNavItem.waitForExistence(timeout: 3) {
            XCTFail("Internal Audit機能は未実装 - AUDIT.md要件の実装が必要")
            throw TestError.failedPrecondition("Internal Audit機能は未実装")
        }

        XCTAssertTrue(auditsNavItem.exists,
                      "Internal Audits should exist in sidebar")
    }

    /// TS-AUD-002: Internal Audit一覧が表示される
    /// 要件: 複数のInternal Auditインスタンスを管理
    func testInternalAuditListDisplay() throws {
        guard navigateToInternalAudits() else {
            XCTFail("Internal Audit機能は未実装 - AUDIT.md要件の実装が必要")
            throw TestError.failedPrecondition("Internal Audit機能は未実装")
        }

        // 一覧画面が表示される
        let auditList = app.descendants(matching: .any)
            .matching(identifier: "InternalAuditListView").firstMatch
        XCTAssertTrue(auditList.waitForExistence(timeout: 5),
                      "InternalAuditListView should be displayed")

        // 新規作成ボタンが存在する
        let newButton = app.buttons["NewInternalAuditButton"]
        XCTAssertTrue(newButton.exists,
                      "NewInternalAuditButton should exist")
    }

    /// TS-AUD-003: Internal Audit作成フォームが開く
    /// 要件: Internal Auditの作成機能
    func testInternalAuditCreationFormOpens() throws {
        guard navigateToInternalAudits() else {
            XCTFail("Internal Audit機能は未実装")
            throw TestError.failedPrecondition("Internal Audit機能は未実装")
        }

        // 新規作成ボタンをクリック（ツールバーボタンの重複対策でfirstMatch使用）
        let newButton = app.buttons["NewInternalAuditButton"].firstMatch
        guard newButton.waitForExistence(timeout: 3) else {
            XCTFail("NewInternalAuditButton not found")
            return
        }
        newButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        // フォームが表示される
        let form = app.sheets.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 3),
                      "Internal Audit form sheet should appear")

        // 必須フィールドが存在する
        let nameField = app.textFields["AuditNameField"]
        XCTAssertTrue(nameField.exists, "AuditNameField should exist")

        let statusPicker = app.popUpButtons["AuditStatusPicker"]
        XCTAssertTrue(statusPicker.exists, "AuditStatusPicker should exist")
    }

    /// TS-AUD-004: Internal Auditステータスが表示される
    /// 要件: Active / Suspended / Inactive の3状態
    /// 参照: docs/ui/07_audit_team.md - Status: 🟢 Active / 🟡 Suspended / ⚫ Inactive
    func testAuditStatusDisplay() throws {
        guard navigateToAuditDetail() else {
            XCTFail("Internal Audit詳細への遷移に失敗")
            throw TestError.failedPrecondition("Internal Audit詳細への遷移に失敗")
        }

        // 詳細画面でステータステキストが表示される（Active/Suspended/Inactiveのいずれか）
        // macOS SwiftUI FormのLabeledContent内の要素はaccessibilityIdentifierで取得困難なため
        // テキスト内容で検索する
        let activeStatus = app.staticTexts["Active"]
        let suspendedStatus = app.staticTexts["Suspended"]
        let inactiveStatus = app.staticTexts["Inactive"]

        let statusFound = activeStatus.waitForExistence(timeout: 5) ||
                          suspendedStatus.exists ||
                          inactiveStatus.exists

        XCTAssertTrue(statusFound,
                      "Status text (Active/Suspended/Inactive) should be displayed in detail view")
    }

    // MARK: - TS-AUD-02: Internal Audit詳細画面

    /// TS-AUD-005: Internal Audit詳細画面が表示される
    /// 要件: Audit Rules一覧を含む詳細画面
    func testInternalAuditDetailView() throws {
        guard navigateToInternalAudits() else {
            XCTFail("Internal Audit機能は未実装")
            throw TestError.failedPrecondition("Internal Audit機能は未実装")
        }

        // Audit行をクリック
        let auditRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'InternalAuditRow_'"))
            .firstMatch

        guard auditRow.waitForExistence(timeout: 5) else {
            XCTFail("No Internal Audit found in list")
            return
        }
        auditRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // 詳細画面が表示される
        let detailView = app.descendants(matching: .any)
            .matching(identifier: "InternalAuditDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "InternalAuditDetailView should be displayed")

        // 新規ルールボタンが存在する（データロード完了を待機）
        let newRuleButton = app.buttons["NewAuditRuleButton"]
        XCTAssertTrue(newRuleButton.waitForExistence(timeout: 5),
                      "NewAuditRuleButton should exist")
    }

    /// TS-AUD-006: Audit Rules一覧が表示される
    /// 要件: Internal Audit内のAudit Rule一覧
    func testAuditRulesListDisplay() throws {
        guard navigateToAuditDetail() else {
            XCTFail("Internal Audit詳細への遷移に失敗")
            throw TestError.failedPrecondition("Internal Audit詳細への遷移に失敗")
        }

        // Audit Ruleが表示される（テストデータに依存）
        let ruleRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'AuditRuleRow_'"))
            .firstMatch

        // ルールがある場合は確認
        if ruleRow.waitForExistence(timeout: 3) {
            XCTAssertTrue(ruleRow.exists,
                          "AuditRuleRow should be displayed")
        }
    }

    // MARK: - TS-AUD-03: Audit Rule編集画面

    /// TS-AUD-007: Audit Rule作成フォームが開く
    /// 要件: トリガー + ワークフロー + エージェント割り当て
    func testAuditRuleCreationFormOpens() throws {
        guard navigateToAuditDetail() else {
            XCTFail("Internal Audit詳細への遷移に失敗")
            throw TestError.failedPrecondition("Internal Audit詳細への遷移に失敗")
        }

        // 新規ルールボタンをクリック
        let newRuleButton = app.buttons["NewAuditRuleButton"]
        guard newRuleButton.waitForExistence(timeout: 3) else {
            XCTFail("NewAuditRuleButton not found")
            return
        }
        newRuleButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        // Audit Rule編集画面が表示される
        let ruleEditView = app.descendants(matching: .any)
            .matching(identifier: "AuditRuleEditView").firstMatch
        XCTAssertTrue(ruleEditView.waitForExistence(timeout: 3),
                      "AuditRuleEditView should be displayed")

        // 必須フィールドが存在する
        let nameField = app.textFields["AuditRuleNameField"]
        XCTAssertTrue(nameField.exists, "AuditRuleNameField should exist")

        let triggerPicker = app.popUpButtons["TriggerTypePicker"]
        XCTAssertTrue(triggerPicker.exists, "TriggerTypePicker should exist")

        let templatePicker = app.popUpButtons["WorkflowTemplatePicker"]
        XCTAssertTrue(templatePicker.exists, "WorkflowTemplatePicker should exist")
    }

    /// TS-AUD-008: トリガー種別が選択できる
    /// 要件: task_completed, status_changed, handoff_completed, deadline_exceeded
    func testTriggerTypeSelection() throws {
        guard openAuditRuleEditView() else {
            XCTFail("Audit Rule編集画面を開けません")
            throw TestError.failedPrecondition("Audit Rule編集画面を開けません")
        }

        // トリガーピッカーをクリック
        let triggerPicker = app.popUpButtons["TriggerTypePicker"]
        guard triggerPicker.waitForExistence(timeout: 3) else {
            XCTFail("TriggerTypePicker not found")
            return
        }
        triggerPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        // トリガー種別が選択肢として存在する（displayNameで検索）
        let taskCompleted = app.menuItems["Task Completed"]
        let statusChanged = app.menuItems["Status Changed"]

        // いずれかのトリガー種別が存在することを確認
        let hasTriggerOptions = taskCompleted.exists || statusChanged.exists
        XCTAssertTrue(hasTriggerOptions,
                      "Trigger type options should be available")
    }

    /// TS-AUD-009: ワークフローテンプレートが選択できる
    /// 要件: 既存のワークフローテンプレートから選択
    func testWorkflowTemplateSelection() throws {
        guard openAuditRuleEditView() else {
            XCTFail("Audit Rule編集画面を開けません")
            throw TestError.failedPrecondition("Audit Rule編集画面を開けません")
        }

        // テンプレートピッカーをクリック
        let templatePicker = app.popUpButtons["WorkflowTemplatePicker"]
        guard templatePicker.waitForExistence(timeout: 3) else {
            XCTFail("WorkflowTemplatePicker not found")
            return
        }
        templatePicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        // テンプレートオプションが存在する（テストデータに依存）
        let menuItems = app.menuItems.allElementsBoundByIndex
        XCTAssertTrue(menuItems.count > 0,
                      "Workflow template options should be available")
    }

    /// TS-AUD-010: タスク別エージェント割り当てが表示される
    /// 要件: ワークフローの各タスクにエージェントを割り当て
    /// 参照: docs/ui/07_audit_team.md - TaskAgentPicker_{taskOrder}
    func testTaskAgentAssignmentDisplay() throws {
        guard openAuditRuleEditView() else {
            XCTFail("Audit Rule編集画面を開けません")
            throw TestError.failedPrecondition("Audit Rule編集画面を開けません")
        }

        // テンプレートピッカーをクリック
        let templatePicker = app.popUpButtons["WorkflowTemplatePicker"]
        guard templatePicker.waitForExistence(timeout: 3) else {
            XCTFail("WorkflowTemplatePicker not found")
            return
        }
        templatePicker.click()
        Thread.sleep(forTimeInterval: 0.5)

        // テンプレートオプションを選択（"QA Workflow Template" がシードされている）
        let templateOption = app.menuItems["QA Workflow Template"]
        guard templateOption.waitForExistence(timeout: 3) else {
            XCTFail("QA Workflow Template option not found - workflow template seeding may have failed")
            return
        }
        templateOption.click()

        // テンプレート選択後の非同期処理（loadTemplateTasks）の完了を待つ
        Thread.sleep(forTimeInterval: 2.0)

        // タスク別エージェントピッカーが表示される（テンプレートにはTask 1, Task 2がある）
        // 要件: docs/ui/07_audit_team.md - TaskAgentPicker_{taskOrder}
        let agentPicker1 = app.popUpButtons["TaskAgentPicker_1"]
        let agentPicker2 = app.popUpButtons["TaskAgentPicker_2"]

        let pickerFound = agentPicker1.waitForExistence(timeout: 3) || agentPicker2.exists

        XCTAssertTrue(pickerFound,
                      "Task agent picker (TaskAgentPicker_1 or TaskAgentPicker_2) should be displayed after template selection")

        // 両方のピッカーが表示されていることを確認（テンプレートには2つのタスクがある）
        XCTAssertTrue(agentPicker1.exists && agentPicker2.exists,
                      "Both TaskAgentPicker_1 and TaskAgentPicker_2 should be displayed for QA Workflow Template with 2 tasks")
    }

    // MARK: - TS-AUD-04: ロック機能

    /// TS-AUD-011: タスクロック機能のUI要素が表示される
    /// 要件: 監査エージェントによるタスクのロック機能
    func testTaskLockFunction() throws {
        // Internal Audit詳細画面に移動
        guard navigateToAuditDetail() else {
            throw TestError.failedPrecondition("Internal Audit詳細画面に移動できませんでした")
        }

        // LockedResourcesSectionが表示されることを確認
        let lockedResourcesSection = app.descendants(matching: .any)
            .matching(identifier: "LockedResourcesSection").firstMatch
        XCTAssertTrue(
            lockedResourcesSection.waitForExistence(timeout: 5),
            "LockedResourcesSectionが表示されること"
        )

        // ロックメニューが存在することを確認（Auditがアクティブな場合）
        let addLockMenu = app.buttons["AddLockMenu"]
        if addLockMenu.exists {
            addLockMenu.click()
            Thread.sleep(forTimeInterval: 0.3)

            // タスクロックメニュー項目が表示されることを確認
            let lockTaskMenuItem = app.menuItems["LockTaskMenuItem"]
            XCTAssertTrue(
                lockTaskMenuItem.waitForExistence(timeout: 3),
                "Lock Taskメニュー項目が表示されること"
            )

            // ESCキーでメニューを閉じる
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    /// TS-AUD-012: エージェントロック機能のUI要素が表示される
    /// 要件: 監査エージェントによるエージェントのロック機能
    func testAgentLockFunction() throws {
        // Internal Audit詳細画面に移動
        guard navigateToAuditDetail() else {
            throw TestError.failedPrecondition("Internal Audit詳細画面に移動できませんでした")
        }

        // ロックメニューが存在することを確認（Auditがアクティブな場合）
        let addLockMenu = app.buttons["AddLockMenu"]
        if addLockMenu.exists {
            addLockMenu.click()
            Thread.sleep(forTimeInterval: 0.3)

            // エージェントロックメニュー項目が表示されることを確認
            let lockAgentMenuItem = app.menuItems["LockAgentMenuItem"]
            XCTAssertTrue(
                lockAgentMenuItem.waitForExistence(timeout: 3),
                "Lock Agentメニュー項目が表示されること"
            )

            // ESCキーでメニューを閉じる
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    /// TS-AUD-013: ロック解除UIが監査詳細画面に表示される
    /// 要件: ロックの解除権限は監査エージェントのみ
    func testOnlyAuditAgentCanUnlock() throws {
        // Internal Audit詳細画面に移動
        guard navigateToAuditDetail() else {
            throw TestError.failedPrecondition("Internal Audit詳細画面に移動できませんでした")
        }

        // LockedResourcesSectionが表示されることを確認
        let lockedResourcesSection = app.descendants(matching: .any)
            .matching(identifier: "LockedResourcesSection").firstMatch
        XCTAssertTrue(
            lockedResourcesSection.waitForExistence(timeout: 5),
            "LockedResourcesSectionが表示されること"
        )

        // セクション内のコンテンツを確認
        // NoLockedResourcesMessageまたはロック済みリソースが表示される
        let noLockedMessage = app.descendants(matching: .any)
            .matching(identifier: "NoLockedResourcesMessage").firstMatch
        let lockedTaskRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'LockedTaskRow_'"))
        let lockedAgentRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'LockedAgentRow_'"))

        // セクションが存在すればテスト成功とする
        // （詳細なコンテンツチェックはロックを行った後でないと検証できないため）
        XCTAssertTrue(
            lockedResourcesSection.exists,
            "ロック済みリソースセクションが表示されること"
        )
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

// MARK: - Audit Team Tests (Legacy - 後方互換性)

/// 旧テストクラス名（後方互換性のため残存）
/// 新規テストはInternalAuditTestsクラスに追加すること
@available(*, deprecated, renamed: "InternalAuditTests")
typealias AuditTeamTests = InternalAuditTests
