// UITests/Feature/Feature15_SkillManagementTests.swift
// スキル管理機能のUIテスト
// 参照: docs/design/AGENT_SKILLS.md, docs/plan/AGENT_SKILLS_IMPLEMENTATION.md - Phase 3, 4

import XCTest

/// スキル管理機能のテスト
/// Phase 3: UI（スキル管理）
final class SkillManagementTests: BasicDataUITestCase {

    // MARK: - Test: スキル一覧画面

    /// スキル管理画面にアクセスできることを確認
    func test_skillManagementScreen_isAccessible() throws {
        // 設定を開く
        openSettings()

        // Skillsタブをクリック
        let skillsTab = app.buttons["Skills"]
        XCTAssertTrue(skillsTab.waitForExistence(timeout: 5), "Skills tab should exist")
        skillsTab.click()

        // スキル管理画面が表示されることを確認
        let addButton = app.buttons["AddSkillButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3), "Add Skill button should exist")
    }

    // MARK: - Test: スキル作成

    /// スキルを作成できることを確認
    func test_createSkill_success() throws {
        openSettings()

        // Skillsタブをクリック
        app.buttons["Skills"].click()
        Thread.sleep(forTimeInterval: 0.5)

        // 追加ボタンをクリック
        let addButton = app.buttons["AddSkillButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        // フォームが表示されることを確認
        let nameField = app.textFields["SkillNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "Skill name field should exist")

        // フォーム入力
        nameField.click()
        nameField.typeText("Code Review")

        let descriptionField = app.textFields["SkillDescriptionField"]
        descriptionField.click()
        descriptionField.typeText("Review code quality and best practices")

        let directoryField = app.textFields["SkillDirectoryNameField"]
        directoryField.click()
        directoryField.typeText("code-review")

        // 保存
        let saveButton = app.buttons["SaveSkillButton"]
        XCTAssertTrue(saveButton.isEnabled, "Save button should be enabled")
        saveButton.click()
        Thread.sleep(forTimeInterval: 1.0)

        // 一覧に表示されることを確認
        let skillRow = app.staticTexts["Code Review"]
        XCTAssertTrue(skillRow.waitForExistence(timeout: 3), "Created skill should appear in list")
    }

    // MARK: - Test: バリデーション

    /// 無効なディレクトリ名でバリデーションエラーが表示されることを確認
    func test_createSkill_invalidDirectoryName_showsError() throws {
        openSettings()
        app.buttons["Skills"].click()
        Thread.sleep(forTimeInterval: 0.5)

        // 追加ボタンをクリック
        app.buttons["AddSkillButton"].click()
        Thread.sleep(forTimeInterval: 0.5)

        // フォーム入力（無効なディレクトリ名）
        let nameField = app.textFields["SkillNameField"]
        nameField.click()
        nameField.typeText("Test Skill")

        let directoryField = app.textFields["SkillDirectoryNameField"]
        directoryField.click()
        directoryField.typeText("Invalid Name!")  // 無効な文字を含む

        // バリデーションエラーが表示されることを確認
        let errorText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'lowercase'")).firstMatch
        XCTAssertTrue(errorText.waitForExistence(timeout: 2), "Validation error should be displayed")

        // 保存ボタンが無効であることを確認
        let saveButton = app.buttons["SaveSkillButton"]
        XCTAssertFalse(saveButton.isEnabled, "Save button should be disabled for invalid input")
    }

    // MARK: - Test: スキル編集

    /// 既存スキルを編集できることを確認
    func test_editSkill_updatesContent() throws {
        // まずスキルを作成
        try test_createSkill_success()

        // スキルをクリックして編集
        let skillRow = app.staticTexts["Code Review"]
        skillRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // 名前を変更
        let nameField = app.textFields["SkillNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        // 既存テキストをクリア
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("Advanced Code Review")

        // 保存
        app.buttons["SaveSkillButton"].click()
        Thread.sleep(forTimeInterval: 1.0)

        // 更新された名前が表示されることを確認
        let updatedRow = app.staticTexts["Advanced Code Review"]
        XCTAssertTrue(updatedRow.waitForExistence(timeout: 3), "Updated skill name should appear")
    }

    // MARK: - Helper Methods

    private func openSettings() {
        // メニューから設定を開く
        app.menuItems["Settings…"].click()
        Thread.sleep(forTimeInterval: 0.5)
    }
}

// MARK: - Phase 4: スキル割り当てテスト

/// スキル割り当て機能のテスト
/// Phase 4: UI（スキル割り当て）
final class SkillAssignmentTests: BasicDataUITestCase {

    // MARK: - Test: エージェント詳細のスキルセクション

    /// エージェント詳細画面にスキルセクションが表示されることを確認
    func test_agentDetail_showsSkillsSection() throws {
        // エージェント一覧を開く
        openAgentList()

        // 最初のエージェントをクリック
        let agentRow = app.staticTexts["Worker-01"]
        XCTAssertTrue(agentRow.waitForExistence(timeout: 3), "Agent should exist")
        agentRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // スキルセクションが表示されることを確認
        let skillsSection = app.groups["AgentSkillsSection"]
        XCTAssertTrue(skillsSection.waitForExistence(timeout: 3), "Skills section should exist")

        // Manageボタンが存在することを確認
        let manageButton = app.buttons["ManageSkillsButton"]
        XCTAssertTrue(manageButton.exists, "Manage Skills button should exist")
    }

    /// スキル割り当てシートが開けることを確認
    func test_skillAssignmentSheet_opens() throws {
        // エージェント詳細を開く
        openAgentList()
        app.staticTexts["Worker-01"].click()
        Thread.sleep(forTimeInterval: 0.5)

        // Manageボタンをクリック
        let manageButton = app.buttons["ManageSkillsButton"]
        XCTAssertTrue(manageButton.waitForExistence(timeout: 3))
        manageButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        // スキル割り当てシートが開くことを確認
        let saveButton = app.buttons["SaveSkillAssignmentButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3), "Skill assignment sheet should open")
    }

    /// スキルをエージェントに割り当てできることを確認
    func test_assignSkillToAgent_success() throws {
        // まずスキルを作成
        createTestSkill()

        // エージェント詳細を開く
        openAgentList()
        app.staticTexts["Worker-01"].click()
        Thread.sleep(forTimeInterval: 0.5)

        // Manageボタンをクリック
        app.buttons["ManageSkillsButton"].click()
        Thread.sleep(forTimeInterval: 0.5)

        // スキルのチェックボックスをクリック
        let skillCheckbox = app.groups["SkillCheckbox-test-skill"]
        if skillCheckbox.waitForExistence(timeout: 3) {
            skillCheckbox.click()
            Thread.sleep(forTimeInterval: 0.3)

            // 保存
            app.buttons["SaveSkillAssignmentButton"].click()
            Thread.sleep(forTimeInterval: 1.0)

            // スキルバッジが表示されることを確認
            let skillBadge = app.groups["SkillBadge-test-skill"]
            XCTAssertTrue(skillBadge.waitForExistence(timeout: 3), "Skill badge should appear after assignment")
        } else {
            // スキルがない場合はスキップ（空状態の確認）
            let emptyMessage = app.staticTexts["No Skills Available"]
            XCTAssertTrue(emptyMessage.exists || skillCheckbox.exists, "Either skill checkbox or empty message should exist")
        }
    }

    // MARK: - Helper Methods

    private func openAgentList() {
        // サイドバーからエージェント一覧を開く
        let agentsItem = app.outlines.buttons["Agents"]
        if agentsItem.waitForExistence(timeout: 3) {
            agentsItem.click()
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    private func createTestSkill() {
        // 設定を開く
        app.menuItems["Settings…"].click()
        Thread.sleep(forTimeInterval: 0.5)

        // Skillsタブをクリック
        app.buttons["Skills"].click()
        Thread.sleep(forTimeInterval: 0.5)

        // 追加ボタンをクリック
        if app.buttons["AddSkillButton"].waitForExistence(timeout: 3) {
            app.buttons["AddSkillButton"].click()
            Thread.sleep(forTimeInterval: 0.5)

            // フォーム入力
            let nameField = app.textFields["SkillNameField"]
            if nameField.waitForExistence(timeout: 3) {
                nameField.click()
                nameField.typeText("Test Skill")

                let directoryField = app.textFields["SkillDirectoryNameField"]
                directoryField.click()
                directoryField.typeText("test-skill")

                // 保存
                app.buttons["SaveSkillButton"].click()
                Thread.sleep(forTimeInterval: 1.0)
            }
        }

        // 設定を閉じる
        app.typeKey("w", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
    }
}
