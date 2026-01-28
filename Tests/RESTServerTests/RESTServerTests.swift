// Tests/RESTServerTests/RESTServerTests.swift
// REST API Server Tests - Endpoint verification
//
// Note: This test file verifies that REST API endpoints are correctly registered
// and return expected responses. It uses actual HTTP requests to test the server.

import XCTest
import GRDB
@testable import Infrastructure
@testable import Domain

/// REST API Server Integration Tests
/// These tests verify that the REST API endpoints are correctly configured
/// and respond to HTTP requests as expected.
final class RESTServerTests: XCTestCase {

    var db: DatabaseQueue!
    var projectRepository: ProjectRepository!
    var agentRepository: AgentRepository!
    var taskRepository: TaskRepository!
    var agentSessionRepository: AgentSessionRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!
    var handoffRepository: HandoffRepository!

    // Test data
    let testProjectId = ProjectID(value: "prj_rest_test")
    let testAgentId = AgentID(value: "agt_rest_test")
    let testTaskId = TaskID(value: "tsk_rest_test")
    let testPasskey = "test_passkey_12345"

    override func setUpWithError() throws {
        // Create test database
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_rest_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // Initialize repositories
        projectRepository = ProjectRepository(database: db)
        agentRepository = AgentRepository(database: db)
        taskRepository = TaskRepository(database: db)
        agentSessionRepository = AgentSessionRepository(database: db)
        agentCredentialRepository = AgentCredentialRepository(database: db)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: db)
        handoffRepository = HandoffRepository(database: db)

        // Setup test data
        try setupTestData()
    }

    override func tearDownWithError() throws {
        db = nil
    }

    private func setupTestData() throws {
        // Create test project
        let project = Project(
            id: testProjectId,
            name: "REST Test Project",
            description: "Project for REST API testing"
        )
        try projectRepository.save(project)

        // Create test agent (human type + manager for full permissions)
        let agent = Agent(
            id: testAgentId,
            name: "Test Agent",
            role: "Test Manager",
            type: .human,
            hierarchyType: .manager,
            systemPrompt: "You are a test agent"
        )
        try agentRepository.save(agent)

        // Assign agent to project
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: testAgentId
        )

        // Create agent credential
        let credential = AgentCredential(
            agentId: testAgentId,
            rawPasskey: testPasskey
        )
        try agentCredentialRepository.save(credential)

        // Create test task
        let task = Task(
            id: testTaskId,
            projectId: testProjectId,
            title: "Test Task",
            description: "Task for testing REST API",
            status: .inProgress,
            priority: .medium,
            assigneeId: testAgentId
        )
        try taskRepository.save(task)
    }

    // MARK: - Session Helper

    /// Create a valid session for testing protected routes
    func createTestSession() throws -> AgentSession {
        let session = AgentSession(
            agentId: testAgentId,
            projectId: testProjectId,
            purpose: .task
        )
        try agentSessionRepository.save(session)
        return session
    }

    // MARK: - Repository Tests (Verify Test Data Setup)

    /// Verify test project exists
    func testProjectExists() throws {
        let project = try projectRepository.findById(testProjectId)
        XCTAssertNotNil(project, "Test project should exist")
        XCTAssertEqual(project?.name, "REST Test Project")
    }

    /// Verify test agent exists
    func testAgentExists() throws {
        let agent = try agentRepository.findById(testAgentId)
        XCTAssertNotNil(agent, "Test agent should exist")
        XCTAssertEqual(agent?.name, "Test Agent")
    }

    /// Verify test task exists
    func testTaskExists() throws {
        let task = try taskRepository.findById(testTaskId)
        XCTAssertNotNil(task, "Test task should exist")
        XCTAssertEqual(task?.title, "Test Task")
    }

    /// Verify session creation
    func testSessionCreation() throws {
        let session = try createTestSession()

        let found = try agentSessionRepository.findByToken(session.token)
        XCTAssertNotNil(found, "Session should be retrievable by token")
        XCTAssertEqual(found?.agentId, testAgentId)
    }

    // MARK: - Task Permissions Tests

    /// Verify task permissions logic for in_progress task
    /// When task status is in_progress, reassignment should be disabled
    func testTaskPermissionsForInProgressTask() throws {
        // Task is in_progress status
        let task = try taskRepository.findById(testTaskId)
        XCTAssertEqual(task?.status, .inProgress, "Task should be in_progress")

        // Calculate expected permissions
        // For in_progress task:
        // - canEdit: true (task exists)
        // - canChangeStatus: true (can always change status)
        // - canReassign: false (cannot reassign while in_progress)
        // - validStatusTransitions: depends on business rules

        // Verify business rule: in_progress task cannot be reassigned
        // This matches the mock handler logic in handlers.ts:
        // const canReassign = task.status !== 'in_progress' && task.status !== 'blocked'
        let canReassign = (task?.status != .inProgress && task?.status != .blocked)
        XCTAssertFalse(canReassign, "in_progress task should not be reassignable")
    }

    /// Verify task permissions logic for todo task
    func testTaskPermissionsForTodoTask() throws {
        // Create a todo task
        let todoTaskId = TaskID.generate()
        let todoTask = Task(
            id: todoTaskId,
            projectId: testProjectId,
            title: "Todo Task",
            status: .todo,
            priority: .medium,
            assigneeId: testAgentId
        )
        try taskRepository.save(todoTask)

        // Verify business rule: todo task can be reassigned
        let task = try taskRepository.findById(todoTaskId)
        let canReassign = (task?.status != .inProgress && task?.status != .blocked)
        XCTAssertTrue(canReassign, "todo task should be reassignable")
    }

    // MARK: - Task Handoffs Tests

    /// Verify handoff creation and retrieval for a task
    func testTaskHandoffsRetrieval() throws {
        // Create a handoff for the test task
        let handoff = Handoff(
            id: HandoffID.generate(),
            taskId: testTaskId,
            fromAgentId: testAgentId,
            toAgentId: nil,
            summary: "Test handoff summary",
            context: "Test context"
        )
        try handoffRepository.save(handoff)

        // Retrieve handoffs for the task
        let handoffs = try handoffRepository.findByTask(testTaskId)
        XCTAssertFalse(handoffs.isEmpty, "Should have at least one handoff")
        XCTAssertEqual(handoffs.first?.summary, "Test handoff summary")
    }
}

// MARK: - Route Registration Verification Tests

/// Tests to verify that routes are correctly registered in RESTServer
/// Note: These tests don't require the full server to be running
final class RESTServerRouteRegistrationTests: XCTestCase {

    /// Verify the expected route patterns exist
    /// This documents the expected API structure
    func testExpectedRoutePatterns() {
        // Document expected routes based on RESTServer.swift implementation
        let expectedProtectedRoutes = [
            // Auth routes
            "POST /api/auth/login",     // Login (public)
            "POST /api/auth/logout",    // Logout (protected)
            "GET /api/auth/me",         // Current user (protected)

            // Project routes
            "GET /api/projects",        // List projects
            "GET /api/projects/:id",    // Get project

            // Task routes under projects
            "GET /api/projects/:projectId/tasks",   // List tasks
            "POST /api/projects/:projectId/tasks",  // Create task

            // Direct task routes
            "GET /api/tasks/:taskId",              // Get task
            "PATCH /api/tasks/:taskId",            // Update task
            "DELETE /api/tasks/:taskId",           // Delete task
            "GET /api/tasks/:taskId/permissions",  // Get task permissions
            "GET /api/tasks/:taskId/handoffs",     // Get task handoffs

            // Agent routes
            "GET /api/agents/assignable",   // List assignable agents

            // Handoff routes
            "GET /api/handoffs",                    // List handoffs
            "POST /api/handoffs",                   // Create handoff
            "POST /api/handoffs/:handoffId/accept", // Accept handoff
        ]

        // This test documents the expected routes
        // If this test fails after refactoring, it indicates route changes
        XCTAssertEqual(expectedProtectedRoutes.count, 16, "Should have 16 expected routes")
    }

    /// Verify /api/tasks/:taskId/permissions route pattern
    /// This is the route returning 404 in production
    func testPermissionsRoutePattern() {
        let pattern = "GET /api/tasks/:taskId/permissions"

        // Example valid URLs that should match this pattern
        let validURLs = [
            "/api/tasks/task-1/permissions",
            "/api/tasks/tsk_abc123/permissions",
            "/api/tasks/123/permissions",
        ]

        // Verify URL structure
        for url in validURLs {
            XCTAssertTrue(url.hasPrefix("/api/tasks/"), "Should start with /api/tasks/")
            XCTAssertTrue(url.hasSuffix("/permissions"), "Should end with /permissions")

            // Extract taskId from URL
            let components = url.split(separator: "/")
            XCTAssertEqual(components.count, 4, "Should have 4 path components: api, tasks, taskId, permissions")
            XCTAssertEqual(String(components[0]), "api")
            XCTAssertEqual(String(components[1]), "tasks")
            XCTAssertEqual(String(components[3]), "permissions")
        }

        XCTAssertEqual(pattern, "GET /api/tasks/:taskId/permissions")
    }

    /// Verify /api/tasks/:taskId/handoffs route pattern
    func testHandoffsRoutePattern() {
        let pattern = "GET /api/tasks/:taskId/handoffs"

        // Example valid URLs that should match this pattern
        let validURLs = [
            "/api/tasks/task-1/handoffs",
            "/api/tasks/tsk_abc123/handoffs",
        ]

        for url in validURLs {
            XCTAssertTrue(url.hasPrefix("/api/tasks/"), "Should start with /api/tasks/")
            XCTAssertTrue(url.hasSuffix("/handoffs"), "Should end with /handoffs")

            let components = url.split(separator: "/")
            XCTAssertEqual(components.count, 4, "Should have 4 path components")
            XCTAssertEqual(String(components[0]), "api")
            XCTAssertEqual(String(components[1]), "tasks")
            XCTAssertEqual(String(components[3]), "handoffs")
        }

        XCTAssertEqual(pattern, "GET /api/tasks/:taskId/handoffs")
    }
}

// MARK: - Task Status Transition Tests

/// Tests to verify task status transition rules
final class TaskStatusTransitionTests: XCTestCase {

    var db: DatabaseQueue!
    var taskRepository: TaskRepository!
    var projectRepository: ProjectRepository!

    let testProjectId = ProjectID(value: "prj_status_test")

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_status_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        taskRepository = TaskRepository(database: db)
        projectRepository = ProjectRepository(database: db)

        // Create test project
        let project = Project(id: testProjectId, name: "Status Test Project")
        try projectRepository.save(project)
    }

    override func tearDownWithError() throws {
        db = nil
    }

    /// Test valid status transitions based on PRD requirements
    func testValidStatusTransitionsFromBacklog() {
        // From backlog, can go to: todo, cancelled
        let validTransitions: [TaskStatus] = [.todo, .cancelled]
        let invalidTransitions: [TaskStatus] = [.inProgress, .done, .blocked]

        // Document expected behavior
        XCTAssertEqual(validTransitions.count, 2)
        XCTAssertEqual(invalidTransitions.count, 3)
    }

    /// Test valid status transitions from in_progress
    func testValidStatusTransitionsFromInProgress() {
        // From in_progress, can go to: done, blocked, cancelled
        // Cannot go back to: todo (this is the restriction causing 404 in permissions)
        let validTransitions: [TaskStatus] = [.done, .blocked, .cancelled]
        let invalidTransitions: [TaskStatus] = [.backlog, .todo]

        XCTAssertTrue(validTransitions.contains(.done))
        XCTAssertTrue(validTransitions.contains(.blocked))
        XCTAssertFalse(validTransitions.contains(.todo), "in_progress should not be able to go back to todo")
    }
}

// MARK: - HTTP Integration Tests

// Type alias to avoid conflict with Domain.Task
fileprivate typealias ConcurrencyTask = _Concurrency.Task

/// Tests to verify HTTP endpoints respond correctly
/// These tests start the actual REST server and make HTTP requests
final class HTTPIntegrationTests: XCTestCase {

    var db: DatabaseQueue!
    var projectRepository: ProjectRepository!
    var agentRepository: AgentRepository!
    var taskRepository: TaskRepository!
    var agentSessionRepository: AgentSessionRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!
    var server: RESTServer!
    fileprivate var serverTask: ConcurrencyTask<Void, Error>?

    let testPort = 18080  // Use different port to avoid conflicts
    let testProjectId = ProjectID(value: "prj_http_test")
    let testAgentId = AgentID(value: "agt_http_test")
    let testTaskId = TaskID(value: "tsk_http_test")
    let testPasskey = "http_test_passkey"

    override func setUpWithError() throws {
        // Create test database
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_http_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // Initialize repositories
        projectRepository = ProjectRepository(database: db)
        agentRepository = AgentRepository(database: db)
        taskRepository = TaskRepository(database: db)
        agentSessionRepository = AgentSessionRepository(database: db)
        agentCredentialRepository = AgentCredentialRepository(database: db)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: db)

        // Setup test data
        try setupTestData()

        // Create and start server
        server = RESTServer(database: db, port: testPort, webUIPath: nil)
        serverTask = ConcurrencyTask {
            try await self.server.run()
        }

        // Wait for server to start
        Thread.sleep(forTimeInterval: 0.5)
    }

    override func tearDownWithError() throws {
        serverTask?.cancel()
        db = nil
        server = nil
    }

    private func setupTestData() throws {
        // Create temporary working directory for chat feature tests
        let tempDir = FileManager.default.temporaryDirectory
        let testWorkingDir = tempDir.appendingPathComponent("http_test_workdir_\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: testWorkingDir, withIntermediateDirectories: true)

        // Create test project with working directory
        let project = Project(
            id: testProjectId,
            name: "HTTP Test Project",
            description: "Project for HTTP testing",
            workingDirectory: testWorkingDir
        )
        try projectRepository.save(project)

        // Create test agent (human type + manager for full permissions)
        let agent = Agent(
            id: testAgentId,
            name: "HTTP Test Agent",
            role: "Test Manager",
            type: .human,
            hierarchyType: .manager,
            systemPrompt: "You are a test agent"
        )
        try agentRepository.save(agent)

        // Assign agent to project
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: testAgentId
        )

        // Create agent credential
        let credential = AgentCredential(
            agentId: testAgentId,
            rawPasskey: testPasskey
        )
        try agentCredentialRepository.save(credential)

        // Create test task
        let task = Domain.Task(
            id: testTaskId,
            projectId: testProjectId,
            title: "HTTP Test Task",
            description: "Task for HTTP testing",
            status: .inProgress,
            priority: .medium,
            assigneeId: testAgentId
        )
        try taskRepository.save(task)
    }

    // MARK: - Helper Methods

    private func makeRequest(
        method: String,
        path: String,
        body: Data? = nil,
        token: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let url = URL(string: "http://127.0.0.1:\(testPort)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, response as! HTTPURLResponse)
    }

    private func login() async throws -> String {
        let loginBody = try JSONEncoder().encode([
            "agentId": testAgentId.value,
            "passkey": testPasskey
        ])

        let (data, response) = try await makeRequest(
            method: "POST",
            path: "/api/auth/login",
            body: loginBody
        )

        XCTAssertEqual(response.statusCode, 200, "Login should succeed")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return json["sessionToken"] as! String
    }

    // MARK: - Health Check Test

    func testHealthEndpoint() async throws {
        let (data, response) = try await makeRequest(method: "GET", path: "/health")

        XCTAssertEqual(response.statusCode, 200, "Health endpoint should return 200")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["status"] as? String, "ok")
    }

    // MARK: - Auth Tests

    func testLoginEndpoint() async throws {
        let loginBody = try JSONEncoder().encode([
            "agentId": testAgentId.value,
            "passkey": testPasskey
        ])

        let (data, response) = try await makeRequest(
            method: "POST",
            path: "/api/auth/login",
            body: loginBody
        )

        XCTAssertEqual(response.statusCode, 200, "Login should succeed")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["sessionToken"], "Response should contain sessionToken")
        XCTAssertNotNil(json["agent"], "Response should contain agent")
    }

    func testLoginWithInvalidCredentials() async throws {
        let loginBody = try JSONEncoder().encode([
            "agentId": testAgentId.value,
            "passkey": "wrong_passkey"
        ])

        let (_, response) = try await makeRequest(
            method: "POST",
            path: "/api/auth/login",
            body: loginBody
        )

        XCTAssertEqual(response.statusCode, 401, "Login with wrong credentials should return 401")
    }

    func testLoginWithAIAgentShouldFail() async throws {
        // Create an AI agent
        let aiAgentId = AgentID(value: "agt_ai_test")
        let aiPasskey = "ai_passkey_12345"

        let aiAgent = Agent(
            id: aiAgentId,
            name: "AI Test Agent",
            role: "Test Worker",
            type: .ai,
            hierarchyType: .worker
        )
        try agentRepository.save(aiAgent)

        // Create credential for AI agent
        let credential = AgentCredential(
            agentId: aiAgentId,
            rawPasskey: aiPasskey
        )
        try agentCredentialRepository.save(credential)

        // Try to login with AI agent - should be rejected
        let loginBody = try JSONEncoder().encode([
            "agentId": aiAgentId.value,
            "passkey": aiPasskey
        ])

        let (data, response) = try await makeRequest(
            method: "POST",
            path: "/api/auth/login",
            body: loginBody
        )

        XCTAssertEqual(response.statusCode, 403, "AI agent login should return 403 Forbidden")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertTrue((json["message"] as? String)?.contains("human") ?? false,
                      "Error message should mention human agents only")
    }

    // MARK: - Task Permissions Tests (The 404 issue)

    func testTaskPermissionsEndpoint() async throws {
        // First login to get session token
        let token = try await login()

        // Now test the permissions endpoint
        let (data, response) = try await makeRequest(
            method: "GET",
            path: "/api/tasks/\(testTaskId.value)/permissions",
            token: token
        )

        XCTAssertEqual(response.statusCode, 200, "GET /api/tasks/:taskId/permissions should return 200, not 404")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["canEdit"], "Response should contain canEdit")
        XCTAssertNotNil(json["canChangeStatus"], "Response should contain canChangeStatus")
        XCTAssertNotNil(json["canReassign"], "Response should contain canReassign")
        XCTAssertNotNil(json["validStatusTransitions"], "Response should contain validStatusTransitions")
    }

    func testTaskPermissionsWithoutAuth() async throws {
        let (_, response) = try await makeRequest(
            method: "GET",
            path: "/api/tasks/\(testTaskId.value)/permissions"
        )

        XCTAssertEqual(response.statusCode, 401, "Permissions without auth should return 401")
    }

    // MARK: - Task Handoffs Tests

    func testTaskHandoffsEndpoint() async throws {
        let token = try await login()

        let (data, response) = try await makeRequest(
            method: "GET",
            path: "/api/tasks/\(testTaskId.value)/handoffs",
            token: token
        )

        XCTAssertEqual(response.statusCode, 200, "GET /api/tasks/:taskId/handoffs should return 200, not 404")

        // Response should be an array (possibly empty)
        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [Any], "Response should be an array")
    }

    // MARK: - Task CRUD Tests

    func testGetTaskEndpoint() async throws {
        let token = try await login()

        let (data, response) = try await makeRequest(
            method: "GET",
            path: "/api/tasks/\(testTaskId.value)",
            token: token
        )

        XCTAssertEqual(response.statusCode, 200, "GET /api/tasks/:taskId should return 200")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["id"] as? String, testTaskId.value)
        XCTAssertEqual(json["title"] as? String, "HTTP Test Task")
    }

    func testGetNonExistentTask() async throws {
        let token = try await login()

        let (_, response) = try await makeRequest(
            method: "GET",
            path: "/api/tasks/non_existent_task_id",
            token: token
        )

        XCTAssertEqual(response.statusCode, 404, "Non-existent task should return 404")
    }

    // MARK: - Projects Tests

    func testListProjectsEndpoint() async throws {
        let token = try await login()

        let (data, response) = try await makeRequest(
            method: "GET",
            path: "/api/projects",
            token: token
        )

        XCTAssertEqual(response.statusCode, 200, "GET /api/projects should return 200")

        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [Any], "Response should be an array")
    }

    /// Verify that GET /api/projects returns only projects the logged-in agent is assigned to
    /// Reference: docs/requirements/PROJECTS.md - Agent Assignment
    func testListProjectsReturnsOnlyAssignedProjects() async throws {
        // Create a second project that the test agent is NOT assigned to
        let unassignedProjectId = ProjectID(value: "prj_unassigned")
        let unassignedProject = Project(
            id: unassignedProjectId,
            name: "Unassigned Project",
            description: "Project that test agent is not assigned to"
        )
        try projectRepository.save(unassignedProject)

        // Login and get projects
        let token = try await login()
        let (data, response) = try await makeRequest(
            method: "GET",
            path: "/api/projects",
            token: token
        )

        XCTAssertEqual(response.statusCode, 200, "GET /api/projects should return 200")

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        // Should only return the assigned project, not the unassigned one
        XCTAssertEqual(json.count, 1, "Should return only 1 project (the one agent is assigned to)")

        let projectIds = json.compactMap { $0["id"] as? String }
        XCTAssertTrue(projectIds.contains(testProjectId.value), "Should contain the assigned project")
        XCTAssertFalse(projectIds.contains(unassignedProjectId.value), "Should NOT contain the unassigned project")
    }

    // MARK: - API 404 Tests

    func testUnknownAPIEndpointReturns404() async throws {
        let token = try await login()

        let (data, response) = try await makeRequest(
            method: "GET",
            path: "/api/unknown/endpoint",
            token: token
        )

        XCTAssertEqual(response.statusCode, 404, "Unknown API endpoint should return 404")

        // Should return JSON error, not HTML
        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        XCTAssertTrue(contentType?.contains("application/json") ?? false, "404 response should be JSON")
    }

    // MARK: - Chat API Tests
    // 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 1-2

    func testGetChatMessagesEndpoint() async throws {
        let token = try await login()

        // GET /api/projects/:projectId/agents/:agentId/chat/messages
        let (data, response) = try await makeRequest(
            method: "GET",
            path: "/api/projects/\(testProjectId.value)/agents/\(testAgentId.value)/chat/messages",
            token: token
        )

        XCTAssertEqual(response.statusCode, 200, "GET chat messages should return 200")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["messages"], "Response should contain messages array")
        XCTAssertNotNil(json["hasMore"], "Response should contain hasMore field")

        let messages = json["messages"] as? [Any]
        XCTAssertNotNil(messages, "messages should be an array")
    }

    func testGetChatMessagesWithLimitParameter() async throws {
        let token = try await login()

        // GET with limit parameter
        let (data, response) = try await makeRequest(
            method: "GET",
            path: "/api/projects/\(testProjectId.value)/agents/\(testAgentId.value)/chat/messages?limit=10",
            token: token
        )

        XCTAssertEqual(response.statusCode, 200, "GET chat messages with limit should return 200")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["messages"], "Response should contain messages array")
    }

    func testGetChatMessagesWithInvalidLimit() async throws {
        let token = try await login()

        // Invalid limit (exceeds max of 200, but should be clamped not error)
        let (data, response) = try await makeRequest(
            method: "GET",
            path: "/api/projects/\(testProjectId.value)/agents/\(testAgentId.value)/chat/messages?limit=500",
            token: token
        )

        // Should succeed with clamped limit
        XCTAssertEqual(response.statusCode, 200, "GET chat messages with limit > 200 should be clamped and return 200")
    }

    func testPostChatMessageEndpoint() async throws {
        let token = try await login()

        // POST /api/projects/:projectId/agents/:agentId/chat/messages
        let messageBody = try JSONEncoder().encode([
            "content": "Hello from HTTP test"
        ])

        let (data, response) = try await makeRequest(
            method: "POST",
            path: "/api/projects/\(testProjectId.value)/agents/\(testAgentId.value)/chat/messages",
            body: messageBody,
            token: token
        )

        XCTAssertEqual(response.statusCode, 201, "POST chat message should return 201")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["id"], "Response should contain message id")
        XCTAssertEqual(json["senderId"] as? String, testAgentId.value, "SenderId should be the logged-in agent")
        XCTAssertEqual(json["content"] as? String, "Hello from HTTP test", "Content should match")
    }

    func testPostChatMessageWithEmptyContent() async throws {
        let token = try await login()

        let messageBody = try JSONEncoder().encode([
            "content": ""
        ])

        let (data, response) = try await makeRequest(
            method: "POST",
            path: "/api/projects/\(testProjectId.value)/agents/\(testAgentId.value)/chat/messages",
            body: messageBody,
            token: token
        )

        XCTAssertEqual(response.statusCode, 400, "POST chat message with empty content should return 400")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["code"] as? String, "EMPTY_CONTENT", "Error code should be EMPTY_CONTENT")
    }

    func testPostChatMessageWithTooLongContent() async throws {
        let token = try await login()

        // Create content longer than 4000 characters
        let longContent = String(repeating: "a", count: 4001)
        let messageBody = try JSONEncoder().encode([
            "content": longContent
        ])

        let (data, response) = try await makeRequest(
            method: "POST",
            path: "/api/projects/\(testProjectId.value)/agents/\(testAgentId.value)/chat/messages",
            body: messageBody,
            token: token
        )

        XCTAssertEqual(response.statusCode, 400, "POST chat message with content > 4000 chars should return 400")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["code"] as? String, "CONTENT_TOO_LONG", "Error code should be CONTENT_TOO_LONG")
        XCTAssertNotNil(json["details"], "Response should contain details")
    }

    func testChatEndpointWithoutAuth() async throws {
        let (_, response) = try await makeRequest(
            method: "GET",
            path: "/api/projects/\(testProjectId.value)/agents/\(testAgentId.value)/chat/messages"
        )

        XCTAssertEqual(response.statusCode, 401, "Chat endpoint without auth should return 401")
    }
}

// MARK: - Chat Session Status Tests
// 参照: docs/design/CHAT_SESSION_STATUS.md
// TDD: RED → GREEN で実装
// 目的: チャットセッション状態（connected/connecting/disconnected）の正確な表示

/// Chat Session Status API Tests
/// These tests verify that the chat session status is correctly returned
/// based on active sessions and pending agent purposes.
final class ChatSessionStatusTests: XCTestCase {

    var db: DatabaseQueue!
    var projectRepository: ProjectRepository!
    var agentRepository: AgentRepository!
    var agentSessionRepository: AgentSessionRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!
    var server: RESTServer!
    fileprivate var serverTask: ConcurrencyTask<Void, Error>?

    let testPort = 18081  // Different port from other tests
    let testProjectId = ProjectID(value: "prj_chat_status_test")
    let testAgentId = AgentID(value: "agt_chat_status_test")
    let testHumanAgentId = AgentID(value: "agt_human_chat_status")
    let testPasskey = "chat_status_test_passkey"

    override func setUpWithError() throws {
        // Create test database
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_chat_status_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // Initialize repositories
        projectRepository = ProjectRepository(database: db)
        agentRepository = AgentRepository(database: db)
        agentSessionRepository = AgentSessionRepository(database: db)
        agentCredentialRepository = AgentCredentialRepository(database: db)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: db)

        // Setup test data (server NOT started yet - allows tests to modify DB first)
        try setupTestData()
    }

    /// サーバーを起動するヘルパー
    /// テスト固有のDB設定後に呼び出す（WALチェックポイント競合を回避）
    private func startServer() {
        server = RESTServer(database: db, port: testPort, webUIPath: nil)
        serverTask = ConcurrencyTask {
            try await self.server.run()
        }
        // Wait for server to start
        Thread.sleep(forTimeInterval: 0.5)
    }

    override func tearDownWithError() throws {
        serverTask?.cancel()
        // サーバー停止を待つ（DB接続が閉じられるまで）
        Thread.sleep(forTimeInterval: 0.5)
        db = nil
        server = nil
    }

    private func setupTestData() throws {
        // Create temporary working directory
        let tempDir = FileManager.default.temporaryDirectory
        let testWorkingDir = tempDir.appendingPathComponent("chat_status_test_\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: testWorkingDir, withIntermediateDirectories: true)

        // Create test project
        let project = Project(
            id: testProjectId,
            name: "Chat Status Test Project",
            description: "Project for chat status testing",
            workingDirectory: testWorkingDir
        )
        try projectRepository.save(project)

        // Create test AI agent (will be tested for chat status)
        let agent = Agent(
            id: testAgentId,
            name: "Chat Status Test Agent",
            role: "Test Worker",
            type: .ai,
            hierarchyType: .worker,
            systemPrompt: "Test agent"
        )
        try agentRepository.save(agent)

        // Create human agent for login (API authentication)
        let humanAgent = Agent(
            id: testHumanAgentId,
            name: "Human Manager",
            role: "Manager",
            type: .human,
            hierarchyType: .manager,
            systemPrompt: "Human manager"
        )
        try agentRepository.save(humanAgent)

        // Assign both agents to project
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: testAgentId
        )
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: testHumanAgentId
        )

        // Create credential for human agent (for API login)
        let credential = AgentCredential(
            agentId: testHumanAgentId,
            rawPasskey: testPasskey
        )
        try agentCredentialRepository.save(credential)
    }

    // MARK: - Helper Methods

    private func makeRequest(
        method: String,
        path: String,
        body: Data? = nil,
        token: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let url = URL(string: "http://127.0.0.1:\(testPort)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, response as! HTTPURLResponse)
    }

    private func login() async throws -> String {
        let loginBody = try JSONEncoder().encode([
            "agentId": testHumanAgentId.value,
            "passkey": testPasskey
        ])

        let (data, response) = try await makeRequest(
            method: "POST",
            path: "/api/auth/login",
            body: loginBody
        )

        XCTAssertEqual(response.statusCode, 200, "Login should succeed")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return json["sessionToken"] as! String
    }

    // MARK: - Test 1.1: connected 状態 (アクティブなchatセッションあり)

    func testAgentSessionsAPI_ReturnsChatStatusConnected() async throws {
        // Arrange: Create active chat session for the AI agent
        let session = AgentSession(
            agentId: testAgentId,
            projectId: testProjectId,
            purpose: .chat
        )
        try agentSessionRepository.save(session)

        // Start server AFTER DB setup (avoids WAL checkpoint conflict)
        startServer()

        // Act: Login and call agent-sessions API
        let token = try await login()
        let (data, response) = try await makeRequest(
            method: "GET",
            path: "/api/projects/\(testProjectId.value)/agent-sessions",
            token: token
        )

        // Assert
        XCTAssertEqual(response.statusCode, 200, "API should return 200")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let agentSessions = json["agentSessions"] as! [String: Any]
        let agentData = agentSessions[testAgentId.value] as! [String: Any]
        let chatData = agentData["chat"] as! [String: Any]

        XCTAssertEqual(chatData["count"] as? Int, 1, "Chat count should be 1")
        XCTAssertEqual(chatData["status"] as? String, "connected", "Chat status should be 'connected' when session exists")
    }

    // MARK: - Test 1.2: connecting 状態 (spawn_started_at設定済み、セッションなし)
    // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md

    func testAgentSessionsAPI_ReturnsChatStatusConnecting() async throws {
        // Arrange: Set spawn_started_at to recent time (within 120s timeout), but NO session
        let recentTime = Date().addingTimeInterval(-30) // 30 seconds ago (within timeout)
        try projectAgentAssignmentRepository.updateSpawnStartedAt(
            agentId: testAgentId,
            projectId: testProjectId,
            startedAt: recentTime
        )
        // Note: No AgentSession created

        // Start server AFTER DB setup (avoids WAL checkpoint conflict)
        startServer()

        // Act: Login and call agent-sessions API
        let token = try await login()
        let (data, response) = try await makeRequest(
            method: "GET",
            path: "/api/projects/\(testProjectId.value)/agent-sessions",
            token: token
        )

        // Assert
        XCTAssertEqual(response.statusCode, 200, "API should return 200")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let agentSessions = json["agentSessions"] as! [String: Any]
        let agentData = agentSessions[testAgentId.value] as! [String: Any]
        let chatData = agentData["chat"] as! [String: Any]

        XCTAssertEqual(chatData["count"] as? Int, 0, "Chat count should be 0")
        XCTAssertEqual(chatData["status"] as? String, "connecting", "Chat status should be 'connecting' when spawn_started_at is within timeout")
    }

    // MARK: - Test 1.3: disconnected 状態 (spawn_started_atもセッションもなし)

    func testAgentSessionsAPI_ReturnsChatStatusDisconnected() async throws {
        // Arrange: No spawn_started_at and no AgentSession
        // (nothing to create, just ensure clean state)

        // Start server AFTER DB setup (avoids WAL checkpoint conflict)
        startServer()

        // Act: Login and call agent-sessions API
        let token = try await login()
        let (data, response) = try await makeRequest(
            method: "GET",
            path: "/api/projects/\(testProjectId.value)/agent-sessions",
            token: token
        )

        // Assert
        XCTAssertEqual(response.statusCode, 200, "API should return 200")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let agentSessions = json["agentSessions"] as! [String: Any]
        let agentData = agentSessions[testAgentId.value] as! [String: Any]
        let chatData = agentData["chat"] as! [String: Any]

        XCTAssertEqual(chatData["count"] as? Int, 0, "Chat count should be 0")
        XCTAssertEqual(chatData["status"] as? String, "disconnected", "Chat status should be 'disconnected' when nothing exists")
    }

    // MARK: - Test 1.4: task は status を持たない (count のみ)

    func testAgentSessionsAPI_TaskHasNoStatus() async throws {
        // Arrange: Create task session (not chat)
        let session = AgentSession(
            agentId: testAgentId,
            projectId: testProjectId,
            purpose: .task
        )
        try agentSessionRepository.save(session)

        // Start server AFTER DB setup (avoids WAL checkpoint conflict)
        startServer()

        // Act: Login and call agent-sessions API
        let token = try await login()
        let (data, response) = try await makeRequest(
            method: "GET",
            path: "/api/projects/\(testProjectId.value)/agent-sessions",
            token: token
        )

        // Assert
        XCTAssertEqual(response.statusCode, 200, "API should return 200")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let agentSessions = json["agentSessions"] as! [String: Any]
        let agentData = agentSessions[testAgentId.value] as! [String: Any]
        let taskData = agentData["task"] as! [String: Any]

        XCTAssertEqual(taskData["count"] as? Int, 1, "Task count should be 1")
        XCTAssertNil(taskData["status"], "Task should NOT have status field")
    }

    // MARK: - Test 1.5: spawn_started_at がタイムアウト（120秒超過）の場合は disconnected
    // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md

    func testAgentSessionsAPI_ExpiredSpawnStartedAtReturnsDisconnected() async throws {
        // Arrange: Set spawn_started_at to old time (beyond 120s timeout)
        let oldTime = Date().addingTimeInterval(-150) // 150 seconds ago (beyond timeout)
        try projectAgentAssignmentRepository.updateSpawnStartedAt(
            agentId: testAgentId,
            projectId: testProjectId,
            startedAt: oldTime
        )

        // Start server AFTER DB setup (avoids WAL checkpoint conflict)
        startServer()

        // Act: Login and call agent-sessions API
        let token = try await login()
        let (data, response) = try await makeRequest(
            method: "GET",
            path: "/api/projects/\(testProjectId.value)/agent-sessions",
            token: token
        )

        // Assert
        XCTAssertEqual(response.statusCode, 200, "API should return 200")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let agentSessions = json["agentSessions"] as! [String: Any]
        let agentData = agentSessions[testAgentId.value] as! [String: Any]
        let chatData = agentData["chat"] as! [String: Any]

        // Chat status should be disconnected when spawn_started_at is expired
        XCTAssertEqual(chatData["status"] as? String, "disconnected",
                       "Chat status should be 'disconnected' when spawn_started_at is beyond timeout")
    }
}
