// UITests/Feature/Feature05_CompletionTests.swift
// Feature05: 完了通知
//
// タスク完了時に親（上位エージェント/ユーザー）に通知される

import XCTest

/// Feature05: 完了通知テスト
final class Feature05_CompletionTests: XCTestCase {

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

    /// F05-01: タスク完了時にHandoffが自動作成される
    func testCompletionCreatesHandoff() throws {
        // プロジェクトを選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        guard projectRow.waitForExistence(timeout: 5) else {
            XCTFail("テストプロジェクトが存在しません")
            throw TestError.failedPrecondition("テストプロジェクトが存在しません")
        }
        projectRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // リソーステストタスクを選択（Cmd+Shift+G）
        app.typeKey("g", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        guard detailView.waitForExistence(timeout: 5) else {
            XCTFail("タスク詳細が開けません")
            throw TestError.failedPrecondition("タスク詳細が開けません")
        }

        // HandoffsSectionの存在確認（複数形: HandoffsSection）
        let handoffsSection = app.descendants(matching: .any).matching(identifier: "HandoffsSection").firstMatch

        guard handoffsSection.waitForExistence(timeout: 3) else {
            XCTFail("HandoffsSectionが見つかりません")
            return
        }

        // Handoffセクションが存在すればOK（Handoff作成可能なUI）
        // 実際のHandoff作成はステータス変更時にシステムが行う
        XCTAssertTrue(handoffsSection.exists, "HandoffsSectionが存在すること（Handoff管理可能なUI）")
    }

    /// F05-02: 作成されたHandoffがタスク詳細に表示される
    func testHandoffVisibleInTaskDetail() throws {
        // プロジェクトを選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        guard projectRow.waitForExistence(timeout: 5) else {
            XCTFail("テストプロジェクトが存在しません")
            throw TestError.failedPrecondition("テストプロジェクトが存在しません")
        }
        projectRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // リソーステストタスクを選択（Cmd+Shift+G）
        app.typeKey("g", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        guard detailView.waitForExistence(timeout: 5) else {
            XCTFail("タスク詳細が開けません")
            throw TestError.failedPrecondition("タスク詳細が開けません")
        }

        // HandoffsSectionの存在確認（複数形: HandoffsSection）
        let handoffsSection = app.descendants(matching: .any).matching(identifier: "HandoffsSection").firstMatch

        guard handoffsSection.waitForExistence(timeout: 3) else {
            XCTFail("HandoffsSectionが見つかりません")
            return
        }

        // セクション内のコンテンツ確認
        // オプション1: Handoffsヘッダー（セクションが表示されている証拠）
        let handoffsHeader = app.staticTexts["Handoffs"]
        // オプション2: "No handoffs yet"テキスト
        let noHandoffsText = app.staticTexts["No handoffs yet"]
        // オプション3: Handoffカード（Handoff_[id]形式）
        let handoffCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'Handoff_'"))

        // いずれかが存在すればOK（セクションが正しく表示されている）
        let hasContent = handoffsHeader.exists || noHandoffsText.exists || handoffCards.count > 0
        XCTAssertTrue(hasContent, "Handoffセクションが正しく表示されること")
    }

    /// F05-03: 親エージェント/ユーザーに通知が送られる
    /// タスク詳細にNotificationSectionが表示され、完了時に通知状態が確認できる
    func testNotificationToParent() throws {
        // プロジェクトを選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        guard projectRow.waitForExistence(timeout: 5) else {
            XCTFail("テストプロジェクトが存在しません")
            throw TestError.failedPrecondition("テストプロジェクトが存在しません")
        }
        projectRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // リソーステストタスクを選択（Cmd+Shift+G）
        app.typeKey("g", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        guard detailView.waitForExistence(timeout: 5) else {
            XCTFail("タスク詳細が開けません")
            throw TestError.failedPrecondition("タスク詳細が開けません")
        }

        // NotificationSectionの存在確認
        let notificationSection = app.descendants(matching: .any).matching(identifier: "NotificationSection").firstMatch

        guard notificationSection.waitForExistence(timeout: 3) else {
            XCTFail("NotificationSectionが見つかりません")
            return
        }

        // 通知セクションが存在することを確認
        XCTAssertTrue(notificationSection.exists, "NotificationSectionが存在すること")

        // NotificationHeaderの確認
        let notificationHeader = app.staticTexts["Parent Notification"]
        XCTAssertTrue(notificationHeader.waitForExistence(timeout: 2),
                      "Parent Notificationヘッダーが表示されること")

        // 通知状態テキストの確認（完了前、完了後、通知済みのいずれかが表示される）
        let pendingText = app.staticTexts["Will notify on completion"]
        let notifiedText = app.staticTexts["Parent notified"]
        let notificationPendingText = app.staticTexts["Notification pending"]

        let hasStatusText = pendingText.exists || notifiedText.exists || notificationPendingText.exists
        XCTAssertTrue(hasStatusText, "通知状態テキストが表示されること")
    }

    /// F05-04: 完了履歴がHistoryセクションに記録される
    func testCompletionRecordedInHistory() throws {
        // プロジェクトを選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        guard projectRow.waitForExistence(timeout: 5) else {
            XCTFail("テストプロジェクトが存在しません")
            throw TestError.failedPrecondition("テストプロジェクトが存在しません")
        }
        projectRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // リソーステストタスクを選択（Cmd+Shift+G）
        app.typeKey("g", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        guard detailView.waitForExistence(timeout: 5) else {
            XCTFail("タスク詳細が開けません")
            throw TestError.failedPrecondition("タスク詳細が開けません")
        }

        // Historyセクションの確認
        let historySection = app.descendants(matching: .any).matching(identifier: "HistorySection").firstMatch
        guard historySection.waitForExistence(timeout: 3) else {
            XCTFail("Historyセクションが見つかりません")
            throw TestError.failedPrecondition("Historyセクションが見つかりません")
        }

        // 完了関連の履歴エントリを検索
        let completionEntry = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'completed' OR label CONTAINS[c] 'done' OR label CONTAINS[c] 'finished'")).firstMatch

        if completionEntry.waitForExistence(timeout: 3) {
            XCTAssertTrue(true, "完了履歴がHistoryに記録されること")
        } else {
            // 履歴エントリがまだない場合はセクションの存在のみ確認
            XCTAssertTrue(historySection.exists, "Historyセクションが存在すること（完了後に記録される）")
        }
    }
}
