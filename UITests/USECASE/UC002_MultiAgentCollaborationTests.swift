// UITests/USECASE/UC002_MultiAgentCollaborationTests.swift
// UC002: マルチエージェント協調テスト - Runner統合
//
// このテストは Runner との統合テスト用です。
// 2つのエージェント（詳細ライター、簡潔ライター）のタスクを
// 順番に in_progress に変更し、Runner がそれを検出して
// Claude CLI を実行することを確認します。

import XCTest

/// UC002: マルチエージェント協調テスト
///
/// シードデータ（UC002シナリオ）:
/// - 詳細ライターエージェント: agt_detailed_writer
/// - 簡潔ライターエージェント: agt_concise_writer
/// - 詳細ライター用タスク: tsk_uc002_detailed (backlog状態)
/// - 簡潔ライター用タスク: tsk_uc002_concise (backlog状態)
/// - 認証情報: passkey=test_passkey_detailed, test_passkey_concise
final class UC002_MultiAgentCollaborationTests: UC002UITestCase {

    /// UC002統合テスト: 両タスクをin_progressに変更
    ///
    /// このテストは以下を行います:
    /// 1. 詳細ライターPJを選択
    /// 2. 詳細ライタータスクをin_progressに変更
    /// 3. 簡潔ライターPJを選択
    /// 4. 簡潔ライタータスクをin_progressに変更
    ///
    /// その後、バックグラウンドの2つのRunnerがタスクを検出してCLIを実行します。
    func testMultiAgentIntegration_ChangeBothTasksToInProgress() throws {
        // ========================================
        // Phase 1: 詳細ライタータスクをin_progressに変更
        // ========================================
        print("🔍 Phase 1: 詳細ライタータスクをin_progressに変更")
        try changeTaskStatusToInProgress(
            projectName: "UC002詳細ライターPJ",
            taskTitle: "詳細プロジェクトサマリー作成"
        )
        print("✅ Phase 1完了: 詳細ライタータスクがin_progress")

        // ========================================
        // Phase 2: 簡潔ライタータスクをin_progressに変更
        // ========================================
        print("🔍 Phase 2: 簡潔ライタータスクをin_progressに変更")
        try changeTaskStatusToInProgress(
            projectName: "UC002簡潔ライターPJ",
            taskTitle: "簡潔プロジェクトサマリー作成"
        )
        print("✅ Phase 2完了: 簡潔ライタータスクがin_progress")

        print("🎯 UC002 マルチエージェント統合テスト: 両タスクがin_progress状態になりました")
    }

    // MARK: - Helper Methods

    /// プロジェクトを選択してタスクをin_progressに変更
    private func changeTaskStatusToInProgress(projectName: String, taskTitle: String) throws {
        // #1: プロジェクト選択
        print("  🔍 プロジェクト「\(projectName)」を検索中...")
        let projectRow = app.staticTexts[projectName]
        guard projectRow.waitForExistence(timeout: 10) else {
            // デバッグ: 利用可能なstaticTextsを出力
            let allTexts = app.staticTexts.allElementsBoundByIndex.prefix(20).map { $0.label }
            print("  ⚠️ 利用可能なstaticTexts: \(allTexts)")
            XCTFail("❌ SETUP: プロジェクト「\(projectName)」が見つからない")
            return
        }
        print("  ✅ プロジェクト「\(projectName)」が見つかりました")
        projectRow.click()
        Thread.sleep(forTimeInterval: 1.0)

        // #2: タスクボードの表示を確認
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5),
                      "❌ SETUP: タスクボードが表示されない")

        // Refreshボタンをクリックしてタスクボードを更新
        let refreshButton = app.buttons.matching(identifier: "RefreshButton").firstMatch
        if refreshButton.waitForExistence(timeout: 2) {
            print("  🔄 Refreshボタンをクリック")
            refreshButton.click()
            Thread.sleep(forTimeInterval: 2.0)
        } else {
            // タスクボードの内容が更新されるのを待つ
            Thread.sleep(forTimeInterval: 2.0)
        }

        // #3: タスクを探す
        print("  🔍 タスク「\(taskTitle)」を検索中...")

        // デバッグ: 利用可能な要素を出力
        let allButtons = app.buttons.allElementsBoundByIndex.prefix(20).map { $0.label }
        let allTexts = app.staticTexts.allElementsBoundByIndex.prefix(30).map { $0.label }
        print("  📋 利用可能なbuttons: \(allButtons)")
        print("  📋 利用可能なstaticTexts: \(allTexts)")

        let taskCard = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", taskTitle)).firstMatch
        guard taskCard.waitForExistence(timeout: 5) else {
            XCTFail("❌ STEP1: タスク「\(taskTitle)」が見つからない")
            return
        }
        print("  ✅ タスク「\(taskTitle)」が見つかりました")

        // #4: タスク詳細を開く
        taskCard.click()
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "❌ STEP2: タスク詳細画面が開かない")

        // #5: ステータスピッカーを確認
        let statusPicker = app.popUpButtons["StatusPicker"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 3),
                      "❌ STEP3: StatusPickerが見つからない")

        let beforeValue = statusPicker.value as? String ?? ""
        print("  変更前ステータス: \(beforeValue)")

        // #6: backlog → todo → in_progress と順番に変更
        if beforeValue == "Backlog" {
            // Backlog → To Do
            statusPicker.click()
            Thread.sleep(forTimeInterval: 0.3)

            let todoOption = app.menuItems["To Do"]
            XCTAssertTrue(todoOption.waitForExistence(timeout: 2),
                          "❌ STEP4: To Doオプションが見つからない")
            todoOption.click()
            Thread.sleep(forTimeInterval: 0.5)

            // エラーチェック
            let alertSheet = app.sheets.firstMatch
            if alertSheet.waitForExistence(timeout: 1) {
                let okButton = alertSheet.buttons["OK"]
                if okButton.exists { okButton.click() }
                XCTFail("❌ STEP4: Backlog → To Do のステータス変更がブロックされた")
                return
            }

            print("  ✅ Backlog → To Do 完了")
            Thread.sleep(forTimeInterval: 0.5)
        }

        // #7: To Do → In Progress
        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        let inProgressOption = app.menuItems["In Progress"]
        XCTAssertTrue(inProgressOption.waitForExistence(timeout: 2),
                      "❌ STEP5: In Progressオプションが見つからない")
        inProgressOption.click()
        Thread.sleep(forTimeInterval: 0.5)

        // エラーチェック
        let alertSheet2 = app.sheets.firstMatch
        if alertSheet2.waitForExistence(timeout: 1) {
            let okButton = alertSheet2.buttons["OK"]
            if okButton.exists { okButton.click() }
            XCTFail("❌ STEP5: To Do → In Progress のステータス変更がブロックされた")
            return
        }

        // #8: ステータス変更の確認
        let afterValue = statusPicker.value as? String
        XCTAssertEqual(afterValue, "In Progress",
                       "❌ STEP6: ステータスがIn Progressになっていない（実際の値: \(afterValue ?? "nil")）")

        print("  ✅ ステータスをIn Progressに変更完了")

        // #9: 詳細画面を閉じる
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 1.0)

        // 詳細画面が閉じたことを確認
        let detailViewClosed = !detailView.exists || detailView.waitForNonExistence(timeout: 3)
        if !detailViewClosed {
            print("  ⚠️ 詳細画面がまだ表示されている、再度Escapeを試行")
            app.typeKey(.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 1.0)
        }
    }
}
