// UITests/Feature/Feature12_TaskStatusTransitionTests.swift
// Feature 12: タスクステータス遷移制限テスト
//
// 要件: docs/requirements/TASKS.md - 状態遷移の制限
// - in_progress/blocked → todo/backlog への遷移禁止
//
// TDDサイクル:
// - RED: 機能未実装のため遷移制限が効いていない → テスト失敗
// - GREEN: 実装後、同じテストが成功

import XCTest

final class TaskStatusTransitionTests: BasicDataUITestCase {

    /// in_progressタスクはtodoへの遷移が禁止される
    /// 検証方法: 1) ステータスピッカー 2) ドラッグ＆ドロップ
    func testInProgressToTodoTransitionDisabled() throws {
        // タスクボードを表示
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5))
        projectRow.click()

        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5))

        // In Progressステータスのタスクを探す
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        var inProgressCard: XCUIElement?
        var inProgressTaskId: String?

        for i in 0..<taskCards.count {
            let card = taskCards.element(boundBy: i)
            guard card.exists && card.isHittable else { continue }

            card.click()
            let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
            guard detailView.waitForExistence(timeout: 3) else { continue }

            let statusPicker = app.popUpButtons["StatusPicker"]
            guard statusPicker.waitForExistence(timeout: 3) else { continue }

            if let status = statusPicker.value as? String, status == "In Progress" {
                inProgressCard = card
                inProgressTaskId = card.identifier
                break
            }
            app.typeKey(.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.3)
        }

        guard inProgressCard != nil else {
            XCTFail("In Progressステータスのタスクが必要")
            return
        }

        // === 検証1: ステータスピッカーでTo Doオプションが無効化されている ===
        let statusPicker = app.popUpButtons["StatusPicker"]
        statusPicker.click()

        let todoOption = app.menuItems["To Do"]
        XCTAssertTrue(todoOption.waitForExistence(timeout: 3))
        XCTAssertFalse(todoOption.isEnabled,
                       "ステータスピッカー: in_progressタスクのTo Doオプションは無効化されるべき")

        // メニューを閉じる
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)

        // 詳細を閉じる
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)

        // === 検証2: ドラッグ＆ドロップでTo Doカラムへの移動が拒否される ===
        let todoColumn = app.descendants(matching: .any).matching(identifier: "TaskColumn_todo").firstMatch
        XCTAssertTrue(todoColumn.waitForExistence(timeout: 3), "To Doカラムが必要")

        // タスクカードを再取得（詳細を閉じた後）
        let cardToMove = app.descendants(matching: .any).matching(identifier: inProgressTaskId!).firstMatch
        XCTAssertTrue(cardToMove.waitForExistence(timeout: 3))

        // ドラッグ＆ドロップ実行
        cardToMove.click(forDuration: 0.5, thenDragTo: todoColumn)
        Thread.sleep(forTimeInterval: 0.5)

        // タスクがまだIn Progressカラムにあることを確認
        cardToMove.click()
        let detailAfterDrag = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailAfterDrag.waitForExistence(timeout: 3))

        let statusAfterDrag = app.popUpButtons["StatusPicker"]
        XCTAssertTrue(statusAfterDrag.waitForExistence(timeout: 3))
        XCTAssertEqual(statusAfterDrag.value as? String, "In Progress",
                       "ドラッグ: in_progressタスクはTo Doカラムに移動できないはず")
    }
}
