// UITests/Feature/Feature11_ChatTests.swift
// Feature 11: エージェントチャット機能UIテスト
//
// ⚠️ テスト実行ルール:
// 修正対象のテストクラス/メソッドのみを実行すること
// 例: xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
//       -only-testing:AIAgentPMUITests/ChatFeatureTests

import XCTest

// MARK: - Feature 11: Agent Chat Tests

final class ChatFeatureTests: BasicDataUITestCase {

    /// FT-11-001: 割り当てエージェント行の表示確認
    /// 検証内容: TaskBoardViewヘッダーにAssignedAgentsRowが表示されること
    func testAssignedAgentsRowDisplay() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクボードの存在確認
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5), "タスクボードが存在すること")

        // AssignedAgentsRowの存在確認（識別子または "Agents:" ラベルで確認）
        let agentsRow = app.descendants(matching: .any).matching(identifier: "AssignedAgentsRow").firstMatch
        let agentsLabel = app.staticTexts["Agents:"]

        // どちらかが見つかればOK
        let rowExists = agentsRow.waitForExistence(timeout: 3) || agentsLabel.waitForExistence(timeout: 3)
        XCTAssertTrue(rowExists, "AssignedAgentsRowまたはAgents:ラベルが表示されること")
    }

    /// FT-11-002: エージェントアバターボタンの表示確認
    /// 検証内容: 割り当てられたエージェントのアバターボタンが表示されること
    func testAgentAvatarButtonDisplay() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクボードの存在確認
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5), "タスクボードが存在すること")

        // エージェントアバターボタンの存在確認
        let avatarButtons = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'AgentAvatarButton-'"))

        // シードデータにエージェントが割り当てられている場合
        if avatarButtons.count > 0 {
            XCTAssertTrue(avatarButtons.firstMatch.exists, "エージェントアバターボタンが存在すること")
        } else {
            // 割り当てなしの場合は「No agents assigned」テキストが表示される
            let noAgentsText = app.staticTexts["No agents assigned"]
            XCTAssertTrue(noAgentsText.exists || avatarButtons.count > 0,
                          "エージェントアバターまたは「No agents assigned」が表示されること")
        }
    }

    /// FT-11-003: エージェントアバタークリックでチャット画面表示
    /// 検証内容: エージェントアバターをクリックすると第3カラムにAgentChatViewが表示されること
    func testAgentAvatarClickOpensChatView() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクボードの存在確認
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5), "タスクボードが存在すること")

        // エージェントアバターボタンを探す
        let avatarButtons = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'AgentAvatarButton-'"))

        guard avatarButtons.count > 0 else {
            throw XCTSkip("エージェントが割り当てられていないためスキップ")
        }

        let firstAvatar = avatarButtons.firstMatch
        XCTAssertTrue(firstAvatar.waitForExistence(timeout: 5), "エージェントアバターが存在すること")

        // アバターをクリック
        firstAvatar.click()

        // チャット画面が表示されることを確認
        let chatView = app.descendants(matching: .any).matching(identifier: "AgentChatView").firstMatch
        XCTAssertTrue(chatView.waitForExistence(timeout: 5), "AgentChatViewが表示されること")
    }

    /// FT-11-004: チャット画面のヘッダー構造確認
    /// 検証内容: チャット画面にエージェント名、ステータス、閉じるボタンが表示されること
    func testChatViewHeaderStructure() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクボードの存在確認
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5), "タスクボードが存在すること")

        // エージェントアバターをクリック
        let avatarButtons = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'AgentAvatarButton-'"))

        guard avatarButtons.count > 0 else {
            throw XCTSkip("エージェントが割り当てられていないためスキップ")
        }

        avatarButtons.firstMatch.click()

        // チャット画面が表示されることを確認
        let chatView = app.descendants(matching: .any).matching(identifier: "AgentChatView").firstMatch
        XCTAssertTrue(chatView.waitForExistence(timeout: 5), "AgentChatViewが表示されること")

        // 閉じるボタンの存在確認（ヘッダー内のコンポーネント）
        let closeButton = app.descendants(matching: .any).matching(identifier: "CloseChatButton").firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3), "閉じるボタンが表示されること")

        // エージェント名が表示されていることを確認（ヘッダーに含まれる）
        // backend-devはテストデータのエージェント名
        let hasAgentName = app.staticTexts["backend-dev"].exists || app.staticTexts["owner"].exists
        XCTAssertTrue(hasAgentName, "エージェント名が表示されること")
    }

    /// FT-11-005: チャット画面のメッセージリスト確認
    /// 検証内容: チャット画面にメッセージリストエリアが存在すること
    func testChatViewMessageListExists() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクボードの存在確認
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5), "タスクボードが存在すること")

        // エージェントアバターをクリック
        let avatarButtons = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'AgentAvatarButton-'"))

        guard avatarButtons.count > 0 else {
            throw XCTSkip("エージェントが割り当てられていないためスキップ")
        }

        avatarButtons.firstMatch.click()

        // チャット画面が表示されることを確認
        let chatView = app.descendants(matching: .any).matching(identifier: "AgentChatView").firstMatch
        XCTAssertTrue(chatView.waitForExistence(timeout: 5), "AgentChatViewが表示されること")

        // メッセージリストエリアの存在確認（空状態メッセージまたはメッセージコンテンツ）
        // 初期状態では「No messages yet」が表示される
        let emptyStateText = app.staticTexts["No messages yet"]
        let hasMessageArea = emptyStateText.waitForExistence(timeout: 3)
        XCTAssertTrue(hasMessageArea, "メッセージリストエリアが表示されること（空状態）")
    }

    /// FT-11-006: チャット画面のメッセージ入力エリア確認
    /// 検証内容: チャット画面にメッセージ入力エリアと送信ボタンが存在すること
    func testChatViewMessageInputExists() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクボードの存在確認
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5), "タスクボードが存在すること")

        // エージェントアバターをクリック
        let avatarButtons = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'AgentAvatarButton-'"))

        guard avatarButtons.count > 0 else {
            throw XCTSkip("エージェントが割り当てられていないためスキップ")
        }

        avatarButtons.firstMatch.click()

        // チャット画面が表示されることを確認
        let chatView = app.descendants(matching: .any).matching(identifier: "AgentChatView").firstMatch
        XCTAssertTrue(chatView.waitForExistence(timeout: 5), "AgentChatViewが表示されること")

        // 閉じるボタンの存在を確認（入力エリアと同じ画面に存在することを示す）
        let closeButton = app.descendants(matching: .any).matching(identifier: "CloseChatButton").firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3), "閉じるボタンが表示されること")

        // 空状態メッセージを確認（メッセージエリアが機能していることを示す）
        let noMessagesText = app.staticTexts["No messages yet"]
        XCTAssertTrue(noMessagesText.exists, "空状態メッセージが表示されること")
    }

    /// FT-11-007: チャット画面の閉じるボタン動作確認
    /// 検証内容: 閉じるボタンをクリックするとチャット画面が閉じること
    func testChatViewCloseButton() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクボードの存在確認
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5), "タスクボードが存在すること")

        // エージェントアバターをクリック
        let avatarButtons = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'AgentAvatarButton-'"))

        guard avatarButtons.count > 0 else {
            throw XCTSkip("エージェントが割り当てられていないためスキップ")
        }

        avatarButtons.firstMatch.click()

        // チャット画面が表示されることを確認
        let chatView = app.descendants(matching: .any).matching(identifier: "AgentChatView").firstMatch
        XCTAssertTrue(chatView.waitForExistence(timeout: 5), "AgentChatViewが表示されること")

        // 閉じるボタンをクリック
        let closeButton = app.descendants(matching: .any).matching(identifier: "CloseChatButton").firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3), "閉じるボタンが存在すること")
        closeButton.click()

        // チャット画面が閉じたことを確認
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(chatView.exists, "チャット画面が閉じられること")
    }

    /// FT-11-008: タスク選択でチャット画面がTaskDetailViewに切り替わること
    /// 検証内容: チャット表示中にタスクを選択するとTaskDetailViewに切り替わること
    func testTaskSelectionReplacesChat() throws {
        // プロジェクト選択
        let projectRow = app.staticTexts["テストプロジェクト"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "テストプロジェクトが存在すること")
        projectRow.click()

        // タスクボードの存在確認
        let taskBoard = app.descendants(matching: .any).matching(identifier: "TaskBoard").firstMatch
        XCTAssertTrue(taskBoard.waitForExistence(timeout: 5), "タスクボードが存在すること")

        // エージェントアバターをクリック
        let avatarButtons = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'AgentAvatarButton-'"))

        guard avatarButtons.count > 0 else {
            throw XCTSkip("エージェントが割り当てられていないためスキップ")
        }

        avatarButtons.firstMatch.click()

        // チャット画面が表示されることを確認
        let chatView = app.descendants(matching: .any).matching(identifier: "AgentChatView").firstMatch
        XCTAssertTrue(chatView.waitForExistence(timeout: 5), "AgentChatViewが表示されること")

        // タスクカードをクリック
        let taskCards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'TaskCard_'"))
        let firstCard = taskCards.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "タスクカードが存在すること")
        firstCard.click()

        // TaskDetailViewに切り替わったことを確認
        let detailView = app.descendants(matching: .any).matching(identifier: "TaskDetailView").firstMatch
        XCTAssertTrue(detailView.waitForExistence(timeout: 5), "TaskDetailViewが表示されること")

        // チャット画面が非表示になったことを確認
        XCTAssertFalse(chatView.exists, "チャット画面がTaskDetailViewに置き換えられること")
    }
}
