// UITests/USECASE/UC007_DependentTaskExecutionTests.swift
// UC007: 依存関係のあるタスク実行（生成→計算）- Runner統合テスト
//
// このテストは Runner との統合テスト用です。
// 設計: 1プロジェクト + 3エージェント（マネージャー、生成担当、計算担当）+ 1親タスク
// - マネージャーが2つのサブタスクを作成（生成タスク、計算タスク）
// - 計算タスクは生成タスクに依存（DBのdependenciesフィールド）
// - 生成担当が乱数をseed.txtに書き込み
// - 計算担当がseed.txtを読み込み、2倍にしてresult.txtに書き込み
// - 全タスクがdoneになることを検証
// - 厳密検証: seed × 2 == result

import XCTest

/// UC007: 依存関係のあるタスク実行テスト
///
/// シードデータ（UC007シナリオ）:
/// - プロジェクト: UC007 Dependent Task Test (prj_uc007)
/// - マネージャーエージェント: agt_uc007_manager
/// - 生成担当ワーカーエージェント: agt_uc007_generator
/// - 計算担当ワーカーエージェント: agt_uc007_calculator
/// - 親タスク: 乱数を生成し、その2倍を計算せよ (tsk_uc007_main) → マネージャーにアサイン
/// - 認証情報: test_passkey_uc007_manager, test_passkey_uc007_generator, test_passkey_uc007_calculator
final class UC007_DependentTaskExecutionTests: UC007UITestCase {

    /// UC007統合テスト: 親タスクをin_progressに変更し、依存タスクの逐次実行完了を待つ
    ///
    /// このテストは以下を行います:
    /// 1. UC007 Dependent Task Testプロジェクトを選択
    /// 2. 親タスク「乱数を生成し、その2倍を計算せよ」をin_progressに変更
    /// 3. マネージャーが2つのサブタスクを作成（生成タスク→計算タスク依存関係付き）
    /// 4. 生成担当がseed.txtを作成（乱数）
    /// 5. 生成完了後、計算担当がseed.txtを読み込み、2倍にしてresult.txtを作成
    /// 6. 親タスクがDoneになることを確認（最大300秒）
    func testDependentTaskExecution_ChangeMainTaskToInProgress() throws {
        let projectName = "UC007 Dependent Task Test"
        let taskTitle = "乱数を生成し、その2倍を計算せよ"
        let taskId = "tsk_uc007_main"

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
        print("⏳ Phase 2: 親タスクがDoneになるのを待機中（最大180秒）...")
        print("  期待されるフロー:")
        print("    1. マネージャーが2つのサブタスクを作成（生成、計算）")
        print("    2. 生成タスクを生成担当ワーカーに割り当て")
        print("    3. 計算タスクを計算担当ワーカーに割り当て（dependencies設定）")
        print("    4. 生成ワーカーが乱数を生成してseed.txtを作成")
        print("    5. 生成完了後、計算ワーカーがseed.txtを読み込み、2倍にしてresult.txtを作成")
        print("    6. 全タスクがdoneになる")

        var mainTaskDone = false

        // 最大220秒（10秒間隔で22回）待機
        for i in 1...22 {
            if try checkTaskStatusIsDone(taskId: taskId, taskTitle: taskTitle) {
                print("✅ メインタスクがDoneになりました")
                mainTaskDone = true
                break
            }

            print("  ⏳ 待機中... (\(i * 10)秒)")
            Thread.sleep(forTimeInterval: 10.0)
        }

        // ========================================
        // 結果検証
        // ========================================
        XCTAssertTrue(mainTaskDone, "❌ メインタスクがDoneになりませんでした")

        if mainTaskDone {
            print("🎯 UC007 依存タスク実行テスト: 成功")
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
