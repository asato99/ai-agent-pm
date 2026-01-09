// UITests/USECASE/UC005_ManagerWorkerDelegationTests.swift
// UC005: マネージャー→ワーカー委任 - Runner統合テスト
//
// このテストは Runner との統合テスト用です。
// 設計: 1プロジェクト + 2エージェント（マネージャー、ワーカー）+ 1親タスク
// - マネージャーがサブタスクを作成してワーカーに委任
// - ワーカーがサブサブタスクを作成して実行
// - 全タスクがdoneになることを検証

import XCTest

/// UC005: マネージャー→ワーカー委任テスト
///
/// シードデータ（UC005シナリオ）:
/// - プロジェクト: UC005 Manager Test (prj_uc005)
/// - マネージャーエージェント: agt_uc005_manager
/// - ワーカーエージェント: agt_uc005_worker
/// - 親タスク: READMEを作成 (tsk_uc005_main) → マネージャーにアサイン
/// - 認証情報: test_passkey_uc005_manager, test_passkey_uc005_worker
final class UC005_ManagerWorkerDelegationTests: UC005UITestCase {

    /// UC005統合テスト: 親タスクをin_progressに変更し、委任フロー完了を待つ
    ///
    /// このテストは以下を行います:
    /// 1. UC005 Manager Testプロジェクトを選択
    /// 2. 親タスク「READMEを作成」をin_progressに変更
    /// 3. マネージャーがサブタスクを作成してワーカーに委任するのを待つ
    /// 4. ワーカーがサブサブタスクを作成して実行するのを待つ
    /// 5. 親タスクがDoneになることを確認（最大240秒）
    func testManagerWorkerDelegation_ChangeMainTaskToInProgress() throws {
        let projectName = "UC005 Manager Test"
        let taskTitle = "READMEを作成"
        let taskId = "tsk_uc005_main"

        // ========================================
        // Phase 1: プロジェクト選択とタスクをin_progressに変更
        // ========================================
        print("🔍 Phase 1: プロジェクト「\(projectName)」を選択し、タスクをin_progressに変更")
        try selectProject(projectName)
        try changeTaskStatusToInProgress(taskId: taskId, taskTitle: taskTitle)
        print("✅ Phase 1完了: メインタスクがin_progress（マネージャー起動済み）")

        // ========================================
        // Phase 2: 親タスクがDoneになるのを待機
        // ========================================
        print("⏳ Phase 2: 親タスクがDoneになるのを待機中（最大240秒）...")
        print("  期待されるフロー:")
        print("    1. マネージャーがサブタスクを作成してワーカーに委任")
        print("    2. ワーカーがサブサブタスクを作成して実行")
        print("    3. 全タスクがdoneになる")

        var mainTaskDone = false

        // 最大240秒（5秒間隔で48回）待機
        for i in 1...48 {
            if try checkTaskStatusIsDone(taskId: taskId, taskTitle: taskTitle) {
                print("✅ メインタスクがDoneになりました")
                mainTaskDone = true
                break
            }

            if i % 6 == 0 {
                print("  ⏳ 待機中... (\(i * 5)秒)")
            }

            Thread.sleep(forTimeInterval: 5.0)
        }

        // ========================================
        // 結果検証
        // ========================================
        XCTAssertTrue(mainTaskDone, "❌ メインタスクがDoneになりませんでした")

        if mainTaskDone {
            print("🎯 UC005 マネージャー→ワーカー委任テスト: 成功")
            print("  - メインタスク: Done ✅")
        }
    }

    // MARK: - Helper Methods

    /// プロジェクトを選択
    private func selectProject(_ projectName: String) throws {
        print("  🔍 プロジェクト「\(projectName)」を検索中...")

        app.activate()
        Thread.sleep(forTimeInterval: 1.0)

        let projectRow = app.staticTexts[projectName]
        guard projectRow.waitForExistence(timeout: 10) else {
            XCTFail("❌ SETUP: プロジェクト「\(projectName)」が見つからない")
            return
        }
        print("  ✅ プロジェクト「\(projectName)」が見つかりました")
        projectRow.click()
        Thread.sleep(forTimeInterval: 1.0)

        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5),
                      "❌ SETUP: タスクボードが表示されない")
        Thread.sleep(forTimeInterval: 1.0)
    }

    /// タスクをin_progressに変更
    private func changeTaskStatusToInProgress(taskId: String, taskTitle: String) throws {
        print("  🔍 タスク「\(taskTitle)」(ID: \(taskId)) を検索中...")

        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        guard taskBoard.waitForExistence(timeout: 5) else {
            XCTFail("❌ TaskBoardが見つかりません")
            return
        }

        // Backlogカラムを表示
        taskBoard.swipeRight()
        taskBoard.swipeRight()
        Thread.sleep(forTimeInterval: 0.5)

        // タスクカードを検索
        let taskCardIdentifier = "TaskCard_\(taskId)"
        let taskCard = app.descendants(matching: .any).matching(identifier: taskCardIdentifier).firstMatch

        guard taskCard.waitForExistence(timeout: 5) else {
            XCTFail("❌ STEP1: タスク「\(taskTitle)」が見つからない")
            return
        }
        print("  ✅ タスク「\(taskTitle)」が見つかりました")

        taskCard.click()
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "❌ STEP2: タスク詳細画面が開かない")

        let statusPicker = app.popUpButtons["StatusPicker"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 3),
                      "❌ STEP3: StatusPickerが見つからない")

        let beforeValue = statusPicker.value as? String ?? ""
        print("  変更前ステータス: \(beforeValue)")

        // backlog → todo → in_progress
        if beforeValue == "Backlog" {
            statusPicker.click()
            Thread.sleep(forTimeInterval: 0.3)

            let todoOption = app.menuItems["To Do"]
            XCTAssertTrue(todoOption.waitForExistence(timeout: 2),
                          "❌ STEP4: To Doオプションが見つからない")
            todoOption.click()
            Thread.sleep(forTimeInterval: 0.5)

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

        let alertSheet2 = app.sheets.firstMatch
        if alertSheet2.waitForExistence(timeout: 1) {
            let okButton = alertSheet2.buttons["OK"]
            if okButton.exists { okButton.click() }
            XCTFail("❌ STEP5: To Do → In Progress のステータス変更がブロックされた")
            return
        }

        let afterValue = statusPicker.value as? String
        XCTAssertEqual(afterValue, "In Progress",
                       "❌ STEP6: ステータスがIn Progressになっていない")

        print("  ✅ ステータスをIn Progressに変更完了")

        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 1.0)
    }

    /// タスクのステータスがDoneかどうかを確認
    private func checkTaskStatusIsDone(taskId: String, taskTitle: String) throws -> Bool {
        app.activate()

        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        guard taskBoard.waitForExistence(timeout: 5) else {
            print("  ❌ TaskBoardが見つかりません")
            return false
        }

        // Refresh
        let refreshButton = app.buttons.matching(identifier: "RefreshButton").firstMatch
        if refreshButton.waitForExistence(timeout: 2) {
            refreshButton.click()
            Thread.sleep(forTimeInterval: 1.5)
        }

        // Doneカラムを表示
        taskBoard.swipeLeft()
        taskBoard.swipeLeft()
        Thread.sleep(forTimeInterval: 0.5)

        // タスクカードを検索
        let taskCardId = "TaskCard_\(taskId)"
        let taskCard = app.descendants(matching: .any).matching(identifier: taskCardId).firstMatch
        if taskCard.exists {
            // Doneカラムの位置を取得
            let doneColumns = app.descendants(matching: .any).matching(identifier: "TaskColumn_done").allElementsBoundByIndex
            for col in doneColumns where col.frame.width > 100 {
                let doneFrame = col.frame
                let taskFrame = taskCard.frame

                if taskFrame.origin.x >= doneFrame.origin.x - 50 &&
                   taskFrame.origin.x < doneFrame.origin.x + doneFrame.width + 50 {
                    print("  ✅ タスク「\(taskTitle)」がDoneカラム内で見つかりました")
                    return true
                }
            }
        }

        print("  ❌ タスク「\(taskTitle)」がDoneカラムにありません")
        return false
    }
}
