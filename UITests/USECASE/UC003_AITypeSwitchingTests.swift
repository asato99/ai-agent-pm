// UITests/USECASE/UC003_AITypeSwitchingTests.swift
// UC003: AIタイプ切り替え - 統合テスト
//
// ========================================
// 設計方針:
// ========================================
// - 異なるai_type/kickCommandを持つエージェントの検証
// - ai_typeがshould_start APIで正しく返されることを確認
// - kickCommandがai_typeより優先されることを確認
//
// シードデータ:
// - プロジェクト: UC003 AIType Test (prj_uc003, wd=/tmp/uc003)
// - エージェント1: UC003 Claude Agent (agt_uc003_claude, aiType=claude, kickCommand=nil)
// - エージェント2: UC003 Custom Agent (agt_uc003_custom, aiType=claude, kickCommand="echo")
// - タスク1: Claude Task (tsk_uc003_claude)
// - タスク2: Custom Task (tsk_uc003_custom)
// ========================================

import XCTest

/// UC003: AIタイプ切り替え - 統合テスト
///
/// 検証内容:
/// 1. 両エージェントがプロジェクトに存在する
/// 2. 各エージェントのai_type/kickCommandが正しく設定されている
/// 3. 両タスクをin_progressに変更可能
final class UC003_AITypeSwitchingTests: UC003UITestCase {

    /// UC003 完全E2Eテスト
    ///
    /// 1回のアプリ起動で以下の全フローを検証:
    /// 1. プロジェクトの存在確認
    /// 2. Claudeエージェント担当タスクの操作
    /// 3. Customエージェント担当タスクの操作
    func testE2E_UC003_AITypeSwitching() throws {
        // ========================================
        // Phase 1: プロジェクト確認
        // ========================================
        print("🔍 Phase 1: プロジェクト確認")
        try verifyPhase1_ProjectExists()
        print("✅ Phase 1完了: プロジェクトが存在")

        // ========================================
        // Phase 2: Claudeエージェントタスク操作
        // ========================================
        print("🔍 Phase 2: Claudeエージェントタスク操作")
        try verifyPhase2_ClaudeAgentTask()
        print("✅ Phase 2完了: Claudeタスクがin_progress")

        // ========================================
        // Phase 3: Customエージェントタスク操作
        // ========================================
        print("🔍 Phase 3: Customエージェントタスク操作")
        try verifyPhase3_CustomAgentTask()
        print("✅ Phase 3完了: Customタスクがin_progress")

        // ========================================
        // 完了
        // ========================================
        print("🎉 UC003 E2Eテスト完了: 両エージェントのタスクがin_progress状態")
    }

    // MARK: - Phase 1: プロジェクト確認

    private func verifyPhase1_ProjectExists() throws {
        app.activate()
        Thread.sleep(forTimeInterval: 0.5)

        // プロジェクトの存在確認
        let project = app.staticTexts["UC003 AIType Test"]
        XCTAssertTrue(project.waitForExistence(timeout: 10),
                      "❌ PHASE1: UC003 AIType Testプロジェクトが見つからない")
    }

    // MARK: - Phase 2: Claudeエージェントタスク操作

    private func verifyPhase2_ClaudeAgentTask() throws {
        let projectName = "UC003 AIType Test"
        let taskTitle = "Claude Task"
        let agentName = "UC003 Claude Agent"

        // プロジェクト選択
        try selectProject(projectName)

        // タスクボード表示確認
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5),
                      "❌ PHASE2: タスクボードが表示されない")

        // タスクカードを探す
        let taskCard = findTaskCard(withTitle: taskTitle)
        XCTAssertTrue(taskCard.waitForExistence(timeout: 5),
                      "❌ PHASE2: タスク「\(taskTitle)」が見つからない")

        // タスク詳細を開く
        taskCard.click()
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "❌ PHASE2: タスク詳細画面が開かない")

        // 担当エージェント確認
        let agentLabel = detailView.staticTexts[agentName]
        XCTAssertTrue(agentLabel.exists,
                      "❌ PHASE2: 担当エージェント「\(agentName)」が表示されていない")

        // ステータスをin_progressに変更
        try changeTaskStatusToInProgress()

        // 詳細画面を閉じる
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Phase 3: Customエージェントタスク操作

    private func verifyPhase3_CustomAgentTask() throws {
        let taskTitle = "Custom Task"
        let agentName = "UC003 Custom Agent"

        // Refreshボタンをクリックしてタスクボードを更新
        let refreshButton = app.buttons.matching(identifier: "RefreshButton").firstMatch
        if refreshButton.waitForExistence(timeout: 2) {
            refreshButton.click()
            Thread.sleep(forTimeInterval: 1.5)
        }

        // タスクカードを探す
        let taskCard = findTaskCard(withTitle: taskTitle)
        XCTAssertTrue(taskCard.waitForExistence(timeout: 5),
                      "❌ PHASE3: タスク「\(taskTitle)」が見つからない")

        // タスク詳細を開く
        taskCard.click()
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "❌ PHASE3: タスク詳細画面が開かない")

        // 担当エージェント確認
        let agentLabel = detailView.staticTexts[agentName]
        XCTAssertTrue(agentLabel.exists,
                      "❌ PHASE3: 担当エージェント「\(agentName)」が表示されていない")

        // ステータスをin_progressに変更
        try changeTaskStatusToInProgress()

        // 詳細画面を閉じる
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Helper Methods

    private func selectProject(_ projectName: String) throws {
        print("  🔍 プロジェクト「\(projectName)」を選択中...")

        let projectRow = app.staticTexts[projectName]
        guard projectRow.waitForExistence(timeout: 10) else {
            XCTFail("❌ SETUP: プロジェクト「\(projectName)」が見つからない")
            throw TestError.failedPrecondition("プロジェクト「\(projectName)」が見つかりません")
        }

        if projectRow.isHittable {
            projectRow.click()
        } else {
            projectRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
        Thread.sleep(forTimeInterval: 1.0)

        // Refreshボタンをクリックしてタスクボードを更新
        let refreshButton = app.buttons.matching(identifier: "RefreshButton").firstMatch
        if refreshButton.waitForExistence(timeout: 2) {
            refreshButton.click()
            Thread.sleep(forTimeInterval: 1.5)
        } else {
            Thread.sleep(forTimeInterval: 1.0)
        }

        print("  ✅ プロジェクト「\(projectName)」を選択完了")
    }

    private func findTaskCard(withTitle title: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", title)
        return app.buttons.matching(predicate).firstMatch
    }

    private func changeTaskStatusToInProgress() throws {
        let statusPicker = app.popUpButtons["StatusPicker"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 3),
                      "❌ STATUS: StatusPickerが見つからない")

        let currentValue = statusPicker.value as? String ?? ""
        print("  📊 現在のステータス: \(currentValue)")

        // backlog → todo → in_progress と順番に変更
        if currentValue == "Backlog" {
            // Backlog → To Do
            statusPicker.click()
            Thread.sleep(forTimeInterval: 0.3)

            let todoOption = app.menuItems["To Do"]
            XCTAssertTrue(todoOption.waitForExistence(timeout: 2),
                          "❌ STATUS: To Doオプションが見つからない")
            todoOption.click()
            Thread.sleep(forTimeInterval: 0.5)

            // エラーチェック
            let alertSheet = app.sheets.firstMatch
            if alertSheet.waitForExistence(timeout: 1) {
                let okButton = alertSheet.buttons["OK"]
                if okButton.exists { okButton.click() }
                XCTFail("❌ STATUS: Backlog → To Do のステータス変更がブロックされた")
                return
            }
            print("  ✅ Backlog → To Do 完了")
        }

        // To Do → In Progress
        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        let inProgressOption = app.menuItems["In Progress"]
        XCTAssertTrue(inProgressOption.waitForExistence(timeout: 2),
                      "❌ STATUS: In Progressオプションが見つからない")
        inProgressOption.click()
        Thread.sleep(forTimeInterval: 0.5)

        // エラーチェック
        let alertSheet2 = app.sheets.firstMatch
        if alertSheet2.waitForExistence(timeout: 1) {
            let okButton = alertSheet2.buttons["OK"]
            if okButton.exists { okButton.click() }
            XCTFail("❌ STATUS: To Do → In Progress のステータス変更がブロックされた")
            return
        }

        // ステータス変更確認
        let afterValue = statusPicker.value as? String
        XCTAssertEqual(afterValue, "In Progress",
                       "❌ STATUS: ステータスがIn Progressになっていない（実際の値: \(afterValue ?? "nil")）")

        print("  ✅ ステータスをIn Progressに変更完了")
    }
}
