// Tests/MCPServerTests/ChatSessionTimeoutTests.swift
// Chat Session Maintenance Mode のタイムアウト機能テスト
// 参照: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md

import XCTest
import GRDB
@testable import Domain
@testable import UseCase
@testable import Infrastructure

/// チャットセッションのタイムアウト機能テスト
/// TDD: RED → GREEN で実装
final class ChatSessionTimeoutTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var agentSessionRepository: AgentSessionRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!
    var chatRepository: ChatFileRepository!

    let testAgentId = AgentID(value: "agt_chat_timeout_test")
    let testProjectId = ProjectID(value: "prj_chat_timeout_test")
    let targetAgentId = AgentID(value: "agt_chat_timeout_target")  // send_message のターゲット
    var tempDirectory: URL!

    override func setUpWithError() throws {
        // Create temp directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat_timeout_test_\(UUID().uuidString)")
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
            name: "Chat Timeout Test Project",
            description: "Project for chat session timeout testing",
            workingDirectory: tempDirectory.path
        )
        try projectRepository.save(project)

        // Create agent
        let agent = Agent(
            id: testAgentId,
            name: "Chat Timeout Test Agent",
            role: "Test agent",
            hierarchyType: .worker,
            systemPrompt: "Test prompt"
        )
        try agentRepository.save(agent)

        // Create target agent for send_message tests (human type to avoid AI-to-AI conversation requirement)
        let targetAgent = Agent(
            id: targetAgentId,
            name: "Chat Timeout Target Agent",
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
            rawPasskey: "test_passkey_chat_timeout"
        )
        try agentCredentialRepository.save(credential)
    }

    /// チャットセッションを作成するヘルパー
    /// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
    /// - Returns: セッショントークン
    private func createChatSession() throws -> String {
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
                "passkey": "test_passkey_chat_timeout",
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        guard let dict = result as? [String: Any],
              let token = dict["session_token"] as? String else {
            XCTFail("Failed to get session token")
            return ""
        }

        return token
    }

    // MARK: - Test 1: lastActivityAt ベースのタイムアウト

    /// タイムアウトは lastActivityAt から計算されることを確認
    /// lastActivityAt が 11分前の場合、タイムアウトとなる
    func testChatSessionTimeoutBasedOnLastActivityAt() throws {
        let token = try createChatSession()

        // セッションの lastActivityAt を11分前に設定（タイムアウト超過）
        let elevenMinutesAgo = Date().addingTimeInterval(-11 * 60)
        try agentSessionRepository.updateLastActivity(token: token, at: elevenMinutesAgo)

        // model_verified を設定（get_next_action が report_model を要求しないように）
        guard var session = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found")
            return
        }
        session.modelVerified = true
        try agentSessionRepository.save(session)

        // getNextAction を呼び出し
        let result = try mcpServer.executeTool(
            name: "get_next_action",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        // タイムアウトによる logout アクションを期待
        XCTAssertEqual(dict["action"] as? String, "logout", "Should return logout action when timed out")
        XCTAssertEqual(dict["state"] as? String, "chat_timeout", "Should have chat_timeout state")
    }

    // MARK: - Test 2: lastActivityAt が新しければ継続

    /// createdAt が古くても lastActivityAt が新しければタイムアウトしない
    func testChatSessionContinuesWhenLastActivityRecent() throws {
        let token = try createChatSession()

        // lastActivityAt を1分前に設定（タイムアウト未満）
        let oneMinuteAgo = Date().addingTimeInterval(-1 * 60)
        try agentSessionRepository.updateLastActivity(token: token, at: oneMinuteAgo)

        // model_verified を設定
        guard var session = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found")
            return
        }
        session.modelVerified = true
        try agentSessionRepository.save(session)

        // getNextAction を呼び出し
        let result = try mcpServer.executeTool(
            name: "get_next_action",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        // タイムアウトしていないので logout 以外のアクション
        let action = dict["action"] as? String ?? ""
        XCTAssertNotEqual(action, "logout", "Should NOT return logout when lastActivityAt is recent")
        // チャットセッションなので wait_for_messages または get_pending_messages
        XCTAssertTrue(
            action == "wait_for_messages" || action == "get_pending_messages",
            "Should return chat-related action, got: \(action)"
        )
    }

    // MARK: - Test 3: respondChat が lastActivityAt を更新

    /// respondChat 呼び出し後に lastActivityAt が更新されることを確認
    func testRespondChatUpdatesLastActivityAt() throws {
        let token = try createChatSession()

        // lastActivityAt を5分前に設定
        let fiveMinutesAgo = Date().addingTimeInterval(-5 * 60)
        try agentSessionRepository.updateLastActivity(token: token, at: fiveMinutesAgo)

        // 更新前の lastActivityAt を記録
        guard let sessionBefore = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found")
            return
        }
        let lastActivityBefore = sessionBefore.lastActivityAt

        // sendMessage を呼び出し
        let result = try mcpServer.executeTool(
            name: "send_message",
            arguments: [
                "session_token": token,
                "target_agent_id": targetAgentId.value,
                "content": "Test response message"
            ],
            caller: .worker(agentId: testAgentId, session: sessionBefore)
        )

        guard let dict = result as? [String: Any],
              let success = dict["success"] as? Bool else {
            XCTFail("send_message should return success")
            return
        }
        XCTAssertTrue(success, "send_message should succeed")

        // 更新後の lastActivityAt を確認
        guard let sessionAfter = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found after send_message")
            return
        }

        // lastActivityAt が更新されていることを確認
        XCTAssertGreaterThan(
            sessionAfter.lastActivityAt,
            lastActivityBefore,
            "lastActivityAt should be updated after send_message"
        )

        // 更新後の時刻が現在時刻に近いことを確認（1秒以内）
        let timeDiff = abs(sessionAfter.lastActivityAt.timeIntervalSinceNow)
        XCTAssertLessThan(timeDiff, 1.0, "lastActivityAt should be close to now")
    }

    // MARK: - Test 4: sendMessage 後のタイムアウトリセット

    /// sendMessage 呼び出し後、タイムアウトウィンドウがリセットされることを確認
    func testSendMessageResetsTimeoutWindow() throws {
        let token = try createChatSession()

        // lastActivityAt を9分前に設定（タイムアウト間近）
        let nineMinutesAgo = Date().addingTimeInterval(-9 * 60)
        try agentSessionRepository.updateLastActivity(token: token, at: nineMinutesAgo)

        // model_verified を設定
        guard var session = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found")
            return
        }
        session.modelVerified = true
        try agentSessionRepository.save(session)

        // sendMessage を呼び出し（タイムアウトリセット）
        _ = try mcpServer.executeTool(
            name: "send_message",
            arguments: [
                "session_token": token,
                "target_agent_id": targetAgentId.value,
                "content": "Test response to reset timeout"
            ],
            caller: .worker(agentId: testAgentId, session: session)
        )

        // セッションを再取得（lastActivityAt が更新されている）
        guard let updatedSession = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found")
            return
        }

        // getNextAction を呼び出し
        let result = try mcpServer.executeTool(
            name: "get_next_action",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: updatedSession)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        // タイムアウトリセットされているので logout ではない
        let action = dict["action"] as? String ?? ""
        XCTAssertNotEqual(action, "logout", "Should NOT timeout after send_message resets the timer")
    }
}
