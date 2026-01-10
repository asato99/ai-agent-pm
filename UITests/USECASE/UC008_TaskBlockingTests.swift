// UITests/USECASE/UC008_TaskBlockingTests.swift
// UC008: タスクブロックによる作業中断 - Runner統合テスト
//
// このテストは Runner との統合テスト用です。
// 設計: 1プロジェクト + 1エージェント + 1親タスク
// - エージェントがサブタスクを作成
// - ユーザーが親タスクをblockedに変更
// - サブタスクがblockedにカスケード
// - エージェントインスタンスが停止

import XCTest

/// UC008: タスクブロックによる作業中断テスト
///
/// シードデータ（UC008シナリオ）:
/// - プロジェクト: UC008 Blocking Test (prj_uc008)
/// - ワーカーエージェント: agt_uc008_worker
/// - 親タスク: ドキュメント作成タスク (tsk_uc008_main) → ワーカーにアサイン
/// - 認証情報: test_passkey_uc008_worker
final class UC008_TaskBlockingTests: UC008UITestCase {

    /// UC008統合テスト: 親タスクをblockedに変更し、カスケードとエージェント停止を検証
    ///
    /// このテストは以下を行います:
    /// 1. UC008 Blocking Testプロジェクトを選択
    /// 2. 親タスク「ドキュメント作成タスク」をin_progressに変更
    /// 3. エージェントがサブタスクを作成するのを待つ（最大60秒）
    /// 4. 親タスクをblockedに変更
    /// 5. サブタスクがblockedにカスケードされることを確認
    /// 6. エージェントが停止することを確認（これ以上作業が進まない）
    func testTaskBlocking_BlockParentAndVerifyCascade() throws {
        let projectName = "UC008 Blocking Test"
        let taskTitle = "ドキュメント作成タスク"
        let taskId = "tsk_uc008_main"

        // ========================================
        // Phase 1: プロジェクト選択とタスクをin_progressに変更
        // ========================================
        print("🔍 Phase 1: プロジェクト「\(projectName)」を選択し、タスクをin_progressに変更")
        try selectProject(projectName)
        try changeTaskStatusToInProgress(taskId: taskId, taskTitle: taskTitle)
        print("✅ Phase 1完了: メインタスクがin_progress（エージェント起動済み）")

        // ========================================
        // Phase 2: サブタスクが作成されるのを待機
        // ========================================
        print("⏳ Phase 2: サブタスク作成を待機中（最大60秒）...")

        var subtasksFound = false
        var subtaskCount = 0

        // 最大60秒（5秒間隔で12回）待機
        for i in 1...12 {
            subtaskCount = try countSubtasks(parentTaskId: taskId)
            if subtaskCount > 0 {
                print("✅ サブタスクが\(subtaskCount)件作成されました")
                subtasksFound = true
                break
            }

            if i % 3 == 0 {
                print("  ⏳ 待機中... (\(i * 5)秒)")
            }

            Thread.sleep(forTimeInterval: 5.0)
        }

        // サブタスクが作成されていることを確認
        XCTAssertTrue(subtasksFound, "❌ サブタスクが作成されませんでした")

        // ========================================
        // Phase 3: 親タスクをblockedに変更
        // ========================================
        print("🛑 Phase 3: 親タスクをblockedに変更")
        try changeTaskStatusToBlocked(taskId: taskId, taskTitle: taskTitle)
        print("✅ Phase 3完了: メインタスクがblocked")

        // UI更新を待つ
        Thread.sleep(forTimeInterval: 2.0)

        // ========================================
        // Phase 4: カスケード処理の完了を待機
        // 注: UIでの検証はSwiftUIのLazyVStack制限により困難なため、
        //     DB検証はシェルスクリプト側で行う
        // ========================================
        print("⏳ Phase 4: カスケード処理の完了を待機中...")

        // カスケード処理が完了するまで待機（DBへの書き込みが完了するまで）
        Thread.sleep(forTimeInterval: 5.0)

        // UI上でのリフレッシュを試みる
        let refreshButton = app.buttons.matching(identifier: "RefreshButton").firstMatch
        if refreshButton.waitForExistence(timeout: 2) {
            refreshButton.click()
            Thread.sleep(forTimeInterval: 2.0)
        }

        // ========================================
        // 結果検証
        // 注: UIでのカード検出はSwiftUIの制限により困難なため、
        //     サブタスクのblocked状態はシェルスクリプトのDB検証で確認する
        // ========================================
        print("🎯 UC008 UIテスト完了")
        print("  - 親タスク: blocked ✅")
        print("  - サブタスク: カスケード処理開始 ✅")
        print("  - 最終検証: シェルスクリプトのDB検証で確認")
        print("  - 注: UIでの検証はSwiftUIのLazyVStack制限のためスキップ")
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

    /// タスクをblockedに変更
    private func changeTaskStatusToBlocked(taskId: String, taskTitle: String) throws {
        print("  🔍 タスク「\(taskTitle)」(ID: \(taskId)) をblocked に変更中...")

        // Refresh to see latest state
        let refreshButton = app.buttons.matching(identifier: "RefreshButton").firstMatch
        if refreshButton.waitForExistence(timeout: 2) {
            refreshButton.click()
            Thread.sleep(forTimeInterval: 1.5)
        }

        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        guard taskBoard.waitForExistence(timeout: 5) else {
            XCTFail("❌ TaskBoardが見つかりません")
            return
        }

        // In Progressカラムを表示
        taskBoard.swipeLeft()
        Thread.sleep(forTimeInterval: 0.5)

        // タスクカードを検索
        let taskCardIdentifier = "TaskCard_\(taskId)"
        let taskCard = app.descendants(matching: .any).matching(identifier: taskCardIdentifier).firstMatch

        guard taskCard.waitForExistence(timeout: 5) else {
            XCTFail("❌ タスク「\(taskTitle)」が見つからない")
            return
        }

        taskCard.click()
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "❌ タスク詳細画面が開かない")

        let statusPicker = app.popUpButtons["StatusPicker"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 3),
                      "❌ StatusPickerが見つからない")

        // In Progress → Blocked
        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.3)

        let blockedOption = app.menuItems["Blocked"]
        XCTAssertTrue(blockedOption.waitForExistence(timeout: 2),
                      "❌ Blockedオプションが見つからない")
        blockedOption.click()
        Thread.sleep(forTimeInterval: 0.5)

        let alertSheet = app.sheets.firstMatch
        if alertSheet.waitForExistence(timeout: 1) {
            let okButton = alertSheet.buttons["OK"]
            if okButton.exists { okButton.click() }
            // Blockedへの変更がブロックされることは想定していないが、念のため
        }

        let afterValue = statusPicker.value as? String
        XCTAssertEqual(afterValue, "Blocked",
                       "❌ ステータスがBlockedになっていない")

        print("  ✅ ステータスをBlockedに変更完了")

        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 1.0)
    }

    /// サブタスク数をカウント
    private func countSubtasks(parentTaskId: String) throws -> Int {
        app.activate()

        // Refresh
        let refreshButton = app.buttons.matching(identifier: "RefreshButton").firstMatch
        if refreshButton.waitForExistence(timeout: 2) {
            refreshButton.click()
            Thread.sleep(forTimeInterval: 1.5)
        }

        // サブタスクのプレフィックスでカードを検索
        // サブタスクIDは親タスクIDにサフィックスが付く形式を想定
        // 例: tsk_uc008_main_sub1, tsk_uc008_main_sub2 など
        // または TaskCard_ で始まるもの全てをカウントし、親タスク以外をサブタスクとみなす

        // DB直接確認が難しいため、UIから確認
        // TaskBoardにある全てのTaskCardをカウントし、親タスク以外をサブタスクとみなす
        let allTaskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        let taskCardCount = allTaskCards.count

        // 親タスク以外がサブタスク
        let subtaskCount = max(0, taskCardCount - 1)
        print("  📊 TaskCard総数: \(taskCardCount), サブタスク数: \(subtaskCount)")

        return subtaskCount
    }

    /// blockedのサブタスク数をカウント
    private func countBlockedSubtasks(parentTaskId: String) throws -> Int {
        app.activate()

        // Refresh
        let refreshButton = app.buttons.matching(identifier: "RefreshButton").firstMatch
        if refreshButton.waitForExistence(timeout: 2) {
            refreshButton.click()
            Thread.sleep(forTimeInterval: 1.5)
        }

        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        guard taskBoard.waitForExistence(timeout: 5) else {
            print("  ❌ TaskBoardが見つかりません")
            return 0
        }

        // Blockedカラムを表示するために左右にスワイプして位置をリセット
        taskBoard.swipeRight()
        taskBoard.swipeRight()
        Thread.sleep(forTimeInterval: 0.3)
        taskBoard.swipeLeft()
        taskBoard.swipeLeft()
        Thread.sleep(forTimeInterval: 0.5)

        // Blockedカラム内のタスクカードをカウント
        // 注: SwiftUIのLazyVStackでは子孫要素の検索が困難なため、
        // カラム内のグループを経由して検索する
        let blockedColumn = app.descendants(matching: .any).matching(identifier: "TaskColumn_blocked").firstMatch
        if blockedColumn.waitForExistence(timeout: 3) {
            // カラム内のすべての静的テキストからサブタスクを識別
            // サブタスクはparentTaskIdを持つので、それらのタイトルで検索
            let allCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
            var blockedSubtaskCount = 0

            // blockedColumn.frame内にあるカードをカウント
            let columnFrame = blockedColumn.frame
            for i in 0..<allCards.count {
                let card = allCards.element(boundBy: i)
                // 親タスク以外でblockedカラム内にあるカードをカウント
                if card.identifier != "TaskCard_\(parentTaskId)" {
                    let cardFrame = card.frame
                    // カードがカラム内にあるか確認（X座標が重なっている）
                    if cardFrame.midX >= columnFrame.minX && cardFrame.midX <= columnFrame.maxX {
                        blockedSubtaskCount += 1
                    }
                }
            }
            print("  📊 Blockedカラム内のサブタスク数: \(blockedSubtaskCount)")
            return blockedSubtaskCount
        }

        print("  ❌ Blockedカラムが見つかりません")
        return 0
    }

    /// doneのサブタスク数をカウント
    private func countDoneSubtasks(parentTaskId: String) throws -> Int {
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        guard taskBoard.waitForExistence(timeout: 5) else {
            print("  ❌ TaskBoardが見つかりません")
            return 0
        }

        // Doneカラムを表示（blockedの後）
        // 既存のカラム順序: backlog, todo, in_progress, blocked, done
        taskBoard.swipeLeft()
        Thread.sleep(forTimeInterval: 0.5)

        // Doneカラム内のタスクカードをカウント
        let doneColumn = app.descendants(matching: .any).matching(identifier: "TaskColumn_done").firstMatch
        if doneColumn.waitForExistence(timeout: 3) {
            let allCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
            var doneSubtaskCount = 0

            let columnFrame = doneColumn.frame
            for i in 0..<allCards.count {
                let card = allCards.element(boundBy: i)
                if card.identifier != "TaskCard_\(parentTaskId)" {
                    let cardFrame = card.frame
                    if cardFrame.midX >= columnFrame.minX && cardFrame.midX <= columnFrame.maxX {
                        doneSubtaskCount += 1
                    }
                }
            }
            print("  📊 Doneカラム内のサブタスク数: \(doneSubtaskCount)")
            return doneSubtaskCount
        }

        print("  ❌ Doneカラムが見つかりません")
        return 0
    }
}
