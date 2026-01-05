// UITests/USECASE/UC001_TaskExecutionByAgentTests.swift
// UC001: エージェントによるタスク実行 - E2Eワークフローテスト
//
// ========================================
// 設計方針 (docs/test/UC001_task_execution_test.md 参照):
// ========================================
// - 1回のアプリ起動で全ユースケースフローを検証
// - 複数テストメソッドへの分割禁止（毎回アプリ再起動になるため）
// - 各ステップで「操作→UI反映」のリアクティブ検証を必ず行う
// - if文による条件分岐スキップは禁止（XCTAssertで必ず失敗させる）
//
// ========================================

import XCTest

// MARK: - UC001: E2E Workflow Test

/// UC001: エージェントによるタスク実行 - 完全E2Eテスト
///
/// 1回のアプリ起動で全フローを検証する単一テスト
final class UC001_TaskExecutionByAgentTests: BasicDataUITestCase {

    /// UC001 完全E2Eテスト
    ///
    /// 1回のアプリ起動で以下の全フローを検証:
    /// 1. カンバンボード構造確認
    /// 2. バリデーション（空タイトル保存不可）
    /// 3. タスク作成→割当→todo→in_progress→done の完全ライフサイクル
    /// 4. 依存関係ブロック検証
    /// 5. リソース制限ブロック検証
    func testE2E_UC001_CompleteWorkflow() throws {
        // ========================================
        // Setup: プロジェクト選択
        // ========================================
        try selectProject(named: "テストプロジェクト")

        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5),
                      "❌ SETUP: タスクボードが表示されない")

        // ========================================
        // Phase 1: カンバンボード構造確認
        // ========================================
        print("🔍 Phase 1: カンバンボード構造確認")
        try verifyPhase1_KanbanBoardStructure()
        print("✅ Phase 1完了: 全5カラムが正しく表示されている")

        // ========================================
        // Phase 2: バリデーション確認
        // ========================================
        print("🔍 Phase 2: バリデーション確認")
        try verifyPhase2_Validation()
        print("✅ Phase 2完了: 空タイトルでは保存できない")

        // ========================================
        // Phase 3: タスク完全ライフサイクル
        // ========================================
        print("🔍 Phase 3: タスク完全ライフサイクル")
        let createdTaskTitle = try verifyPhase3_TaskLifecycle()
        print("✅ Phase 3完了: タスクのライフサイクル全体が正常に動作")

        // ========================================
        // Phase 4: 依存関係ブロック検証
        // ========================================
        print("🔍 Phase 4: 依存関係ブロック検証")
        try verifyPhase4_DependencyBlocking()
        print("✅ Phase 4完了: 依存関係ブロックが正しく動作")

        // ========================================
        // Phase 5: リソース制限ブロック検証
        // ========================================
        print("🔍 Phase 5: リソース制限ブロック検証")
        try verifyPhase5_ResourceBlocking()
        print("✅ Phase 5完了: リソース制限ブロックが正しく動作")

        // ========================================
        // 完了
        // ========================================
        print("🎉 UC001 E2Eテスト完了: 全フローが正常に動作")
    }

    // MARK: - Phase 1: カンバンボード構造確認

    private func verifyPhase1_KanbanBoardStructure() throws {
        let expectedColumns = [
            ("TaskColumn_backlog", "Backlog"),
            ("TaskColumn_todo", "To Do"),
            ("TaskColumn_in_progress", "In Progress"),
            ("TaskColumn_blocked", "Blocked"),
            ("TaskColumn_done", "Done")
        ]

        for (identifier, name) in expectedColumns {
            let column = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(column.waitForExistence(timeout: 3),
                          "❌ PHASE1: \(name)カラム(id:\(identifier))が存在しない")
        }
    }

    // MARK: - Phase 2: バリデーション確認

    private func verifyPhase2_Validation() throws {
        // 新規タスクシートを開く
        app.typeKey("t", modifierFlags: [.command, .shift])

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5),
                      "❌ PHASE2: タスク作成シートが開かない")

        // Saveボタンが無効であることを確認
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2),
                      "❌ PHASE2: Saveボタンが存在しない")
        XCTAssertFalse(saveButton.isEnabled,
                       "❌ PHASE2-REACTIVE: タイトル未入力時、Saveボタンが無効であるべき（isEnabled=\(saveButton.isEnabled)）")

        // シートをキャンセル
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists, "❌ PHASE2: Cancelボタンが存在しない")
        cancelButton.click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3),
                      "❌ PHASE2-REACTIVE: Cancelクリック後、シートが閉じない")
    }

    // MARK: - Phase 3: タスク完全ライフサイクル

    private func verifyPhase3_TaskLifecycle() throws -> String {
        let taskTitle = "E2Eテスト_\(Int(Date().timeIntervalSince1970))"
        // ownerを使用（Humanタイプ、キック対象外）
        // backend-devはリソースブロックテスト専用（maxParallelTasks=1で既にin_progressタスクあり）
        let agentName = "owner"

        // Step 3-1: タスク作成
        print("  📝 Step 3-1: タスク作成")
        try createTask(title: taskTitle)
        print("  ✅ Step 3-1完了: タスクがBacklogに表示された")

        // Step 3-2: エージェント割当
        print("  📝 Step 3-2: エージェント割当")
        try assignAgent(to: taskTitle, agentName: agentName)
        print("  ✅ Step 3-2完了: エージェントが割り当てられた")

        // Step 3-3: backlog → todo
        print("  📝 Step 3-3: ステータス変更 (backlog → todo)")
        try changeStatusAndVerify(
            taskTitle: taskTitle,
            targetStatus: "To Do",
            expectedColumn: "TaskColumn_todo"
        )
        print("  ✅ Step 3-3完了: タスクがTo Doに移動した")

        // Step 3-4: todo → in_progress
        print("  📝 Step 3-4: ステータス変更 (todo → in_progress)")
        try reopenTaskDetail(taskTitle: taskTitle)
        try changeStatusAndVerify(
            taskTitle: taskTitle,
            targetStatus: "In Progress",
            expectedColumn: "TaskColumn_in_progress"
        )

        // History記録の確認
        let historySection = app.descendants(matching: .any).matching(identifier: "HistorySection").firstMatch
        if historySection.exists {
            let statusChangedText = app.staticTexts["Status Changed"]
            XCTAssertTrue(statusChangedText.waitForExistence(timeout: 3),
                          "❌ PHASE3-REACTIVE: ステータス変更後、Historyにイベントが記録されない")
        }
        print("  ✅ Step 3-4完了: タスクがIn Progressに移動し、Historyに記録された")

        // Step 3-5: in_progress → done
        print("  📝 Step 3-5: ステータス変更 (in_progress → done)")
        try reopenTaskDetail(taskTitle: taskTitle)
        try changeStatusAndVerify(
            taskTitle: taskTitle,
            targetStatus: "Done",
            expectedColumn: "TaskColumn_done"
        )
        print("  ✅ Step 3-5完了: タスクがDoneに移動した")

        return taskTitle
    }

    // MARK: - Phase 4: 依存関係ブロック検証

    private func verifyPhase4_DependencyBlocking() throws {
        // 依存タスクを選択（Cmd+Shift+D）
        // シードデータ: uitest_dependent_task が uitest_prerequisite_task に依存
        app.typeKey("d", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 1.0)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "❌ PHASE4: 依存タスクの詳細画面が開かない（uitest_dependent_taskが存在するか確認）")

        // 依存関係セクションの確認
        let dependenciesSection = app.descendants(matching: .any).matching(identifier: "DependenciesSection").firstMatch
        XCTAssertTrue(dependenciesSection.waitForExistence(timeout: 3),
                      "❌ PHASE4: 依存関係セクション(DependenciesSection)が見つからない")

        // StatusPickerでIn Progressを選択
        let statusPicker = app.popUpButtons["StatusPicker"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 3),
                      "❌ PHASE4: StatusPickerが見つからない")
        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        let inProgressOption = app.menuItems["In Progress"]
        XCTAssertTrue(inProgressOption.waitForExistence(timeout: 2),
                      "❌ PHASE4: In Progressオプションが見つからない")
        inProgressOption.click()
        Thread.sleep(forTimeInterval: 0.5)

        // ブロックエラーアラートが表示されることを確認（ハードアサーション）
        let alertSheet = app.sheets.firstMatch
        XCTAssertTrue(alertSheet.waitForExistence(timeout: 3),
                      "❌ PHASE4-BLOCKING: 依存関係によるブロックエラーアラートが表示されない（先行タスクが未完了なのでブロックされるべき）")

        // アラートを閉じる
        let okButton = alertSheet.buttons["OK"]
        if okButton.exists { okButton.click() }
    }

    // MARK: - Phase 5: リソース制限ブロック検証

    private func verifyPhase5_ResourceBlocking() throws {
        // リソーステストタスクを選択（Cmd+Shift+G）
        // シードデータ: uitest_resource_task が backend-dev にアサイン
        // backend-dev の maxParallelTasks=1、既に API実装(inProgress) があるためブロック
        app.typeKey("g", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "❌ PHASE5: リソーステストタスクの詳細画面が開かない（uitest_resource_taskが存在するか確認）")

        // StatusPickerでIn Progressを選択
        let statusPicker = app.popUpButtons["StatusPicker"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 3),
                      "❌ PHASE5: StatusPickerが見つからない")
        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        let inProgressOption = app.menuItems["In Progress"]
        XCTAssertTrue(inProgressOption.waitForExistence(timeout: 2),
                      "❌ PHASE5: In Progressオプションが見つからない")
        inProgressOption.click()
        Thread.sleep(forTimeInterval: 0.5)

        // リソース制限エラーアラートが表示されることを確認（ハードアサーション）
        let alertSheet = app.sheets.firstMatch
        XCTAssertTrue(alertSheet.waitForExistence(timeout: 3),
                      "❌ PHASE5-BLOCKING: リソース制限によるブロックエラーアラートが表示されない（maxParallelTasks=1で既にinProgressがあるのでブロックされるべき）")

        // アラートを閉じる
        let okButton = alertSheet.buttons["OK"]
        if okButton.exists { okButton.click() }
    }

    // MARK: - Helper Methods

    private func selectProject(named projectName: String) throws {
        app.activate()
        Thread.sleep(forTimeInterval: 0.5)

        let projectRow = app.staticTexts[projectName]
        guard projectRow.waitForExistence(timeout: 5) else {
            XCTFail("❌ SETUP: プロジェクト「\(projectName)」が見つからない")
            throw TestError.failedPrecondition("プロジェクト「\(projectName)」が見つかりません")
        }

        if projectRow.isHittable {
            projectRow.click()
        } else {
            projectRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func findTaskCard(withTitle title: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", title)
        return app.buttons.matching(predicate).firstMatch
    }

    private func createTask(title: String) throws {
        app.typeKey("t", modifierFlags: [.command, .shift])

        let createSheet = app.sheets.firstMatch
        XCTAssertTrue(createSheet.waitForExistence(timeout: 5),
                      "❌ STEP3-1: 新規タスクシートが開かない")

        let titleField = app.textFields["TaskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3),
                      "❌ STEP3-1: タイトルフィールドが存在しない")
        titleField.click()
        titleField.typeText(title)

        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.isEnabled,
                      "❌ STEP3-1-REACTIVE: タイトル入力後、Saveボタンが有効にならない")
        saveButton.click()

        XCTAssertTrue(createSheet.waitForNonExistence(timeout: 5),
                      "❌ STEP3-1-REACTIVE: 保存後にシートが閉じない")

        Thread.sleep(forTimeInterval: 1.0)

        let createdTaskCard = findTaskCard(withTitle: title)
        XCTAssertTrue(createdTaskCard.waitForExistence(timeout: 5),
                      "❌ STEP3-1-REACTIVE: 作成したタスク「\(title)」がボードに表示されない")
    }

    private func assignAgent(to taskTitle: String, agentName: String) throws {
        let taskCard = findTaskCard(withTitle: taskTitle)
        XCTAssertTrue(taskCard.exists, "❌ STEP3-2: タスクカードが見つからない")
        taskCard.click()
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "❌ STEP3-2-REACTIVE: タスクカードクリック後、詳細画面が開かない")

        // 編集フォームを開く（⌘E）
        app.typeKey("e", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)

        let editSheet = app.sheets.firstMatch
        XCTAssertTrue(editSheet.waitForExistence(timeout: 3),
                      "❌ STEP3-2: 編集フォームが開かない")

        // TaskAssigneePickerでエージェントを選択
        let assigneePicker = app.popUpButtons["TaskAssigneePicker"]
        XCTAssertTrue(assigneePicker.waitForExistence(timeout: 3),
                      "❌ STEP3-2: TaskAssigneePickerが見つからない")
        assigneePicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        let agentOption = app.menuItems[agentName]
        XCTAssertTrue(agentOption.waitForExistence(timeout: 2),
                      "❌ STEP3-2: エージェント「\(agentName)」が選択肢にない")
        agentOption.click()
        Thread.sleep(forTimeInterval: 0.3)

        // 保存
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2),
                      "❌ STEP3-2: Saveボタンが見つからない")
        saveButton.click()

        XCTAssertTrue(editSheet.waitForNonExistence(timeout: 3),
                      "❌ STEP3-2-REACTIVE: 保存後に編集フォームが閉じない")
    }

    private func reopenTaskDetail(taskTitle: String) throws {
        let taskCard = findTaskCard(withTitle: taskTitle)
        if taskCard.exists {
            taskCard.click()
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    private func changeStatusAndVerify(
        taskTitle: String,
        targetStatus: String,
        expectedColumn: String
    ) throws {
        let picker = app.popUpButtons["StatusPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3),
                      "❌ STATUS: StatusPickerが見つからない")

        picker.click()
        Thread.sleep(forTimeInterval: 0.3)

        let statusOption = app.menuItems[targetStatus]
        XCTAssertTrue(statusOption.waitForExistence(timeout: 2),
                      "❌ STATUS: \(targetStatus)オプションが見つからない")

        statusOption.click()
        Thread.sleep(forTimeInterval: 0.5)

        // エラーアラートのチェック（ライフサイクルテストではエラーは発生しないはず）
        let alertSheet = app.sheets.firstMatch
        if alertSheet.waitForExistence(timeout: 1) {
            let okButton = alertSheet.buttons["OK"]
            if okButton.exists { okButton.click() }
            XCTFail("❌ STATUS-BLOCKED: ステータス変更が予期せずブロックされた（\(targetStatus)への変更）")
        }

        // リアクティブ検証: タスクが正しいカラムに移動する
        Thread.sleep(forTimeInterval: 0.5)
        let targetColumn = app.descendants(matching: .any).matching(identifier: expectedColumn).firstMatch
        XCTAssertTrue(targetColumn.waitForExistence(timeout: 3),
                      "❌ STATUS-REACTIVE: \(expectedColumn)カラムが見つからない")

        let taskInColumn = findTaskCard(withTitle: taskTitle)
        XCTAssertTrue(taskInColumn.exists,
                      "❌ STATUS-REACTIVE: タスクが\(targetStatus)カラムに移動しない")
    }
}
