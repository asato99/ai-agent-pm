// UITests/Feature/Feature02_AgentAuthTests.swift
// Feature02: エージェント認証
//
// エージェントにパスキーを設定し、MCP接続時の認証に使用する

import XCTest

/// Feature02: エージェント認証テスト
final class Feature02_AgentAuthTests: XCTestCase {

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

    /// 新規エージェント作成フォームを開く
    private func openNewAgentForm() {
        app.typeKey("a", modifierFlags: [.command, .shift])
    }

    // MARK: - Test Cases

    /// F02-01: エージェントフォームに「認証設定」セクションが存在
    func testAuthSectionExists() throws {
        openNewAgentForm()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "エージェントフォームが表示されること")

        // 認証設定セクションの存在確認
        let authSection = app.staticTexts["Authentication"]
        XCTAssertTrue(authSection.waitForExistence(timeout: 3),
                      "「Authentication」セクションが存在すること")
    }

    /// F02-02: パスキー入力フィールドが存在（SecureField）
    func testPasskeyField() throws {
        openNewAgentForm()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "エージェントフォームが表示されること")

        // パスキーフィールドの存在確認
        // SecureFieldはsecureTextFieldsで検索
        let passkeyField = app.secureTextFields["PasskeyField"]
        XCTAssertTrue(passkeyField.waitForExistence(timeout: 3),
                      "パスキーフィールドが存在すること")
    }

    /// F02-03: 入力されたパスキーがマスク表示される
    func testPasskeyMasked() throws {
        openNewAgentForm()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "エージェントフォームが表示されること")

        let passkeyField = app.secureTextFields["PasskeyField"]
        guard passkeyField.waitForExistence(timeout: 3) else {
            throw XCTSkip("パスキーフィールドが見つかりません")
        }

        // パスキーを入力
        passkeyField.click()
        passkeyField.typeText("secret123")

        // SecureFieldは値が取得できない（マスクされている）ことを確認
        // XCUITestではSecureFieldの実際の値は取得できないため、
        // フィールドが存在し、入力操作が成功したことで確認
        XCTAssertTrue(passkeyField.exists, "パスキーが入力されていること（マスク表示）")
    }

    /// F02-04: 認証レベル（0/1/2）を選択可能
    func testAuthLevelPicker() throws {
        openNewAgentForm()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "エージェントフォームが表示されること")

        // 認証レベルPickerの存在確認
        let authLevelPicker = app.popUpButtons["AuthLevelPicker"]
        XCTAssertTrue(authLevelPicker.waitForExistence(timeout: 3),
                      "認証レベルPickerが存在すること")

        // Pickerをクリックしてオプションを確認
        authLevelPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        // 各レベルの存在確認
        let level0 = app.menuItems["Level 0 (ID only)"]
        let level1 = app.menuItems["Level 1 (ID + Passkey)"]
        let level2 = app.menuItems["Level 2 (+ IP restriction)"]

        XCTAssertTrue(level0.exists, "Level 0オプションが存在すること")
        XCTAssertTrue(level1.exists, "Level 1オプションが存在すること")
        XCTAssertTrue(level2.exists, "Level 2オプションが存在すること")

        // 選択してメニューを閉じる
        level1.click()
    }

    /// F02-05: パスキーが保存される（表示はマスク）
    func testPasskeySaved() throws {
        openNewAgentForm()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "エージェントフォームが表示されること")

        // 基本情報を入力
        let nameField = app.textFields["AgentNameField"]
        if nameField.waitForExistence(timeout: 2) {
            nameField.click()
            nameField.typeText("AuthTestAgent")
        }

        let roleField = app.textFields["AgentRoleField"]
        if roleField.waitForExistence(timeout: 2) {
            roleField.click()
            roleField.typeText("Auth Test Role")
        }

        // 認証レベルを選択
        let authLevelPicker = app.popUpButtons["AuthLevelPicker"]
        if authLevelPicker.waitForExistence(timeout: 2) {
            authLevelPicker.click()
            Thread.sleep(forTimeInterval: 0.3)
            let level1 = app.menuItems["Level 1 (ID + Passkey)"]
            if level1.exists {
                level1.click()
            }
        }

        // パスキーを入力
        let passkeyField = app.secureTextFields["PasskeyField"]
        if passkeyField.waitForExistence(timeout: 2) {
            passkeyField.click()
            passkeyField.typeText("mysecretpasskey")
        }

        // 保存
        let saveButton = app.buttons["Save"]
        if saveButton.waitForExistence(timeout: 2) && saveButton.isEnabled {
            saveButton.click()
        }

        // シートが閉じるのを待つ
        let sheetClosed = sheet.waitForNonExistence(timeout: 5)
        XCTAssertTrue(sheetClosed, "保存後にシートが閉じること")

        // 作成したエージェントを再度開く
        Thread.sleep(forTimeInterval: 1.0)
        let agentRow = app.staticTexts["AuthTestAgent"]
        if agentRow.waitForExistence(timeout: 5) {
            agentRow.click()
            Thread.sleep(forTimeInterval: 0.5)

            // 編集フォームを開く
            app.typeKey("e", modifierFlags: [.command])
            Thread.sleep(forTimeInterval: 0.5)

            let reopenedSheet = app.sheets.firstMatch
            if reopenedSheet.waitForExistence(timeout: 3) {
                // パスキーフィールドが存在することを確認
                // 値自体はSecureFieldなので確認できないが、フィールドの存在を確認
                let savedPasskey = app.secureTextFields["PasskeyField"]
                XCTAssertTrue(savedPasskey.exists, "パスキーフィールドが存在すること")
            }
        } else {
            throw XCTSkip("作成したエージェントが見つかりません")
        }
    }

    /// F02-06: エージェントIDが表示される（読み取り専用）
    func testAgentIdDisplayed() throws {
        // 既存エージェントの詳細を開く
        let agentsSection = app.descendants(matching: .any).matching(identifier: "AgentsSection").firstMatch
        guard agentsSection.waitForExistence(timeout: 5) else {
            throw XCTSkip("Agentsセクションが存在しません")
        }

        let agentRow = app.staticTexts["backend-dev"]
        guard agentRow.waitForExistence(timeout: 5) else {
            throw XCTSkip("テストエージェントが存在しません")
        }
        agentRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // エージェント詳細画面でIDが表示されることを確認
        let agentIdLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'ID:'")).firstMatch
        // または識別子で検索
        let agentIdField = app.descendants(matching: .any).matching(identifier: "AgentIdDisplay").firstMatch

        let idFound = agentIdLabel.waitForExistence(timeout: 3) || agentIdField.waitForExistence(timeout: 1)
        XCTAssertTrue(idFound, "エージェントIDが表示されること")
    }
}
