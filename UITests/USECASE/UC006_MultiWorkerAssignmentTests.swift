// UITests/USECASE/UC006_MultiWorkerAssignmentTests.swift
// UC006: 複数ワーカーへのタスク割り当て - Runner統合テスト
//
// このテストは Runner との統合テスト用です。
// 設計: 1プロジェクト + 3エージェント（マネージャー、日本語ワーカー、中国語ワーカー）+ 1親タスク
// - マネージャーが2つのサブタスクを作成
// - 日本語タスクは日本語担当ワーカーに割り当て
// - 中国語タスクは中国語担当ワーカーに割り当て
// - 全タスクがdoneになることを検証

import XCTest

/// UC006: 複数ワーカーへのタスク割り当てテスト
///
/// シードデータ（UC006シナリオ）:
/// - プロジェクト: UC006 Translation Test (prj_uc006)
/// - マネージャーエージェント: agt_uc006_manager
/// - 日本語ワーカーエージェント: agt_uc006_ja
/// - 中国語ワーカーエージェント: agt_uc006_zh
/// - 親タスク: ドキュメントを翻訳してください (tsk_uc006_main) → マネージャーにアサイン
/// - 入力ファイル: hello.txt
/// - 認証情報: test_passkey_uc006_manager, test_passkey_uc006_ja, test_passkey_uc006_zh
final class UC006_MultiWorkerAssignmentTests: UC006UITestCase {

    /// UC006統合テスト: 親タスクをin_progressに変更し、複数ワーカーへの委任フロー完了を待つ
    ///
    /// このテストは以下を行います:
    /// 1. UC006 Translation Testプロジェクトを選択
    /// 2. 親タスク「ドキュメントを翻訳してください」をin_progressに変更
    /// 3. マネージャーが2つのサブタスクを作成してそれぞれのワーカーに委任するのを待つ
    /// 4. 各ワーカーが翻訳を実行するのを待つ
    /// 5. 親タスクがDoneになることを確認（最大300秒）
    func testMultiWorkerAssignment_ChangeMainTaskToInProgress() throws {
        let projectName = "UC006 Translation Test"
        let taskTitle = "ドキュメントを翻訳してください"
        let taskId = "tsk_uc006_main"

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
        print("⏳ Phase 2: 親タスクがDoneになるのを待機中（最大120秒）...")
        print("  期待されるフロー:")
        print("    1. マネージャーが2つのサブタスクを作成")
        print("    2. 日本語タスクを日本語担当ワーカーに割り当て")
        print("    3. 中国語タスクを中国語担当ワーカーに割り当て")
        print("    4. 各ワーカーが翻訳を実行")
        print("    5. 全タスクがdoneになる")

        var mainTaskDone = false

        // 最大180秒（10秒間隔で18回）待機
        for i in 1...18 {
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
            print("🎯 UC006 複数ワーカーへのタスク割り当てテスト: 成功")
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
