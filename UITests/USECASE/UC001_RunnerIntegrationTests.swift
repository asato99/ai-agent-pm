// UITests/USECASE/UC001_RunnerIntegrationTests.swift
// UC001: Runner統合テスト - Pull Architecture対応
//
// このテストは Runner との統合テスト用です。
// Runner がバックグラウンドで動作している前提で、
// タスクを in_progress に変更し、Runner がそれを検出して
// Claude CLI を実行することを確認します。

import XCTest

/// UC001: Runner統合テスト
///
/// シードデータ（UC001シナリオ）:
/// - Runner用エージェント: agt_uitest_runner
/// - Runner用タスク: uitest_runner_task (backlog状態)
/// - 認証情報: passkey=test_passkey_12345
final class UC001_RunnerIntegrationTests: UC001UITestCase {

    /// Runner統合テスト: タスクをin_progressに変更
    ///
    /// このテストは以下を行います:
    /// 1. UC001テストプロジェクトを選択
    /// 2. Runner用タスクを選択
    /// 3. ステータスをin_progressに変更
    ///
    /// その後、バックグラウンドのRunnerがタスクを検出してCLIを実行します。
    func testRunnerIntegration_ChangeStatusToInProgress() throws {
        // UC001テストプロジェクトを選択
        let projectName = "UC001テストプロジェクト"
        let projectRow = app.staticTexts[projectName]
        guard projectRow.waitForExistence(timeout: 10) else {
            XCTFail("❌ SETUP: プロジェクト「\(projectName)」が見つからない")
            return
        }
        projectRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // タスクボードの表示を確認
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5),
                      "❌ SETUP: タスクボードが表示されない")

        // Runner用タスクを探す
        let taskTitle = "Runner統合テストタスク"
        let taskCard = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", taskTitle)).firstMatch
        guard taskCard.waitForExistence(timeout: 5) else {
            XCTFail("❌ STEP1: タスク「\(taskTitle)」が見つからない")
            return
        }

        // タスク詳細を開く
        taskCard.click()
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5),
                      "❌ STEP2: タスク詳細画面が開かない")

        // ステータスピッカーを確認
        let statusPicker = app.popUpButtons["StatusPicker"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 3),
                      "❌ STEP3: StatusPickerが見つからない")

        let beforeValue = statusPicker.value as? String ?? ""
        print("✅ 変更前ステータス: \(beforeValue)")

        // backlog → todo → in_progress と順番に変更
        // backlogから直接in_progressには変更できない場合があるため

        if beforeValue == "Backlog" {
            // Backlog → To Do
            statusPicker.click()
            Thread.sleep(forTimeInterval: 0.3)

            let todoOption = app.menuItems["To Do"]
            XCTAssertTrue(todoOption.waitForExistence(timeout: 2),
                          "❌ STEP4: To Doオプションが見つからない")
            todoOption.click()
            Thread.sleep(forTimeInterval: 0.5)

            // エラーチェック
            let alertSheet = app.sheets.firstMatch
            if alertSheet.waitForExistence(timeout: 1) {
                let okButton = alertSheet.buttons["OK"]
                if okButton.exists { okButton.click() }
                XCTFail("❌ STEP4: Backlog → To Do のステータス変更がブロックされた")
                return
            }

            print("✅ Backlog → To Do 完了")
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

        // エラーチェック
        let alertSheet2 = app.sheets.firstMatch
        if alertSheet2.waitForExistence(timeout: 1) {
            let okButton = alertSheet2.buttons["OK"]
            if okButton.exists { okButton.click() }
            XCTFail("❌ STEP5: To Do → In Progress のステータス変更がブロックされた")
            return
        }

        // ステータス変更の確認
        let afterValue = statusPicker.value as? String
        XCTAssertEqual(afterValue, "In Progress",
                       "❌ STEP6: ステータスがIn Progressになっていない（実際の値: \(afterValue ?? "nil")）")

        print("✅ ステータスをIn Progressに変更完了 - Runnerがタスクを検出して実行するのを待ちます")

        // 詳細画面を閉じる
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        // Runnerがタスクを検出・実行するまで待機
        // （統合テストスクリプト側でファイル作成を確認）
        print("🎯 UC001 Runner統合テスト: タスクがin_progress状態になりました")
    }
}
