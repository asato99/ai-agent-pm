// Tests/MCPServerTests/TaskChatDelegationIntegrationTests.swift
// タスク/チャットセッション委譲の統合テスト
// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
// 参照: docs/plan/TASK_CHAT_SEPARATION_IMPL_PLAN.md - Phase 5

import XCTest
import GRDB
// MCPServerのソースはテストターゲットに直接含まれている（toolタイプのため@testable import不可）
@testable import Domain
@testable import UseCase
@testable import Infrastructure

/// タスクセッション→チャットセッションへの委譲フローの統合テスト
final class TaskChatDelegationIntegrationTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var mcpServer: MCPServer!
    private var agentSessionRepository: AgentSessionRepository!
    private var agentRepository: AgentRepository!
    private var projectRepository: ProjectRepository!
    private var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!
    private var agentCredentialRepository: AgentCredentialRepository!

    // テストデータ
    private let workerAId = AgentID(value: "worker-a")
    private let workerBId = AgentID(value: "worker-b")
    private let projectId = ProjectID(value: "prj_test")

    override func setUpWithError() throws {
        try super.setUpWithError()

        // インメモリDBでMCPServerを初期化
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_delegation_integration_\(UUID().uuidString).db").path
        dbQueue = try DatabaseSetup.createDatabase(at: dbPath)
        mcpServer = MCPServer(database: dbQueue, transport: NullTransport())

        // リポジトリを初期化
        agentSessionRepository = AgentSessionRepository(database: dbQueue)
        agentRepository = AgentRepository(database: dbQueue)
        projectRepository = ProjectRepository(database: dbQueue)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: dbQueue)
        agentCredentialRepository = AgentCredentialRepository(database: dbQueue)

        // テスト用データをセットアップ
        try setupTestData()
    }

    override func tearDownWithError() throws {
        mcpServer = nil
        agentSessionRepository = nil
        agentRepository = nil
        projectRepository = nil
        projectAgentAssignmentRepository = nil
        agentCredentialRepository = nil
        dbQueue = nil
        try super.tearDownWithError()
    }

    private func setupTestData() throws {
        // プロジェクト作成
        var project = Project(
            id: projectId,
            name: "Test Project",
            description: "Test Description"
        )
        project.workingDirectory = FileManager.default.temporaryDirectory.path
        try projectRepository.save(project)

        // ワーカーエージェント作成
        let workerA = Agent(
            id: workerAId,
            name: "Worker A",
            role: "developer",
            hierarchyType: .worker,
            systemPrompt: "Test worker A"
        )
        try agentRepository.save(workerA)

        let workerB = Agent(
            id: workerBId,
            name: "Worker B",
            role: "developer",
            hierarchyType: .worker,
            systemPrompt: "Test worker B"
        )
        try agentRepository.save(workerB)

        // プロジェクト割り当て
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: workerAId)
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: workerBId)

        // 認証情報作成
        let credentialA = AgentCredential(agentId: workerAId, rawPasskey: "passkey_a")
        try agentCredentialRepository.save(credentialA)
        let credentialB = AgentCredential(agentId: workerBId, rawPasskey: "passkey_b")
        try agentCredentialRepository.save(credentialB)
    }

    /// 完全な委譲フローのテスト
    /// タスクセッション → delegate_to_chat_session → チャットセッション → get_pending_messages → report_delegation_completed
    func testFullDelegationFlow() throws {
        // ========================================
        // Phase 1: タスクセッションを作成して委譲を依頼
        // ========================================

        // タスクセッションを作成
        let taskSession = AgentSession(
            agentId: workerAId,
            projectId: projectId,
            purpose: .task
        )
        try agentSessionRepository.save(taskSession)
        let taskCaller = CallerType.worker(agentId: workerAId, session: taskSession)

        // delegate_to_chat_session を呼び出す
        let delegateResult = try mcpServer.executeTool(
            name: "delegate_to_chat_session",
            arguments: [
                "session_token": taskSession.token,
                "target_agent_id": workerBId.value,
                "purpose": "6往復しりとりをしてください",
                "context": "テスト用の会話依頼"
            ],
            caller: taskCaller
        )

        // 委譲が成功したことを確認
        guard let delegateDict = delegateResult as? [String: Any],
              let success = delegateDict["success"] as? Bool,
              let delegationId = delegateDict["delegation_id"] as? String else {
            XCTFail("Failed to parse delegate result: \(delegateResult)")
            return
        }

        XCTAssertTrue(success, "Delegation should succeed")
        XCTAssertFalse(delegationId.isEmpty, "Delegation ID should not be empty")

        // DBに委譲が保存されていることを確認
        let pendingCount: Int = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chat_delegations WHERE status = 'pending'") ?? 0
        }
        XCTAssertEqual(pendingCount, 1, "Should have 1 pending delegation")

        // ========================================
        // Phase 2: チャットセッションを作成して委譲を取得
        // ========================================

        // チャットセッションを作成
        let chatSession = AgentSession(
            agentId: workerAId,
            projectId: projectId,
            purpose: .chat
        )
        try agentSessionRepository.save(chatSession)
        let chatCaller = CallerType.worker(agentId: workerAId, session: chatSession)

        // get_pending_messages を呼び出す
        let pendingResult = try mcpServer.executeTool(
            name: "get_pending_messages",
            arguments: [
                "session_token": chatSession.token
            ],
            caller: chatCaller
        )

        // pending_delegations が含まれていることを確認
        guard let pendingDict = pendingResult as? [String: Any],
              let pendingDelegations = pendingDict["pending_delegations"] as? [[String: Any]] else {
            XCTFail("Failed to parse pending messages result: \(pendingResult)")
            return
        }

        XCTAssertEqual(pendingDelegations.count, 1, "Should have 1 pending delegation")
        XCTAssertEqual(pendingDelegations[0]["target_agent_id"] as? String, workerBId.value)
        XCTAssertEqual(pendingDelegations[0]["purpose"] as? String, "6往復しりとりをしてください")

        // 委譲のステータスがprocessingに更新されていることを確認
        let processingCount: Int = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chat_delegations WHERE status = 'processing'") ?? 0
        }
        XCTAssertEqual(processingCount, 1, "Delegation should be in processing status")

        // ========================================
        // Phase 3: 委譲完了を報告
        // ========================================

        // report_delegation_completed を呼び出す
        let completeResult = try mcpServer.executeTool(
            name: "report_delegation_completed",
            arguments: [
                "session_token": chatSession.token,
                "delegation_id": delegationId,
                "result": "しりとり会話が完了しました"
            ],
            caller: chatCaller
        )

        // 完了報告が成功したことを確認
        guard let completeDict = completeResult as? [String: Any],
              let completeSuccess = completeDict["success"] as? Bool else {
            XCTFail("Failed to parse complete result: \(completeResult)")
            return
        }

        XCTAssertTrue(completeSuccess, "Completion report should succeed")

        // 委譲のステータスがcompletedに更新されていることを確認
        let completedCount: Int = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chat_delegations WHERE status = 'completed'") ?? 0
        }
        XCTAssertEqual(completedCount, 1, "Delegation should be in completed status")

        // resultが保存されていることを確認
        let savedResult: String? = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT result FROM chat_delegations WHERE id = ?", arguments: [delegationId])
        }
        XCTAssertEqual(savedResult, "しりとり会話が完了しました")
    }
}
