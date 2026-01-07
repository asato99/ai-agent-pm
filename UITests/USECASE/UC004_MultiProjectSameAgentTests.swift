// UITests/USECASE/UC004_MultiProjectSameAgentTests.swift
// UC004: 複数プロジェクト×同一エージェント - 統合テスト
//
// ========================================
// 設計方針:
// ========================================
// - 同一エージェントが複数プロジェクトに割り当てられることを検証
// - 各プロジェクトで異なるworking_directoryで動作することを確認
// - プロジェクト分離: 各プロジェクトのタスクが独立して管理されることを検証
// - タスク割当制約: プロジェクトに割り当てられたエージェントのみ選択可能
//
// シードデータ:
// - プロジェクト1: UC004 Frontend (prj_uc004_fe, wd=/tmp/uc004/frontend)
// - プロジェクト2: UC004 Backend (prj_uc004_be, wd=/tmp/uc004/backend)
// - エージェント: UC004開発者 (agt_uc004_dev) - 両プロジェクトに割り当て
// - タスク1: README作成（Frontend）(tsk_uc004_fe)
// - タスク2: README作成（Backend）(tsk_uc004_be)
// ========================================

import XCTest

/// UC004: 複数プロジェクト×同一エージェント - 統合テスト
///
/// 検証内容:
/// 1. 同一エージェントが複数プロジェクトに割り当て可能
/// 2. 各プロジェクトのタスクが独立して管理される
/// 3. 両プロジェクトのタスクを同時にin_progressに変更可能（並列実行の準備）
final class UC004_MultiProjectSameAgentTests: UC004UITestCase {

    /// UC004 完全E2Eテスト
    ///
    /// 1回のアプリ起動で以下の全フローを検証:
    /// 1. 両プロジェクトの存在確認
    /// 2. フロントエンドプロジェクトでタスク操作
    /// 3. バックエンドプロジェクトでタスク操作
    /// 4. 同一エージェントによる両タスクのin_progress状態確認
    func testE2E_UC004_MultiProjectSameAgent() throws {
        // ========================================
        // Phase 1: プロジェクト一覧確認
        // ========================================
        print("🔍 Phase 1: プロジェクト一覧確認")
        try verifyPhase1_ProjectListExists()
        print("✅ Phase 1完了: 両プロジェクトが存在")

        // ========================================
        // Phase 2: フロントエンドプロジェクトでタスク操作
        // ========================================
        print("🔍 Phase 2: フロントエンドプロジェクトでタスク操作")
        try verifyPhase2_FrontendProjectTask()
        print("✅ Phase 2完了: フロントエンドタスクがin_progress")

        // ========================================
        // Phase 3: バックエンドプロジェクトでタスク操作
        // ========================================
        print("🔍 Phase 3: バックエンドプロジェクトでタスク操作")
        try verifyPhase3_BackendProjectTask()
        print("✅ Phase 3完了: バックエンドタスクがin_progress")

        // ========================================
        // 完了
        // ========================================
        print("🎉 UC004 E2Eテスト完了: 同一エージェントで両プロジェクトのタスクがin_progress状態")
    }

    // MARK: - Phase 1: プロジェクト一覧確認

    private func verifyPhase1_ProjectListExists() throws {
        app.activate()
        Thread.sleep(forTimeInterval: 0.5)

        // フロントエンドプロジェクトの存在確認
        let frontendProject = app.staticTexts["UC004 Frontend"]
        XCTAssertTrue(frontendProject.waitForExistence(timeout: 10),
                      "❌ PHASE1: UC004 Frontendプロジェクトが見つからない")

        // バックエンドプロジェクトの存在確認
        let backendProject = app.staticTexts["UC004 Backend"]
        XCTAssertTrue(backendProject.waitForExistence(timeout: 5),
                      "❌ PHASE1: UC004 Backendプロジェクトが見つからない")
    }

    // MARK: - Phase 2: フロントエンドプロジェクトでタスク操作

    private func verifyPhase2_FrontendProjectTask() throws {
        let projectName = "UC004 Frontend"
        let taskTitle = "README作成（Frontend）"
        let agentName = "UC004開発者"

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

    // MARK: - Phase 3: バックエンドプロジェクトでタスク操作

    private func verifyPhase3_BackendProjectTask() throws {
        let projectName = "UC004 Backend"
        let taskTitle = "README作成（Backend）"
        let agentName = "UC004開発者"

        // プロジェクト選択
        try selectProject(projectName)

        // タスクボード表示確認
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5),
                      "❌ PHASE3: タスクボードが表示されない")

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

        // 担当エージェント確認（同一エージェント）
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
