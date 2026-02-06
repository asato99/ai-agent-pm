// Tests/UseCaseTests/AuthenticateUseCaseTests.swift
// Session Spawn Architecture: AuthenticateUseCaseV3 のテスト
// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md

import XCTest
@testable import UseCase
@testable import Domain

// MARK: - Mock Repositories

final class MockAgentSessionRepositoryForAuth: AgentSessionRepositoryProtocol {
    var sessions: [AgentSessionID: AgentSession] = [:]

    func findById(_ id: AgentSessionID) throws -> AgentSession? {
        sessions[id]
    }

    func findByToken(_ token: String) throws -> AgentSession? {
        sessions.values.first { $0.token == token && !$0.isExpired }
    }

    func findByAgentId(_ agentId: AgentID) throws -> [AgentSession] {
        Array(sessions.values.filter { $0.agentId == agentId })
    }

    func findByAgentIdAndProjectId(_ agentId: AgentID, projectId: ProjectID) throws -> [AgentSession] {
        Array(sessions.values.filter { $0.agentId == agentId && $0.projectId == projectId })
    }

    func findByProjectId(_ projectId: ProjectID) throws -> [AgentSession] {
        Array(sessions.values.filter { $0.projectId == projectId })
    }

    func save(_ session: AgentSession) throws {
        sessions[session.id] = session
    }

    func delete(_ id: AgentSessionID) throws {
        sessions.removeValue(forKey: id)
    }

    func deleteByToken(_ token: String) throws {
        let toDelete = sessions.values.filter { $0.token == token }.map { $0.id }
        for id in toDelete {
            sessions.removeValue(forKey: id)
        }
    }

    func deleteByAgentId(_ agentId: AgentID) throws {
        let toDelete = sessions.values.filter { $0.agentId == agentId }.map { $0.id }
        for id in toDelete {
            sessions.removeValue(forKey: id)
        }
    }

    func deleteExpired() throws {
        let toDelete = sessions.values.filter { $0.isExpired }.map { $0.id }
        for id in toDelete {
            sessions.removeValue(forKey: id)
        }
    }

    func countActiveSessions(agentId: AgentID) throws -> Int {
        sessions.values.filter { $0.agentId == agentId && !$0.isExpired }.count
    }

    func findActiveSessions(agentId: AgentID) throws -> [AgentSession] {
        Array(sessions.values.filter { $0.agentId == agentId && !$0.isExpired })
    }

    func countActiveSessionsByPurpose(agentId: AgentID) throws -> [AgentPurpose: Int] {
        var counts: [AgentPurpose: Int] = [.chat: 0, .task: 0]
        for session in sessions.values where session.agentId == agentId && !session.isExpired {
            counts[session.purpose, default: 0] += 1
        }
        return counts
    }

    func updateLastActivity(token: String, at date: Date) throws {
        // Not needed for these tests
    }

    func updateState(token: String, state: SessionState) throws {
        // Not needed for these tests
    }

    // Helper for tests
    func addActiveSession(_ agentId: AgentID, _ projectId: ProjectID, _ purpose: AgentPurpose) {
        let now = Date()
        let session = AgentSession(
            id: AgentSessionID(value: UUID().uuidString),
            token: UUID().uuidString,
            agentId: agentId,
            projectId: projectId,
            purpose: purpose,
            state: .active,
            expiresAt: now.addingTimeInterval(3600),
            createdAt: now,
            lastActivityAt: now
        )
        sessions[session.id] = session
    }
}

final class MockAgentCredentialRepositoryForAuth: AgentCredentialRepositoryProtocol {
    var credentials: [AgentID: AgentCredential] = [:]

    func findById(_ id: AgentCredentialID) throws -> AgentCredential? {
        credentials.values.first { $0.id == id }
    }

    func findByAgentId(_ agentId: AgentID) throws -> AgentCredential? {
        credentials[agentId]
    }

    func save(_ credential: AgentCredential) throws {
        credentials[credential.agentId] = credential
    }

    func delete(_ id: AgentCredentialID) throws {
        credentials = credentials.filter { $0.value.id != id }
    }
}

final class MockAgentRepositoryForAuth: AgentRepositoryProtocol {
    var agents: [AgentID: Agent] = [:]

    func findById(_ id: AgentID) throws -> Agent? {
        agents[id]
    }

    func findAll() throws -> [Agent] {
        Array(agents.values)
    }

    func findByType(_ type: AgentType) throws -> [Agent] {
        agents.values.filter { $0.type == type }
    }

    func findByParent(_ parentAgentId: AgentID?) throws -> [Agent] {
        agents.values.filter { $0.parentAgentId == parentAgentId }
    }

    func findAllDescendants(_ parentAgentId: AgentID) throws -> [Agent] {
        []  // Not needed for these tests
    }

    func findRootAgents() throws -> [Agent] {
        agents.values.filter { $0.parentAgentId == nil }
    }

    func findLocked(byAuditId auditId: InternalAuditID?) throws -> [Agent] {
        []  // Not needed for these tests
    }

    func save(_ agent: Agent) throws {
        agents[agent.id] = agent
    }

    func delete(_ id: AgentID) throws {
        agents.removeValue(forKey: id)
    }
}

final class MockTaskRepositoryForAuth: TaskRepositoryProtocol {
    var tasks: [TaskID: Task] = [:]

    func findById(_ id: TaskID) throws -> Task? {
        tasks[id]
    }

    func findAll(projectId: ProjectID) throws -> [Task] {
        tasks.values.filter { $0.projectId == projectId }
    }

    func findByProject(_ projectId: ProjectID, status: TaskStatus?) throws -> [Task] {
        var result = tasks.values.filter { $0.projectId == projectId }
        if let status = status {
            result = result.filter { $0.status == status }
        }
        return Array(result)
    }

    func findByAssignee(_ agentId: AgentID) throws -> [Task] {
        Array(tasks.values.filter { $0.assigneeId == agentId })
    }

    func findPendingByAssignee(_ agentId: AgentID) throws -> [Task] {
        Array(tasks.values.filter { $0.assigneeId == agentId && $0.status == .inProgress })
    }

    func findByStatus(_ status: TaskStatus, projectId: ProjectID) throws -> [Task] {
        Array(tasks.values.filter { $0.status == status && $0.projectId == projectId })
    }

    func findLocked(byAuditId auditId: InternalAuditID?) throws -> [Task] {
        []  // Not needed for these tests
    }

    func save(_ task: Task) throws {
        tasks[task.id] = task
    }

    func delete(_ id: TaskID) throws {
        tasks.removeValue(forKey: id)
    }
}

final class MockChatRepositoryForAuth: ChatRepositoryProtocol {
    var messages: [String: [ChatMessage]] = [:]  // key: "projectId:agentId"

    private func key(_ projectId: ProjectID, _ agentId: AgentID) -> String {
        "\(projectId.value):\(agentId.value)"
    }

    func findMessages(projectId: ProjectID, agentId: AgentID) throws -> [ChatMessage] {
        messages[key(projectId, agentId)] ?? []
    }

    func saveMessage(_ message: ChatMessage, projectId: ProjectID, agentId: AgentID) throws {
        let k = key(projectId, agentId)
        var list = messages[k] ?? []
        list.append(message)
        messages[k] = list
    }

    func getLastMessages(projectId: ProjectID, agentId: AgentID, limit: Int) throws -> [ChatMessage] {
        let all = messages[key(projectId, agentId)] ?? []
        return Array(all.suffix(limit))
    }

    func findUnreadMessages(projectId: ProjectID, agentId: AgentID) throws -> [ChatMessage] {
        messages[key(projectId, agentId)] ?? []
    }

    func saveMessageDualWrite(
        _ message: ChatMessage,
        projectId: ProjectID,
        senderAgentId: AgentID,
        receiverAgentId: AgentID
    ) throws {
        // Not needed for these tests
    }

    func findMessagesWithCursor(
        projectId: ProjectID,
        agentId: AgentID,
        limit: Int,
        after: ChatMessageID?,
        before: ChatMessageID?
    ) throws -> ChatMessagePage {
        ChatMessagePage(messages: [], hasMore: false, totalCount: 0)
    }

    func countMessages(projectId: ProjectID, agentId: AgentID) throws -> Int {
        messages[key(projectId, agentId)]?.count ?? 0
    }

    func findByConversationId(
        projectId: ProjectID,
        agentId: AgentID,
        conversationId: ConversationID
    ) throws -> [ChatMessage] {
        let allMessages = messages[key(projectId, agentId)] ?? []
        return allMessages.filter { $0.conversationId == conversationId }
    }

    // Helper for tests
    func addUnreadMessage(_ projectId: ProjectID, _ agentId: AgentID) {
        let message = ChatMessage(
            id: ChatMessageID(value: UUID().uuidString),
            senderId: AgentID(value: "other-agent"),
            receiverId: agentId,
            content: "Hello",
            createdAt: Date()
        )
        let k = key(projectId, agentId)
        var list = messages[k] ?? []
        list.append(message)
        messages[k] = list
    }
}

// MARK: - AuthenticateUseCaseV3Tests

final class AuthenticateUseCaseTests: XCTestCase {
    var credentialRepo: MockAgentCredentialRepositoryForAuth!
    var sessionRepo: MockAgentSessionRepositoryForAuth!
    var agentRepo: MockAgentRepositoryForAuth!
    var taskRepo: MockTaskRepositoryForAuth!
    var chatRepo: MockChatRepositoryForAuth!
    var workService: WorkDetectionService!

    let testAgentId = AgentID(value: "test-agent")
    let testProjectId = ProjectID(value: "test-project")
    let testPasskey = "test-passkey-12345"

    override func setUp() {
        super.setUp()
        credentialRepo = MockAgentCredentialRepositoryForAuth()
        sessionRepo = MockAgentSessionRepositoryForAuth()
        agentRepo = MockAgentRepositoryForAuth()
        taskRepo = MockTaskRepositoryForAuth()
        chatRepo = MockChatRepositoryForAuth()
        workService = WorkDetectionService(
            chatRepository: chatRepo,
            sessionRepository: sessionRepo,
            taskRepository: taskRepo
        )

        // Setup test agent
        let agent = Agent(
            id: testAgentId,
            name: "Test Agent",
            role: "Tester",
            type: .ai,
            status: .active
        )
        agentRepo.agents[testAgentId] = agent

        // Setup credentials
        let credential = AgentCredential(agentId: testAgentId, rawPasskey: testPasskey)
        credentialRepo.credentials[testAgentId] = credential
    }

    override func tearDown() {
        credentialRepo = nil
        sessionRepo = nil
        agentRepo = nil
        taskRepo = nil
        chatRepo = nil
        workService = nil
        super.tearDown()
    }

    // MARK: - Helper

    private func createUseCase() -> AuthenticateUseCaseV3 {
        AuthenticateUseCaseV3(
            credentialRepository: credentialRepo,
            sessionRepository: sessionRepo,
            agentRepository: agentRepo,
            workDetectionService: workService
        )
    }

    private func createInProgressTask() -> Task {
        Task(
            id: TaskID(value: "test-task"),
            projectId: testProjectId,
            title: "Test Task",
            status: .inProgress,
            assigneeId: testAgentId,
            createdByAgentId: testAgentId
        )
    }

    // MARK: - Test Cases

    /// テスト1: in_progressタスクがあればタスクセッション作成
    func testAuthenticate_WithInProgressTask_CreatesTaskSession() throws {
        // Given
        let task = createInProgressTask()
        taskRepo.tasks[task.id] = task

        // When
        let useCase = createUseCase()
        let result = try useCase.execute(
            agentId: testAgentId.value,
            passkey: testPasskey,
            projectId: testProjectId.value
        )

        // Then
        XCTAssertTrue(result.success, "Authentication should succeed")

        // Verify task session was created
        let sessions = try sessionRepo.findByAgentIdAndProjectId(testAgentId, projectId: testProjectId)
        let taskSession = sessions.first { $0.purpose == .task && !$0.isExpired }
        XCTAssertNotNil(taskSession, "Task session should be created")
    }

    /// テスト2: 未読メッセージがあればチャットセッション作成
    func testAuthenticate_WithUnreadMessages_CreatesChatSession() throws {
        // Given
        chatRepo.addUnreadMessage(testProjectId, testAgentId)

        // When
        let useCase = createUseCase()
        let result = try useCase.execute(
            agentId: testAgentId.value,
            passkey: testPasskey,
            projectId: testProjectId.value
        )

        // Then
        XCTAssertTrue(result.success, "Authentication should succeed")

        // Verify chat session was created
        let sessions = try sessionRepo.findByAgentIdAndProjectId(testAgentId, projectId: testProjectId)
        let chatSession = sessions.first { $0.purpose == .chat && !$0.isExpired }
        XCTAssertNotNil(chatSession, "Chat session should be created")
    }

    /// テスト3: 両方ある場合はタスク優先
    func testAuthenticate_WithBothTaskAndChat_PrefersTask() throws {
        // Given
        let task = createInProgressTask()
        taskRepo.tasks[task.id] = task
        chatRepo.addUnreadMessage(testProjectId, testAgentId)

        // When
        let useCase = createUseCase()
        let result = try useCase.execute(
            agentId: testAgentId.value,
            passkey: testPasskey,
            projectId: testProjectId.value
        )

        // Then
        XCTAssertTrue(result.success, "Authentication should succeed")

        // Verify task session was created (not chat)
        let sessions = try sessionRepo.findByAgentIdAndProjectId(testAgentId, projectId: testProjectId)
        let taskSession = sessions.first { $0.purpose == .task && !$0.isExpired }
        let chatSession = sessions.first { $0.purpose == .chat && !$0.isExpired }

        XCTAssertNotNil(taskSession, "Task session should be created")
        XCTAssertNil(chatSession, "Chat session should NOT be created (task takes priority)")
    }

    /// テスト4: タスクセッション既存時はチャット作成
    func testAuthenticate_WithExistingTaskSession_CreatesChatSession() throws {
        // Given
        let task = createInProgressTask()
        taskRepo.tasks[task.id] = task
        sessionRepo.addActiveSession(testAgentId, testProjectId, .task)
        chatRepo.addUnreadMessage(testProjectId, testAgentId)

        // When
        let useCase = createUseCase()
        let result = try useCase.execute(
            agentId: testAgentId.value,
            passkey: testPasskey,
            projectId: testProjectId.value
        )

        // Then
        XCTAssertTrue(result.success, "Authentication should succeed")

        // Verify chat session was created
        let sessions = try sessionRepo.findByAgentIdAndProjectId(testAgentId, projectId: testProjectId)
        let chatSessions = sessions.filter { $0.purpose == .chat && !$0.isExpired }

        XCTAssertEqual(chatSessions.count, 1, "Chat session should be created")
    }

    /// テスト5: 両セッション既存時は失敗
    func testAuthenticate_WithBothSessionsExisting_Fails() throws {
        // Given
        sessionRepo.addActiveSession(testAgentId, testProjectId, .task)
        sessionRepo.addActiveSession(testAgentId, testProjectId, .chat)

        // When
        let useCase = createUseCase()
        let result = try useCase.execute(
            agentId: testAgentId.value,
            passkey: testPasskey,
            projectId: testProjectId.value
        )

        // Then
        XCTAssertFalse(result.success, "Authentication should fail when both sessions exist")
    }

    /// テスト6: 何も該当しない場合は失敗
    func testAuthenticate_WithNoWork_Fails() throws {
        // Given
        // No in-progress task, no unread messages

        // When
        let useCase = createUseCase()
        let result = try useCase.execute(
            agentId: testAgentId.value,
            passkey: testPasskey,
            projectId: testProjectId.value
        )

        // Then
        XCTAssertFalse(result.success, "Authentication should fail with no valid work")
    }

    /// テスト7: 無効なパスキーで失敗
    func testAuthenticate_WithInvalidPasskey_Fails() throws {
        // Given
        let task = createInProgressTask()
        taskRepo.tasks[task.id] = task

        // When
        let useCase = createUseCase()
        let result = try useCase.execute(
            agentId: testAgentId.value,
            passkey: "wrong-passkey",
            projectId: testProjectId.value
        )

        // Then
        XCTAssertFalse(result.success, "Authentication should fail with invalid passkey")
    }

    /// テスト8: 存在しないエージェントで失敗
    func testAuthenticate_WithNonExistentAgent_Fails() throws {
        // When
        let useCase = createUseCase()
        let result = try useCase.execute(
            agentId: "non-existent-agent",
            passkey: testPasskey,
            projectId: testProjectId.value
        )

        // Then
        XCTAssertFalse(result.success, "Authentication should fail with non-existent agent")
    }
}
