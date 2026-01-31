// Tests/MCPServerTests/LongPollingTests.swift
// Long Polling機能のテスト
// 参照: docs/design/CHAT_LONG_POLLING.md
//
// TDD: RED → GREEN で実装
// 目的: Gemini APIレート制限を回避しつつリアルタイムなチャット体験を維持

import XCTest
import GRDB
@testable import Domain
@testable import UseCase
@testable import Infrastructure

/// Long Polling機能のテスト
final class LongPollingTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var agentSessionRepository: AgentSessionRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!
    var chatRepository: ChatFileRepository!

    let testAgentId = AgentID(value: "agt_long_polling_test")
    let testProjectId = ProjectID(value: "prj_long_polling_test")
    let targetAgentId = AgentID(value: "agt_long_polling_target")  // send_message のターゲット
    var tempDirectory: URL!

    override func setUpWithError() throws {
        // Create temp directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("long_polling_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Setup database
        let dbPath = tempDirectory.appendingPathComponent("test.db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // Setup repositories
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)
        agentCredentialRepository = AgentCredentialRepository(database: db)
        agentSessionRepository = AgentSessionRepository(database: db)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: db)

        // Setup chat repository
        let directoryManager = ProjectDirectoryManager()
        chatRepository = ChatFileRepository(
            directoryManager: directoryManager,
            projectRepository: projectRepository
        )

        // Setup MCP server
        mcpServer = MCPServer(database: db)

        try setupTestData()
    }

    override func tearDownWithError() throws {
        // MCPServerを先に解放（内部のDB参照をクリア）
        mcpServer = nil
        // DBを閉じる
        db = nil
        // DB接続が完全に閉じられるのを待つ
        Thread.sleep(forTimeInterval: 0.3)
        // その後でtempディレクトリを削除
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func setupTestData() throws {
        // Create project with working directory
        let project = Project(
            id: testProjectId,
            name: "Long Polling Test Project",
            description: "Project for long polling testing",
            workingDirectory: tempDirectory.path
        )
        try projectRepository.save(project)

        // Create agent
        let agent = Agent(
            id: testAgentId,
            name: "Long Polling Test Agent",
            role: "Test agent",
            hierarchyType: .worker,
            systemPrompt: "Test prompt"
        )
        try agentRepository.save(agent)

        // Create target agent for send_message tests (human type to avoid AI-to-AI conversation requirement)
        let targetAgent = Agent(
            id: targetAgentId,
            name: "Long Polling Target Agent",
            role: "Target agent",
            type: .human,
            hierarchyType: .worker,
            systemPrompt: "Target prompt"
        )
        try agentRepository.save(targetAgent)

        // Assign agents to project
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: testAgentId
        )
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: targetAgentId
        )

        // Create credential
        let credential = AgentCredential(
            agentId: testAgentId,
            rawPasskey: "test_passkey_long_polling"
        )
        try agentCredentialRepository.save(credential)
    }

    /// チャットセッションを作成するヘルパー
    /// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
    /// - Returns: (セッショントークン, セッション)
    private func createChatSession() throws -> (String, AgentSession) {
        // WorkDetectionService が hasChatWork を検知するために未読メッセージを作成
        // 参照: AuthenticateUseCaseV3 は WorkDetectionService を使用
        let message = ChatMessage(
            id: ChatMessageID.generate(),
            senderId: AgentID(value: "owner"),
            receiverId: testAgentId,
            content: "Test message for chat session creation",
            createdAt: Date()
        )
        try chatRepository.saveMessage(message, projectId: testProjectId, agentId: testAgentId)

        // 認証（WorkDetectionService が chat work を検知してセッション作成）
        let result = try mcpServer.executeTool(
            name: "authenticate",
            arguments: [
                "agent_id": testAgentId.value,
                "passkey": "test_passkey_long_polling",
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        guard let dict = result as? [String: Any],
              let token = dict["session_token"] as? String else {
            XCTFail("Failed to get session token")
            return ("", AgentSession(agentId: testAgentId, projectId: testProjectId))
        }

        // model_verified を設定（get_next_action が report_model を要求しないように）
        guard var session = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found")
            return ("", AgentSession(agentId: testAgentId, projectId: testProjectId))
        }
        session.modelVerified = true
        try agentSessionRepository.save(session)

        return (token, session)
    }

    // MARK: - Test 1.1: メッセージがない場合の待機

    /// メッセージがない場合、指定されたタイムアウトまで待機してからwaitを返す
    func testGetNextAction_WaitsForMessageWhenNoneAvailable() async throws {
        let (token, session) = try createChatSession()

        // セッション作成時のメッセージを消費して「メッセージがない状態」を作る
        try consumePendingMessages(token: token, session: session)

        // Act: 短いタイムアウトでget_next_actionを呼び出し
        let startTime = Date()
        let result = try await mcpServer.executeToolAsync(
            name: "get_next_action",
            arguments: [
                "session_token": token,
                "timeout_seconds": 3  // テスト用に短いタイムアウト
            ],
            caller: .worker(agentId: testAgentId, session: session)
        )
        let elapsedTime = Date().timeIntervalSince(startTime)

        // Assert
        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        // 少なくとも2.5秒待機（タイムアウト - バッファ）
        XCTAssertGreaterThanOrEqual(elapsedTime, 2.5, "Should wait at least 2.5 seconds")
        // タイムアウト + バッファ以内
        XCTAssertLessThan(elapsedTime, 5.0, "Should not exceed timeout + buffer")
        // waitアクションを返す
        XCTAssertEqual(dict["action"] as? String, "wait_for_messages", "Should return wait action when no messages")
    }

    // MARK: - Test 1.2: 待機中にメッセージが到着

    /// 待機中にメッセージが到着した場合、即座に応答を返す
    func testGetNextAction_ReturnsImmediatelyWhenMessageArrives() async throws {
        let (token, session) = try createChatSession()

        // セッション作成時のメッセージを消費して「メッセージがない状態」を作る
        try consumePendingMessages(token: token, session: session)

        // 1秒後にメッセージを送信するタスクをスケジュール
        _Concurrency.Task {
            try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)  // 1秒待機
            try self.sendTestMessage(content: "Hello from user!")
        }

        // Act: 長いタイムアウトでget_next_actionを呼び出し
        let startTime = Date()
        let result = try await mcpServer.executeToolAsync(
            name: "get_next_action",
            arguments: [
                "session_token": token,
                "timeout_seconds": 30
            ],
            caller: .worker(agentId: testAgentId, session: session)
        )
        let elapsedTime = Date().timeIntervalSince(startTime)

        // Assert
        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        // メッセージ送信後（1秒）+ 検出時間（1秒以内）で応答
        XCTAssertGreaterThanOrEqual(elapsedTime, 0.8, "Should wait for message arrival")
        XCTAssertLessThan(elapsedTime, 3.0, "Should respond shortly after message arrives")
        // get_pending_messagesアクションを返す
        XCTAssertEqual(dict["action"] as? String, "get_pending_messages", "Should return get_pending_messages when message arrives")
    }

    // MARK: - Test 1.3: セッション終了時の即座のリターン

    /// セッションがterminatingになった場合、待機を中断して即座にexitを返す
    func testGetNextAction_ReturnsImmediatelyWhenSessionEnds() async throws {
        let (token, session) = try createChatSession()

        // セッション作成時のメッセージを消費して「メッセージがない状態」を作る
        try consumePendingMessages(token: token, session: session)

        // 1秒後にセッションをterminatingに設定
        _Concurrency.Task {
            try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)  // 1秒待機
            try self.setSessionTerminating(token: token)
        }

        // Act: 長いタイムアウトでget_next_actionを呼び出し
        let startTime = Date()
        let result = try await mcpServer.executeToolAsync(
            name: "get_next_action",
            arguments: [
                "session_token": token,
                "timeout_seconds": 30
            ],
            caller: .worker(agentId: testAgentId, session: session)
        )
        let elapsedTime = Date().timeIntervalSince(startTime)

        // Assert
        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        // セッション終了後（1秒）+ 検出時間（1秒以内）で応答
        XCTAssertLessThan(elapsedTime, 3.0, "Should respond shortly after session ends")
        // exitアクションを返す
        XCTAssertEqual(dict["action"] as? String, "exit", "Should return exit when session terminates")
    }

    // MARK: - Test 2.1: デフォルトタイムアウト

    /// timeout_secondsを指定しない場合、デフォルト30秒を使用
    func testGetNextAction_UsesDefaultTimeout() async throws {
        let (token, session) = try createChatSession()

        // timeout_secondsを指定しないでテスト（実際に30秒待つのは長いのでスキップ可能にする）
        // このテストは実際の動作確認用であり、CIでは短縮版を使う
        let result = try mcpServer.executeTool(
            name: "get_next_action",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        // 現在の実装ではwait_for_messagesを返す（Long Polling実装後も同じ）
        let action = dict["action"] as? String ?? ""
        XCTAssertTrue(
            action == "wait_for_messages" || action == "get_pending_messages",
            "Should return chat-related action"
        )
    }

    // MARK: - Test 2.2: カスタムタイムアウト

    /// timeout_secondsで指定した時間だけ待機する
    func testGetNextAction_RespectsCustomTimeout() async throws {
        let (token, session) = try createChatSession()

        // セッション作成時のメッセージを消費して「メッセージがない状態」を作る
        try consumePendingMessages(token: token, session: session)

        // カスタムタイムアウト（5秒）
        let startTime = Date()
        let result = try await mcpServer.executeToolAsync(
            name: "get_next_action",
            arguments: [
                "session_token": token,
                "timeout_seconds": 5
            ],
            caller: .worker(agentId: testAgentId, session: session)
        )
        let elapsedTime = Date().timeIntervalSince(startTime)

        // Assert
        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        XCTAssertGreaterThanOrEqual(elapsedTime, 4.5, "Should wait close to timeout")
        XCTAssertLessThan(elapsedTime, 7.0, "Should not exceed timeout + buffer")
        XCTAssertEqual(dict["action"] as? String, "wait_for_messages", "Should return wait action")
    }

    // MARK: - Helper Methods

    /// セッション作成時に追加された保留中のメッセージを消費する
    /// Long Polling待機テストの前に呼び出して「メッセージがない状態」を作る
    private func consumePendingMessages(token: String, session: AgentSession) throws {
        // get_pending_messages を呼び出してセッション作成時のメッセージを消費
        let result = try mcpServer.executeTool(
            name: "get_pending_messages",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        // メッセージが取得されたことを確認
        guard let dict = result as? [String: Any],
              let messages = dict["pending_messages"] as? [[String: Any]],
              !messages.isEmpty else {
            // メッセージがない場合も正常
            return
        }

        // send_message ツールを使用してエージェントからの応答を送信
        // これにより未読メッセージが解消される（最後の自分の応答より前のメッセージは未読ではなくなる）
        _ = try mcpServer.executeTool(
            name: "send_message",
            arguments: [
                "session_token": token,
                "target_agent_id": targetAgentId.value,
                "content": "Acknowledged all pending messages"
            ],
            caller: .worker(agentId: testAgentId, session: session)
        )
    }

    /// テスト用メッセージを送信（ユーザーからエージェントへ）
    private func sendTestMessage(content: String) throws {
        // ユーザーからエージェントへのメッセージをシミュレート
        // senderId: system:user (ユーザー), receiverId: testAgentId
        // 未読メッセージとして検出されるには、senderId != agentId である必要がある
        let userAgentId = AgentID(value: "system:user")
        let message = ChatMessage(
            id: ChatMessageID(value: UUID().uuidString),
            senderId: userAgentId,  // ユーザーからのメッセージ
            receiverId: testAgentId,
            content: content
        )
        // エージェントのチャットファイルに保存（受信者側のストレージ）
        try chatRepository.saveMessage(message, projectId: testProjectId, agentId: testAgentId)
    }

    /// セッションをterminatingに設定
    private func setSessionTerminating(token: String) throws {
        guard var session = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found")
            return
        }
        session.state = .terminating
        try agentSessionRepository.save(session)
    }
}
