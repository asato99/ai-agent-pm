// UITests/Feature/Feature15_SkillManagementTests.swift
// スキル管理機能のUIテスト
// 参照: docs/design/AGENT_SKILLS.md, docs/plan/AGENT_SKILLS_IMPLEMENTATION.md - Phase 3

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
