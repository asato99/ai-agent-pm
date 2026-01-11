// UITests/USECASE/UC009_ChatCommunicationTests.swift
// UC009: エージェントとのチャット通信 - Runner統合テスト
//
// このテストは Runner との統合テスト用です。
// 設計: 1プロジェクト + 1エージェント（チャット応答用）
// - ユーザーがメッセージを送信
// - エージェントが名前を含む応答を返す

import XCTest

/// UC009: エージェントとのチャット通信テスト
///
/// シードデータ（UC009シナリオ）:
/// - プロジェクト: UC009 Chat Test (prj_uc009)
/// - エージェント: chat-responder (agt_uc009_chat)
/// - 認証情報: test_passkey_uc009_chat
final class UC009_ChatCommunicationTests: UC009UITestCase {

    /// UC009統合テスト: エージェントにメッセージを送信し応答を待つ
    ///
    /// このテストは以下を行います:
    /// 1. UC009 Chat Testプロジェクトを選択
    /// 2. エージェントアバターをクリックしてチャット画面を開く
    /// 3. 「あなたの名前を教えてください」と入力・送信
    /// 4. エージェントの応答を待機（最大60秒）
    /// 5. 応答に「chat-responder」が含まれることを確認
    func testChatWithAgent_AskName() throws {
        let projectName = "UC009 Chat Test"
        let agentName = "chat-responder"
        let agentId = "agt_uc009_chat"
        let userMessage = "あなたの名前を教えてください"

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
        // Phase 4: エージェントの応答を待機
        // ========================================
        print("Phase 4: エージェントの応答を待機（最大60秒）...")
        let responseReceived = try waitForAgentResponse(containingText: agentName, timeout: 60)

        // ========================================
        // 結果検証
        // ========================================
        XCTAssertTrue(responseReceived, "エージェントから「\(agentName)」を含む応答がありませんでした")

        if responseReceived {
            print("UC009 チャット通信テスト: 成功")
            print("  - メッセージ送信: 完了")
            print("  - エージェント応答: 「\(agentName)」を含む応答を受信")
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

    /// エージェントの応答を待機
    private func waitForAgentResponse(containingText: String, timeout: TimeInterval) throws -> Bool {
        let startTime = Date()
        let pollInterval: TimeInterval = 2.0

        while Date().timeIntervalSince(startTime) < timeout {
            // 応答テキストを検索
            let responseTexts = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", containingText)
            )

            if responseTexts.count > 0 {
                print("  エージェント応答を検出: 「\(containingText)」を含むテキストが見つかりました")
                return true
            }

            // 待機状況を表示（10秒ごと）
            let elapsed = Int(Date().timeIntervalSince(startTime))
            if elapsed > 0 && elapsed % 10 == 0 {
                print("  待機中... (\(elapsed)秒経過)")
            }

            Thread.sleep(forTimeInterval: pollInterval)
        }

        print("  タイムアウト: \(timeout)秒以内に応答を受信できませんでした")
        return false
    }
}
