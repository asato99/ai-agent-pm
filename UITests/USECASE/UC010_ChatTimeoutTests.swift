// UITests/USECASE/UC010_ChatTimeoutTests.swift
// UC010: チャットタイムアウトエラー表示 - Runner統合テスト
//
// このテストは Runner との統合テスト用です。
// 設計: 1プロジェクト + 1エージェント（認証失敗用）+ TTL=10秒
// - ユーザーがメッセージを送信
// - エージェントが認証失敗（パスキーなし）
// - TTL経過後にシステムエラーメッセージが表示される

import XCTest

/// UC010: チャットタイムアウトエラー表示テスト
///
/// シードデータ（UC010シナリオ）:
/// - プロジェクト: UC010 Timeout Test (prj_uc010)
/// - エージェント: timeout-test-agent (agt_uc010_timeout)
/// - 認証情報: なし（認証失敗させるため）
/// - TTL: 10秒
final class UC010_ChatTimeoutTests: UC010UITestCase {

    /// UC010統合テスト: メッセージ送信後タイムアウトでシステムエラーが表示される
    ///
    /// このテストは以下を行います:
    /// 1. UC010 Timeout Testプロジェクトを選択
    /// 2. エージェントアバターをクリックしてチャット画面を開く
    /// 3. テストメッセージを入力・送信
    /// 4. タイムアウト（TTL経過）を待機
    /// 5. システムエラーメッセージが表示されることを確認
    func testChatTimeout_ShowsSystemError() throws {
        let projectName = "UC010 Timeout Test"
        let agentName = "timeout-test-agent"
        let agentId = "agt_uc010_timeout"
        let userMessage = "テストメッセージ"
        let ttlSeconds = 10
        let waitBuffer = 5  // TTL後の追加待機時間

        // ========================================
        // Phase 1: プロジェクト選択
        // ========================================
        print("Phase 1: プロジェクト「\(projectName)」を選択")
        try selectProject(projectName)
        print("Phase 1完了: プロジェクト選択完了")

        // ========================================
        // Phase 2: エージェントアバターをクリックしてチャット画面を開く
        // ========================================
        print("Phase 2: エージェントアバターをクリック")
        try openChatWithAgent(agentId: agentId, agentName: agentName)
        print("Phase 2完了: チャット画面表示")

        // ========================================
        // Phase 3: メッセージを送信
        // ========================================
        print("Phase 3: メッセージ送信「\(userMessage)」")
        try sendMessage(userMessage)
        print("Phase 3完了: メッセージ送信完了")

        // ========================================
        // Phase 4: タイムアウトを待機
        // ========================================
        let totalWait = ttlSeconds + waitBuffer
        print("Phase 4: タイムアウト待機（\(totalWait)秒）...")
        Thread.sleep(forTimeInterval: TimeInterval(totalWait))
        print("Phase 4完了: タイムアウト待機完了")

        // ========================================
        // Phase 5: システムエラーメッセージを確認
        // ========================================
        print("Phase 5: システムエラーメッセージを確認")
        let systemErrorFound = try waitForSystemErrorMessage(timeout: 10)

        // ========================================
        // 結果検証
        // ========================================
        XCTAssertTrue(systemErrorFound, "タイムアウト後にシステムエラーメッセージが表示されませんでした")

        if systemErrorFound {
            print("UC010 チャットタイムアウトテスト: 成功")
            print("  - メッセージ送信: 完了")
            print("  - タイムアウト待機: 完了")
            print("  - システムエラー表示: 確認")
        }
    }

    // MARK: - Helper Methods

    /// プロジェクトを選択
    private func selectProject(_ projectName: String) throws {
        print("  プロジェクト「\(projectName)」を検索中...")

        app.activate()
        Thread.sleep(forTimeInterval: 1.0)

        let projectRow = app.staticTexts[projectName]
        guard projectRow.waitForExistence(timeout: 10) else {
            XCTFail("SETUP: プロジェクト「\(projectName)」が見つからない")
            return
        }
        print("  プロジェクト「\(projectName)」が見つかりました")
        projectRow.click()
        Thread.sleep(forTimeInterval: 1.0)

        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5),
                      "SETUP: タスクボードが表示されない")
        print("  タスクボード表示確認")
    }

    /// エージェントアバターをクリックしてチャット画面を開く
    private func openChatWithAgent(agentId: String, agentName: String) throws {
        print("  エージェント「\(agentName)」のアバターを検索中...")

        // エージェントアバターボタンを検索
        let avatarButton = app.descendants(matching: .any)
            .matching(identifier: "AgentAvatarButton-\(agentId)").firstMatch

        guard avatarButton.waitForExistence(timeout: 5) else {
            // フォールバック: 全てのアバターボタンから検索
            let allAvatars = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'AgentAvatarButton-'"))
            if allAvatars.count > 0 {
                print("  アバターボタン（フォールバック）をクリック")
                allAvatars.firstMatch.click()
            } else {
                XCTFail("エージェントアバターが見つからない")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
            return
        }

        print("  エージェントアバターをクリック")
        avatarButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        // チャット画面が表示されることを確認
        let chatView = app.descendants(matching: .any).matching(identifier: "AgentChatView").firstMatch
        XCTAssertTrue(chatView.waitForExistence(timeout: 5), "AgentChatViewが表示されること")
        print("  チャット画面表示確認")
    }

    /// メッセージを送信
    private func sendMessage(_ message: String) throws {
        // メッセージ入力フィールドを検索
        // TextEditorはtextViewsとして認識される
        let inputField = app.textViews.firstMatch

        guard inputField.waitForExistence(timeout: 5) else {
            XCTFail("メッセージ入力フィールドが見つからない")
            return
        }

        print("  メッセージ入力フィールドをクリック")
        inputField.click()
        Thread.sleep(forTimeInterval: 0.3)

        // メッセージを入力
        print("  メッセージを入力中...")
        inputField.typeText(message)
        Thread.sleep(forTimeInterval: 0.3)

        // 送信ボタンを検索
        let sendButton = app.descendants(matching: .any).matching(identifier: "SendButton").firstMatch

        guard sendButton.waitForExistence(timeout: 3) else {
            // フォールバック: "Send"または"送信"ボタンを検索
            let sendButtonAlt = app.buttons["Send"].firstMatch
            if sendButtonAlt.exists {
                sendButtonAlt.click()
                return
            }
            XCTFail("送信ボタンが見つからない")
            return
        }

        print("  送信ボタンをクリック")
        sendButton.click()
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// システムエラーメッセージの表示を待機
    /// sender=system のメッセージが表示されることを確認
    private func waitForSystemErrorMessage(timeout: TimeInterval) throws -> Bool {
        let startTime = Date()
        let pollInterval: TimeInterval = 1.0

        while Date().timeIntervalSince(startTime) < timeout {
            // ChatMessageContent- プレフィックスを持つ要素から検索
            let messageContents = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'ChatMessageContent-'"))

            let messageCount = messageContents.count
            print("  現在のメッセージ数: \(messageCount)")

            for i in 0..<messageCount {
                let element = messageContents.element(boundBy: i)
                let identifier = element.identifier

                // sys_ プレフィックスを持つIDはシステムメッセージ
                if identifier.contains("sys_") {
                    print("  システムメッセージを検出: \(identifier)")
                    return true
                }

                // labelにタイムアウトキーワードが含まれているか
                if let label = element.label as String? {
                    if label.contains("タイムアウト") || label.contains("timeout") {
                        print("  タイムアウトメッセージを検出: \(label)")
                        return true
                    }
                }
            }

            // staticTextsからも検索（システムメッセージのラベル）
            let systemLabel = app.staticTexts["System"]
            if systemLabel.exists {
                print("  Systemラベルを検出")
                // さらにタイムアウトメッセージを確認
                let allTexts = app.staticTexts.allElementsBoundByIndex
                for text in allTexts {
                    if let label = text.label as String?,
                       (label.contains("タイムアウト") || label.contains("timeout")) {
                        print("  タイムアウトテキストを検出: \(label)")
                        return true
                    }
                }
            }

            Thread.sleep(forTimeInterval: pollInterval)
        }

        print("  タイムアウト: システムエラーメッセージが見つかりませんでした")
        return false
    }
}
