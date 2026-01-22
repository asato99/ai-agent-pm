// UITests/USECASE/UC011_ProjectPauseIntegrationTests.swift
// UC011: プロジェクト一時停止 - Runner統合テスト
//
// 要件: docs/plan/PROJECT_PAUSE_FEATURE.md
// テスト設計: docs/usecase/UC011_PROJECT_PAUSE.md
//
// テストシナリオ:
// 1. 実行中エージェントへのexit指示（最重要）
// 2. 新規エージェント起動のブロック
// 3. 再開後のタスク継続
//
// フレーキー回避策:
// - 段階的ファイル作成タスクを使用
// - step1.md作成で「実行中」と判断
// - complete.md作成で「完了」と判断

import XCTest

/// UC011: プロジェクト一時停止 - 統合テスト
///
/// シードデータ（UC011シナリオ）:
/// - プロジェクト: UC011 Pause Test (prj_uc011, wd=/tmp/uc011_test)
/// - エージェント: UC011開発者 (agt_uc011_dev)
/// - タスク: UC011テストタスク (tsk_uc011_main) → 段階的ファイル作成
/// - 認証情報: passkey=test_passkey_uc011
final class UC011_ProjectPauseIntegrationTests: UC011UITestCase {

    let projectName = "UC011 Pause Test"
    let projectId = "prj_uc011"
    let taskId = "tsk_uc011_main"
    let taskTitle = "UC011テストタスク"
    let agentId = "agt_uc011_dev"
    let workingDir = "/tmp/uc011_test"

    // DB検証用
    let dbPath = "/tmp/AIAgentPM_UITest.db"

    // ファイルマーカー
    let completeFile = "complete.md" // 完了マーカー

    // MARK: - DB Helper Methods

    /// プロジェクトのステータスをDBから取得
    private func getProjectStatusFromDB() -> String? {
        let query = "SELECT status FROM projects WHERE id = '\(projectId)';"

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
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        return output
    }

    // MARK: - Integration Tests

    /// UC011統合テスト: 実行中エージェントの停止→再開→完了
    ///
    /// このテストは以下を検証:
    /// 1. タスク開始後、エージェントが実行中になる（ファイル作成検出）
    /// 2. 一時停止により、プロジェクトステータスがpausedに変更される（DB検証）
    /// 3. 再開により、エージェントがタスクを完了する（complete.md作成）
    func testPauseResumeIntegration_RunningAgentStopsAndResumes() throws {
        print("🔍 UC011統合テスト開始: 実行中エージェント停止→再開フロー")

        let fileManager = FileManager.default
        let completePath = "\(workingDir)/\(completeFile)"

        // ========================================
        // Phase 1: タスク開始
        // ========================================
        print("📌 Phase 1: タスクを開始")
        try selectProject(projectName)
        try changeTaskStatusToInProgress(taskId: taskId, taskTitle: taskTitle)
        print("✅ Phase 1完了: タスクをin_progressに変更")

        // ========================================
        // Phase 2: エージェント実行中を確認
        // ========================================
        print("📌 Phase 2: エージェントが実行中になるのを待機")

        // 任意の.mdファイル作成を待機（最大120秒）
        // LLMはタスク指示の順番を必ずしも守らないため、任意のファイル作成を検出
        var anyFileCreated = false
        var createdFile = ""
        for i in 1...24 {
            if let files = try? fileManager.contentsOfDirectory(atPath: workingDir) {
                let mdFiles = files.filter { $0.hasSuffix(".md") }
                if !mdFiles.isEmpty {
                    anyFileCreated = true
                    createdFile = mdFiles.first ?? ""
                    print("  ✓ ファイル作成検出: \(mdFiles) (\(i * 5)秒後) → エージェント実行中")
                    break
                }
            }
            if i % 4 == 0 {
                print("  ⏳ ファイル待機中... (\(i * 5)秒)")
            }
            Thread.sleep(forTimeInterval: 5)
        }

        guard anyFileCreated else {
            XCTFail("❌ Phase 2失敗: ファイルが作成されない（エージェントが起動していない）")
            return
        }
        print("✅ Phase 2完了: エージェントが実行中であることを確認")

        // ========================================
        // Phase 3: 一時停止
        // ========================================
        print("📌 Phase 3: プロジェクトを一時停止")
        try pauseProject(projectName)
        print("✅ Phase 3完了: プロジェクトを一時停止")

        // ========================================
        // Phase 4: 一時停止中の検証（DBステータス確認）
        // ========================================
        print("📌 Phase 4: プロジェクトステータスがpausedであることを確認")

        // DBからプロジェクトステータスを取得して検証
        Thread.sleep(forTimeInterval: 1)  // DB反映待機
        let pausedStatus = getProjectStatusFromDB()
        print("  DBのプロジェクトステータス: \(pausedStatus ?? "取得失敗")")

        XCTAssertEqual(pausedStatus, "paused", "❌ Phase 4失敗: プロジェクトステータスがpausedになっていない")
        print("✅ Phase 4完了: プロジェクトステータスがpausedであることを確認")

        // ========================================
        // Phase 5: 再開
        // ========================================
        print("📌 Phase 5: プロジェクトを再開")
        try resumeProject(projectName)
        print("✅ Phase 5完了: プロジェクトを再開")

        // ========================================
        // Phase 6: タスク完了待機
        // ========================================
        print("📌 Phase 6: タスク完了を待機")

        // complete.md作成を待機（最大180秒）
        var completeCreated = false
        for i in 1...36 {
            if fileManager.fileExists(atPath: completePath) {
                completeCreated = true
                print("  ✓ complete.md作成検出 (\(i * 5)秒後) → タスク完了")
                break
            }
            if i % 6 == 0 {
                print("  ⏳ complete.md待機中... (\(i * 5)秒)")
            }
            Thread.sleep(forTimeInterval: 5)
        }

        XCTAssertTrue(completeCreated, "❌ Phase 6失敗: complete.mdが作成されない")
        print("✅ Phase 6完了: タスクが完了")

        // ========================================
        // Phase 7: ファイル内容検証
        // ========================================
        print("📌 Phase 7: ファイル内容を検証")

        if let content = try? String(contentsOfFile: completePath, encoding: .utf8) {
            XCTAssertTrue(
                content.contains("uc011 integration test content"),
                "❌ ファイル内容に期待する文字列が含まれていない"
            )
            print("✅ Phase 7完了: ファイル内容が正しい")
        } else {
            XCTFail("❌ complete.mdの内容を読み取れない")
        }

        print("🎉 UC011統合テスト完了: 実行中エージェント停止→再開フローが正常に動作")
    }

    /// UC011テスト: 新規エージェント起動のブロック（シナリオ2）
    ///
    /// 一時停止中は新規エージェントが起動されないことを確認
    func testPauseBlocksNewAgentStart() throws {
        print("🔍 UC011テスト開始: 新規エージェント起動のブロック")

        let fileManager = FileManager.default

        // ========================================
        // Phase 1: 先に一時停止
        // ========================================
        print("📌 Phase 1: プロジェクトを先に一時停止")
        try selectProject(projectName)
        try pauseProject(projectName)
        print("✅ Phase 1完了: プロジェクトを一時停止")

        // ========================================
        // Phase 2: タスクをin_progressに変更
        // ========================================
        print("📌 Phase 2: タスクをin_progressに変更（一時停止中）")
        try changeTaskStatusToInProgress(taskId: taskId, taskTitle: taskTitle)
        print("✅ Phase 2完了: タスクをin_progressに変更")

        // ========================================
        // Phase 3: エージェントが起動されないことを確認
        // ========================================
        print("📌 Phase 3: エージェントが起動されないことを確認")
        print("  ⏳ 30秒待機中...")
        Thread.sleep(forTimeInterval: 30)

        // 任意の.mdファイルが作成されていないことを確認
        let mdFiles = (try? fileManager.contentsOfDirectory(atPath: workingDir))?.filter { $0.hasSuffix(".md") } ?? []
        XCTAssertTrue(
            mdFiles.isEmpty,
            "❌ 一時停止中にファイルが作成された: \(mdFiles)（エージェントが起動された）"
        )
        print("✅ Phase 3完了: ファイル未作成（エージェントは起動されていない）")

        // ========================================
        // Phase 4: 再開してエージェント起動を確認
        // ========================================
        print("📌 Phase 4: プロジェクトを再開")
        try resumeProject(projectName)

        // 任意のファイル作成を待機
        var fileCreated = false
        for i in 1...24 {
            if let files = try? fileManager.contentsOfDirectory(atPath: workingDir) {
                let newMdFiles = files.filter { $0.hasSuffix(".md") }
                if !newMdFiles.isEmpty {
                    fileCreated = true
                    print("  ✓ ファイル作成検出: \(newMdFiles) (\(i * 5)秒後) → エージェント起動")
                    break
                }
            }
            Thread.sleep(forTimeInterval: 5)
        }

        XCTAssertTrue(fileCreated, "❌ 再開後もファイルが作成されない")
        print("✅ Phase 4完了: 再開後にエージェントが起動")

        print("🎉 UC011テスト完了: 新規エージェント起動のブロックが正常に動作")
    }

    // MARK: - Helper Methods

    /// プロジェクトを選択
    private func selectProject(_ name: String) throws {
        let projectRow = app.staticTexts[name]
        guard projectRow.waitForExistence(timeout: 10) else {
            XCTFail("❌ プロジェクト「\(name)」が見つからない")
            throw TestError.failedPrecondition("Project not found")
        }
        projectRow.click()
        Thread.sleep(forTimeInterval: 0.5)

        // タスクボードの表示を確認
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        guard taskBoard.waitForExistence(timeout: 5) else {
            XCTFail("❌ タスクボードが表示されない")
            throw TestError.failedPrecondition("TaskBoard not visible")
        }
    }

    /// タスクのステータスをin_progressに変更
    private func changeTaskStatusToInProgress(taskId: String, taskTitle: String) throws {
        // タスクを探す
        let taskCard = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", taskTitle)).firstMatch
        guard taskCard.waitForExistence(timeout: 5) else {
            XCTFail("❌ タスク「\(taskTitle)」が見つからない")
            throw TestError.failedPrecondition("Task not found")
        }

        // タスク詳細を開く
        taskCard.click()
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        guard detailView.waitForExistence(timeout: 5) else {
            XCTFail("❌ タスク詳細画面が開かない")
            throw TestError.failedPrecondition("TaskDetailView not visible")
        }

        // ステータスピッカー
        let statusPicker = app.popUpButtons["StatusPicker"]
        guard statusPicker.waitForExistence(timeout: 3) else {
            XCTFail("❌ StatusPickerが見つからない")
            throw TestError.failedPrecondition("StatusPicker not found")
        }

        let beforeValue = statusPicker.value as? String ?? ""
        print("  現在のステータス: \(beforeValue)")

        // backlog → todo → in_progress と順番に変更
        if beforeValue == "Backlog" {
            statusPicker.click()
            Thread.sleep(forTimeInterval: 0.3)
            let todoOption = app.menuItems["To Do"]
            guard todoOption.waitForExistence(timeout: 2) else {
                XCTFail("❌ To Doオプションが見つからない")
                throw TestError.failedPrecondition("To Do option not found")
            }
            todoOption.click()
            Thread.sleep(forTimeInterval: 0.5)
            print("  Backlog → To Do 完了")
        }

        // To Do → In Progress
        statusPicker.click()
        Thread.sleep(forTimeInterval: 0.3)
        let inProgressOption = app.menuItems["In Progress"]
        guard inProgressOption.waitForExistence(timeout: 2) else {
            XCTFail("❌ In Progressオプションが見つからない")
            throw TestError.failedPrecondition("In Progress option not found")
        }
        inProgressOption.click()
        Thread.sleep(forTimeInterval: 0.5)
        print("  → In Progress 完了")

        // エラーシートが表示されないことを確認
        let alertSheet = app.sheets.firstMatch
        if alertSheet.waitForExistence(timeout: 1) {
            let okButton = alertSheet.buttons["OK"]
            if okButton.exists { okButton.click() }
            XCTFail("❌ ステータス変更がブロックされた")
            throw TestError.failedPrecondition("Status change blocked")
        }
    }

    /// プロジェクトを一時停止
    private func pauseProject(_ name: String) throws {
        // プロジェクト行を右クリック
        let projectRow = app.staticTexts[name]
        guard projectRow.waitForExistence(timeout: 5) else {
            XCTFail("❌ プロジェクト「\(name)」が見つからない")
            throw TestError.failedPrecondition("Project not found")
        }

        projectRow.rightClick()
        Thread.sleep(forTimeInterval: 0.3)

        // コンテキストメニューから「一時停止」を選択
        let pauseMenuItem = app.menuItems["PauseProjectMenuItem"]
        guard pauseMenuItem.waitForExistence(timeout: 3) else {
            // メニューが表示されない場合はEscでキャンセル
            app.typeKey(.escape, modifierFlags: [])
            XCTFail("❌ PauseProjectMenuItemが見つからない")
            throw TestError.failedPrecondition("Pause menu item not found")
        }
        pauseMenuItem.click()
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// プロジェクトを再開
    private func resumeProject(_ name: String) throws {
        // プロジェクト行を右クリック
        let projectRow = app.staticTexts[name]
        guard projectRow.waitForExistence(timeout: 5) else {
            XCTFail("❌ プロジェクト「\(name)」が見つからない")
            throw TestError.failedPrecondition("Project not found")
        }

        projectRow.rightClick()
        Thread.sleep(forTimeInterval: 0.3)

        // コンテキストメニューから「再開」を選択
        let resumeMenuItem = app.menuItems["ResumeProjectMenuItem"]
        guard resumeMenuItem.waitForExistence(timeout: 3) else {
            // メニューが表示されない場合はEscでキャンセル
            app.typeKey(.escape, modifierFlags: [])
            XCTFail("❌ ResumeProjectMenuItemが見つからない")
            throw TestError.failedPrecondition("Resume menu item not found")
        }
        resumeMenuItem.click()
        Thread.sleep(forTimeInterval: 0.5)
    }
}
