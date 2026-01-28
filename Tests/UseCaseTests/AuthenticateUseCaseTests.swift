// Tests/UseCaseTests/AuthenticateUseCaseTests.swift
// Session Spawn Architecture: authenticate の状態ベース判定テスト
// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md

import XCTest
@testable import UseCase
@testable import Domain

// MARK: - Mock Repositories

final class MockPendingAgentPurposeRepository: PendingAgentPurposeRepositoryProtocol {
    var purposes: [String: PendingAgentPurpose] = [:]  // key: "agentId:projectId:purpose"

    private func key(_ agentId: AgentID, _ projectId: ProjectID, _ purpose: AgentPurpose) -> String {
        "\(agentId.value):\(projectId.value):\(purpose.rawValue)"
    }

    private func keyPrefix(_ agentId: AgentID, _ projectId: ProjectID) -> String {
        "\(agentId.value):\(projectId.value):"
    }

    func find(agentId: AgentID, projectId: ProjectID, purpose: AgentPurpose) throws -> PendingAgentPurpose? {
        purposes[key(agentId, projectId, purpose)]
    }

    func find(agentId: AgentID, projectId: ProjectID) throws -> PendingAgentPurpose? {
        let prefix = keyPrefix(agentId, projectId)
        return purposes.values.first { key(agentId, projectId, $0.purpose).hasPrefix(prefix) }
    }

    func save(_ purpose: PendingAgentPurpose) throws {
        purposes[key(purpose.agentId, purpose.projectId, purpose.purpose)] = purpose
    }

    func delete(agentId: AgentID, projectId: ProjectID, purpose: AgentPurpose) throws {
        purposes.removeValue(forKey: key(agentId, projectId, purpose))
    }

    func delete(agentId: AgentID, projectId: ProjectID) throws {
        let prefix = keyPrefix(agentId, projectId)
        for k in purposes.keys where k.hasPrefix(prefix) {
            purposes.removeValue(forKey: k)
        }
    }

    func deleteExpired(olderThan: Date) throws {
        purposes = purposes.filter { !$0.value.isExpired(now: olderThan, ttlSeconds: 0) }
    }

    func markAsStarted(agentId: AgentID, projectId: ProjectID, purpose: AgentPurpose, startedAt: Date) throws {
        let k = key(agentId, projectId, purpose)
        if var p = purposes[k] {
            p = PendingAgentPurpose(
                agentId: p.agentId,
                projectId: p.projectId,
                purpose: p.purpose,
                createdAt: p.createdAt,
                startedAt: startedAt,
                conversationId: p.conversationId
            )
            purposes[k] = p
        }
    }

    func clearStartedAt(agentId: AgentID, projectId: ProjectID, purpose: AgentPurpose) throws {
        let k = key(agentId, projectId, purpose)
        if var p = purposes[k] {
            p = PendingAgentPurpose(
                agentId: p.agentId,
                projectId: p.projectId,
                purpose: p.purpose,
                createdAt: p.createdAt,
                startedAt: nil,
                conversationId: p.conversationId
            )
            purposes[k] = p
        }
    }
}

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
    func findActiveByPurpose(_ agentId: AgentID, _ projectId: ProjectID, _ purpose: AgentPurpose) -> AgentSession? {
        sessions.values.first {
            $0.agentId == agentId &&
            $0.projectId == projectId &&
            $0.purpose == purpose &&
            !$0.isExpired
        }
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

    // Helper for tests
    func findInProgressTaskForAgent(_ agentId: AgentID, _ projectId: ProjectID) -> Task? {
        tasks.values.first {
            $0.assigneeId == agentId &&
            $0.projectId == projectId &&
            $0.status == .inProgress
        }
    }
}

// MARK: - AuthenticateUseCaseTests

final class AuthenticateUseCaseTests: XCTestCase {
    var credentialRepo: MockAgentCredentialRepositoryForAuth!
    var sessionRepo: MockAgentSessionRepositoryForAuth!
    var agentRepo: MockAgentRepositoryForAuth!
    var pendingRepo: MockPendingAgentPurposeRepository!
    var taskRepo: MockTaskRepositoryForAuth!

    let testAgentId = AgentID(value: "test-agent")
    let testProjectId = ProjectID(value: "test-project")
    let testPasskey = "test-passkey-12345"

    override func setUp() {
        super.setUp()
        credentialRepo = MockAgentCredentialRepositoryForAuth()
        sessionRepo = MockAgentSessionRepositoryForAuth()
        agentRepo = MockAgentRepositoryForAuth()
        pendingRepo = MockPendingAgentPurposeRepository()
        taskRepo = MockTaskRepositoryForAuth()

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

    // MARK: - Helper

    private func createUseCase() -> AuthenticateUseCaseV2 {
        AuthenticateUseCaseV2(
            credentialRepository: credentialRepo,
            sessionRepository: sessionRepo,
            agentRepository: agentRepo,
            pendingPurposeRepository: pendingRepo,
            taskRepository: taskRepo
        )
    }

    private func createTaskSession() -> AgentSession {
        AgentSession(agentId: testAgentId, projectId: testProjectId, purpose: .task)
    }

    private func createChatSession() -> AgentSession {
        AgentSession(agentId: testAgentId, projectId: testProjectId, purpose: .chat)
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

    private func createChatPending() -> PendingAgentPurpose {
        PendingAgentPurpose(
            agentId: testAgentId,
            projectId: testProjectId,
            purpose: .chat,
            createdAt: Date()
        )
    }

    private func createTaskPending() -> PendingAgentPurpose {
        PendingAgentPurpose(
            agentId: testAgentId,
            projectId: testProjectId,
            purpose: .task,
            createdAt: Date()
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

    /// テスト2: chatPendingがあればチャットセッション作成
    func testAuthenticate_WithChatPending_CreatesChatSession() throws {
        // Given
        let chatPending = createChatPending()
        try pendingRepo.save(chatPending)

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

        let chatPending = createChatPending()
        try pendingRepo.save(chatPending)

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

        let existingTaskSession = createTaskSession()
        sessionRepo.sessions[existingTaskSession.id] = existingTaskSession

        let chatPending = createChatPending()
        try pendingRepo.save(chatPending)

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
        let existingTaskSession = createTaskSession()
        sessionRepo.sessions[existingTaskSession.id] = existingTaskSession

        let existingChatSession = createChatSession()
        sessionRepo.sessions[existingChatSession.id] = existingChatSession

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
    func testAuthenticate_WithNoPurpose_Fails() throws {
        // Given
        // No in-progress task, no chat pending

        // When
        let useCase = createUseCase()
        let result = try useCase.execute(
            agentId: testAgentId.value,
            passkey: testPasskey,
            projectId: testProjectId.value
        )

        // Then
        XCTAssertFalse(result.success, "Authentication should fail with no valid purpose")
    }

    /// テスト7: タスクセッション作成時にtask pending削除
    func testAuthenticate_CreatingTaskSession_DeletesTaskPending() throws {
        // Given
        let task = createInProgressTask()
        taskRepo.tasks[task.id] = task

        let taskPending = createTaskPending()
        try pendingRepo.save(taskPending)

        // When
        let useCase = createUseCase()
        _ = try useCase.execute(
            agentId: testAgentId.value,
            passkey: testPasskey,
            projectId: testProjectId.value
        )

        // Then
        let remainingPending = try pendingRepo.find(agentId: testAgentId, projectId: testProjectId, purpose: .task)
        XCTAssertNil(remainingPending, "Task pending should be deleted after task session creation")
    }

    /// テスト8: チャットセッション作成時にchat pending削除
    func testAuthenticate_CreatingChatSession_DeletesChatPending() throws {
        // Given
        let chatPending = createChatPending()
        try pendingRepo.save(chatPending)

        // When
        let useCase = createUseCase()
        _ = try useCase.execute(
            agentId: testAgentId.value,
            passkey: testPasskey,
            projectId: testProjectId.value
        )

        // Then
        let remainingPending = try pendingRepo.find(agentId: testAgentId, projectId: testProjectId, purpose: .chat)
        XCTAssertNil(remainingPending, "Chat pending should be deleted after chat session creation")
    }
}
