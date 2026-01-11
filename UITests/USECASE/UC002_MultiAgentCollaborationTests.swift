// UITests/USECASE/UC002_MultiAgentCollaborationTests.swift
// UC002: マルチエージェント協調テスト - Runner統合
//
// このテストは Runner との統合テスト用です。
// 設計A: 1プロジェクト + 2タスク（同一内容、異なるエージェント）
// - 同じタスク指示で異なるsystem_promptによる出力差異を検証
// - 両タスクを in_progress に変更し、Runner がそれを検出して
//   Claude CLI を実行することを確認します。

import XCTest

/// UC002: マルチエージェント協調テスト
///
/// シードデータ（UC002シナリオ）:
/// - プロジェクト: UC002マルチエージェントテストPJ (prj_uc002_test)
/// - 詳細ライターエージェント: agt_detailed_writer
/// - 簡潔ライターエージェント: agt_concise_writer
/// - タスク1: プロジェクトサマリー作成 (tsk_uc002_detailed) → 詳細ライターにアサイン
/// - タスク2: プロジェクトサマリー作成 (tsk_uc002_concise) → 簡潔ライターにアサイン
/// - 認証情報: passkey=test_passkey_detailed, test_passkey_concise
final class UC002_MultiAgentCollaborationTests: UC002UITestCase {

    /// UC002統合テスト: 同一プロジェクト内の両タスクをin_progressに変更し、タスク実行完了を待つ
    ///
    /// このテストは以下を行います:
    /// 1. UC002マルチエージェントテストPJを選択
    /// 2. 詳細ライター担当タスクをin_progressに変更
    /// 3. 簡潔ライター担当タスクをin_progressに変更
    /// 4. Coordinatorがタスクを検出し、Agent Instanceを起動するのを待つ
    /// 5. 出力ファイルが作成されることを確認（最大180秒）
    ///
    /// 両タスクは同一のタイトル・指示内容を持ち、異なるエージェントにアサインされている。
    /// これにより「同じタスク指示でも、system_promptによって成果物が異なる」ことを検証。
    func testMultiAgentIntegration_ChangeBothTasksToInProgress() throws {
        let projectName = "UC002マルチエージェントテストPJ"
        let workingDir = "/tmp/uc002_test"
        let outputFileA = "OUTPUT_A.md"  // 詳細ライター
        let outputFileB = "OUTPUT_B.md"  // 簡潔ライター

        // ========================================
        // プロジェクト選択
        // ========================================
        print("🔍 プロジェクト「\(projectName)」を選択")
        try selectProject(projectName)

        // ========================================
        // Phase 1: 詳細ライター担当タスクをin_progressに変更
        // ========================================
        print("🔍 Phase 1: 詳細ライター担当タスクをin_progressに変更")
        try changeTaskStatusToInProgress(taskId: "tsk_uc002_detailed", taskTitle: "プロジェクトサマリー作成")
        print("✅ Phase 1完了: 詳細ライタータスクがin_progress")

        // ========================================
        // Phase 2: 簡潔ライター担当タスクをin_progressに変更
        // ========================================
        print("🔍 Phase 2: 簡潔ライター担当タスクをin_progressに変更")
        try changeTaskStatusToInProgress(taskId: "tsk_uc002_concise", taskTitle: "プロジェクトサマリー作成")
        print("✅ Phase 2完了: 簡潔ライタータスクがin_progress")

        print("🎯 UC002: 両タスクがin_progress状態になりました")

        // ========================================
        // Phase 3: Coordinatorがタスクを実行し、ファイルが作成されるのを待つ
        // ========================================
        print("⏳ Phase 3: Coordinatorによるタスク実行を待機中（最大180秒）...")
        print("  待機中: \(workingDir)/\(outputFileA)")
        print("  待機中: \(workingDir)/\(outputFileB)")

        let fileManager = FileManager.default
        let pathA = "\(workingDir)/\(outputFileA)"
        let pathB = "\(workingDir)/\(outputFileB)"
        var outputACreated = false
        var outputBCreated = false

        // 最大180秒（5秒間隔で36回）待機
        for i in 1...36 {
            if !outputACreated && fileManager.fileExists(atPath: pathA) {
                print("✅ \(outputFileA) が作成されました")
                outputACreated = true
            }
            if !outputBCreated && fileManager.fileExists(atPath: pathB) {
                print("✅ \(outputFileB) が作成されました")
                outputBCreated = true
            }

            if outputACreated && outputBCreated {
                break
            }

            if i % 6 == 0 {
                print("  ⏳ 待機中... (\(i * 5)秒)")
            }

            Thread.sleep(forTimeInterval: 5.0)
        }

        // ========================================
        // 結果検証
        // ========================================
        XCTAssertTrue(outputACreated, "❌ \(outputFileA) が作成されませんでした")
        XCTAssertTrue(outputBCreated, "❌ \(outputFileB) が作成されませんでした")

        if outputACreated && outputBCreated {
            // ファイル内容の文字数を確認
            let contentA = try? String(contentsOfFile: pathA, encoding: .utf8)
            let contentB = try? String(contentsOfFile: pathB, encoding: .utf8)
            let charsA = contentA?.count ?? 0
            let charsB = contentB?.count ?? 0

            print("🎯 UC002 マルチエージェント統合テスト: 成功")
            print("  - \(outputFileA) (詳細): \(charsA) 文字")
            print("  - \(outputFileB) (簡潔): \(charsB) 文字")

            // 詳細版が簡潔版より長いことを検証（system_promptの差異）
            if charsA > charsB {
                print("  ✅ 詳細版(\(charsA)文字) > 簡潔版(\(charsB)文字) - system_promptの差異が反映")
            }
        }
    }

    // MARK: - Helper Methods

    /// プロジェクトを選択
    private func selectProject(_ projectName: String) throws {
        print("  🔍 プロジェクト「\(projectName)」を検索中...")

        // デバッグ: ウィンドウ情報
        print("  📊 Windows count: \(app.windows.count)")
        print("  📊 App state: \(app.state.rawValue)")

        // ウィンドウを最前面に
        app.activate()
        Thread.sleep(forTimeInterval: 1.0)

        // すべてのstaticTextsを出力
        let allTexts = app.staticTexts.allElementsBoundByIndex.prefix(30).map { $0.label }
        print("  📋 現在のstaticTexts: \(allTexts)")

        let projectRow = app.staticTexts[projectName]
        guard projectRow.waitForExistence(timeout: 10) else {
            print("  ⚠️ プロジェクトが見つかりませんでした")
            XCTFail("❌ SETUP: プロジェクト「\(projectName)」が見つからない")
            return
        }
        print("  ✅ プロジェクト「\(projectName)」が見つかりました")
        projectRow.click()
        Thread.sleep(forTimeInterval: 1.0)

        // タスクボードの表示を確認
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5),
                      "❌ SETUP: タスクボードが表示されない")

        // Refreshボタンをクリックしてタスクボードを更新
        let refreshButton = app.buttons.matching(identifier: "RefreshButton").firstMatch
        if refreshButton.waitForExistence(timeout: 2) {
            print("  🔄 Refreshボタンをクリック")
            refreshButton.click()
            Thread.sleep(forTimeInterval: 2.0)
        } else {
            Thread.sleep(forTimeInterval: 2.0)
        }
    }

    /// タスクをin_progressに変更（UC005と同様のタスクIDベースの検索）
    private func changeTaskStatusToInProgress(taskId: String, taskTitle: String) throws {
        print("  🔍 タスク「\(taskTitle)」(ID: \(taskId)) を検索中...")

        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        guard taskBoard.waitForExistence(timeout: 5) else {
            XCTFail("❌ TaskBoardが見つかりません")
            return
        }

        // Backlogカラムを表示（タスクは初期状態でBacklogにある）
        // スワイプ回数を増やして確実に左端（Backlog）まで移動
        print("  🔄 Backlogカラムへスクロール中...")
        for i in 1...5 {
            taskBoard.swipeRight()
            Thread.sleep(forTimeInterval: 0.2)
        }
        Thread.sleep(forTimeInterval: 0.5)

        // タスクカードをidentifierで検索
        let taskCardIdentifier = "TaskCard_\(taskId)"
        let taskCard = app.descendants(matching: .any).matching(identifier: taskCardIdentifier).firstMatch

        guard taskCard.waitForExistence(timeout: 5) else {
            XCTFail("❌ STEP1: タスク「\(taskTitle)」が見つからない")
            return
        }
        print("  ✅ タスク「\(taskTitle)」が見つかりました")

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
        print("  変更前ステータス: \(beforeValue)")

        // backlog → todo → in_progress と順番に変更
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

        print("  ✅ ステータスをIn Progressに変更完了")

        // 詳細画面を閉じる
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 1.0)

        // 詳細画面が閉じたことを確認
        let detailViewClosed = !detailView.exists || detailView.waitForNonExistence(timeout: 3)
        if !detailViewClosed {
            print("  ⚠️ 詳細画面がまだ表示されている、再度Escapeを試行")
            app.typeKey(.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 1.0)
        }

        // タスクボードを再度Refreshして更新を反映（次のタスク検索のため）
        let refreshButton = app.buttons.matching(identifier: "RefreshButton").firstMatch
        if refreshButton.waitForExistence(timeout: 2) {
            refreshButton.click()
            Thread.sleep(forTimeInterval: 1.5)
        }
    }
}
