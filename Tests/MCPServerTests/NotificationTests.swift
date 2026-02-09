// Tests/MCPServerTests/NotificationTests.swift
// NotificationToolDefinitionTests, NotificationToolAuthorizationTests, NotificationSystemIntegrationTests
// - extracted from MCPServerTests.swift

import XCTest
import GRDB
@testable import Domain
@testable import UseCase
@testable import Infrastructure

// MARK: - Notification System Tests
// 参照: docs/design/NOTIFICATION_SYSTEM.md

/// get_notifications ツール定義テスト
final class NotificationToolDefinitionTests: XCTestCase {

    func testGetNotificationsToolDefinition() {
        let tools = ToolDefinitions.all()
        let tool = tools.first { ($0["name"] as? String) == "get_notifications" }

        XCTAssertNotNil(tool, "get_notifications tool should be defined")
        XCTAssertNotNil(tool?["description"])

        if let schema = tool?["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "get_notifications should require session_token")
        }
    }

    func testGetNotificationsToolInAllTools() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(toolNames.contains("get_notifications"), "get_notifications should be in all tools")
    }

    func testGetNotificationsToolHasMarkAsReadParameter() {
        let tools = ToolDefinitions.all()
        let tool = tools.first { ($0["name"] as? String) == "get_notifications" }

        XCTAssertNotNil(tool, "get_notifications tool should be defined")

        if let schema = tool?["inputSchema"] as? [String: Any],
           let properties = schema["properties"] as? [String: Any] {
            XCTAssertNotNil(properties["mark_as_read"], "get_notifications should have mark_as_read parameter")
        }
    }
}

/// get_notifications ツール認可テスト
final class NotificationToolAuthorizationTests: XCTestCase {

    func testGetNotificationsRequiresAuthentication() {
        let permission = ToolAuthorization.permissions["get_notifications"]
        XCTAssertEqual(permission, .authenticated, "get_notifications should require authentication")
    }
}

/// 通知システム統合テスト
final class NotificationSystemIntegrationTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var notificationRepository: NotificationRepository!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var taskRepository: TaskRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var agentSessionRepository: AgentSessionRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!

    let testAgentId = AgentID(value: "agt_notif_test")
    let testProjectId = ProjectID(value: "prj_notif_test")
    var sessionToken: String?
    var tempDirectory: URL!

    override func setUpWithError() throws {
        // Create temp directory for working directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notif_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let dbPath = tempDirectory.appendingPathComponent("test.db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        notificationRepository = NotificationRepository(database: db)
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)
        taskRepository = TaskRepository(database: db)
        agentCredentialRepository = AgentCredentialRepository(database: db)
        agentSessionRepository = AgentSessionRepository(database: db)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: db)

        mcpServer = MCPServer(database: db)

        try setupTestData()
    }

    override func tearDownWithError() throws {
        mcpServer = nil
        db = nil
        sessionToken = nil
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
            name: "Notification Test Project",
            description: "Project for notification testing",
            workingDirectory: tempDirectory.path
        )
        try projectRepository.save(project)

        // エージェントを作成
        let agent = Agent(
            id: testAgentId,
            name: "Notification Test Agent",
            role: "Test agent",
            hierarchyType: .worker,
            systemPrompt: "Test prompt"
        )
        try agentRepository.save(agent)

        // プロジェクトにエージェントを割り当て
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: testAgentId
        )

        // 認証情報を作成
        let credential = AgentCredential(
            agentId: testAgentId,
            rawPasskey: "test_passkey_notif"
        )
        try agentCredentialRepository.save(credential)

        // Session Spawn Architecture: Create in_progress task for task session authentication
        let task = Domain.Task(
            id: TaskID(value: "tsk_test_notif"),
            projectId: testProjectId,
            title: "Test Task for Notification",
            status: .inProgress,
            assigneeId: testAgentId
        )
        try taskRepository.save(task)

        // 認証してセッショントークンを取得
        let result = try mcpServer.executeTool(
            name: "authenticate",
            arguments: [
                "agent_id": testAgentId.value,
                "passkey": "test_passkey_notif",
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        if let dict = result as? [String: Any],
           let token = dict["session_token"] as? String {
            sessionToken = token
        }
    }

    // MARK: - get_notifications Tests

    func testGetNotificationsReturnsEmptyWhenNoNotifications() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        let session = try agentSessionRepository.findByToken(token)!
        let result = try mcpServer.executeTool(
            name: "get_notifications",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        XCTAssertEqual(dict["success"] as? Bool, true)
        XCTAssertEqual(dict["count"] as? Int, 0)
        XCTAssertEqual((dict["notifications"] as? [[String: Any]])?.count, 0)
    }

    func testGetNotificationsReturnsUnreadNotifications() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        // 未読通知を作成
        let notification = AgentNotification.createStatusChangeNotification(
            targetAgentId: testAgentId,
            targetProjectId: testProjectId,
            taskId: TaskID(value: "tsk_test"),
            newStatus: "blocked"
        )
        try notificationRepository.save(notification)

        let session = try agentSessionRepository.findByToken(token)!
        let result = try mcpServer.executeTool(
            name: "get_notifications",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        XCTAssertEqual(dict["success"] as? Bool, true)
        XCTAssertEqual(dict["count"] as? Int, 1)

        let notifications = dict["notifications"] as? [[String: Any]]
        XCTAssertEqual(notifications?.count, 1)
        XCTAssertEqual(notifications?.first?["type"] as? String, "status_change")
        XCTAssertEqual(notifications?.first?["action"] as? String, "blocked")
    }

    func testGetNotificationsMarksAsReadByDefault() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        // 未読通知を作成
        let notification = AgentNotification.createStatusChangeNotification(
            targetAgentId: testAgentId,
            targetProjectId: testProjectId,
            taskId: TaskID(value: "tsk_test"),
            newStatus: "blocked"
        )
        try notificationRepository.save(notification)

        let session = try agentSessionRepository.findByToken(token)!

        // 最初の取得
        _ = try mcpServer.executeTool(
            name: "get_notifications",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        // 2回目の取得 - 既読になっているはず
        let result = try mcpServer.executeTool(
            name: "get_notifications",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        XCTAssertEqual(dict["count"] as? Int, 0, "Notifications should be marked as read")
    }

    func testGetNotificationsWithMarkAsReadFalse() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        // 未読通知を作成
        let notification = AgentNotification.createStatusChangeNotification(
            targetAgentId: testAgentId,
            targetProjectId: testProjectId,
            taskId: TaskID(value: "tsk_test"),
            newStatus: "blocked"
        )
        try notificationRepository.save(notification)

        let session = try agentSessionRepository.findByToken(token)!

        // mark_as_read=false で取得
        _ = try mcpServer.executeTool(
            name: "get_notifications",
            arguments: ["session_token": token, "mark_as_read": false],
            caller: .worker(agentId: testAgentId, session: session)
        )

        // 2回目の取得 - まだ未読のはず
        let result = try mcpServer.executeTool(
            name: "get_notifications",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        XCTAssertEqual(dict["count"] as? Int, 1, "Notifications should still be unread")
    }

    func testGetNotificationsOnlyReturnsForCurrentAgentAndProject() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        // 別のエージェント宛の通知
        let otherAgentNotification = AgentNotification.createStatusChangeNotification(
            targetAgentId: AgentID(value: "agt_other"),
            targetProjectId: testProjectId,
            taskId: TaskID(value: "tsk_test"),
            newStatus: "blocked"
        )
        try notificationRepository.save(otherAgentNotification)

        // 別のプロジェクト宛の通知
        let otherProjectNotification = AgentNotification.createStatusChangeNotification(
            targetAgentId: testAgentId,
            targetProjectId: ProjectID(value: "prj_other"),
            taskId: TaskID(value: "tsk_test"),
            newStatus: "blocked"
        )
        try notificationRepository.save(otherProjectNotification)

        // 正しい宛先の通知
        let correctNotification = AgentNotification.createStatusChangeNotification(
            targetAgentId: testAgentId,
            targetProjectId: testProjectId,
            taskId: TaskID(value: "tsk_test"),
            newStatus: "done"
        )
        try notificationRepository.save(correctNotification)

        let session = try agentSessionRepository.findByToken(token)!
        let result = try mcpServer.executeTool(
            name: "get_notifications",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        XCTAssertEqual(dict["count"] as? Int, 1, "Should only return notification for current agent and project")

        let notifications = dict["notifications"] as? [[String: Any]]
        XCTAssertEqual(notifications?.first?["action"] as? String, "done")
    }
}
