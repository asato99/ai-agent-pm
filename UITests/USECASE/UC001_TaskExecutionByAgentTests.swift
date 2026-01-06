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
// ⚠️ 重要: テスト実装の目的は「テストを通すこと」ではなく
//          「ドキュメント通りにアサートを正確に実装すること」である
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
        // #1: Cmd+Shift+T押下 → シートが開く
        app.typeKey("t", modifierFlags: [.command, .shift])

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5),
                      "❌ PHASE2: タスク作成シートが開かない")

        // #2: タイトル未入力状態確認 → Saveボタンが無効
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2),
                      "❌ PHASE2: Saveボタンが存在しない")
        XCTAssertFalse(saveButton.isEnabled,
                       "❌ PHASE2-REACTIVE: タイトル未入力時、Saveボタンが無効であるべき（isEnabled=\(saveButton.isEnabled)）")

        // #3: シートキャンセル → シートが閉じる
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
        try reopenTaskDetail(taskTitle: taskTitle)
        try changeStatusAndVerify(
            taskTitle: taskTitle,
            fromStatus: "Backlog",
            targetStatus: "To Do",
            fromColumn: "TaskColumn_backlog",
            expectedColumn: "TaskColumn_todo"
        )
        print("  ✅ Step 3-3完了: タスクがTo Doに移動した")

        // Step 3-4: todo → in_progress
        print("  📝 Step 3-4: ステータス変更 (todo → in_progress)")
        try reopenTaskDetail(taskTitle: taskTitle)
        try changeStatusAndVerify(
            taskTitle: taskTitle,
            fromStatus: "To Do",
            targetStatus: "In Progress",
            fromColumn: "TaskColumn_todo",
            expectedColumn: "TaskColumn_in_progress"
        )

        // History記録の確認（ハードアサーション）
        // ステータス変更後のデータリロードを待つ
        Thread.sleep(forTimeInterval: 1.0)

        // タスク詳細を再度開いて最新データを取得
        try reopenTaskDetail(taskTitle: taskTitle)

        // データロード待機
        Thread.sleep(forTimeInterval: 1.0)

        // TaskDetailViewをスクロールしてHistorySectionを表示
        let taskDetailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(taskDetailView.exists, "❌ STEP3-4: TaskDetailViewが存在しない")
        taskDetailView.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)

        // #9: 履歴セクション確認
        let historySection = app.descendants(matching: .any).matching(identifier: "HistorySection").firstMatch
        XCTAssertTrue(historySection.waitForExistence(timeout: 3),
                      "❌ STEP3-4: HistorySectionが見つからない")

        // #10: 履歴空でない確認
        let noHistoryMessage = app.descendants(matching: .any).matching(identifier: "NoHistoryMessage").firstMatch
        XCTAssertFalse(noHistoryMessage.exists,
                       "❌ STEP3-4-HISTORY: 履歴イベントが記録されていない（NoHistoryMessageが表示されている）")

        // #11: 履歴イベント内容確認
        let statusChangedText = historySection.staticTexts["Status Changed"]
        XCTAssertTrue(statusChangedText.exists,
                      "❌ STEP3-4-HISTORY: Status Changedイベントが記録されていない")

        // #12: 履歴遷移内容確認
        let transitionText = historySection.staticTexts["todo → in_progress"]
        XCTAssertTrue(transitionText.exists,
                      "❌ STEP3-4-HISTORY: 遷移内容「todo → in_progress」が記録されていない")

        print("  ✅ Step 3-4完了: タスクがIn Progressに移動し、Historyに記録された")

        // Step 3-5: in_progress → done
        print("  📝 Step 3-5: ステータス変更 (in_progress → done)")
        try reopenTaskDetail(taskTitle: taskTitle)
        try changeStatusAndVerify(
            taskTitle: taskTitle,
            fromStatus: "In Progress",
            targetStatus: "Done",
            fromColumn: "TaskColumn_in_progress",
            expectedColumn: "TaskColumn_done"
        )
        print("  ✅ Step 3-5完了: タスクがDoneに移動した")

        return taskTitle
    }

    // MARK: - Phase 4: 依存関係ブロック検証

    private func verifyPhase4_DependencyBlocking() throws {
        // 依存タスクを選択（Cmd+Shift+D）
        // シードデータ: uitest_dependent_task が uitest_prerequisite_task に依存
        let dependentTaskTitle = "依存タスク"

        // #1: Cmd+Shift+D押下で依存タスク選択 → 詳細画面が開く
        app.typeKey("d", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 1.0)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "❌ PHASE4: 依存タスクの詳細画面が開かない（uitest_dependent_taskが存在するか確認）")

        // #2: 変更前ステータス確認 → To DoまたはBacklog
        let statusPicker = app.popUpButtons["StatusPicker"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 3),
                      "❌ PHASE4: StatusPickerが見つからない")

        let beforeValue = statusPicker.value as? String ?? ""
        XCTAssertTrue(["To Do", "Backlog"].contains(beforeValue),
                      "❌ PHASE4: 変更前ステータスがTo DoまたはBacklogでない（実際の値: \(beforeValue)）")

        // #3: DependenciesSectionを確認 → 依存関係セクションが存在
        let dependenciesSection = app.descendants(matching: .any).matching(identifier: "DependenciesSection").firstMatch
        XCTAssertTrue(dependenciesSection.waitForExistence(timeout: 3),
                      "❌ PHASE4: 依存関係セクション(DependenciesSection)が見つからない")

        // #4: StatusPickerクリック → メニューが表示される
        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        // #5: "In Progress"メニュー項目選択 → ブロックエラーが発生
        let inProgressOption = app.menuItems["In Progress"]
        XCTAssertTrue(inProgressOption.waitForExistence(timeout: 2),
                      "❌ PHASE4: In Progressオプションが見つからない")
        inProgressOption.click()
        Thread.sleep(forTimeInterval: 0.5)

        // #6: エラーアラート表示確認 → エラーシートが表示される
        let alertSheet = app.sheets.firstMatch
        XCTAssertTrue(alertSheet.waitForExistence(timeout: 3),
                      "❌ PHASE4-BLOCKING: 依存関係によるブロックエラーアラートが表示されない（先行タスクが未完了なのでブロックされるべき）")

        // #7: OKボタン押下でアラートを閉じる → アラートが閉じる
        let okButton = alertSheet.buttons["OK"]
        XCTAssertTrue(okButton.waitForExistence(timeout: 2),
                      "❌ PHASE4: アラートのOKボタンが見つからない")
        okButton.click()
        XCTAssertTrue(alertSheet.waitForNonExistence(timeout: 3),
                      "❌ PHASE4: アラートが閉じない")

        // リアクティブ検証のための待機
        Thread.sleep(forTimeInterval: 0.5)

        // #8: ステータス未変更確認 → StatusPickerの値がIn Progressでない
        let afterValue = statusPicker.value as? String
        XCTAssertNotEqual(afterValue, "In Progress",
                          "❌ PHASE4-REACTIVE: ブロックされるべきなのにステータスがIn Progressになっている")

        // #9: Escape押下で詳細画面を閉じる
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        // #10: タスクカード存在確認 → タスクカードがボードに存在
        let taskCard = findTaskCard(withTitle: dependentTaskTitle)
        XCTAssertTrue(taskCard.exists,
                      "❌ PHASE4-REACTIVE: ブロック後、タスク「\(dependentTaskTitle)」がボードから消えた")
    }

    // MARK: - Phase 5: リソース制限ブロック検証

    private func verifyPhase5_ResourceBlocking() throws {
        // リソーステストタスクを選択（Cmd+Shift+G）
        // シードデータ: uitest_resource_task が backend-dev にアサイン
        // backend-dev の maxParallelTasks=1、既に API実装(inProgress) があるためブロック
        let resourceTaskTitle = "追加開発タスク"
        let expectedAgentName = "backend-dev"

        // #1: Cmd+Shift+G押下でリソーステストタスク選択 → 詳細画面が開く
        app.typeKey("g", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 1.0)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "❌ PHASE5: リソーステストタスクの詳細画面が開かない（uitest_resource_taskが存在するか確認）")

        // #2: 変更前ステータス確認 → StatusPickerの値がTo Do
        let statusPicker = app.popUpButtons["StatusPicker"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 3),
                      "❌ PHASE5: StatusPickerが見つからない")

        let beforeValue = statusPicker.value as? String
        XCTAssertEqual(beforeValue, "To Do",
                       "❌ PHASE5: 変更前ステータスがTo Doでない（実際の値: \(beforeValue ?? "nil")）")

        // #3: 担当エージェント確認 → 詳細ビューにbackend-devが表示
        let agentLabel = detailView.staticTexts[expectedAgentName]
        XCTAssertTrue(agentLabel.exists,
                      "❌ PHASE5: 担当エージェント「\(expectedAgentName)」が表示されていない")

        // #4: StatusPickerクリック → メニューが表示される
        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        // #5: "In Progress"メニュー項目選択 → ブロックエラーが発生
        let inProgressOption = app.menuItems["In Progress"]
        XCTAssertTrue(inProgressOption.waitForExistence(timeout: 2),
                      "❌ PHASE5: In Progressオプションが見つからない")
        inProgressOption.click()
        Thread.sleep(forTimeInterval: 0.5)

        // #6: エラーアラート表示確認 → エラーシートが表示される
        let alertSheet = app.sheets.firstMatch
        XCTAssertTrue(alertSheet.waitForExistence(timeout: 3),
                      "❌ PHASE5-BLOCKING: リソース制限によるブロックエラーアラートが表示されない（maxParallelTasks=1で既にinProgressがあるのでブロックされるべき）")

        // #7: OKボタン押下でアラートを閉じる → アラートが閉じる
        let okButton = alertSheet.buttons["OK"]
        XCTAssertTrue(okButton.waitForExistence(timeout: 2),
                      "❌ PHASE5: アラートのOKボタンが見つからない")
        okButton.click()
        XCTAssertTrue(alertSheet.waitForNonExistence(timeout: 3),
                      "❌ PHASE5: アラートが閉じない")

        // リアクティブ検証のための待機
        Thread.sleep(forTimeInterval: 0.5)

        // #8: ステータス未変更確認 → StatusPickerの値がTo Doのまま
        let afterValue = statusPicker.value as? String
        XCTAssertEqual(afterValue, "To Do",
                       "❌ PHASE5-REACTIVE: ブロックされるべきなのにステータスがTo Doでなくなっている（実際の値: \(afterValue ?? "nil")）")

        // #9: Escape押下で詳細画面を閉じる
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        // #10: タスクカード存在確認 → タスクカードがボードに存在
        let taskCard = findTaskCard(withTitle: resourceTaskTitle)
        XCTAssertTrue(taskCard.exists,
                      "❌ PHASE5-REACTIVE: ブロック後、タスク「\(resourceTaskTitle)」がボードから消えた")
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

    /// 指定カラム内にタスクカードが存在するか確認
    /// カラムヘッダーのX位置からカラム範囲を推定
    private func taskExistsInColumn(taskTitle: String, columnIdentifier: String) -> Bool {
        let columnDisplayNames: [String: String] = [
            "TaskColumn_backlog": "Backlog",
            "TaskColumn_todo": "To Do",
            "TaskColumn_in_progress": "In Progress",
            "TaskColumn_blocked": "Blocked",
            "TaskColumn_done": "Done"
        ]

        guard let displayName = columnDisplayNames[columnIdentifier] else {
            return false
        }

        let columnHeader = app.staticTexts[displayName].firstMatch
        guard columnHeader.exists else { return false }

        let taskCard = findTaskCard(withTitle: taskTitle)
        guard taskCard.exists else { return false }

        let headerFrame = columnHeader.frame
        let cardFrame = taskCard.frame

        // カラム幅280px、ヘッダーは左端から8pxパディング
        let columnMinX = headerFrame.minX - 8
        let columnMaxX = columnMinX + 280

        let cardCenterX = cardFrame.midX
        return cardCenterX >= columnMinX && cardCenterX <= columnMaxX
    }

    private func createTask(title: String) throws {
        // #1: Cmd+Shift+T押下 → シートが開く
        app.typeKey("t", modifierFlags: [.command, .shift])

        let createSheet = app.sheets.firstMatch
        XCTAssertTrue(createSheet.waitForExistence(timeout: 5),
                      "❌ STEP3-1: 新規タスクシートが開かない")

        // #2: TaskTitleFieldにタイトル入力
        let titleField = app.textFields["TaskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3),
                      "❌ STEP3-1: タイトルフィールドが存在しない")
        titleField.click()
        titleField.typeText(title)

        // #3: Save押下 → シートが閉じる
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.isEnabled,
                      "❌ STEP3-1-REACTIVE: タイトル入力後、Saveボタンが有効にならない")
        saveButton.click()

        XCTAssertTrue(createSheet.waitForNonExistence(timeout: 5),
                      "❌ STEP3-1-REACTIVE: 保存後にシートが閉じない")

        Thread.sleep(forTimeInterval: 1.0)

        // #4: リアクティブ確認 → タスクカードが存在する
        let createdTaskCard = findTaskCard(withTitle: title)
        XCTAssertTrue(createdTaskCard.waitForExistence(timeout: 5),
                      "❌ STEP3-1-REACTIVE: 作成したタスク「\(title)」がボードに表示されない")

        // #5: タスクカードクリック→詳細確認 → 詳細画面が開く
        createdTaskCard.click()
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "❌ STEP3-1-REACTIVE: 作成したタスクの詳細画面が開かない")

        // #6: ステータス確認 → StatusPickerがBacklog
        let statusPicker = app.popUpButtons["StatusPicker"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 3),
                      "❌ STEP3-1-REACTIVE: StatusPickerが見つからない")

        let statusValue = statusPicker.value as? String
        XCTAssertEqual(statusValue, "Backlog",
                       "❌ STEP3-1-REACTIVE: 新規タスクのステータスがBacklogでない（実際の値: \(statusValue ?? "nil")）")

        // #7: Escape押下 → 詳細画面を閉じる
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        // #8: カラム所属確認 → タスクがBacklogカラム内にある
        XCTAssertTrue(taskExistsInColumn(taskTitle: title, columnIdentifier: "TaskColumn_backlog"),
                      "❌ STEP3-1-REACTIVE: タスク「\(title)」がBacklogカラム内に存在しない")

        // #9: 他カラム不在確認 → タスクがTo Doカラムにない
        XCTAssertFalse(taskExistsInColumn(taskTitle: title, columnIdentifier: "TaskColumn_todo"),
                       "❌ STEP3-1-REACTIVE: 新規タスク「\(title)」がTo Doカラムに存在してはいけない")
    }

    private func assignAgent(to taskTitle: String, agentName: String) throws {
        // #1: タスクカードクリック → 詳細画面が開く
        let taskCard = findTaskCard(withTitle: taskTitle)
        XCTAssertTrue(taskCard.exists, "❌ STEP3-2: タスクカードが見つからない")
        taskCard.click()
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "❌ STEP3-2-REACTIVE: タスクカードクリック後、詳細画面が開かない")

        // #2: 割当前確認 → 詳細ビューにエージェント名がない
        let existingAgentLabel = detailView.staticTexts[agentName]
        XCTAssertFalse(existingAgentLabel.exists,
                       "❌ STEP3-2: 割当前なのにエージェント「\(agentName)」が既に表示されている")

        // #3: Cmd+E押下（編集フォーム） → 編集シートが開く
        app.typeKey("e", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)

        let editSheet = app.sheets.firstMatch
        XCTAssertTrue(editSheet.waitForExistence(timeout: 5),
                      "❌ STEP3-2: 編集フォームが開かない")

        // #4: TaskAssigneePicker確認 → ピッカーが存在する
        let assigneePicker = app.popUpButtons["TaskAssigneePicker"]
        XCTAssertTrue(assigneePicker.waitForExistence(timeout: 3),
                      "❌ STEP3-2: TaskAssigneePickerが見つからない")

        // #5: TaskAssigneePickerクリック → メニューが表示される
        assigneePicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        // #6: エージェント名選択 → メニュー項目をクリック
        let agentOption = app.menuItems[agentName]
        XCTAssertTrue(agentOption.waitForExistence(timeout: 2),
                      "❌ STEP3-2: エージェント「\(agentName)」が選択肢にない")
        agentOption.click()
        Thread.sleep(forTimeInterval: 0.3)

        // #7: Save押下 → 編集シートが閉じる
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2),
                      "❌ STEP3-2: Saveボタンが見つからない")
        saveButton.click()

        XCTAssertTrue(editSheet.waitForNonExistence(timeout: 5),
                      "❌ STEP3-2-REACTIVE: 保存後に編集フォームが閉じない")

        // データ更新待機
        Thread.sleep(forTimeInterval: 1.0)

        // #8: リアクティブ確認 → 詳細ビューにエージェント名が表示
        let updatedAgentLabel = detailView.staticTexts[agentName]
        XCTAssertTrue(updatedAgentLabel.waitForExistence(timeout: 3),
                      "❌ STEP3-2-REACTIVE: 保存後、詳細ビューにエージェント「\(agentName)」が表示されない")

        // 詳細画面を閉じてボードに戻る
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        // #9: タスクカードにも反映確認 → カードのラベルにエージェント名含む
        let updatedTaskCard = findTaskCard(withTitle: taskTitle)
        XCTAssertTrue(updatedTaskCard.exists,
                      "❌ STEP3-2-REACTIVE: 割当後、タスクカードが見つからない")
        let cardLabel = updatedTaskCard.label
        XCTAssertTrue(cardLabel.contains(agentName),
                      "❌ STEP3-2-REACTIVE: タスクカードのラベルにエージェント名「\(agentName)」が含まれていない（実際のラベル: \(cardLabel)）")
    }

    private func reopenTaskDetail(taskTitle: String) throws {
        let taskCard = findTaskCard(withTitle: taskTitle)
        XCTAssertTrue(taskCard.exists, "❌ reopenTaskDetail: タスクカード「\(taskTitle)」が見つからない")
        taskCard.click()
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func changeStatusAndVerify(
        taskTitle: String,
        fromStatus: String,
        targetStatus: String,
        fromColumn: String,
        expectedColumn: String
    ) throws {
        // #1: 変更前確認 → StatusPickerの値がfromStatus
        let statusPicker = app.popUpButtons["StatusPicker"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 3),
                      "❌ STATUS: StatusPickerが見つからない")

        let beforeValue = statusPicker.value as? String
        XCTAssertEqual(beforeValue, fromStatus,
                       "❌ STATUS-BEFORE: 変更前ステータスが\(fromStatus)でない（実際の値: \(beforeValue ?? "nil")）")

        // #2: StatusPickerクリック → メニューが表示される
        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        // #3: targetStatusメニュー項目選択 → 選択される
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

        // #4: ステータス更新確認 → StatusPickerの値がtargetStatus
        let afterValue = statusPicker.value as? String
        XCTAssertEqual(afterValue, targetStatus,
                       "❌ STATUS-AFTER: ステータスが\(targetStatus)に更新されていない（実際の値: \(afterValue ?? "nil")）")

        // #5: 詳細画面を閉じる（リアクティブ更新を期待）
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 1.0)  // UI更新待機

        // タスクカードがまだ存在することを確認
        let taskCard = findTaskCard(withTitle: taskTitle)
        XCTAssertTrue(taskCard.exists,
                      "❌ STATUS-REACTIVE: ステータス変更後、タスク「\(taskTitle)」がボードから消えた")

        // #6: カラム移動確認 → タスクが移動先カラム内にある
        XCTAssertTrue(taskExistsInColumn(taskTitle: taskTitle, columnIdentifier: expectedColumn),
                      "❌ STATUS-COLUMN: タスク「\(taskTitle)」が\(expectedColumn)カラム内に存在しない")

        // #7: 前カラム不在確認 → タスクが移動元カラムから消えている
        XCTAssertFalse(taskExistsInColumn(taskTitle: taskTitle, columnIdentifier: fromColumn),
                       "❌ STATUS-COLUMN: タスク「\(taskTitle)」が\(fromColumn)カラムにまだ存在している")
    }
}
