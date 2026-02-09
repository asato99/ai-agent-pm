// Tests/MCPServerTests/ReportCompletedTests.swift
// MCPServerReportCompletedTests, MCPServerRegisterExecutionLogFileTests, ExecutionLogRepositoryFindLatestTests
// - extracted from MCPServerTests.swift

import XCTest
import GRDB
@testable import Domain
@testable import UseCase
@testable import Infrastructure

// MARK: - MCPServer Integration Tests

/// MCPServer統合テスト - reportCompletedのstatusChangedByAgentId設定バグ修正
/// 参照: TDD RED-GREEN アプローチ
final class MCPServerReportCompletedTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var taskRepository: TaskRepository!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var agentSessionRepository: AgentSessionRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!

    // テストデータ
    let testAgentId = AgentID(value: "agt_test_worker")
    let testProjectId = ProjectID(value: "prj_test")
    let testTaskId = TaskID(value: "tsk_test")

    override func setUpWithError() throws {
        // テスト用インメモリDBを作成
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_mcp_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // リポジトリを初期化
        taskRepository = TaskRepository(database: db)
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)
        agentCredentialRepository = AgentCredentialRepository(database: db)
        agentSessionRepository = AgentSessionRepository(database: db)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: db)

        // MCPServerを初期化
        mcpServer = MCPServer(database: db)

        // テストデータを作成
        try setupTestData()
    }

    override func tearDownWithError() throws {
        db = nil
        mcpServer = nil
    }

    private func setupTestData() throws {
        // プロジェクトを作成
        let project = Project(
            id: testProjectId,
            name: "Test Project",
            description: "Integration test project"
        )
        try projectRepository.save(project)

        // エージェントを作成（Worker）
        let agent = Agent(
            id: testAgentId,
            name: "Test Worker",
            role: "Worker agent for testing",
            hierarchyType: .worker,
            systemPrompt: "You are a test worker"
        )
        try agentRepository.save(agent)

        // プロジェクトにエージェントを割り当て
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: testAgentId
        )

        // エージェント認証情報を作成（rawPasskeyを使用）
        let credential = AgentCredential(
            agentId: testAgentId,
            rawPasskey: "test_passkey_12345"
        )
        try agentCredentialRepository.save(credential)

        // サブタスク付きのタスクを作成（in_progress状態）
        // メインタスク
        let mainTask = Task(
            id: testTaskId,
            projectId: testProjectId,
            title: "Main Test Task",
            description: "Main task for testing",
            status: .inProgress,
            priority: .medium,
            assigneeId: testAgentId
        )
        try taskRepository.save(mainTask)

        // サブタスク（完了済み - メインタスクの完了条件）
        let subTask = Task(
            id: TaskID.generate(),
            projectId: testProjectId,
            title: "Subtask 1",
            description: "Completed subtask",
            status: .done,
            priority: .medium,
            assigneeId: testAgentId,
            parentTaskId: testTaskId
        )
        try taskRepository.save(subTask)
    }

    /// RED: reportCompletedがstatusChangedByAgentIdを設定することを検証
    /// 期待: result="blocked"でタスクをブロック状態に変更した時、
    ///       statusChangedByAgentIdに報告者のagentIdが設定される
    func testReportCompletedSetsStatusChangedByAgentId() throws {
        // Arrange: セッションを作成（認証状態をシミュレート）
        let session = AgentSession(
            agentId: testAgentId,
            projectId: testProjectId,
            purpose: .task
        )
        try agentSessionRepository.save(session)

        // Act: report_completedツールを呼び出し（result=blocked）
        // MCPServerのexecuteToolを使用してreport_completedを実行
        // Note: summaryを省略（contextテーブルのFK制約回避のため）
        let arguments: [String: Any] = [
            "session_token": session.token,
            "result": "blocked"
        ]

        // CallerTypeを設定（Worker認証済み）
        let caller = CallerType.worker(agentId: testAgentId, session: session)

        // ツール実行
        let result = try mcpServer.executeTool(
            name: "report_completed",
            arguments: arguments,
            caller: caller
        )

        // Assert: タスクのstatusChangedByAgentIdが報告者のエージェントIDに設定されている
        let updatedTask = try taskRepository.findById(testTaskId)
        XCTAssertNotNil(updatedTask, "Task should exist after report_completed")
        XCTAssertEqual(updatedTask?.status, .blocked, "Task status should be blocked")

        // ★ これがREDになる検証ポイント ★
        // 現在のバグ: statusChangedByAgentIdが設定されていない
        XCTAssertEqual(
            updatedTask?.statusChangedByAgentId,
            testAgentId,
            "statusChangedByAgentId should be set to the reporting agent's ID, not nil or system:user"
        )

        // statusChangedAtも設定されていることを確認
        XCTAssertNotNil(
            updatedTask?.statusChangedAt,
            "statusChangedAt should be set when status is changed"
        )

        // 成功レスポンスの確認
        if let resultDict = result as? [String: Any],
           let successFlag = resultDict["success"] as? Bool {
            XCTAssertTrue(successFlag, "report_completed should succeed")
        }
    }

    /// Context作成時にFK制約違反が発生しないことを検証
    /// Bug fix: SessionID.generate()ではなく、有効なワークフローセッションを使用
    func testReportCompletedWithSummaryDoesNotCauseFKError() throws {
        // Arrange: AgentSessionを作成
        let agentSession = AgentSession(
            agentId: testAgentId,
            projectId: testProjectId,
            purpose: .task
        )
        try agentSessionRepository.save(agentSession)

        // ワークフローセッションも作成（Context作成に必要）
        let sessionRepository = SessionRepository(database: db)
        let workflowSession = Session(
            id: SessionID.generate(),
            projectId: testProjectId,
            agentId: testAgentId,
            startedAt: Date()
        )
        try sessionRepository.save(workflowSession)

        // Act: summaryを含めてreport_completedを呼び出し
        let arguments: [String: Any] = [
            "session_token": agentSession.token,
            "result": "blocked",
            "summary": "This is a test summary that should be saved to context"
        ]

        let caller = CallerType.worker(agentId: testAgentId, session: agentSession)

        // Assert: FK制約違反なく成功すること
        XCTAssertNoThrow(
            try mcpServer.executeTool(
                name: "report_completed",
                arguments: arguments,
                caller: caller
            ),
            "report_completed with summary should not throw FK constraint error"
        )

        // Contextが正しく保存されていることを確認
        let contextRepository = ContextRepository(database: db)
        let contexts = try contextRepository.findByTask(testTaskId)
        XCTAssertFalse(contexts.isEmpty, "Context should be saved when summary is provided")
        XCTAssertEqual(contexts.first?.sessionId, workflowSession.id, "Context should use the active workflow session ID")
    }
}

// MARK: - register_execution_log_file Tool Tests

/// register_execution_log_file MCPツールの統合テスト
final class MCPServerRegisterExecutionLogFileTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var taskRepository: TaskRepository!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var executionLogRepository: ExecutionLogRepository!

    // テストデータ
    let testAgentId = AgentID(value: "agt_test_log")
    let testProjectId = ProjectID(value: "prj_test_log")
    let testTaskId = TaskID(value: "tsk_test_log")

    override func setUpWithError() throws {
        // テスト用インメモリDBを作成
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_mcp_log_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // リポジトリを初期化
        taskRepository = TaskRepository(database: db)
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)
        executionLogRepository = ExecutionLogRepository(database: db)

        // MCPServerを初期化
        mcpServer = MCPServer(database: db)

        // テストデータを作成
        try setupTestData()
    }

    override func tearDownWithError() throws {
        db = nil
        mcpServer = nil
    }

    private func setupTestData() throws {
        // プロジェクトを作成
        let project = Project(
            id: testProjectId,
            name: "Test Project for Log",
            description: "Test project for execution log tests"
        )
        try projectRepository.save(project)

        // エージェントを作成
        let agent = Agent(
            id: testAgentId,
            name: "Test Agent",
            role: "Worker agent for log testing",
            hierarchyType: .worker
        )
        try agentRepository.save(agent)

        // タスクを作成
        let task = Task(
            id: testTaskId,
            projectId: testProjectId,
            title: "Test Task for Log",
            status: .inProgress,
            assigneeId: testAgentId
        )
        try taskRepository.save(task)
    }

    /// register_execution_log_file がログファイルパスを正しく登録することを検証
    func testRegisterExecutionLogFileUpdatesLogPath() throws {
        // Arrange: 実行ログを作成（通常は report_execution_start で作成される）
        let executionLog = ExecutionLog(
            taskId: testTaskId,
            agentId: testAgentId
        )
        try executionLogRepository.save(executionLog)

        let logFilePath = "/tmp/test_agent_logs/20260116_120000.log"

        // Act: Coordinatorとしてツールを呼び出し
        let arguments: [String: Any] = [
            "agent_id": testAgentId.value,
            "task_id": testTaskId.value,
            "log_file_path": logFilePath
        ]

        let result = try mcpServer.executeTool(
            name: "register_execution_log_file",
            arguments: arguments,
            caller: .coordinator
        )

        // Assert: 成功レスポンスを確認
        guard let resultDict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(resultDict["success"] as? Bool, true)
        XCTAssertEqual(resultDict["log_file_path"] as? String, logFilePath)

        // Assert: DBに保存されたログファイルパスを確認
        let updatedLog = try executionLogRepository.findById(executionLog.id)
        XCTAssertNotNil(updatedLog, "Execution log should exist")
        XCTAssertEqual(updatedLog?.logFilePath, logFilePath, "Log file path should be updated")
    }

    /// 実行ログが存在しない場合にエラーを返すことを検証
    func testRegisterExecutionLogFileReturnsErrorWhenLogNotFound() throws {
        // Arrange: 実行ログを作成しない
        let logFilePath = "/tmp/test_agent_logs/not_found.log"

        // Act: 存在しないエージェント/タスクで呼び出し
        let arguments: [String: Any] = [
            "agent_id": "agt_nonexistent",
            "task_id": "tsk_nonexistent",
            "log_file_path": logFilePath
        ]

        let result = try mcpServer.executeTool(
            name: "register_execution_log_file",
            arguments: arguments,
            caller: .coordinator
        )

        // Assert: エラーレスポンスを確認
        guard let resultDict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(resultDict["success"] as? Bool, false)
        XCTAssertEqual(resultDict["error"] as? String, "execution_log_not_found")
    }

    /// Coordinator以外からの呼び出しを拒否することを検証
    /// Note: executeTool は認可後の入り口なので、認可テストは ToolAuthorization.authorize を使用
    func testRegisterExecutionLogFileRequiresCoordinator() throws {
        // Act & Assert: Coordinatorからの呼び出しは許可される
        XCTAssertNoThrow(
            try ToolAuthorization.authorize(
                tool: "register_execution_log_file",
                caller: .coordinator
            )
        )

        // Act & Assert: Unauthenticatedからの呼び出しは拒否される
        XCTAssertThrowsError(
            try ToolAuthorization.authorize(
                tool: "register_execution_log_file",
                caller: .unauthenticated
            )
        ) { error in
            guard case ToolAuthorizationError.coordinatorRequired(let tool) = error else {
                XCTFail("Should throw ToolAuthorizationError.coordinatorRequired, got: \(error)")
                return
            }
            XCTAssertEqual(tool, "register_execution_log_file")
        }
    }

    /// 必須パラメータが欠けている場合のエラーを検証
    func testRegisterExecutionLogFileMissingArguments() throws {
        // Act & Assert: agent_idが欠けている
        XCTAssertThrowsError(
            try mcpServer.executeTool(
                name: "register_execution_log_file",
                arguments: ["task_id": "tsk_1", "log_file_path": "/tmp/test.log"],
                caller: .coordinator
            )
        ) { error in
            if case MCPError.missingArguments(let args) = error {
                XCTAssertTrue(args.contains("agent_id"))
            } else {
                XCTFail("Should throw MCPError.missingArguments")
            }
        }
    }
}

// MARK: - findLatestByAgentAndTask Repository Tests

/// ExecutionLogRepository.findLatestByAgentAndTask の単体テスト
final class ExecutionLogRepositoryFindLatestTests: XCTestCase {

    var db: DatabaseQueue!
    var executionLogRepository: ExecutionLogRepository!
    var taskRepository: TaskRepository!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!

    let testAgentId = AgentID(value: "agt_latest_test")
    let testProjectId = ProjectID(value: "prj_latest_test")
    let testTaskId = TaskID(value: "tsk_latest_test")

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_exec_log_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        executionLogRepository = ExecutionLogRepository(database: db)
        taskRepository = TaskRepository(database: db)
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)

        try setupTestData()
    }

    override func tearDownWithError() throws {
        db = nil
    }

    private func setupTestData() throws {
        let project = Project(id: testProjectId, name: "Test Project")
        try projectRepository.save(project)

        let agent = Agent(id: testAgentId, name: "Test Agent", role: "Worker")
        try agentRepository.save(agent)

        let task = Task(id: testTaskId, projectId: testProjectId, title: "Test Task")
        try taskRepository.save(task)
    }

    /// 最新の実行ログを正しく取得することを検証
    func testFindLatestByAgentAndTaskReturnsLatest() throws {
        // Arrange: 複数の実行ログを作成（異なる開始時刻で）
        let oldLog = ExecutionLog(
            id: ExecutionLogID.generate(),
            taskId: testTaskId,
            agentId: testAgentId,
            startedAt: Date().addingTimeInterval(-3600)  // 1時間前
        )
        try executionLogRepository.save(oldLog)

        // 少し待機して新しいログを作成
        let newLog = ExecutionLog(
            id: ExecutionLogID.generate(),
            taskId: testTaskId,
            agentId: testAgentId,
            startedAt: Date()  // 現在
        )
        try executionLogRepository.save(newLog)

        // Act
        let result = try executionLogRepository.findLatestByAgentAndTask(
            agentId: testAgentId,
            taskId: testTaskId
        )

        // Assert: 最新のログが返される
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, newLog.id, "Should return the most recent log")
    }

    /// 該当するログが存在しない場合にnilを返すことを検証
    func testFindLatestByAgentAndTaskReturnsNilWhenNotFound() throws {
        // Act: 存在しないエージェント/タスクで検索
        let result = try executionLogRepository.findLatestByAgentAndTask(
            agentId: AgentID(value: "agt_nonexistent"),
            taskId: TaskID(value: "tsk_nonexistent")
        )

        // Assert
        XCTAssertNil(result, "Should return nil when no log exists")
    }

    /// エージェントIDとタスクIDの両方が一致するログのみを返すことを検証
    func testFindLatestByAgentAndTaskMatchesBothIds() throws {
        // Arrange: 同じタスクで異なるエージェントのログ
        let otherAgentId = AgentID(value: "agt_other")
        let otherAgent = Agent(id: otherAgentId, name: "Other Agent", role: "Worker")
        try agentRepository.save(otherAgent)

        let otherAgentLog = ExecutionLog(
            taskId: testTaskId,
            agentId: otherAgentId,
            startedAt: Date()  // 最新
        )
        try executionLogRepository.save(otherAgentLog)

        let myLog = ExecutionLog(
            taskId: testTaskId,
            agentId: testAgentId,
            startedAt: Date().addingTimeInterval(-60)  // 1分前
        )
        try executionLogRepository.save(myLog)

        // Act
        let result = try executionLogRepository.findLatestByAgentAndTask(
            agentId: testAgentId,
            taskId: testTaskId
        )

        // Assert: 自分のエージェントのログが返される
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.agentId, testAgentId, "Should return log for the specified agent")
        XCTAssertEqual(result?.id, myLog.id)
    }
}
