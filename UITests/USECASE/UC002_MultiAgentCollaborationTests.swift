// UITests/USECASE/UC002_MultiAgentCollaborationTests.swift
// UC002: マルチエージェント協調テスト - Runner統合
//
// このテストは Runner との統合テスト用です。
// 設計A: 1プロジェクト + 2タスク（同一内容、異なるエージェント）
// - 同じタスク指示で異なるsystem_promptによる出力差異を検証
// - 両タスクを in_progress に変更し、Runner がそれを検出して
//   Claude CLI を実行することを確認します。

import XCTest

/// UC002: マルチエージェント協調テスト
///
/// シードデータ（UC002シナリオ）:
/// - プロジェクト: UC002マルチエージェントテストPJ (prj_uc002_test)
/// - 詳細ライターエージェント: agt_detailed_writer
/// - 簡潔ライターエージェント: agt_concise_writer
/// - タスク1: プロジェクトサマリー作成 (tsk_uc002_detailed) → 詳細ライターにアサイン
/// - タスク2: プロジェクトサマリー作成 (tsk_uc002_concise) → 簡潔ライターにアサイン
/// - 認証情報: passkey=test_passkey_detailed, test_passkey_concise
final class UC002_MultiAgentCollaborationTests: UC002UITestCase {

    /// UC002統合テスト: 同一プロジェクト内の両タスクをin_progressに変更
    ///
    /// このテストは以下を行います:
    /// 1. UC002マルチエージェントテストPJを選択
    /// 2. 詳細ライター担当タスクをin_progressに変更
    /// 3. 簡潔ライター担当タスクをin_progressに変更
    ///
    /// 両タスクは同一のタイトル・指示内容を持ち、異なるエージェントにアサインされている。
    /// これにより「同じタスク指示でも、system_promptによって成果物が異なる」ことを検証。
    func testMultiAgentIntegration_ChangeBothTasksToInProgress() throws {
        let projectName = "UC002マルチエージェントテストPJ"

        // ========================================
        // プロジェクト選択
        // ========================================
        print("🔍 プロジェクト「\(projectName)」を選択")
        try selectProject(projectName)

        // ========================================
        // Phase 1: 詳細ライター担当タスクをin_progressに変更
        // ========================================
        print("🔍 Phase 1: 詳細ライター担当タスクをin_progressに変更")
        try changeTaskStatusToInProgress(assigneeName: "詳細ライター")
        print("✅ Phase 1完了: 詳細ライタータスクがin_progress")

        // ========================================
        // Phase 2: 簡潔ライター担当タスクをin_progressに変更
        // ========================================
        print("🔍 Phase 2: 簡潔ライター担当タスクをin_progressに変更")
        try changeTaskStatusToInProgress(assigneeName: "簡潔ライター")
        print("✅ Phase 2完了: 簡潔ライタータスクがin_progress")

        print("🎯 UC002 マルチエージェント統合テスト: 両タスクがin_progress状態になりました")
    }

    // MARK: - Helper Methods

    /// プロジェクトを選択
    private func selectProject(_ projectName: String) throws {
        print("  🔍 プロジェクト「\(projectName)」を検索中...")
        let projectRow = app.staticTexts[projectName]
        guard projectRow.waitForExistence(timeout: 10) else {
            let allTexts = app.staticTexts.allElementsBoundByIndex.prefix(20).map { $0.label }
            print("  ⚠️ 利用可能なstaticTexts: \(allTexts)")
            XCTFail("❌ SETUP: プロジェクト「\(projectName)」が見つからない")
            return
        }
        print("  ✅ プロジェクト「\(projectName)」が見つかりました")
        projectRow.click()
        Thread.sleep(forTimeInterval: 1.0)

        // タスクボードの表示を確認
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
            Thread.sleep(forTimeInterval: 2.0)
        }
    }

    /// 指定されたassignee名を持つタスクをin_progressに変更
    private func changeTaskStatusToInProgress(assigneeName: String) throws {
        // タスクカードはラベルに "assigned to [エージェント名]" を含む
        print("  🔍 「\(assigneeName)」担当タスクを検索中...")

        // デバッグ: 利用可能な要素を出力
        let allButtons = app.buttons.allElementsBoundByIndex.prefix(25).map { $0.label }
        print("  📋 利用可能なbuttons: \(allButtons)")

        // タスクカードを探す（assignee名で検索）
        let taskCard = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", assigneeName)).firstMatch
        guard taskCard.waitForExistence(timeout: 5) else {
            XCTFail("❌ STEP1: 「\(assigneeName)」担当タスクが見つからない")
            return
        }
        print("  ✅ 「\(assigneeName)」担当タスクが見つかりました: \(taskCard.label)")

        // タスク詳細を開く
        taskCard.click()
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "❌ STEP2: タスク詳細画面が開かない")

        // ステータスピッカーを確認
        let statusPicker = app.popUpButtons["StatusPicker"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 3),
                      "❌ STEP3: StatusPickerが見つからない")

        let beforeValue = statusPicker.value as? String ?? ""
        print("  変更前ステータス: \(beforeValue)")

        // backlog → todo → in_progress と順番に変更
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

        // To Do → In Progress
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

        // ステータス変更の確認
        let afterValue = statusPicker.value as? String
        XCTAssertEqual(afterValue, "In Progress",
                       "❌ STEP6: ステータスがIn Progressになっていない（実際の値: \(afterValue ?? "nil")）")

        print("  ✅ ステータスをIn Progressに変更完了")

        // 詳細画面を閉じる
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 1.0)

        // 詳細画面が閉じたことを確認
        let detailViewClosed = !detailView.exists || detailView.waitForNonExistence(timeout: 3)
        if !detailViewClosed {
            print("  ⚠️ 詳細画面がまだ表示されている、再度Escapeを試行")
            app.typeKey(.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 1.0)
        }

        // タスクボードを再度Refreshして更新を反映（次のタスク検索のため）
        let refreshButton = app.buttons.matching(identifier: "RefreshButton").firstMatch
        if refreshButton.waitForExistence(timeout: 2) {
            refreshButton.click()
            Thread.sleep(forTimeInterval: 1.5)
        }
    }
}
