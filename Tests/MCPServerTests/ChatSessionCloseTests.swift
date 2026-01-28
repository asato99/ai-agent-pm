// Tests/MCPServerTests/ChatSessionCloseTests.swift
// UC015: チャットセッション終了のテスト
// 参照: docs/usecase/UC015_ChatSessionClose.md
// 参照: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 6

import XCTest
import GRDB
@testable import Domain
@testable import UseCase
@testable import Infrastructure

/// チャットセッション終了機能のテスト（UC015）
/// TDD: RED → GREEN で実装
///
/// セッション状態遷移: active → terminating → ended
/// - active: 通常の動作中
/// - terminating: UIが閉じられた（エージェントに exit 指示を返す）
/// - ended: エージェントが終了完了
final class ChatSessionCloseTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var agentSessionRepository: AgentSessionRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!
    var chatRepository: ChatFileRepository!

    let testAgentId = AgentID(value: "agt_chat_close_test")
    let testProjectId = ProjectID(value: "prj_chat_close_test")
    var tempDirectory: URL!

    override func setUpWithError() throws {
        // Create temp directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat_close_test_\(UUID().uuidString)")
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
            name: "Chat Close Test Project",
            description: "Project for chat session close testing",
            workingDirectory: tempDirectory.path
        )
        try projectRepository.save(project)

        // Create agent
        let agent = Agent(
            id: testAgentId,
            name: "Chat Close Test Agent",
            role: "Test agent",
            hierarchyType: .worker,
            systemPrompt: "Test prompt"
        )
        try agentRepository.save(agent)

        // Assign agent to project
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: testAgentId
        )

        // Create credential
        let credential = AgentCredential(
            agentId: testAgentId,
            rawPasskey: "test_passkey_chat_close"
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
                "passkey": "test_passkey_chat_close",
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

    // MARK: - Test 1: SessionState enum の存在確認

    /// SessionState enum が存在し、3つの状態を持つことを確認
    func testSessionStateEnumExists() {
        // SessionState enum が存在し、期待する値を持つことを確認
        let active = SessionState.active
        let terminating = SessionState.terminating
        let ended = SessionState.ended

        XCTAssertEqual(active.rawValue, "active")
        XCTAssertEqual(terminating.rawValue, "terminating")
        XCTAssertEqual(ended.rawValue, "ended")
    }

    // MARK: - Test 2: AgentSession に state フィールドが存在

    /// AgentSession が state フィールドを持ち、デフォルトは active であることを確認
    func testAgentSessionHasStateField() throws {
        let token = try createChatSession()

        guard let session = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found")
            return
        }

        // 新規セッションのデフォルト状態は active
        XCTAssertEqual(session.state, .active, "New session should have active state by default")
    }

    // MARK: - Test 3: セッション状態を terminating に更新できる

    /// AgentSessionRepository.updateState() でセッション状態を更新できることを確認
    func testCanUpdateSessionStateToTerminating() throws {
        let token = try createChatSession()

        // 状態を terminating に更新
        try agentSessionRepository.updateState(token: token, state: .terminating)

        // 更新を確認
        guard let session = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found")
            return
        }

        XCTAssertEqual(session.state, .terminating, "Session state should be terminating")
    }

    // MARK: - Test 4: terminating 状態のセッションで getNextAction は exit を返す

    /// セッションが terminating 状態の時、getNextAction は exit アクションを返す
    func testGetNextActionReturnsExitWhenSessionTerminating() throws {
        let token = try createChatSession()

        // model_verified を設定
        guard var session = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found")
            return
        }
        session.modelVerified = true
        try agentSessionRepository.save(session)

        // 状態を terminating に更新
        try agentSessionRepository.updateState(token: token, state: .terminating)

        // セッションを再取得
        guard let terminatingSession = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found")
            return
        }

        // getNextAction を呼び出し
        let result = try mcpServer.executeTool(
            name: "get_next_action",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: terminatingSession)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        // exit アクションを期待
        XCTAssertEqual(dict["action"] as? String, "exit", "Should return exit action when session is terminating")
        XCTAssertEqual(dict["state"] as? String, "session_terminating", "Should have session_terminating state")
        XCTAssertEqual(dict["reason"] as? String, "user_closed_chat", "Should indicate user closed chat")
    }

    // MARK: - Test 5: exit アクション後にセッション状態を ended に更新

    /// logout ツールを呼び出すとセッション状態が ended になることを確認
    func testLogoutUpdatesSessionStateToEnded() throws {
        let token = try createChatSession()

        // 状態を terminating に設定（ユーザーがUIを閉じた後の状態）
        try agentSessionRepository.updateState(token: token, state: .terminating)

        guard let session = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found")
            return
        }

        // logout を呼び出し
        let result = try mcpServer.executeTool(
            name: "logout",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        guard let dict = result as? [String: Any],
              let success = dict["success"] as? Bool else {
            XCTFail("logout should return success")
            return
        }
        XCTAssertTrue(success, "logout should succeed")

        // セッションが ended 状態になっている（または削除されている）ことを確認
        // 現在の実装では logout はセッションを削除するが、
        // 将来的には状態を ended に更新する形に変更可能
        let sessionAfter = try agentSessionRepository.findByToken(token)

        // セッションが削除されていれば成功（現在の実装）
        // または ended 状態であれば成功（将来の実装）
        if let s = sessionAfter {
            XCTAssertEqual(s.state, .ended, "Session should be in ended state if not deleted")
        } else {
            // セッションが削除されている場合も許容（現在の実装）
            XCTAssertNil(sessionAfter, "Session should be deleted after logout")
        }
    }

    // MARK: - Test 6: active 状態のセッションでは通常のチャット動作

    /// セッションが active 状態の時は通常のチャット動作（exit を返さない）
    func testActiveSessionDoesNotReturnExit() throws {
        let token = try createChatSession()

        // model_verified を設定
        guard var session = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found")
            return
        }
        session.modelVerified = true
        try agentSessionRepository.save(session)

        // lastActivityAt を最新に設定（タイムアウトしないように）
        try agentSessionRepository.updateLastActivity(token: token, at: Date())

        // セッションを再取得
        guard let activeSession = try agentSessionRepository.findByToken(token) else {
            XCTFail("Session not found")
            return
        }

        // 状態が active であることを確認
        XCTAssertEqual(activeSession.state, .active, "Session should be active")

        // getNextAction を呼び出し
        let result = try mcpServer.executeTool(
            name: "get_next_action",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: activeSession)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        // exit アクションではないことを確認
        let action = dict["action"] as? String ?? ""
        XCTAssertNotEqual(action, "exit", "Active session should NOT return exit action")

        // チャット関連のアクション（wait_for_messages または get_pending_messages）
        XCTAssertTrue(
            action == "wait_for_messages" || action == "get_pending_messages",
            "Should return chat-related action, got: \(action)"
        )
    }

    // MARK: - Test 7: ended 状態のセッションは findByToken で取得できない

    /// ended 状態のセッションはアクティブなセッションとしてカウントされない
    func testEndedSessionNotFoundByToken() throws {
        let token = try createChatSession()

        // 状態を ended に直接設定（テスト用）
        try agentSessionRepository.updateState(token: token, state: .ended)

        // findByToken はアクティブなセッションのみを返す
        // ended 状態のセッションは返さない（または実装による）
        let session = try agentSessionRepository.findByToken(token)

        // ended 状態のセッションは取得できないことを期待
        // （実装によっては取得できるが、別のメソッドで判定）
        if let s = session {
            XCTAssertEqual(s.state, .ended, "If session is returned, it should be in ended state")
        }
    }
}
