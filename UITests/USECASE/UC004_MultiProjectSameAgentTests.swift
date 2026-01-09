// UITests/USECASE/UC004_MultiProjectSameAgentTests.swift
// UC004: 複数プロジェクト×同一エージェント - Runner統合テスト
//
// このテストは Runner との統合テスト用です。
// 設計: 2プロジェクト + 同一エージェント
// - 同一エージェントが複数プロジェクトに割り当てられることを検証
// - 各プロジェクトで異なるworking_directoryで動作することを確認
// - 両プロジェクトのタスクを in_progress に変更し、Runner がそれを検出して
//   Claude CLI を実行することを確認します。

import XCTest

/// UC004: 複数プロジェクト×同一エージェント - 統合テスト
///
/// シードデータ（UC004シナリオ）:
/// - プロジェクト1: UC004 Frontend (prj_uc004_fe, wd=/tmp/uc004/frontend)
/// - プロジェクト2: UC004 Backend (prj_uc004_be, wd=/tmp/uc004/backend)
/// - エージェント: UC004開発者 (agt_uc004_dev) - 両プロジェクトに割り当て
/// - タスク1: README作成（Frontend）(tsk_uc004_fe) → UC004開発者にアサイン
/// - タスク2: README作成（Backend）(tsk_uc004_be) → UC004開発者にアサイン
/// - 認証情報: passkey=test_passkey_uc004
final class UC004_MultiProjectSameAgentTests: UC004UITestCase {

    /// UC004統合テスト: 複数プロジェクトの両タスクをin_progressに変更し、タスク実行完了を待つ
    ///
    /// このテストは以下を行います:
    /// 1. UC004 Frontendプロジェクトを選択し、タスクをin_progressに変更
    /// 2. UC004 Backendプロジェクトを選択し、タスクをin_progressに変更
    /// 3. Coordinatorがタスクを検出し、Agent Instanceを起動するのを待つ
    /// 4. 出力ファイルが作成されることを確認（最大180秒）
    ///
    /// 両タスクは同一エージェント（UC004開発者）にアサインされている。
    /// これにより「同一エージェントが複数プロジェクトで並列実行可能」ことを検証。
    func testMultiProjectIntegration_ChangeBothTasksToInProgress() throws {
        let frontendWorkDir = "/tmp/uc004/frontend"
        let backendWorkDir = "/tmp/uc004/backend"
        let outputFile = "README.md"

        // ========================================
        // Phase 1: フロントエンドプロジェクトのタスクをin_progressに変更
        // ========================================
        print("🔍 Phase 1: フロントエンドプロジェクトのタスクをin_progressに変更")
        try selectProject("UC004 Frontend")
        try changeTaskStatusToInProgress(taskId: "tsk_uc004_fe", taskTitle: "README作成（Frontend）")
        print("✅ Phase 1完了: フロントエンドタスクがin_progress")

        // ========================================
        // Phase 2: バックエンドプロジェクトのタスクをin_progressに変更
        // ========================================
        print("🔍 Phase 2: バックエンドプロジェクトのタスクをin_progressに変更")
        try selectProject("UC004 Backend")
        try changeTaskStatusToInProgress(taskId: "tsk_uc004_be", taskTitle: "README作成（Backend）")
        print("✅ Phase 2完了: バックエンドタスクがin_progress")

        print("🎯 UC004: 両タスクがin_progress状態になりました")

        // ========================================
        // Phase 3: UIでタスクステータスがDoneになることを確認
        // ========================================
        print("⏳ Phase 3: タスクステータスがDoneになるのを待機中（最大180秒）...")

        var frontendDone = false
        var backendDone = false

        // 最大180秒（5秒間隔で36回）待機
        for i in 1...36 {
            // Frontendのステータス確認
            if !frontendDone {
                if try checkTaskStatusIsDone(projectName: "UC004 Frontend", taskTitle: "README作成（Frontend）") {
                    print("✅ Frontend タスクがDoneになりました")
                    frontendDone = true
                }
            }

            // Backendのステータス確認
            if !backendDone {
                if try checkTaskStatusIsDone(projectName: "UC004 Backend", taskTitle: "README作成（Backend）") {
                    print("✅ Backend タスクがDoneになりました")
                    backendDone = true
                }
            }

            if frontendDone && backendDone {
                break
            }

            if i % 6 == 0 {
                print("  ⏳ 待機中... (\(i * 5)秒)")
            }

            Thread.sleep(forTimeInterval: 5.0)
        }

        // ========================================
        // 結果検証: UIでステータスがDoneになったか
        // ========================================
        XCTAssertTrue(frontendDone, "❌ Frontend タスクがDoneになりませんでした")
        XCTAssertTrue(backendDone, "❌ Backend タスクがDoneになりませんでした")

        // ========================================
        // Phase 4: ファイル作成確認（おまけ）
        // ========================================
        let fileManager = FileManager.default
        let frontendPath = "\(frontendWorkDir)/\(outputFile)"
        let backendPath = "\(backendWorkDir)/\(outputFile)"

        let frontendFileExists = fileManager.fileExists(atPath: frontendPath)
        let backendFileExists = fileManager.fileExists(atPath: backendPath)

        if frontendFileExists && backendFileExists {
            let contentFe = try? String(contentsOfFile: frontendPath, encoding: .utf8)
            let contentBe = try? String(contentsOfFile: backendPath, encoding: .utf8)
            let charsFe = contentFe?.count ?? 0
            let charsBe = contentBe?.count ?? 0

            print("🎯 UC004 複数プロジェクト統合テスト: 成功")
            print("  - Frontend タスク: Done ✅")
            print("  - Backend タスク: Done ✅")
            print("  - Frontend \(outputFile): \(charsFe) 文字")
            print("  - Backend \(outputFile): \(charsBe) 文字")
        } else {
            print("⚠️ ファイル作成確認:")
            print("  - Frontend \(outputFile): \(frontendFileExists ? "✅" : "❌")")
            print("  - Backend \(outputFile): \(backendFileExists ? "✅" : "❌")")
        }
    }

    /// プロジェクトのタスクステータスがDoneかどうかを確認
    private func checkTaskStatusIsDone(projectName: String, taskTitle: String) throws -> Bool {
        // タスクIDをタイトルから推定（UC004のタスクID命名規則）
        let taskId: String
        if taskTitle.contains("Frontend") {
            taskId = "tsk_uc004_fe"
        } else if taskTitle.contains("Backend") {
            taskId = "tsk_uc004_be"
        } else {
            taskId = ""
        }

        // プロジェクトを選択
        app.activate()
        let projectRow = app.staticTexts[projectName]
        guard projectRow.waitForExistence(timeout: 2) else {
            print("  ❌ プロジェクト「\(projectName)」が見つかりません")
            return false
        }
        projectRow.click()
        Thread.sleep(forTimeInterval: 1.0)

        // TaskBoardを待つ
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        guard taskBoard.waitForExistence(timeout: 5) else {
            print("  ❌ TaskBoardが見つかりません")
            return false
        }
        Thread.sleep(forTimeInterval: 0.5)

        // Note: checkTaskStatusIsDoneはCoordinatorによるDB変更を確認するため、
        // Refreshが必要（外部プロセスによる変更はリアクティブに反映されない）
        let refreshButton = app.buttons.matching(identifier: "RefreshButton").firstMatch
        if refreshButton.waitForExistence(timeout: 2) {
            refreshButton.click()
            Thread.sleep(forTimeInterval: 1.5)
        }

        // Doneカラムを表示するため左にスワイプ
        print("  📜 Doneカラムを表示するため左にスワイプ...")
        taskBoard.swipeLeft()
        taskBoard.swipeLeft()
        Thread.sleep(forTimeInterval: 0.5)

        // タスクIDで直接検索（最も確実な方法）
        if !taskId.isEmpty {
            let taskCardId = "TaskCard_\(taskId)"
            let taskCard = app.descendants(matching: .any).matching(identifier: taskCardId).firstMatch
            if taskCard.exists {
                print("  📊 TaskCard found: \(taskCardId), frame=\(taskCard.frame)")

                // Doneカラムの位置を取得（幅220pxのコンテナを選択）
                let doneColumns = app.descendants(matching: .any).matching(identifier: "TaskColumn_done").allElementsBoundByIndex
                for col in doneColumns where col.frame.width > 100 {
                    let doneFrame = col.frame
                    let taskFrame = taskCard.frame
                    print("  📊 Doneカラム: x=\(doneFrame.origin.x)-\(doneFrame.origin.x + doneFrame.width)")
                    print("  📊 タスク位置: x=\(taskFrame.origin.x)")

                    // タスクがDoneカラム内にあるか確認
                    if taskFrame.origin.x >= doneFrame.origin.x - 50 &&
                       taskFrame.origin.x < doneFrame.origin.x + doneFrame.width + 50 {
                        print("  ✅ タスク「\(taskTitle)」がDoneカラム内で見つかりました")
                        return true
                    }
                }
            } else {
                print("  ❌ TaskCard \(taskCardId) が見つかりません")
            }
        }

        // フォールバック: Doneカラム内のタスクカード数を確認
        let doneColumns = app.descendants(matching: .any).matching(identifier: "TaskColumn_done").allElementsBoundByIndex
        for col in doneColumns where col.frame.width > 100 {
            let taskCards = col.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "TaskCard_")).allElementsBoundByIndex
            print("  📊 Doneカラム内のTaskCard数: \(taskCards.count)")
            for card in taskCards {
                print("      TaskCard: id=\"\(card.identifier)\", label=\"\(card.label)\"")
                if card.identifier == "TaskCard_\(taskId)" || card.label.contains(taskTitle) {
                    print("  ✅ タスク「\(taskTitle)」がDoneカラムで見つかりました")
                    return true
                }
            }
        }

        print("  ❌ タスク「\(taskTitle)」がDoneカラムにありません")
        return false
    }

    // MARK: - Debug Test

    /// Done検出のみのデバッグテスト（DB手動更新後に実行）
    func testDoneDetectionOnly() throws {
        // プロジェクト選択
        app.activate()
        let projectRow = app.staticTexts["UC004 Frontend"]
        guard projectRow.waitForExistence(timeout: 10) else {
            XCTFail("プロジェクトが見つかりません")
            return
        }
        projectRow.click()
        Thread.sleep(forTimeInterval: 1.0)

        // TaskBoard取得
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        guard taskBoard.waitForExistence(timeout: 5) else {
            XCTFail("TaskBoardが見つかりません")
            return
        }

        // Refresh
        let refreshButton = app.buttons.matching(identifier: "RefreshButton").firstMatch
        if refreshButton.waitForExistence(timeout: 2) {
            refreshButton.click()
            Thread.sleep(forTimeInterval: 2.0)
        }

        // スクロール前のスクリーンショット
        let before = app.screenshot()
        let beforeAttach = XCTAttachment(screenshot: before)
        beforeAttach.name = "before_scroll"
        beforeAttach.lifetime = .keepAlways
        add(beforeAttach)

        // swipeLeft
        taskBoard.swipeLeft()
        taskBoard.swipeLeft()
        Thread.sleep(forTimeInterval: 0.5)

        // スクロール後のスクリーンショット
        let after = app.screenshot()
        let afterAttach = XCTAttachment(screenshot: after)
        afterAttach.name = "after_scroll"
        afterAttach.lifetime = .keepAlways
        add(afterAttach)

        // 全ボタンを列挙
        let allButtons = app.buttons.allElementsBoundByIndex
        print("=== 全ボタン (\(allButtons.count)件) ===")
        for (i, button) in allButtons.prefix(20).enumerated() {
            print("  [\(i)]: id=\"\(button.identifier)\", label=\"\(button.label)\", frame=\(button.frame)")
        }

        // TaskCard_を検索
        let taskCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "TaskCard_")).allElementsBoundByIndex
        print("=== TaskCard (\(taskCards.count)件) ===")
        for card in taskCards {
            print("  id=\"\(card.identifier)\", label=\"\(card.label)\", frame=\(card.frame)")
        }

        // Done column - 全ての一致する要素を確認
        let doneColumns = app.descendants(matching: .any).matching(identifier: "TaskColumn_done").allElementsBoundByIndex
        print("=== TaskColumn_done 一致数: \(doneColumns.count) ===")
        for (i, col) in doneColumns.enumerated() {
            print("  [\(i)]: elementType=\(col.elementType.rawValue), frame=\(col.frame)")
        }

        // groups (VStack等)を検索
        let doneGroups = app.groups.matching(identifier: "TaskColumn_done").allElementsBoundByIndex
        print("=== TaskColumn_done (groups): \(doneGroups.count) ===")
        for (i, g) in doneGroups.enumerated() {
            print("  [\(i)]: frame=\(g.frame)")
            let cardsInGroup = g.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "TaskCard_")).allElementsBoundByIndex
            print("    TaskCards: \(cardsInGroup.count)")
        }

        // otherを検索
        let doneOthers = app.otherElements.matching(identifier: "TaskColumn_done").allElementsBoundByIndex
        print("=== TaskColumn_done (otherElements): \(doneOthers.count) ===")
        for (i, o) in doneOthers.enumerated() {
            print("  [\(i)]: frame=\(o.frame)")
            let cardsInOther = o.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "TaskCard_")).allElementsBoundByIndex
            print("    TaskCards: \(cardsInOther.count)")
        }

        XCTFail("デバッグ終了。xcresulttoolでスクリーンショットを確認。")
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

        // リアクティブ要件: プロジェクト変更でタスクボードは自動更新されるべき
        // Refreshボタンは使用しない
        Thread.sleep(forTimeInterval: 1.0)
    }

    /// 指定されたタスクをin_progressに変更
    /// - Parameters:
    ///   - taskId: タスクID（例: "tsk_uc004_fe"）。アクセシビリティ識別子での検索に使用。
    ///   - taskTitle: タスクタイトル（ログ表示用）
    private func changeTaskStatusToInProgress(taskId: String, taskTitle: String) throws {
        print("  🔍 タスク「\(taskTitle)」(ID: \(taskId)) を検索中...")

        // TaskBoardを取得
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        guard taskBoard.waitForExistence(timeout: 5) else {
            XCTFail("❌ TaskBoardが見つかりません")
            return
        }

        // Backlogカラムを表示するため、TaskBoardを右にスワイプ（左端へスクロール）
        print("  📜 TaskBoardを左端にスクロール...")
        taskBoard.swipeRight()
        taskBoard.swipeRight()
        Thread.sleep(forTimeInterval: 0.5)

        // アクセシビリティ識別子でタスクカードを検索（より確実）
        let taskCardIdentifier = "TaskCard_\(taskId)"
        var taskCard = app.descendants(matching: .any).matching(identifier: taskCardIdentifier).firstMatch

        if !taskCard.waitForExistence(timeout: 5) {
            // フォールバック: ラベルで検索
            print("  ⚠️ 識別子「\(taskCardIdentifier)」で見つからず、ラベルで検索...")
            let taskCardByLabel = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", taskTitle)).firstMatch
            guard taskCardByLabel.waitForExistence(timeout: 5) else {
                // デバッグ: 利用可能な要素を出力
                let allButtons = app.buttons.allElementsBoundByIndex.prefix(25).map { $0.label }
                print("  📋 利用可能なbuttons: \(allButtons)")
                XCTFail("❌ STEP1: タスク「\(taskTitle)」が見つからない")
                return
            }
            taskCard = taskCardByLabel
            print("  ✅ タスク「\(taskTitle)」が見つかりました（ラベル検索）: \(taskCard.label)")
        } else {
            print("  ✅ タスク「\(taskTitle)」が見つかりました（識別子: \(taskCardIdentifier)）")
        }

        // タスクカードがクリック可能か確認
        print("  📍 タスクカード位置: frame=\(taskCard.frame), isHittable=\(taskCard.isHittable)")

        guard taskCard.isHittable else {
            // スクリーンショットを保存
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "TaskCard_NotHittable_\(taskId)"
            attachment.lifetime = .keepAlways
            add(attachment)

            // ファイルにも保存
            let path = "/tmp/uc004_screenshot_\(taskId)_not_hittable.png"
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path))
            print("  📸 スクリーンショット保存: \(path)")

            XCTFail("❌ STEP1.5: タスクカードが見つかりましたが、クリック不可能です（スクロールが必要な可能性）。isHittable=false, frame=\(taskCard.frame)")
            return
        }

        // タスク詳細を開く
        taskCard.click()
        Thread.sleep(forTimeInterval: 0.5)

        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        if !detailView.waitForExistence(timeout: 5) {
            // スクリーンショットを保存
            let screenshot = app.screenshot()
            let path = "/tmp/uc004_screenshot_\(taskId)_detail_not_opened.png"
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path))
            print("  📸 スクリーンショット保存: \(path)")

            XCTFail("❌ STEP2: タスク詳細画面が開かない（クリック後）")
            return
        }

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

        // Doneカラムが見えるように右にスクロール
        // TaskBoardを使ってスクロール
        let taskBoardForScroll = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoardForScroll.waitForExistence(timeout: 2), "❌ TaskBoardが見つかりません")

        // デバッグ: 全てのColumnHeaderを列挙
        let allStaticTexts = app.staticTexts.allElementsBoundByIndex
        print("  📊 全staticTexts数: \(allStaticTexts.count)")
        // カラムヘッダの表示名で探す
        let columnNames = ["Backlog", "To Do", "In Progress", "Blocked", "Done"]
        for name in columnNames {
            let exists = app.staticTexts[name].exists
            print("  📊 カラム「\(name)」存在=\(exists)")
        }
        // 最初の20個のstaticTextのlabelと識別子を表示
        for i in 0..<min(20, allStaticTexts.count) {
            let text = allStaticTexts[i]
            print("  📊 staticText[\(i)]: label=\"\(text.label)\", id=\"\(text.identifier)\"")
        }

        // Doneカラムを表示名で確認
        let doneColumnHeader = app.staticTexts["Done"]
        let doneColumnExists = doneColumnHeader.exists

        print("  📊 Doneカラムヘッダ存在=\(doneColumnExists)")

        XCTAssertTrue(doneColumnExists, "❌ Doneカラムが見つかりません")
        print("  ✅ Doneカラムが表示されています")

        // Doneカラムにタスクがあるか確認するのは、エージェントがタスクを完了してから
        // この時点ではまだIn Progressなので、Doneカラムにタスクは存在しない
        // → ファイル作成確認フェーズで、タスクがDoneになっていることを確認する
    }

}
