// UITests/Feature/Feature13_TaskReassignmentTests.swift
// Feature 13: タスク担当エージェント再割り当て制限テスト
//
// 要件: docs/requirements/TASKS.md - 担当エージェント再割り当て制限
// - in_progress/blocked のタスクは担当変更不可（作業コンテキスト破棄防止）
//
// TDDサイクル:
// - RED: 機能未実装のため担当変更が可能 → テスト失敗
// - GREEN: 実装後、同じテストが成功

import XCTest

final class TaskReassignmentTests: BasicDataUITestCase {

    /// in_progressタスクは担当エージェントの変更が不可
    func testInProgressTaskReassignmentDisabled() throws {
        // タスクボードを表示
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5))
        projectRow.click()

        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5))

        // In Progressステータスのタスクを探して開く
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        var foundInProgress = false

        for i in 0..<taskCards.count {
            let card = taskCards.element(boundBy: i)
            guard card.exists && card.isHittable else { continue }

            card.click()
            let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
            guard detailView.waitForExistence(timeout: 3) else { continue }

            let statusPicker = app.popUpButtons["StatusPicker"]
            guard statusPicker.waitForExistence(timeout: 3) else { continue }

            if let status = statusPicker.value as? String, status == "In Progress" {
                foundInProgress = true
                break
            }
            app.typeKey(.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.3)
        }

        XCTAssertTrue(foundInProgress, "In Progressステータスのタスクが必要")

        // 編集ボタンをクリックしてTaskFormViewを開く
        let editButton = app.buttons["EditTaskButton"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 3), "編集ボタンが必要")
        editButton.click()

        // TaskFormView（編集フォーム）が表示されるのを待つ
        let taskForm = app.descendants(matching: .any).matching(identifier: "TaskForm").firstMatch
        XCTAssertTrue(taskForm.waitForExistence(timeout: 5), "タスク編集フォームが開くこと")

        // 担当エージェントピッカーが無効化されていることを確認
        let assigneePicker = app.popUpButtons["TaskAssigneePicker"]
        XCTAssertTrue(assigneePicker.waitForExistence(timeout: 3), "担当エージェントピッカーが存在すること")
        XCTAssertFalse(assigneePicker.isEnabled,
                       "in_progressタスクの担当エージェントピッカーは無効化されるべき")
    }
}
