// Tests/MCPServerTests/WorkerBlockedStateTests.swift
// WorkerBlockedStateManagementTests - extracted from MCPServerTests.swift

import XCTest
import GRDB
@testable import Domain
@testable import UseCase
@testable import Infrastructure

// MARK: - Worker Blocked State Management Tests

/// ワーカーブロック時のマネージャー即時起動機能のテスト
/// Feature: ワーカーがブロックされた場合、マネージャーを即座に起動してブロック対処を行う
/// States: waiting_for_workers → worker_blocked → handled_blocked
final class WorkerBlockedStateManagementTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var taskRepository: TaskRepository!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var agentSessionRepository: AgentSessionRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!
    var sessionRepository: SessionRepository!
    var contextRepository: ContextRepository!
    var tempDirectory: URL!

    // テストデータ
    let managerAgentId = AgentID(value: "agt_manager_blocked_test")
    let workerAgentId = AgentID(value: "agt_worker_blocked_test")
    let testProjectId = ProjectID(value: "prj_blocked_test")
    let mainTaskId = TaskID(value: "tsk_main_blocked")
    let subTaskId = TaskID(value: "tsk_sub_blocked")

    override func setUpWithError() throws {
        // Create temp directory for working directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("blocked_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let dbPath = tempDirectory.appendingPathComponent("test.db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // リポジトリを初期化
        taskRepository = TaskRepository(database: db)
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)
        agentCredentialRepository = AgentCredentialRepository(database: db)
        agentSessionRepository = AgentSessionRepository(database: db)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: db)
        sessionRepository = SessionRepository(database: db)
        contextRepository = ContextRepository(database: db)

        // MCPServerを初期化
        mcpServer = MCPServer(database: db)

        // テストデータを作成
        try setupTestData()
    }

    override func tearDownWithError() throws {
        mcpServer = nil
        db = nil
        // Clean up temp directory
        Thread.sleep(forTimeInterval: 0.3)
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func setupTestData() throws {
        // プロジェクトを作成（workingDirectory必須）
        let project = Project(
            id: testProjectId,
            name: "Blocked Test Project",
            description: "Test project for worker blocked state management",
            workingDirectory: tempDirectory.path
        )
        try projectRepository.save(project)

        // マネージャーエージェントを作成
        let manager = Agent(
            id: managerAgentId,
            name: "Test Manager",
            role: "Manager agent for testing blocked handling",
            hierarchyType: .manager,
            systemPrompt: "You are a test manager"
        )
        try agentRepository.save(manager)

        // ワーカーエージェントを作成（マネージャーの部下）
        let worker = Agent(
            id: workerAgentId,
            name: "Test Worker",
            role: "Worker agent for testing blocked reporting",
            hierarchyType: .worker,
            parentAgentId: managerAgentId,
            systemPrompt: "You are a test worker"
        )
        try agentRepository.save(worker)

        // プロジェクトにエージェントを割り当て
        _ = try projectAgentAssignmentRepository.assign(projectId: testProjectId, agentId: managerAgentId)
        _ = try projectAgentAssignmentRepository.assign(projectId: testProjectId, agentId: workerAgentId)

        // エージェント認証情報を作成
        let managerCred = AgentCredential(agentId: managerAgentId, rawPasskey: "manager_passkey_12345")
        let workerCred = AgentCredential(agentId: workerAgentId, rawPasskey: "worker_passkey_12345")
        try agentCredentialRepository.save(managerCred)
        try agentCredentialRepository.save(workerCred)

        // メインタスク（マネージャー担当、進行中）
        let mainTask = Task(
            id: mainTaskId,
            projectId: testProjectId,
            title: "Main Task for Blocked Test",
            description: "Main task to test blocked handling",
            status: .inProgress,
            priority: .medium,
            assigneeId: managerAgentId
        )
        try taskRepository.save(mainTask)

        // サブタスク（ワーカー担当、進行中）
        let subTask = Task(
            id: subTaskId,
            projectId: testProjectId,
            title: "Sub Task for Blocked Test",
            description: "Sub task to report blocked",
            status: .inProgress,
            priority: .medium,
            assigneeId: workerAgentId,
            parentTaskId: mainTaskId
        )
        try taskRepository.save(subTask)
    }

    // MARK: - report_completed Updates Parent Context to worker_blocked

    /// ワーカーがブロック報告時に親タスクのコンテキストが worker_blocked に更新されることを検証
    func testReportCompletedBlockedUpdatesParentContextToWorkerBlocked() throws {
        // Arrange: マネージャーを waiting_for_workers 状態に
        let managerSession = Session(
            id: SessionID.generate(),
            projectId: testProjectId,
            agentId: managerAgentId,
            startedAt: Date(),
            status: .active
        )
        try sessionRepository.save(managerSession)

        let waitingContext = Context(
            id: ContextID.generate(),
            taskId: mainTaskId,
            sessionId: managerSession.id,
            agentId: managerAgentId,
            progress: "workflow:waiting_for_workers"
        )
        try contextRepository.save(waitingContext)

        // ワーカーのAgentSessionを作成
        let workerAgentSession = AgentSession(
            agentId: workerAgentId,
            projectId: testProjectId,
            purpose: .task
        )
        try agentSessionRepository.save(workerAgentSession)

        // Act: ワーカーがブロック報告
        let arguments: [String: Any] = [
            "session_token": workerAgentSession.token,
            "result": "blocked",
            "summary": "Blocked because of external dependency"
        ]
        let caller = CallerType.worker(agentId: workerAgentId, session: workerAgentSession)

        _ = try mcpServer.executeTool(name: "report_completed", arguments: arguments, caller: caller)

        // Assert: 親タスク（マネージャー）のコンテキストが worker_blocked に更新されている
        let parentContext = try contextRepository.findLatest(taskId: mainTaskId)
        XCTAssertNotNil(parentContext, "Parent task should have context")
        XCTAssertEqual(
            parentContext?.progress,
            "workflow:worker_blocked",
            "Parent context should be updated to worker_blocked when worker reports blocked"
        )
        XCTAssertNotNil(parentContext?.blockers, "Blockers should contain information about blocked subtask")
    }

    /// waiting_for_workers 以外の状態では親コンテキストが更新されないことを検証
    func testReportCompletedBlockedDoesNotUpdateParentIfNotWaiting() throws {
        // Arrange: マネージャーを handled_blocked 状態に（既に対処済み）
        let managerSession = Session(
            id: SessionID.generate(),
            projectId: testProjectId,
            agentId: managerAgentId,
            startedAt: Date(),
            status: .active
        )
        try sessionRepository.save(managerSession)

        let handledContext = Context(
            id: ContextID.generate(),
            taskId: mainTaskId,
            sessionId: managerSession.id,
            agentId: managerAgentId,
            progress: "workflow:handled_blocked"
        )
        try contextRepository.save(handledContext)

        // ワーカーのAgentSessionを作成
        let workerAgentSession = AgentSession(
            agentId: workerAgentId,
            projectId: testProjectId,
            purpose: .task
        )
        try agentSessionRepository.save(workerAgentSession)

        // Act: ワーカーがブロック報告
        let arguments: [String: Any] = [
            "session_token": workerAgentSession.token,
            "result": "blocked"
        ]
        let caller = CallerType.worker(agentId: workerAgentId, session: workerAgentSession)

        _ = try mcpServer.executeTool(name: "report_completed", arguments: arguments, caller: caller)

        // Assert: 親コンテキストは handled_blocked のまま（変更されない）
        let parentContext = try contextRepository.findLatest(taskId: mainTaskId)
        XCTAssertEqual(
            parentContext?.progress,
            "workflow:handled_blocked",
            "Parent context should NOT be updated if not in waiting_for_workers state"
        )
    }

    // MARK: - get_agent_action Returns start for worker_blocked State

    /// worker_blocked 状態のマネージャーに対して get_agent_action が start を返すことを検証
    func testGetAgentActionReturnsStartForWorkerBlockedState() throws {
        // Arrange: マネージャーを worker_blocked 状態に
        let managerSession = Session(
            id: SessionID.generate(),
            projectId: testProjectId,
            agentId: managerAgentId,
            startedAt: Date(),
            status: .active
        )
        try sessionRepository.save(managerSession)

        let blockedContext = Context(
            id: ContextID.generate(),
            taskId: mainTaskId,
            sessionId: managerSession.id,
            agentId: managerAgentId,
            progress: "workflow:worker_blocked"
        )
        try contextRepository.save(blockedContext)

        // Act: get_agent_action を呼び出し
        let arguments: [String: Any] = [
            "agent_id": managerAgentId.value,
            "project_id": testProjectId.value
        ]
        let result = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: arguments,
            caller: .coordinator
        )

        // Assert: action が start で、理由が worker_blocked
        guard let resultDict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(resultDict["action"] as? String, "start", "Should return 'start' action for worker_blocked state")
        XCTAssertEqual(resultDict["reason"] as? String, "worker_blocked", "Reason should be 'worker_blocked'")
    }

    /// handled_blocked 状態のマネージャーに対して get_agent_action が hold を返すことを検証
    func testGetAgentActionReturnsHoldForHandledBlockedState() throws {
        // Arrange: マネージャーを handled_blocked 状態に
        let managerSession = Session(
            id: SessionID.generate(),
            projectId: testProjectId,
            agentId: managerAgentId,
            startedAt: Date(),
            status: .active
        )
        try sessionRepository.save(managerSession)

        let handledContext = Context(
            id: ContextID.generate(),
            taskId: mainTaskId,
            sessionId: managerSession.id,
            agentId: managerAgentId,
            progress: "workflow:handled_blocked"
        )
        try contextRepository.save(handledContext)

        // Act: get_agent_action を呼び出し
        let arguments: [String: Any] = [
            "agent_id": managerAgentId.value,
            "project_id": testProjectId.value
        ]
        let result = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: arguments,
            caller: .coordinator
        )

        // Assert: action が hold で、理由が handled_blocked
        guard let resultDict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(resultDict["action"] as? String, "hold", "Should return 'hold' action for handled_blocked state")
        XCTAssertEqual(resultDict["reason"] as? String, "handled_blocked", "Reason should be 'handled_blocked'")
    }

    // MARK: - Blocked Task with In-Progress Task

    /// 複数タスクが割り当てられている場合、in_progressタスクがあればblockedタスクの起動チェックをスキップ
    func testGetAgentActionSkipsBlockedCheckWhenInProgressTaskExists() throws {
        // Arrange: ワーカーに2つのタスクを割り当て
        // Task 1: in_progress（実行中）
        // Task 2: blocked
        let secondTaskId = TaskID(value: "tsk_second_blocked")

        // 1つ目のタスク（in_progress）
        var subTask = try taskRepository.findById(subTaskId)!
        subTask = Task(
            id: subTask.id,
            projectId: subTask.projectId,
            title: subTask.title,
            description: subTask.description,
            status: .inProgress,  // 実行中
            priority: subTask.priority,
            assigneeId: workerAgentId,
            parentTaskId: subTask.parentTaskId
        )
        try taskRepository.save(subTask)

        // 2つ目のタスク（blocked）
        let secondTask = Task(
            id: secondTaskId,
            projectId: testProjectId,
            title: "Second Task (blocked)",
            description: "This task is blocked",
            status: .blocked,
            priority: .medium,
            assigneeId: workerAgentId,
            parentTaskId: mainTaskId,
            blockedReason: "Test blocked reason"
        )
        try taskRepository.save(secondTask)

        // Act: get_agent_action を呼び出し
        let arguments: [String: Any] = [
            "agent_id": workerAgentId.value,
            "project_id": testProjectId.value
        ]
        let result = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: arguments,
            caller: .coordinator
        )

        // Assert: blockedタスクではなく、in_progressタスクがあるのでstartを返す
        // （blockedチェックがスキップされ、通常の起動フローに進む）
        guard let resultDict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        // in_progressタスクがあるので、blockedタスクの起動理由ではなく
        // 通常のin_progressタスクに対するstartが返る
        XCTAssertEqual(resultDict["action"] as? String, "start", "Should return 'start' for in_progress task")
        // blockedタスク起動の理由（has_self_blocked_task等）ではないことを確認
        let reason = resultDict["reason"] as? String
        XCTAssertNotEqual(reason, "has_self_blocked_task", "Should not be triggered by blocked task")
        XCTAssertNotEqual(reason, "subordinate_blocked_by_user", "Should not be triggered by blocked task")
    }

    // MARK: - getManagerNextAction Transitions from worker_blocked to handled_blocked

    /// マネージャーがブロック対処を行う際に worker_blocked → handled_blocked に遷移することを検証
    func testGetManagerNextActionTransitionsToHandledBlocked() throws {
        // Arrange: サブタスクをブロック状態に変更
        var subTask = try taskRepository.findById(subTaskId)!
        subTask = Task(
            id: subTask.id,
            projectId: subTask.projectId,
            title: subTask.title,
            description: subTask.description,
            status: .blocked,
            priority: subTask.priority,
            assigneeId: subTask.assigneeId,
            parentTaskId: subTask.parentTaskId,
            blockedReason: "Test blocked reason"
        )
        try taskRepository.save(subTask)

        // マネージャーを worker_blocked 状態に
        let managerSession = Session(
            id: SessionID.generate(),
            projectId: testProjectId,
            agentId: managerAgentId,
            startedAt: Date(),
            status: .active
        )
        try sessionRepository.save(managerSession)

        let workerBlockedContext = Context(
            id: ContextID.generate(),
            taskId: mainTaskId,
            sessionId: managerSession.id,
            agentId: managerAgentId,
            progress: "workflow:worker_blocked"
        )
        try contextRepository.save(workerBlockedContext)

        // マネージャーのAgentSessionを作成（モデル検証済みとして設定）
        let managerAgentSession = AgentSession(
            id: .generate(),
            token: "sess_test_manager_verified",
            agentId: managerAgentId,
            projectId: testProjectId,
            purpose: .task,
            expiresAt: Date().addingTimeInterval(3600),
            createdAt: Date(),
            reportedProvider: "claude",
            reportedModel: "claude-sonnet-4-5",
            modelVerified: true,  // モデル検証済み
            modelVerifiedAt: Date()
        )
        try agentSessionRepository.save(managerAgentSession)

        // Act: get_next_action を呼び出し（マネージャーがブロック対処に入る）
        let arguments: [String: Any] = [
            "session_token": managerAgentSession.token
        ]
        let caller = CallerType.manager(agentId: managerAgentId, session: managerAgentSession)

        let result = try mcpServer.executeTool(name: "get_next_action", arguments: arguments, caller: caller)

        // Assert: action が review_and_resolve_blocks で、コンテキストが handled_blocked に更新
        guard let resultDict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(resultDict["action"] as? String, "review_and_resolve_blocks", "Should return review_and_resolve_blocks action")

        // コンテキストが handled_blocked に更新されていることを確認
        let updatedContext = try contextRepository.findLatest(taskId: mainTaskId)
        XCTAssertEqual(
            updatedContext?.progress,
            "workflow:handled_blocked",
            "Context should transition from worker_blocked to handled_blocked"
        )
    }

    /// マネージャーがブロック解決後に waiting_for_workers に戻ることを検証
    func testGetManagerNextActionTransitionsBackToWaitingAfterResolve() throws {
        // Arrange: handled_blocked 状態で、サブタスクを in_progress に変更（解決済み）
        var subTask = try taskRepository.findById(subTaskId)!
        subTask = Task(
            id: subTask.id,
            projectId: subTask.projectId,
            title: subTask.title,
            description: subTask.description,
            status: .inProgress,  // ブロック解除済み
            priority: subTask.priority,
            assigneeId: subTask.assigneeId,
            parentTaskId: subTask.parentTaskId
        )
        try taskRepository.save(subTask)

        // マネージャーを handled_blocked 状態に
        let managerSession = Session(
            id: SessionID.generate(),
            projectId: testProjectId,
            agentId: managerAgentId,
            startedAt: Date(),
            status: .active
        )
        try sessionRepository.save(managerSession)

        let handledContext = Context(
            id: ContextID.generate(),
            taskId: mainTaskId,
            sessionId: managerSession.id,
            agentId: managerAgentId,
            progress: "workflow:handled_blocked"
        )
        try contextRepository.save(handledContext)

        // マネージャーのAgentSessionを作成（モデル検証済みとして設定）
        let managerAgentSession = AgentSession(
            id: .generate(),
            token: "sess_test_manager_verified_2",
            agentId: managerAgentId,
            projectId: testProjectId,
            purpose: .task,
            expiresAt: Date().addingTimeInterval(3600),
            createdAt: Date(),
            reportedProvider: "claude",
            reportedModel: "claude-sonnet-4-5",
            modelVerified: true,  // モデル検証済み
            modelVerifiedAt: Date()
        )
        try agentSessionRepository.save(managerAgentSession)

        // Act: get_next_action を呼び出し
        let arguments: [String: Any] = [
            "session_token": managerAgentSession.token
        ]
        let caller = CallerType.manager(agentId: managerAgentId, session: managerAgentSession)

        let result = try mcpServer.executeTool(name: "get_next_action", arguments: arguments, caller: caller)

        // Assert: action が exit（ワーカー待機）で、コンテキストが waiting_for_workers に更新
        guard let resultDict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(resultDict["action"] as? String, "exit", "Should return exit action when waiting for workers")
        XCTAssertEqual(resultDict["state"] as? String, "waiting_for_workers", "State should be waiting_for_workers")

        // コンテキストが waiting_for_workers に更新されていることを確認
        let updatedContext = try contextRepository.findLatest(taskId: mainTaskId)
        XCTAssertEqual(
            updatedContext?.progress,
            "workflow:waiting_for_workers",
            "Context should transition back to waiting_for_workers after resolve"
        )
    }
}
