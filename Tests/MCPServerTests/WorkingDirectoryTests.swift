// Tests/MCPServerTests/WorkingDirectoryTests.swift
// WorkingDirectoryResolutionTests - extracted from MCPServerTests.swift

import XCTest
import GRDB
@testable import Domain
@testable import UseCase
@testable import Infrastructure

// MARK: - Working Directory Resolution Tests

/// ワーキングディレクトリ解決のテスト
/// Bug: getMyTask が AgentWorkingDirectory を参照せず、Project.workingDirectory のみを使用している
/// 期待: AgentWorkingDirectory > Project.workingDirectory の優先順位で解決されるべき
final class WorkingDirectoryResolutionTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var taskRepository: TaskRepository!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var agentSessionRepository: AgentSessionRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!
    var workingDirectoryRepository: AgentWorkingDirectoryRepository!
    var executionLogRepository: ExecutionLogRepository!

    // テストデータ
    let testAgentId = AgentID(value: "agt_working_dir_test")
    let testProjectId = ProjectID(value: "prj_working_dir_test")
    let testTaskId = TaskID(value: "tsk_working_dir_test")

    // ワーキングディレクトリのテスト値
    let projectWorkingDirectory = "/project/default/path"
    let agentWorkingDirectory = "/agent/specific/path"  // この値が返されるべき

    override func setUpWithError() throws {
        // テスト用インメモリDBを作成
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_wd_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // リポジトリを初期化
        taskRepository = TaskRepository(database: db)
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)
        agentCredentialRepository = AgentCredentialRepository(database: db)
        agentSessionRepository = AgentSessionRepository(database: db)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: db)
        workingDirectoryRepository = AgentWorkingDirectoryRepository(database: db)
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
        // プロジェクトを作成（workingDirectoryを設定）
        var project = Project(
            id: testProjectId,
            name: "Working Dir Test Project",
            description: "Test project for working directory resolution"
        )
        project.workingDirectory = projectWorkingDirectory
        try projectRepository.save(project)

        // エージェントを作成（Worker）
        let agent = Agent(
            id: testAgentId,
            name: "Test Worker",
            role: "Worker agent for working directory testing",
            hierarchyType: .worker,
            systemPrompt: "You are a test worker"
        )
        try agentRepository.save(agent)

        // プロジェクトにエージェントを割り当て
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: testAgentId
        )

        // エージェント認証情報を作成
        let credential = AgentCredential(
            agentId: testAgentId,
            rawPasskey: "test_wd_passkey_12345"
        )
        try agentCredentialRepository.save(credential)

        // タスクを作成（in_progress状態）
        let task = Task(
            id: testTaskId,
            projectId: testProjectId,
            title: "Working Directory Test Task",
            description: "Task for testing working directory resolution",
            status: .inProgress,
            priority: .medium,
            assigneeId: testAgentId
        )
        try taskRepository.save(task)

        // ★重要★ AgentWorkingDirectoryを設定（これが優先されるべき）
        let agentWD = AgentWorkingDirectory.create(
            agentId: testAgentId,
            projectId: testProjectId,
            workingDirectory: agentWorkingDirectory
        )
        try workingDirectoryRepository.save(agentWD)
    }

    // 削除済み: testGetMyTaskReturnsAgentWorkingDirectory
    // 削除済み: testGetMyTaskFallsBackToProjectWorkingDirectoryWhenAgentWDNotSet
    // 理由: get_my_task は設計上 working_directory を返さない
    // (Coordinator が cwd パラメータで管理するため)
    // 参照: commit 9b0ad78 "Remove working_directory from MCP API responses"

    /// list_active_projects_with_agents が agentId パラメータで AgentWorkingDirectory を返すことを検証
    /// （これは正しく実装されているはず - 参考のため）
    func testListActiveProjectsWithAgentsReturnsAgentWorkingDirectory() throws {
        // Act: list_active_projects_with_agents を agentId 付きで呼び出し
        let arguments: [String: Any] = [
            "agent_id": testAgentId.value
        ]

        let result = try mcpServer.executeTool(
            name: "list_active_projects_with_agents",
            arguments: arguments,
            caller: .coordinator
        )

        // Assert: AgentWorkingDirectoryが返される
        guard let resultDict = result as? [String: Any],
              let projects = resultDict["projects"] as? [[String: Any]] else {
            XCTFail("Projects should be present in result")
            return
        }

        let targetProject = projects.first { ($0["project_id"] as? String) == testProjectId.value }
        XCTAssertNotNil(targetProject, "Test project should be in list")

        let returnedWorkingDir = targetProject?["working_directory"] as? String
        XCTAssertEqual(
            returnedWorkingDir,
            agentWorkingDirectory,
            "list_active_projects_with_agents should return AgentWorkingDirectory when agentId is provided"
        )
    }
}
