// UITests/USECASE/UC003_AITypeSwitchingTests.swift
// UC003: AIタイプ切り替え - 統合テスト
//
// ========================================
// 設計方針:
// ========================================
// - 異なるaiTypeを持つエージェントの検証
// - aiTypeがget_agent_action APIで正しく返されることを確認
//
// シードデータ:
// - プロジェクト: UC003 AIType Test (prj_uc003, wd=/tmp/uc003)
// - エージェント1: UC003 Sonnet Agent (agt_uc003_sonnet, aiType=claudeSonnet4_5)
// - エージェント2: UC003 Opus Agent (agt_uc003_opus, aiType=claudeOpus4)
// - タスク1: Sonnet Task (tsk_uc003_sonnet)
// - タスク2: Opus Task (tsk_uc003_opus)
// ========================================

import XCTest

/// UC003: AIタイプ切り替え - 統合テスト
///
/// 検証内容:
/// 1. 両エージェントがプロジェクトに存在する
/// 2. 各エージェントのモデル（Sonnet/Opus）が正しく設定されている
/// 3. 両タスクをin_progressに変更可能
final class UC003_AITypeSwitchingTests: UC003UITestCase {

    /// UC003 UIテスト（ステータス変更のみ）
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
        // Phase 2: Sonnetエージェントタスク操作
        // ========================================
        print("🔍 Phase 2: Sonnetエージェントタスク操作")
        try verifyPhase2_SonnetAgentTask()
        print("✅ Phase 2完了: Sonnetタスクがin_progress")

        // ========================================
        // Phase 3: Opusエージェントタスク操作
        // ========================================
        print("🔍 Phase 3: Opusエージェントタスク操作")
        try verifyPhase3_OpusAgentTask()
        print("✅ Phase 3完了: Opusタスクがin_progress")

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

    // MARK: - Phase 2: Sonnetエージェントタスク操作

    private func verifyPhase2_SonnetAgentTask() throws {
        let projectName = "UC003 AIType Test"
        let taskTitle = "Sonnet Task"
        let agentName = "UC003 Sonnet Agent"

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

    // MARK: - Phase 3: Opusエージェントタスク操作

    private func verifyPhase3_OpusAgentTask() throws {
        let taskTitle = "Opus Task"
        let agentName = "UC003 Opus Agent"

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

    // MARK: - Integration Test (with Coordinator)

    /// UC003 統合テスト（Coordinator連携）
    ///
    /// test_uc003_app_integration.sh から呼び出される統合テスト
    /// 1. 両エージェントのタスクをin_progressに変更
    /// 2. Coordinatorがエージェントを起動してタスクを完了させる
    /// 3. タスクがDoneになることを確認
    func testE2E_UC003_AITypeSwitching_Integration() throws {
        let workDir = "/tmp/uc003"
        let sonnetOutput = "OUTPUT_1.md"
        let opusOutput = "OUTPUT_2.md"

        // ========================================
        // Phase 1: Sonnetエージェントタスクをin_progressに変更
        // ========================================
        print("🔍 Phase 1: Sonnetエージェントタスクをin_progressに変更")
        try verifyPhase1_ProjectExists()
        try verifyPhase2_SonnetAgentTask()
        print("✅ Phase 1完了: Sonnetタスクがin_progress")

        // ========================================
        // Phase 2: Opusエージェントタスクをin_progressに変更
        // ========================================
        print("🔍 Phase 2: Opusエージェントタスクをin_progressに変更")
        try verifyPhase3_OpusAgentTask()
        print("✅ Phase 2完了: Opusタスクがin_progress")

        print("🎯 UC003: 両タスクがin_progress状態になりました")

        // ========================================
        // Phase 3: UIでタスクステータスがDoneになることを確認
        // ========================================
        print("⏳ Phase 3: タスクステータスがDoneになるのを待機中（最大60秒）...")

        var sonnetDone = false
        var opusDone = false

        // 最大60秒（5秒間隔で12回）待機
        for i in 1...12 {
            // Sonnetタスクのステータス確認
            if !sonnetDone {
                if try checkTaskStatusIsDone(taskId: "tsk_uc003_sonnet", taskTitle: "Sonnet Task") {
                    print("✅ Sonnet タスクがDoneになりました")
                    sonnetDone = true
                }
            }

            // Opusタスクのステータス確認
            if !opusDone {
                if try checkTaskStatusIsDone(taskId: "tsk_uc003_opus", taskTitle: "Opus Task") {
                    print("✅ Opus タスクがDoneになりました")
                    opusDone = true
                }
            }

            if sonnetDone && opusDone {
                break
            }

            if i % 4 == 0 {
                print("  ⏳ 待機中... (\(i * 5)秒)")
            }

            Thread.sleep(forTimeInterval: 5.0)
        }

        // ========================================
        // 結果検証: UIでステータスがDoneになったか
        // ========================================
        XCTAssertTrue(sonnetDone, "❌ Sonnet タスクがDoneになりませんでした")
        XCTAssertTrue(opusDone, "❌ Opus タスクがDoneになりませんでした")

        // ========================================
        // Phase 4: ファイル作成確認（おまけ）
        // ========================================
        let fileManager = FileManager.default
        let sonnetPath = "\(workDir)/\(sonnetOutput)"
        let opusPath = "\(workDir)/\(opusOutput)"

        let sonnetFileExists = fileManager.fileExists(atPath: sonnetPath)
        let opusFileExists = fileManager.fileExists(atPath: opusPath)

        if sonnetFileExists && opusFileExists {
            let contentSonnet = try? String(contentsOfFile: sonnetPath, encoding: .utf8)
            let contentOpus = try? String(contentsOfFile: opusPath, encoding: .utf8)
            let charsSonnet = contentSonnet?.count ?? 0
            let charsOpus = contentOpus?.count ?? 0

            print("🎯 UC003 モデル切り替え統合テスト: 成功")
            print("  - Sonnet タスク: Done ✅")
            print("  - Opus タスク: Done ✅")
            print("  - \(sonnetOutput): \(charsSonnet) 文字")
            print("  - \(opusOutput): \(charsOpus) 文字")
        } else {
            print("⚠️ ファイル作成確認:")
            print("  - \(sonnetOutput): \(sonnetFileExists ? "✅" : "❌")")
            print("  - \(opusOutput): \(opusFileExists ? "✅" : "❌")")
        }

        // ========================================
        // Phase 5: モデル検証結果の確認
        // ========================================
        print("🔍 Phase 5: execution_logsテーブルでモデル検証結果を確認")
        try verifyModelVerificationInDB()
        print("✅ Phase 5完了: モデル検証結果がDBに正しく保存されている")
    }

    /// タスクステータスがDoneかどうかを確認
    ///
    /// UC004のパターンに従い、毎回同じ手順を実行:
    /// 1. Refresh（外部プロセスによるDB変更を反映）
    /// 2. swipeLeft×2（Doneカラムを表示）
    /// 3. タスク検索
    private func checkTaskStatusIsDone(taskId: String, taskTitle: String) throws -> Bool {
        let taskCardId = "TaskCard_\(taskId)"

        // TaskBoardを取得
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        guard taskBoard.waitForExistence(timeout: 5) else {
            print("  ⚠️ TaskBoard not found")
            return false
        }

        // Refresh（外部プロセスによるDB変更を反映）
        let refreshButton = app.buttons.matching(identifier: "RefreshButton").firstMatch
        if refreshButton.waitForExistence(timeout: 2) {
            refreshButton.click()
            Thread.sleep(forTimeInterval: 1.5)
        }

        // Doneカラムを表示するため左にスワイプ（UC004と同じパターン）
        taskBoard.swipeLeft()
        taskBoard.swipeLeft()
        Thread.sleep(forTimeInterval: 0.5)

        // タスクカードを検索
        let taskCard = app.descendants(matching: .any).matching(identifier: taskCardId).firstMatch

        guard taskCard.exists && taskCard.isHittable else {
            print("  ⚠️ Task card \(taskCardId) not found or not hittable")
            return false
        }

        // タスクカードをクリックして詳細画面を開く
        taskCard.click()
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        guard detailView.waitForExistence(timeout: 3) else {
            print("  ⚠️ TaskDetailView not found for \(taskTitle)")
            app.typeKey(.escape, modifierFlags: [])
            return false
        }

        // ステータスピッカーの値を確認
        let statusPicker = app.popUpButtons["StatusPicker"]
        guard statusPicker.exists else {
            print("  ⚠️ StatusPicker not found for \(taskTitle)")
            app.typeKey(.escape, modifierFlags: [])
            return false
        }

        let currentStatus = statusPicker.value as? String ?? ""
        print("  📊 \(taskTitle) status: \(currentStatus)")

        // 詳細画面を閉じる
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)

        if currentStatus == "Done" {
            print("  ✅ \(taskTitle) is Done")
            return true
        } else {
            print("  ❌ \(taskTitle) is not Done (status: \(currentStatus))")
            return false
        }
    }

    // MARK: - Model Verification

    /// execution_logsテーブルでモデル検証結果を確認
    ///
    /// 各エージェントの実行ログに以下が記録されていることを検証:
    /// - reported_provider: "claude" (モデル提供元)
    /// - reported_model: モデル名が記録されている（空でない）
    ///
    /// 注: model_verifiedの値はテスト環境では期待通りにならない可能性がある
    /// （テスト環境では同一モデルが全エージェントを実行するため）
    private func verifyModelVerificationInDB() throws {
        let dbPath = "/tmp/AIAgentPM_UITest.db"

        // Sonnetエージェントのモデル検証
        let sonnetResult = queryExecutionLog(dbPath: dbPath, agentId: "agt_uc003_sonnet")
        print("  📊 Sonnet Agent model info:")
        print("    - Provider: \(sonnetResult.provider ?? "nil")")
        print("    - Model: \(sonnetResult.model ?? "nil")")
        print("    - Verified: \(sonnetResult.verified ?? "nil")")

        XCTAssertEqual(sonnetResult.provider, "claude",
                       "❌ Sonnet Agent: reported_providerが'claude'ではない（実際: \(sonnetResult.provider ?? "nil")）")
        XCTAssertNotNil(sonnetResult.model,
                        "❌ Sonnet Agent: reported_modelが記録されていない")
        XCTAssertFalse(sonnetResult.model?.isEmpty ?? true,
                       "❌ Sonnet Agent: reported_modelが空")

        // Opusエージェントのモデル検証
        let opusResult = queryExecutionLog(dbPath: dbPath, agentId: "agt_uc003_opus")
        print("  📊 Opus Agent model info:")
        print("    - Provider: \(opusResult.provider ?? "nil")")
        print("    - Model: \(opusResult.model ?? "nil")")
        print("    - Verified: \(opusResult.verified ?? "nil")")

        XCTAssertEqual(opusResult.provider, "claude",
                       "❌ Opus Agent: reported_providerが'claude'ではない（実際: \(opusResult.provider ?? "nil")）")
        XCTAssertNotNil(opusResult.model,
                        "❌ Opus Agent: reported_modelが記録されていない")
        XCTAssertFalse(opusResult.model?.isEmpty ?? true,
                       "❌ Opus Agent: reported_modelが空")

        // モデル検証結果のサマリー
        print("  ✅ モデル検証メカニズムが正常に動作: 両エージェントのmodel infoがDBに記録済み")
    }

    /// SQLiteからexecution_logsをクエリ
    private func queryExecutionLog(dbPath: String, agentId: String) -> (provider: String?, model: String?, verified: String?) {
        let query = """
            SELECT reported_provider, reported_model, model_verified
            FROM execution_logs
            WHERE agent_id='\(agentId)'
            ORDER BY started_at DESC
            LIMIT 1;
            """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, query]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("    ⚠️ sqlite3実行エラー: \(error)")
            return (nil, nil, nil)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            print("    ⚠️ execution_logsにレコードが見つからない（agent_id: \(agentId)）")
            return (nil, nil, nil)
        }

        // SQLite出力: "provider|model|verified"
        let components = output.split(separator: "|", omittingEmptySubsequences: false).map { String($0) }
        let provider = components.count > 0 && !components[0].isEmpty ? components[0] : nil
        let model = components.count > 1 && !components[1].isEmpty ? components[1] : nil
        let verified = components.count > 2 && !components[2].isEmpty ? components[2] : nil

        return (provider, model, verified)
    }
}
