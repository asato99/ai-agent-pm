// Tests/MCPServerTests/SessionSpawnArchitectureTests.swift
// Session Spawn Architecture 統合テスト
// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
// 参照: docs/plan/SESSION_SPAWN_IMPLEMENTATION.md - Phase 6

import XCTest
import GRDB
@testable import Domain
@testable import UseCase
@testable import Infrastructure

/// Session Spawn Architecture の統合テスト
/// TDD: RED → GREEN で実装
///
/// テストケース:
/// 1. 重複スポーン防止
/// 2. 認証失敗後の即再試行
/// 3. chat + task 同時存在時の順次処理
/// 4. マネージャーの部下待機
/// 5. 共通ロジック一貫性
final class SessionSpawnArchitectureTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var taskRepository: TaskRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var agentSessionRepository: AgentSessionRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!
    var chatRepository: ChatFileRepository!
    var tempDirectory: URL!

    // テストデータ
    let workerAgentId = AgentID(value: "agt_spawn_worker")
    let managerAgentId = AgentID(value: "agt_spawn_manager")
    let testProjectId = ProjectID(value: "prj_spawn_test")
    let testPasskey = "spawn_test_passkey"

    override func setUpWithError() throws {
        // Create temp directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spawn_arch_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Setup database
        let dbPath = tempDirectory.appendingPathComponent("test.db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // Setup repositories
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)
        taskRepository = TaskRepository(database: db)
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
        mcpServer = nil
        db = nil
        Thread.sleep(forTimeInterval: 0.3)
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func setupTestData() throws {
        // Create project
        let project = Project(
            id: testProjectId,
            name: "Spawn Architecture Test Project",
            description: "Project for session spawn architecture testing",
            workingDirectory: tempDirectory.path
        )
        try projectRepository.save(project)

        // Create worker agent
        let worker = Agent(
            id: workerAgentId,
            name: "Spawn Test Worker",
            role: "Test worker",
            hierarchyType: .worker,
            parentAgentId: managerAgentId,
            systemPrompt: "Test worker prompt"
        )
        try agentRepository.save(worker)

        // Create manager agent
        let manager = Agent(
            id: managerAgentId,
            name: "Spawn Test Manager",
            role: "Test manager",
            hierarchyType: .manager,
            systemPrompt: "Test manager prompt"
        )
        try agentRepository.save(manager)

        // Assign agents to project
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: workerAgentId
        )
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: managerAgentId
        )

        // Create credentials
        let workerCredential = AgentCredential(
            agentId: workerAgentId,
            rawPasskey: testPasskey
        )
        try agentCredentialRepository.save(workerCredential)

        let managerCredential = AgentCredential(
            agentId: managerAgentId,
            rawPasskey: testPasskey
        )
        try agentCredentialRepository.save(managerCredential)
    }

    // MARK: - Test 1: 重複スポーン防止

    /// 連続で getAgentAction を呼んでも1回しか start が返らない
    func testDuplicateSpawnPrevention() throws {
        // Arrange: タスクを作成してワーカーに割り当て
        let task = Task(
            id: TaskID.generate(),
            projectId: testProjectId,
            title: "Test Task",
            status: .inProgress,
            assigneeId: workerAgentId
        )
        try taskRepository.save(task)

        // Act: 連続で getAgentAction を呼ぶ
        let result1 = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: [
                "agent_id": workerAgentId.value,
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        let result2 = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: [
                "agent_id": workerAgentId.value,
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        // Assert
        guard let dict1 = result1 as? [String: Any],
              let dict2 = result2 as? [String: Any] else {
            XCTFail("Results should be dictionaries")
            return
        }

        // 1回目は start
        XCTAssertEqual(dict1["action"] as? String, "start", "First call should return 'start'")

        // 2回目は hold（スポーン中のため）
        XCTAssertEqual(dict2["action"] as? String, "hold", "Second call should return 'hold' due to spawn in progress")
    }

    // MARK: - Test 2: 認証失敗後の即再試行

    /// 認証失敗 → 次の getAgentAction で即 start
    func testRetryAfterAuthenticationFailure() throws {
        // Arrange: タスクを作成してワーカーに割り当て
        let task = Task(
            id: TaskID.generate(),
            projectId: testProjectId,
            title: "Test Task",
            status: .inProgress,
            assigneeId: workerAgentId
        )
        try taskRepository.save(task)

        // Act 1: getAgentAction → start
        let result1 = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: [
                "agent_id": workerAgentId.value,
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        guard let dict1 = result1 as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(dict1["action"] as? String, "start", "Should return 'start'")

        // Act 2: 認証失敗（間違ったパスキー）
        let authResult = try mcpServer.executeTool(
            name: "authenticate",
            arguments: [
                "agent_id": workerAgentId.value,
                "passkey": "wrong_passkey",
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        guard let authDict = authResult as? [String: Any] else {
            XCTFail("Auth result should be a dictionary")
            return
        }
        // 認証失敗を確認
        XCTAssertNil(authDict["session_token"], "Authentication should fail")

        // Act 3: 次の getAgentAction → 即 start（spawn_started_at がクリアされているため）
        let result3 = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: [
                "agent_id": workerAgentId.value,
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        guard let dict3 = result3 as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(dict3["action"] as? String, "start", "Should return 'start' after auth failure clears spawn_started_at")
    }

    // MARK: - Test 3: chat + task 同時存在時の順次処理

    /// 両方ある → task で start → authenticate → task セッション
    /// 再度 getAgentAction → chat で start → authenticate → chat セッション
    func testChatAndTaskSequentialProcessing() throws {
        // Arrange: タスクとチャットメッセージの両方を作成
        let task = Task(
            id: TaskID.generate(),
            projectId: testProjectId,
            title: "Test Task",
            status: .inProgress,
            assigneeId: workerAgentId
        )
        try taskRepository.save(task)

        let chatMessage = ChatMessage(
            id: ChatMessageID.generate(),
            senderId: AgentID(value: "owner"),
            receiverId: workerAgentId,
            content: "Test chat message"
        )
        try chatRepository.saveMessage(chatMessage, projectId: testProjectId, agentId: workerAgentId)

        // Act 1: getAgentAction → start (タスク優先)
        let result1 = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: [
                "agent_id": workerAgentId.value,
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        guard let dict1 = result1 as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(dict1["action"] as? String, "start", "Should return 'start'")
        XCTAssertEqual(dict1["reason"] as? String, "has_task_work", "Reason should be 'has_task_work'")

        // Act 2: authenticate → task セッション作成
        let authResult1 = try mcpServer.executeTool(
            name: "authenticate",
            arguments: [
                "agent_id": workerAgentId.value,
                "passkey": testPasskey,
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        guard let authDict1 = authResult1 as? [String: Any],
              let token1 = authDict1["session_token"] as? String else {
            XCTFail("Authentication should succeed")
            return
        }

        // セッションが task purpose であることを確認
        let session1 = try agentSessionRepository.findByToken(token1)
        XCTAssertEqual(session1?.purpose, .task, "First session should be task purpose")

        // Act 3: 再度 getAgentAction → start (チャット)
        let result2 = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: [
                "agent_id": workerAgentId.value,
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        guard let dict2 = result2 as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(dict2["action"] as? String, "start", "Should return 'start' for chat")
        XCTAssertEqual(dict2["reason"] as? String, "has_chat_work", "Reason should be 'has_chat_work'")

        // Act 4: authenticate → chat セッション作成
        let authResult2 = try mcpServer.executeTool(
            name: "authenticate",
            arguments: [
                "agent_id": workerAgentId.value,
                "passkey": testPasskey,
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        guard let authDict2 = authResult2 as? [String: Any],
              let token2 = authDict2["session_token"] as? String else {
            XCTFail("Authentication should succeed")
            return
        }

        // セッションが chat purpose であることを確認
        let session2 = try agentSessionRepository.findByToken(token2)
        XCTAssertEqual(session2?.purpose, .chat, "Second session should be chat purpose")
    }

    // MARK: - Test 4: マネージャーの部下待機

    /// 部下が仕事中 → マネージャーは hold
    /// 部下が完了 → マネージャーは start
    func testManagerWaitsForSubordinates() throws {
        // Arrange: マネージャーにタスクを割り当て
        let managerTask = Task(
            id: TaskID.generate(),
            projectId: testProjectId,
            title: "Manager Task",
            status: .inProgress,
            assigneeId: managerAgentId
        )
        try taskRepository.save(managerTask)

        // ワーカーにもタスクを割り当て
        let workerTask = Task(
            id: TaskID.generate(),
            projectId: testProjectId,
            title: "Worker Task",
            status: .inProgress,
            assigneeId: workerAgentId
        )
        try taskRepository.save(workerTask)

        // ワーカーにアクティブセッションを作成（仕事中をシミュレート）
        let workerSession = AgentSession(
            agentId: workerAgentId,
            projectId: testProjectId,
            purpose: .task
        )
        try agentSessionRepository.save(workerSession)

        // Act 1: マネージャーの getAgentAction → hold（部下が仕事中）
        let result1 = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: [
                "agent_id": managerAgentId.value,
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        guard let dict1 = result1 as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(dict1["action"] as? String, "hold", "Manager should hold while subordinate is working")

        // ワーカーセッションを終了（部下完了をシミュレート）
        try agentSessionRepository.deleteByToken(workerSession.token)

        // Act 2: マネージャーの getAgentAction → start（部下が完了）
        let result2 = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: [
                "agent_id": managerAgentId.value,
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        guard let dict2 = result2 as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(dict2["action"] as? String, "start", "Manager should start after subordinate completes")
    }

    // MARK: - Test 5: 共通ロジック一貫性

    /// getAgentAction と authenticate が同じ判定結果を返す
    func testConsistentWorkDetection() throws {
        // Arrange: タスクを作成してワーカーに割り当て
        let task = Task(
            id: TaskID.generate(),
            projectId: testProjectId,
            title: "Test Task",
            status: .inProgress,
            assigneeId: workerAgentId
        )
        try taskRepository.save(task)

        // Act 1: getAgentAction → start (has_task_work)
        let actionResult = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: [
                "agent_id": workerAgentId.value,
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        guard let actionDict = actionResult as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(actionDict["action"] as? String, "start")
        let reasonFromAction = actionDict["reason"] as? String

        // Act 2: authenticate → セッション作成
        let authResult = try mcpServer.executeTool(
            name: "authenticate",
            arguments: [
                "agent_id": workerAgentId.value,
                "passkey": testPasskey,
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        guard let authDict = authResult as? [String: Any],
              let token = authDict["session_token"] as? String else {
            XCTFail("Authentication should succeed")
            return
        }

        // Assert: セッションの purpose が getAgentAction の reason と一致
        let session = try agentSessionRepository.findByToken(token)

        if reasonFromAction == "has_task_work" {
            XCTAssertEqual(session?.purpose, .task, "Session purpose should match getAgentAction reason")
        } else if reasonFromAction == "has_chat_work" {
            XCTAssertEqual(session?.purpose, .chat, "Session purpose should match getAgentAction reason")
        }
    }
}
