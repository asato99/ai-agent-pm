// Tests/UseCaseTests/WorkDetectionServiceTests.swift
// WorkDetectionService のテスト
// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md - 共通ロジック

import XCTest
@testable import UseCase
@testable import Domain

// MARK: - Mock ChatRepository

final class MockChatRepositoryForWorkDetection: ChatRepositoryProtocol {
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
        // Mock: 全メッセージを返す（unread のシミュレーション用に setUnreadMessages で設定）
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
        // Not needed for these tests
        ChatMessagePage(messages: [], hasMore: false, totalCount: 0)
    }

    func countMessages(projectId: ProjectID, agentId: AgentID) throws -> Int {
        messages[key(projectId, agentId)]?.count ?? 0
    }

    // Helper for tests
    func setUnreadMessages(_ projectId: ProjectID, _ agentId: AgentID, _ msgs: [ChatMessage]) {
        messages[key(projectId, agentId)] = msgs
    }

    func clearMessages(_ projectId: ProjectID, _ agentId: AgentID) {
        messages[key(projectId, agentId)] = []
    }
}

// MARK: - Mock SessionRepository

final class MockSessionRepositoryForWorkDetection: AgentSessionRepositoryProtocol {
    var sessions: [AgentSessionID: AgentSession] = [:]

    func findById(_ id: AgentSessionID) throws -> AgentSession? {
        sessions[id]
    }

    func findByToken(_ token: String) throws -> AgentSession? {
        sessions.values.first { $0.token == token }
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
            expiresAt: now.addingTimeInterval(3600),  // 1 hour from now
            createdAt: now,
            lastActivityAt: now
        )
        sessions[session.id] = session
    }

    func addExpiredSession(_ agentId: AgentID, _ projectId: ProjectID, _ purpose: AgentPurpose) {
        let past = Date().addingTimeInterval(-7200)  // 2 hours ago
        let session = AgentSession(
            id: AgentSessionID(value: UUID().uuidString),
            token: UUID().uuidString,
            agentId: agentId,
            projectId: projectId,
            purpose: purpose,
            state: .active,
            expiresAt: Date().addingTimeInterval(-3600),  // 1 hour ago (expired)
            createdAt: past,
            lastActivityAt: Date().addingTimeInterval(-3600)
        )
        sessions[session.id] = session
    }
}

// MARK: - Mock ChatDelegationRepository
// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md

final class MockChatDelegationRepositoryForWorkDetection: ChatDelegationRepositoryProtocol {
    var delegations: [ChatDelegationID: ChatDelegation] = [:]

    func save(_ delegation: ChatDelegation) throws {
        delegations[delegation.id] = delegation
    }

    func findById(_ id: ChatDelegationID) throws -> ChatDelegation? {
        delegations[id]
    }

    func findPendingByAgentId(_ agentId: AgentID, projectId: ProjectID) throws -> [ChatDelegation] {
        Array(delegations.values.filter {
            $0.agentId == agentId &&
            $0.projectId == projectId &&
            $0.status == .pending
        })
    }

    func hasPending(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        delegations.values.contains {
            $0.agentId == agentId &&
            $0.projectId == projectId &&
            $0.status == .pending
        }
    }

    func updateStatus(_ id: ChatDelegationID, status: ChatDelegationStatus) throws {
        if var d = delegations[id] {
            d.status = status
            delegations[id] = d
        }
    }

    func markCompleted(_ id: ChatDelegationID, result: String?) throws {
        if var d = delegations[id] {
            d.status = .completed
            d.processedAt = Date()
            d.result = result
            delegations[id] = d
        }
    }

    func markFailed(_ id: ChatDelegationID, result: String?) throws {
        if var d = delegations[id] {
            d.status = .failed
            d.processedAt = Date()
            d.result = result
            delegations[id] = d
        }
    }

    // Helper for tests
    func addPendingDelegation(_ agentId: AgentID, _ projectId: ProjectID) {
        let delegation = ChatDelegation(
            id: ChatDelegationID.generate(),
            agentId: agentId,
            projectId: projectId,
            targetAgentId: AgentID(value: "target-agent"),
            purpose: "Test purpose",
            context: nil,
            status: .pending,
            createdAt: Date()
        )
        delegations[delegation.id] = delegation
    }

    func addProcessingDelegation(_ agentId: AgentID, _ projectId: ProjectID) {
        let delegation = ChatDelegation(
            id: ChatDelegationID.generate(),
            agentId: agentId,
            projectId: projectId,
            targetAgentId: AgentID(value: "target-agent"),
            purpose: "Test purpose",
            context: nil,
            status: .processing,
            createdAt: Date()
        )
        delegations[delegation.id] = delegation
    }

    func clearDelegations() {
        delegations.removeAll()
    }

    func findProcessingDelegation(
        agentId: AgentID,
        targetAgentId: AgentID,
        projectId: ProjectID
    ) throws -> ChatDelegation? {
        delegations.values.first {
            $0.agentId == agentId &&
            $0.targetAgentId == targetAgentId &&
            $0.projectId == projectId &&
            $0.status == .processing
        }
    }
}

// MARK: - Mock TaskRepository

final class MockTaskRepositoryForWorkDetection: TaskRepositoryProtocol {
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
    func addInProgressTask(_ agentId: AgentID, _ projectId: ProjectID) {
        let task = Task(
            id: TaskID(value: UUID().uuidString),
            projectId: projectId,
            title: "Test Task",
            description: "Test Description",
            status: .inProgress,
            priority: .medium,
            assigneeId: agentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        tasks[task.id] = task
    }

    func clearTasks() {
        tasks.removeAll()
    }
}

// MARK: - WorkDetectionServiceTests

final class WorkDetectionServiceTests: XCTestCase {
    var chatRepo: MockChatRepositoryForWorkDetection!
    var sessionRepo: MockSessionRepositoryForWorkDetection!
    var taskRepo: MockTaskRepositoryForWorkDetection!
    var workService: WorkDetectionService!

    let testAgentId = AgentID(value: "test-agent")
    let testProjectId = ProjectID(value: "test-project")

    override func setUp() {
        super.setUp()
        chatRepo = MockChatRepositoryForWorkDetection()
        sessionRepo = MockSessionRepositoryForWorkDetection()
        taskRepo = MockTaskRepositoryForWorkDetection()
        workService = WorkDetectionService(
            chatRepository: chatRepo,
            sessionRepository: sessionRepo,
            taskRepository: taskRepo
        )
    }

    override func tearDown() {
        chatRepo = nil
        sessionRepo = nil
        taskRepo = nil
        workService = nil
        super.tearDown()
    }

    // MARK: - hasChatWork Tests

    func testHasChatWork_WithUnreadMessages_ReturnsTrue() throws {
        // Given: 未読チャットメッセージあり、アクティブチャットセッションなし
        let message = ChatMessage(
            id: ChatMessageID(value: UUID().uuidString),
            senderId: AgentID(value: "other-agent"),
            receiverId: testAgentId,
            content: "Hello",
            createdAt: Date()
        )
        chatRepo.setUnreadMessages(testProjectId, testAgentId, [message])

        // When
        let result = try workService.hasChatWork(agentId: testAgentId, projectId: testProjectId)

        // Then
        XCTAssertTrue(result)
    }

    func testHasChatWork_WithActiveSession_ReturnsFalse() throws {
        // Given: 未読チャットメッセージあり、アクティブチャットセッションあり
        let message = ChatMessage(
            id: ChatMessageID(value: UUID().uuidString),
            senderId: AgentID(value: "other-agent"),
            receiverId: testAgentId,
            content: "Hello",
            createdAt: Date()
        )
        chatRepo.setUnreadMessages(testProjectId, testAgentId, [message])
        sessionRepo.addActiveSession(testAgentId, testProjectId, .chat)

        // When
        let result = try workService.hasChatWork(agentId: testAgentId, projectId: testProjectId)

        // Then
        XCTAssertFalse(result)
    }

    func testHasChatWork_WithExpiredSession_ReturnsTrue() throws {
        // Given: 未読チャットメッセージあり、期限切れチャットセッションあり
        let message = ChatMessage(
            id: ChatMessageID(value: UUID().uuidString),
            senderId: AgentID(value: "other-agent"),
            receiverId: testAgentId,
            content: "Hello",
            createdAt: Date()
        )
        chatRepo.setUnreadMessages(testProjectId, testAgentId, [message])
        sessionRepo.addExpiredSession(testAgentId, testProjectId, .chat)

        // When
        let result = try workService.hasChatWork(agentId: testAgentId, projectId: testProjectId)

        // Then
        XCTAssertTrue(result)
    }

    func testHasChatWork_NoUnreadMessages_ReturnsFalse() throws {
        // Given: 未読チャットメッセージなし
        chatRepo.clearMessages(testProjectId, testAgentId)

        // When
        let result = try workService.hasChatWork(agentId: testAgentId, projectId: testProjectId)

        // Then
        XCTAssertFalse(result)
    }

    func testHasChatWork_WithTaskSession_ReturnsTrue() throws {
        // Given: 未読チャットメッセージあり、アクティブタスクセッションあり（チャットセッションではない）
        let message = ChatMessage(
            id: ChatMessageID(value: UUID().uuidString),
            senderId: AgentID(value: "other-agent"),
            receiverId: testAgentId,
            content: "Hello",
            createdAt: Date()
        )
        chatRepo.setUnreadMessages(testProjectId, testAgentId, [message])
        sessionRepo.addActiveSession(testAgentId, testProjectId, .task)  // タスクセッション

        // When
        let result = try workService.hasChatWork(agentId: testAgentId, projectId: testProjectId)

        // Then: タスクセッションはチャットワークに影響しない
        XCTAssertTrue(result)
    }

    // MARK: - hasTaskWork Tests

    func testHasTaskWork_WithInProgressTask_ReturnsTrue() throws {
        // Given: in_progress タスクあり、アクティブタスクセッションなし
        taskRepo.addInProgressTask(testAgentId, testProjectId)

        // When
        let result = try workService.hasTaskWork(agentId: testAgentId, projectId: testProjectId)

        // Then
        XCTAssertTrue(result)
    }

    func testHasTaskWork_WithActiveSession_ReturnsFalse() throws {
        // Given: in_progress タスクあり、アクティブタスクセッションあり
        taskRepo.addInProgressTask(testAgentId, testProjectId)
        sessionRepo.addActiveSession(testAgentId, testProjectId, .task)

        // When
        let result = try workService.hasTaskWork(agentId: testAgentId, projectId: testProjectId)

        // Then
        XCTAssertFalse(result)
    }

    func testHasTaskWork_WithExpiredSession_ReturnsTrue() throws {
        // Given: in_progress タスクあり、期限切れタスクセッションあり
        taskRepo.addInProgressTask(testAgentId, testProjectId)
        sessionRepo.addExpiredSession(testAgentId, testProjectId, .task)

        // When
        let result = try workService.hasTaskWork(agentId: testAgentId, projectId: testProjectId)

        // Then
        XCTAssertTrue(result)
    }

    func testHasTaskWork_NoInProgressTask_ReturnsFalse() throws {
        // Given: in_progress タスクなし
        taskRepo.clearTasks()

        // When
        let result = try workService.hasTaskWork(agentId: testAgentId, projectId: testProjectId)

        // Then
        XCTAssertFalse(result)
    }

    func testHasTaskWork_WithChatSession_ReturnsTrue() throws {
        // Given: in_progress タスクあり、アクティブチャットセッションあり（タスクセッションではない）
        taskRepo.addInProgressTask(testAgentId, testProjectId)
        sessionRepo.addActiveSession(testAgentId, testProjectId, .chat)  // チャットセッション

        // When
        let result = try workService.hasTaskWork(agentId: testAgentId, projectId: testProjectId)

        // Then: チャットセッションはタスクワークに影響しない
        XCTAssertTrue(result)
    }

    func testHasTaskWork_TaskAssignedToOtherAgent_ReturnsFalse() throws {
        // Given: in_progress タスクはあるが、別のエージェントに割り当て
        let otherAgentId = AgentID(value: "other-agent")
        taskRepo.addInProgressTask(otherAgentId, testProjectId)

        // When
        let result = try workService.hasTaskWork(agentId: testAgentId, projectId: testProjectId)

        // Then
        XCTAssertFalse(result)
    }
}

// MARK: - WorkDetectionService Delegation Tests
// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md

final class WorkDetectionServiceDelegationTests: XCTestCase {
    var chatRepo: MockChatRepositoryForWorkDetection!
    var sessionRepo: MockSessionRepositoryForWorkDetection!
    var taskRepo: MockTaskRepositoryForWorkDetection!
    var delegationRepo: MockChatDelegationRepositoryForWorkDetection!
    var workService: WorkDetectionService!

    let testAgentId = AgentID(value: "test-agent")
    let testProjectId = ProjectID(value: "test-project")

    override func setUp() {
        super.setUp()
        chatRepo = MockChatRepositoryForWorkDetection()
        sessionRepo = MockSessionRepositoryForWorkDetection()
        taskRepo = MockTaskRepositoryForWorkDetection()
        delegationRepo = MockChatDelegationRepositoryForWorkDetection()
        workService = WorkDetectionService(
            chatRepository: chatRepo,
            sessionRepository: sessionRepo,
            taskRepository: taskRepo,
            chatDelegationRepository: delegationRepo
        )
    }

    override func tearDown() {
        chatRepo = nil
        sessionRepo = nil
        taskRepo = nil
        delegationRepo = nil
        workService = nil
        super.tearDown()
    }

    // MARK: - hasChatWork with Delegation Tests

    /// テストケース1: pending委譲があればチャット作業ありと判定
    func testHasChatWork_WithPendingDelegation_ReturnsTrue() throws {
        // Given: pending状態の委譲あり、未読メッセージなし、アクティブセッションなし
        delegationRepo.addPendingDelegation(testAgentId, testProjectId)
        chatRepo.clearMessages(testProjectId, testAgentId)

        // When
        let result = try workService.hasChatWork(agentId: testAgentId, projectId: testProjectId)

        // Then
        XCTAssertTrue(result)
    }

    /// テストケース2: アクティブなチャットセッションがあれば作業なし
    func testHasChatWork_WithPendingDelegationAndActiveSession_ReturnsFalse() throws {
        // Given: pending状態の委譲あり、アクティブなチャットセッションあり
        delegationRepo.addPendingDelegation(testAgentId, testProjectId)
        sessionRepo.addActiveSession(testAgentId, testProjectId, .chat)

        // When
        let result = try workService.hasChatWork(agentId: testAgentId, projectId: testProjectId)

        // Then: 既にチャットセッションがあるため、新しいセッションは不要
        XCTAssertFalse(result)
    }

    /// テストケース3: processing状態の委譲は作業なしと判定
    func testHasChatWork_WithProcessingDelegation_ReturnsFalse() throws {
        // Given: processing状態の委譲あり（既に処理中）、未読メッセージなし
        delegationRepo.addProcessingDelegation(testAgentId, testProjectId)
        chatRepo.clearMessages(testProjectId, testAgentId)

        // When
        let result = try workService.hasChatWork(agentId: testAgentId, projectId: testProjectId)

        // Then: processing状態はトリガーしない
        XCTAssertFalse(result)
    }

    /// テストケース4: 未読メッセージと委譲の両方がある場合
    func testHasChatWork_WithBothUnreadAndDelegation_ReturnsTrue() throws {
        // Given: 未読メッセージあり、pending委譲あり、アクティブセッションなし
        let message = ChatMessage(
            id: ChatMessageID(value: UUID().uuidString),
            senderId: AgentID(value: "other-agent"),
            receiverId: testAgentId,
            content: "Hello",
            createdAt: Date()
        )
        chatRepo.setUnreadMessages(testProjectId, testAgentId, [message])
        delegationRepo.addPendingDelegation(testAgentId, testProjectId)

        // When
        let result = try workService.hasChatWork(agentId: testAgentId, projectId: testProjectId)

        // Then
        XCTAssertTrue(result)
    }

    /// テストケース5: タスクセッションがあってもチャット作業は検出される
    func testHasChatWork_WithPendingDelegationAndTaskSession_ReturnsTrue() throws {
        // Given: pending委譲あり、アクティブなタスクセッションあり（チャットセッションではない）
        delegationRepo.addPendingDelegation(testAgentId, testProjectId)
        sessionRepo.addActiveSession(testAgentId, testProjectId, .task)

        // When
        let result = try workService.hasChatWork(agentId: testAgentId, projectId: testProjectId)

        // Then: タスクセッションはチャット作業に影響しない
        XCTAssertTrue(result)
    }

    /// テストケース6: 別プロジェクトの委譲は検出されない
    func testHasChatWork_WithDelegationInDifferentProject_ReturnsFalse() throws {
        // Given: 別プロジェクトにpending委譲あり
        let otherProjectId = ProjectID(value: "other-project")
        delegationRepo.addPendingDelegation(testAgentId, otherProjectId)
        chatRepo.clearMessages(testProjectId, testAgentId)

        // When
        let result = try workService.hasChatWork(agentId: testAgentId, projectId: testProjectId)

        // Then
        XCTAssertFalse(result)
    }
}
