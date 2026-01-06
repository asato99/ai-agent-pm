// UITests/Feature/Feature01_AgentKickSettingsTests.swift
// Feature01: エージェントキック設定
//
// エージェント管理画面でキック方法（起動コマンド/スクリプト）を設定できる

import XCTest

/// Feature01: エージェントキック設定テスト
final class Feature01_AgentKickSettingsTests: XCTestCase {

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

    /// F01-01: エージェントフォームに「実行設定」セクションが存在
    func testKickSettingsSectionExists() throws {
        // ⌘⇧A で新規エージェント作成
        app.typeKey("a", modifierFlags: [.command, .shift])

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "エージェントフォームが表示されること")

        // 実行設定セクションの存在確認
        let kickSettingsSection = app.staticTexts["Execution Settings"]
        XCTAssertTrue(kickSettingsSection.waitForExistence(timeout: 3),
                      "「Execution Settings」セクションが存在すること")
    }

    /// F01-02: 起動方式（CLI/Script/API/Notification）を選択可能
    func testKickMethodPicker() throws {
        // ⌘⇧A で新規エージェント作成
        app.typeKey("a", modifierFlags: [.command, .shift])

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "エージェントフォームが表示されること")

        // 起動方式Pickerの存在確認
        let kickMethodPicker = app.popUpButtons["KickMethodPicker"]
        XCTAssertTrue(kickMethodPicker.waitForExistence(timeout: 3),
                      "起動方式Pickerが存在すること")

        // Pickerをクリックしてオプションを確認
        kickMethodPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        // 各オプションの存在確認
        let cliOption = app.menuItems["CLI"]
        let scriptOption = app.menuItems["Script"]
        let apiOption = app.menuItems["API"]
        let notificationOption = app.menuItems["Notification"]

        XCTAssertTrue(cliOption.exists, "CLIオプションが存在すること")
        XCTAssertTrue(scriptOption.exists, "Scriptオプションが存在すること")
        XCTAssertTrue(apiOption.exists, "APIオプションが存在すること")
        XCTAssertTrue(notificationOption.exists, "Notificationオプションが存在すること")

        // 選択してメニューを閉じる
        cliOption.click()
    }

    /// F01-03: 起動コマンド入力フィールドが存在
    func testKickCommandField() throws {
        // ⌘⇧A で新規エージェント作成
        app.typeKey("a", modifierFlags: [.command, .shift])

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "エージェントフォームが表示されること")

        // 起動コマンドフィールドの存在確認
        let kickCommandField = app.textFields["KickCommandField"]
        XCTAssertTrue(kickCommandField.waitForExistence(timeout: 3),
                      "起動コマンドフィールドが存在すること")

        // フィールドに入力可能か確認
        kickCommandField.click()
        kickCommandField.typeText("claude --headless")

        // 入力された値を確認
        XCTAssertEqual(kickCommandField.value as? String, "claude --headless",
                       "起動コマンドが入力されること")
    }

    /// F01-04: 設定が保存され、再表示時に反映されている
    func testKickSettingsSaved() throws {
        // ⌘⇧A で新規エージェント作成
        app.typeKey("a", modifierFlags: [.command, .shift])

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "エージェントフォームが表示されること")

        // 基本情報を入力
        let nameField = app.textFields["AgentNameField"]
        if nameField.waitForExistence(timeout: 2) {
            nameField.click()
            nameField.typeText("TestKickAgent")
        }

        let roleField = app.textFields["AgentRoleField"]
        if roleField.waitForExistence(timeout: 2) {
            roleField.click()
            roleField.typeText("Test Developer")
        }

        // 起動方式を選択
        let kickMethodPicker = app.popUpButtons["KickMethodPicker"]
        if kickMethodPicker.waitForExistence(timeout: 2) {
            kickMethodPicker.click()
            Thread.sleep(forTimeInterval: 0.3)
            let cliOption = app.menuItems["CLI"]
            if cliOption.exists {
                cliOption.click()
            }
        }

        // 起動コマンドを入力
        let kickCommandField = app.textFields["KickCommandField"]
        if kickCommandField.waitForExistence(timeout: 2) {
            kickCommandField.click()
            kickCommandField.typeText("claude --headless --agent-id=test")
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
        let agentRow = app.staticTexts["TestKickAgent"]
        if agentRow.waitForExistence(timeout: 5) {
            agentRow.click()
            Thread.sleep(forTimeInterval: 0.5)

            // 編集フォームを開く
            app.typeKey("e", modifierFlags: [.command])
            Thread.sleep(forTimeInterval: 0.5)

            // 設定が保存されているか確認
            let reopenedSheet = app.sheets.firstMatch
            if reopenedSheet.waitForExistence(timeout: 3) {
                let savedCommand = app.textFields["KickCommandField"]
                if savedCommand.exists {
                    let value = savedCommand.value as? String ?? ""
                    XCTAssertTrue(value.contains("claude"),
                                  "保存した起動コマンドが反映されていること")
                }
            }
        } else {
            // エージェントが見つからない場合はスキップ
            XCTFail("作成したエージェントが見つかりません")
            throw TestError.failedPrecondition("作成したエージェントが見つかりません")
        }
    }
}
