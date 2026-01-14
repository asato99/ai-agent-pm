// Tests/UseCaseTests/UseCaseTests.swift
// PRD仕様に基づくUseCase層テスト
// 参照: docs/prd/TASK_MANAGEMENT.md, AGENT_CONCEPT.md, STATE_HISTORY.md

import XCTest
@testable import UseCase
@testable import Domain

// MARK: - Mock Repositories

final class MockProjectRepository: ProjectRepositoryProtocol {
    var projects: [ProjectID: Project] = [:]

    func findById(_ id: ProjectID) throws -> Project? {
        projects[id]
    }

    func findAll() throws -> [Project] {
        Array(projects.values)
    }

    func save(_ project: Project) throws {
        projects[project.id] = project
    }

    func delete(_ id: ProjectID) throws {
        projects.removeValue(forKey: id)
    }
}

final class MockAgentRepository: AgentRepositoryProtocol {
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

    func findRootAgents() throws -> [Agent] {
        agents.values.filter { $0.parentAgentId == nil }
    }

    func findLocked(byAuditId auditId: InternalAuditID?) throws -> [Agent] {
        if let auditId = auditId {
            return agents.values.filter { $0.isLocked && $0.lockedByAuditId == auditId }
        }
        return agents.values.filter { $0.isLocked }
    }

    func save(_ agent: Agent) throws {
        agents[agent.id] = agent
    }

    func delete(_ id: AgentID) throws {
        agents.removeValue(forKey: id)
    }
}

final class MockTaskRepository: TaskRepositoryProtocol {
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
        tasks.values.filter { $0.assigneeId == agentId }
    }

    func findPendingByAssignee(_ agentId: AgentID) throws -> [Task] {
        tasks.values.filter { $0.assigneeId == agentId && $0.status == .inProgress }
    }

    func findByStatus(_ status: TaskStatus, projectId: ProjectID) throws -> [Task] {
        tasks.values.filter { $0.projectId == projectId && $0.status == status }
    }

    func findLocked(byAuditId auditId: InternalAuditID?) throws -> [Task] {
        if let auditId = auditId {
            return tasks.values.filter { $0.isLocked && $0.lockedByAuditId == auditId }
        }
        return tasks.values.filter { $0.isLocked }
    }

    func save(_ task: Task) throws {
        tasks[task.id] = task
    }

    func delete(_ id: TaskID) throws {
        tasks.removeValue(forKey: id)
    }
}

final class MockSessionRepository: SessionRepositoryProtocol {
    var sessions: [SessionID: Session] = [:]

    func findById(_ id: SessionID) throws -> Session? {
        sessions[id]
    }

    func findActive(agentId: AgentID) throws -> Session? {
        sessions.values.first { $0.agentId == agentId && $0.status == .active }
    }

    func findByProject(_ projectId: ProjectID) throws -> [Session] {
        sessions.values.filter { $0.projectId == projectId }
    }

    func findByAgent(_ agentId: AgentID) throws -> [Session] {
        sessions.values.filter { $0.agentId == agentId }
    }

    func save(_ session: Session) throws {
        sessions[session.id] = session
    }

    func delete(_ id: SessionID) throws {
        sessions.removeValue(forKey: id)
    }

    func findActiveByProject(_ projectId: ProjectID) throws -> [Session] {
        sessions.values.filter { $0.projectId == projectId && $0.status == .active }
    }

    func findActiveByAgentAndProject(agentId: AgentID, projectId: ProjectID) throws -> [Session] {
        sessions.values.filter { $0.agentId == agentId && $0.projectId == projectId && $0.status == .active }
    }
}

final class MockContextRepository: ContextRepositoryProtocol {
    var contexts: [ContextID: Context] = [:]

    func findById(_ id: ContextID) throws -> Context? {
        contexts[id]
    }

    func findByTask(_ taskId: TaskID) throws -> [Context] {
        contexts.values.filter { $0.taskId == taskId }
    }

    func findBySession(_ sessionId: SessionID) throws -> [Context] {
        contexts.values.filter { $0.sessionId == sessionId }
    }

    func findLatest(taskId: TaskID) throws -> Context? {
        contexts.values
            .filter { $0.taskId == taskId }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    func save(_ context: Context) throws {
        contexts[context.id] = context
    }

    func delete(_ id: ContextID) throws {
        contexts.removeValue(forKey: id)
    }
}

final class MockEventRepository: EventRepositoryProtocol {
    var events: [EventID: StateChangeEvent] = [:]

    func findByProject(_ projectId: ProjectID, limit: Int?) throws -> [StateChangeEvent] {
        var result = events.values.filter { $0.projectId == projectId }
        if let limit = limit {
            result = Array(result.prefix(limit))
        }
        return result
    }

    func findByEntity(type: EntityType, id: String) throws -> [StateChangeEvent] {
        events.values.filter { $0.entityType == type && $0.entityId == id }
    }

    func findRecent(projectId: ProjectID, since: Date) throws -> [StateChangeEvent] {
        events.values.filter { $0.projectId == projectId && $0.timestamp >= since }
    }

    func save(_ event: StateChangeEvent) throws {
        events[event.id] = event
    }
}

final class MockWorkflowTemplateRepository: WorkflowTemplateRepositoryProtocol {
    var templates: [WorkflowTemplateID: WorkflowTemplate] = [:]

    func findById(_ id: WorkflowTemplateID) throws -> WorkflowTemplate? {
        templates[id]
    }

    func findByProject(_ projectId: ProjectID, includeArchived: Bool) throws -> [WorkflowTemplate] {
        var result = templates.values.filter { $0.projectId == projectId }
        if !includeArchived {
            result = result.filter { $0.status == .active }
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    func findActiveByProject(_ projectId: ProjectID) throws -> [WorkflowTemplate] {
        try findByProject(projectId, includeArchived: false)
    }

    func findAllActive() throws -> [WorkflowTemplate] {
        templates.values.filter { $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ template: WorkflowTemplate) throws {
        templates[template.id] = template
    }

    func delete(_ id: WorkflowTemplateID) throws {
        templates.removeValue(forKey: id)
    }
}

final class MockTemplateTaskRepository: TemplateTaskRepositoryProtocol {
    var tasks: [TemplateTaskID: TemplateTask] = [:]

    func findById(_ id: TemplateTaskID) throws -> TemplateTask? {
        tasks[id]
    }

    func findByTemplate(_ templateId: WorkflowTemplateID) throws -> [TemplateTask] {
        tasks.values
            .filter { $0.templateId == templateId }
            .sorted { $0.order < $1.order }
    }

    func save(_ task: TemplateTask) throws {
        tasks[task.id] = task
    }

    func delete(_ id: TemplateTaskID) throws {
        tasks.removeValue(forKey: id)
    }

    func deleteByTemplate(_ templateId: WorkflowTemplateID) throws {
        let toDelete = tasks.values.filter { $0.templateId == templateId }.map { $0.id }
        for id in toDelete {
            tasks.removeValue(forKey: id)
        }
    }
}

final class MockInternalAuditRepository: InternalAuditRepositoryProtocol {
    var audits: [InternalAuditID: InternalAudit] = [:]

    func findById(_ id: InternalAuditID) throws -> InternalAudit? {
        audits[id]
    }

    func findAll(includeInactive: Bool) throws -> [InternalAudit] {
        var result = Array(audits.values)
        if !includeInactive {
            result = result.filter { $0.status == .active }
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    func findActive() throws -> [InternalAudit] {
        try findAll(includeInactive: false)
    }

    func save(_ audit: InternalAudit) throws {
        audits[audit.id] = audit
    }

    func delete(_ id: InternalAuditID) throws {
        audits.removeValue(forKey: id)
    }
}

final class MockAuditRuleRepository: AuditRuleRepositoryProtocol {
    var rules: [AuditRuleID: AuditRule] = [:]

    func findById(_ id: AuditRuleID) throws -> AuditRule? {
        rules[id]
    }

    func findByAudit(_ auditId: InternalAuditID) throws -> [AuditRule] {
        rules.values
            .filter { $0.auditId == auditId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func findEnabled(auditId: InternalAuditID) throws -> [AuditRule] {
        rules.values
            .filter { $0.auditId == auditId && $0.isEnabled }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func findByTriggerType(_ triggerType: TriggerType) throws -> [AuditRule] {
        rules.values
            .filter { $0.triggerType == triggerType }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ rule: AuditRule) throws {
        rules[rule.id] = rule
    }

    func delete(_ id: AuditRuleID) throws {
        rules.removeValue(forKey: id)
    }
}

// MARK: - Authentication Mock Repositories (Phase 3-1)

final class MockAgentCredentialRepository: AgentCredentialRepositoryProtocol {
    var credentials: [AgentCredentialID: AgentCredential] = [:]

    func findById(_ id: AgentCredentialID) throws -> AgentCredential? {
        credentials[id]
    }

    func findByAgentId(_ agentId: AgentID) throws -> AgentCredential? {
        credentials.values.first { $0.agentId == agentId }
    }

    func save(_ credential: AgentCredential) throws {
        credentials[credential.id] = credential
    }

    func delete(_ id: AgentCredentialID) throws {
        credentials.removeValue(forKey: id)
    }
}

final class MockAgentSessionRepository: AgentSessionRepositoryProtocol {
    var sessions: [AgentSessionID: AgentSession] = [:]

    func findById(_ id: AgentSessionID) throws -> AgentSession? {
        sessions[id]
    }

    func findByToken(_ token: String) throws -> AgentSession? {
        sessions.values.first { $0.token == token && !$0.isExpired }
    }

    func findByAgentId(_ agentId: AgentID) throws -> [AgentSession] {
        sessions.values.filter { $0.agentId == agentId }
    }

    func findByAgentIdAndProjectId(_ agentId: AgentID, projectId: ProjectID) throws -> [AgentSession] {
        sessions.values.filter { $0.agentId == agentId && $0.projectId == projectId }
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
}

final class MockExecutionLogRepository: ExecutionLogRepositoryProtocol {
    var logs: [ExecutionLogID: ExecutionLog] = [:]

    func findById(_ id: ExecutionLogID) throws -> ExecutionLog? {
        logs[id]
    }

    func findByTaskId(_ taskId: TaskID) throws -> [ExecutionLog] {
        logs.values.filter { $0.taskId == taskId }.sorted { $0.startedAt > $1.startedAt }
    }

    func findByAgentId(_ agentId: AgentID) throws -> [ExecutionLog] {
        logs.values.filter { $0.agentId == agentId }.sorted { $0.startedAt > $1.startedAt }
    }

    func findRunning(agentId: AgentID) throws -> [ExecutionLog] {
        logs.values.filter { $0.agentId == agentId && $0.status == .running }.sorted { $0.startedAt > $1.startedAt }
    }

    func findLatestByAgentAndTask(agentId: AgentID, taskId: TaskID) throws -> ExecutionLog? {
        logs.values
            .filter { $0.agentId == agentId && $0.taskId == taskId }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    func save(_ log: ExecutionLog) throws {
        logs[log.id] = log
    }

    func delete(_ id: ExecutionLogID) throws {
        logs.removeValue(forKey: id)
    }
}

// MARK: - UseCase Tests

final class UseCaseTests: XCTestCase {

    var projectRepo: MockProjectRepository!
    var agentRepo: MockAgentRepository!
    var taskRepo: MockTaskRepository!
    var sessionRepo: MockSessionRepository!
    var contextRepo: MockContextRepository!
    var eventRepo: MockEventRepository!
    var templateRepo: MockWorkflowTemplateRepository!
    var templateTaskRepo: MockTemplateTaskRepository!
    var internalAuditRepo: MockInternalAuditRepository!
    var auditRuleRepo: MockAuditRuleRepository!
    var agentCredentialRepo: MockAgentCredentialRepository!
    var agentSessionRepo: MockAgentSessionRepository!
    var executionLogRepo: MockExecutionLogRepository!

    override func setUp() {
        projectRepo = MockProjectRepository()
        agentRepo = MockAgentRepository()
        taskRepo = MockTaskRepository()
        sessionRepo = MockSessionRepository()
        contextRepo = MockContextRepository()
        eventRepo = MockEventRepository()
        templateRepo = MockWorkflowTemplateRepository()
        templateTaskRepo = MockTemplateTaskRepository()
        internalAuditRepo = MockInternalAuditRepository()
        auditRuleRepo = MockAuditRuleRepository()
        agentCredentialRepo = MockAgentCredentialRepository()
        agentSessionRepo = MockAgentSessionRepository()
        executionLogRepo = MockExecutionLogRepository()
    }

    // MARK: - Error Description Tests

    func testUseCaseErrorDescriptions() {
        let taskError = UseCaseError.taskNotFound(TaskID(value: "tsk_test"))
        XCTAssertTrue(taskError.localizedDescription.contains("tsk_test"))

        let transitionError = UseCaseError.invalidStatusTransition(from: .done, to: .inProgress)
        XCTAssertTrue(transitionError.localizedDescription.contains("done"))
    }

    // MARK: - Project UseCase Tests (PRD: 01_project_list.md)

    func testCreateProjectUseCaseSuccess() throws {
        // PRD: プロジェクトの作成
        let useCase = CreateProjectUseCase(projectRepository: projectRepo)

        let project = try useCase.execute(name: "ECサイト開発", description: "EC site development")

        XCTAssertEqual(project.name, "ECサイト開発")
        XCTAssertEqual(project.description, "EC site development")
        XCTAssertEqual(project.status, .active)
        XCTAssertNotNil(projectRepo.projects[project.id])
    }

    func testCreateProjectUseCaseEmptyNameFails() throws {
        // PRD: 名前は必須
        let useCase = CreateProjectUseCase(projectRepository: projectRepo)

        XCTAssertThrowsError(try useCase.execute(name: "")) { error in
            XCTAssertTrue(error is UseCaseError)
            if case UseCaseError.validationFailed = error {
                // Expected
            } else {
                XCTFail("Expected validationFailed error")
            }
        }
    }

    func testGetProjectsUseCase() throws {
        // PRD: プロジェクト一覧取得
        let project1 = Project(id: ProjectID.generate(), name: "Project 1")
        let project2 = Project(id: ProjectID.generate(), name: "Project 2")
        projectRepo.projects[project1.id] = project1
        projectRepo.projects[project2.id] = project2

        let useCase = GetProjectsUseCase(projectRepository: projectRepo)
        let projects = try useCase.execute()

        XCTAssertEqual(projects.count, 2)
    }

    // MARK: - Agent UseCase Tests (要件: エージェントはプロジェクト非依存)

    func testCreateAgentUseCaseSuccess() throws {
        // 要件: エージェントの作成（プロジェクト非依存）
        let useCase = CreateAgentUseCase(agentRepository: agentRepo)

        let agent = try useCase.execute(
            name: "frontend-dev",
            role: "フロントエンド開発",
            roleType: .developer,
            type: .ai
        )

        XCTAssertEqual(agent.name, "frontend-dev")
        XCTAssertEqual(agent.type, AgentType.ai)
        XCTAssertEqual(agent.roleType, AgentRoleType.developer)
        XCTAssertEqual(agent.status, AgentStatus.active)
    }

    func testCreateAgentUseCaseEmptyNameFails() throws {
        // 要件: 名前は必須
        let useCase = CreateAgentUseCase(agentRepository: agentRepo)

        XCTAssertThrowsError(try useCase.execute(
            name: "",
            role: "Role"
        )) { error in
            if case UseCaseError.validationFailed = error {
                // Expected
            } else {
                XCTFail("Expected validationFailed error")
            }
        }
    }

    func testGetAgentProfileUseCase() throws {
        // PRD: エージェントプロファイル取得（get_my_profile）
        let agent = Agent(
            id: AgentID.generate(),
            name: "test-agent",
            role: "Tester"
        )
        agentRepo.agents[agent.id] = agent

        let useCase = GetAgentProfileUseCase(agentRepository: agentRepo)
        let profile = try useCase.execute(agentId: agent.id)

        XCTAssertEqual(profile.name, "test-agent")
    }

    func testGetAgentProfileUseCaseNotFound() throws {
        // PRD: 存在しないエージェントはエラー
        let useCase = GetAgentProfileUseCase(agentRepository: agentRepo)

        XCTAssertThrowsError(try useCase.execute(agentId: AgentID.generate())) { error in
            if case UseCaseError.agentNotFound = error {
                // Expected
            } else {
                XCTFail("Expected agentNotFound error")
            }
        }
    }

    // MARK: - Task UseCase Tests (PRD: TASK_MANAGEMENT.md)

    func testCreateTaskUseCaseSuccess() throws {
        // PRD: タスクの作成
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let useCase = CreateTaskUseCase(
            taskRepository: taskRepo,
            projectRepository: projectRepo,
            eventRepository: eventRepo
        )

        let task = try useCase.execute(
            projectId: project.id,
            title: "API実装",
            description: "REST APIの実装",
            priority: .high,
            actorAgentId: nil,
            sessionId: nil
        )

        XCTAssertEqual(task.title, "API実装")
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.status, .backlog)
        XCTAssertFalse(eventRepo.events.isEmpty, "Event should be recorded")
    }

    func testCreateTaskUseCaseProjectNotFoundFails() throws {
        // PRD: 存在しないプロジェクトにはタスク作成不可
        let useCase = CreateTaskUseCase(
            taskRepository: taskRepo,
            projectRepository: projectRepo,
            eventRepository: eventRepo
        )

        XCTAssertThrowsError(try useCase.execute(
            projectId: ProjectID.generate(),
            title: "Task",
            actorAgentId: nil,
            sessionId: nil
        )) { error in
            if case UseCaseError.projectNotFound = error {
                // Expected
            } else {
                XCTFail("Expected projectNotFound error")
            }
        }
    }

    func testGetMyTasksUseCase() throws {
        // PRD: 自分のタスク取得（get_my_tasks）
        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        agentRepo.agents[agent.id] = agent

        let task1 = Task(id: TaskID.generate(), projectId: ProjectID.generate(), title: "Task1", assigneeId: agent.id)
        let task2 = Task(id: TaskID.generate(), projectId: ProjectID.generate(), title: "Task2", assigneeId: agent.id)
        let task3 = Task(id: TaskID.generate(), projectId: ProjectID.generate(), title: "Task3") // Unassigned
        taskRepo.tasks[task1.id] = task1
        taskRepo.tasks[task2.id] = task2
        taskRepo.tasks[task3.id] = task3

        let useCase = GetMyTasksUseCase(taskRepository: taskRepo)
        let myTasks = try useCase.execute(agentId: agent.id)

        XCTAssertEqual(myTasks.count, 2)
    }

    // MARK: - Phase 3-2: GetPendingTasksUseCase Tests

    func testGetPendingTasksUseCase() throws {
        // Phase 3-2: 作業中タスクのみ取得（in_progress）
        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        agentRepo.agents[agent.id] = agent

        // in_progressのタスク2つ
        var task1 = Task(id: TaskID.generate(), projectId: ProjectID.generate(), title: "InProgress1", assigneeId: agent.id)
        task1.status = .inProgress
        var task2 = Task(id: TaskID.generate(), projectId: ProjectID.generate(), title: "InProgress2", assigneeId: agent.id)
        task2.status = .inProgress
        // backlogのタスク（含まれない）
        let task3 = Task(id: TaskID.generate(), projectId: ProjectID.generate(), title: "Backlog", assigneeId: agent.id)
        // doneのタスク（含まれない）
        var task4 = Task(id: TaskID.generate(), projectId: ProjectID.generate(), title: "Done", assigneeId: agent.id)
        task4.status = .done

        taskRepo.tasks[task1.id] = task1
        taskRepo.tasks[task2.id] = task2
        taskRepo.tasks[task3.id] = task3
        taskRepo.tasks[task4.id] = task4

        let useCase = GetPendingTasksUseCase(taskRepository: taskRepo)
        let pendingTasks = try useCase.execute(agentId: agent.id)

        XCTAssertEqual(pendingTasks.count, 2)
        XCTAssertTrue(pendingTasks.allSatisfy { $0.status == .inProgress })
    }

    func testGetPendingTasksUseCaseExcludesOtherAgents() throws {
        // Phase 3-2: 他のエージェントのタスクは含まない
        let agent1 = Agent(id: AgentID.generate(), name: "Agent1", role: "Role")
        let agent2 = Agent(id: AgentID.generate(), name: "Agent2", role: "Role")
        agentRepo.agents[agent1.id] = agent1
        agentRepo.agents[agent2.id] = agent2

        var task1 = Task(id: TaskID.generate(), projectId: ProjectID.generate(), title: "Agent1Task", assigneeId: agent1.id)
        task1.status = .inProgress
        var task2 = Task(id: TaskID.generate(), projectId: ProjectID.generate(), title: "Agent2Task", assigneeId: agent2.id)
        task2.status = .inProgress

        taskRepo.tasks[task1.id] = task1
        taskRepo.tasks[task2.id] = task2

        let useCase = GetPendingTasksUseCase(taskRepository: taskRepo)
        let pendingTasks = try useCase.execute(agentId: agent1.id)

        XCTAssertEqual(pendingTasks.count, 1)
        XCTAssertEqual(pendingTasks.first?.assigneeId, agent1.id)
    }

    // MARK: - Task Status Transition Tests (要件: ステータスフロー - inReview削除済み)

    func testUpdateTaskStatusValidTransitions() throws {
        // 要件: 有効なステータス遷移（inReview削除後: backlog → todo → inProgress → done）
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        var task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", status: .backlog)
        taskRepo.tasks[task.id] = task

        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo
        )

        // backlog → todo
        task = try useCase.execute(taskId: task.id, newStatus: .todo, agentId: nil, sessionId: nil, reason: nil)
        XCTAssertEqual(task.status, .todo)

        // todo → inProgress
        task = try useCase.execute(taskId: task.id, newStatus: .inProgress, agentId: nil, sessionId: nil, reason: nil)
        XCTAssertEqual(task.status, .inProgress)

        // inProgress → done
        task = try useCase.execute(taskId: task.id, newStatus: .done, agentId: nil, sessionId: nil, reason: nil)
        XCTAssertEqual(task.status, .done)
        XCTAssertNotNil(task.completedAt, "completedAt should be set when task is done")
    }

    func testUpdateTaskStatusInvalidTransitionFails() throws {
        // PRD: 無効なステータス遷移はエラー（done → inProgress は不可）
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", status: .done)
        taskRepo.tasks[task.id] = task

        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo
        )

        XCTAssertThrowsError(try useCase.execute(
            taskId: task.id,
            newStatus: .inProgress,
            agentId: nil,
            sessionId: nil,
            reason: nil
        )) { error in
            if case UseCaseError.invalidStatusTransition = error {
                // Expected
            } else {
                XCTFail("Expected invalidStatusTransition error")
            }
        }
    }

    func testUpdateTaskStatusBlockedTransition() throws {
        // PRD: inProgress → blocked への遷移
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        var task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo
        )

        task = try useCase.execute(
            taskId: task.id,
            newStatus: .blocked,
            agentId: nil,
            sessionId: nil,
            reason: "Waiting for API design"
        )
        XCTAssertEqual(task.status, .blocked)
    }

    func testStatusTransitionCanTransitionFunction() throws {
        // 要件: ステータス遷移ルールの検証（inReview削除済み）
        // 有効な遷移
        XCTAssertTrue(UpdateTaskStatusUseCase.canTransition(from: .backlog, to: .todo))
        XCTAssertTrue(UpdateTaskStatusUseCase.canTransition(from: .todo, to: .inProgress))
        XCTAssertTrue(UpdateTaskStatusUseCase.canTransition(from: .inProgress, to: .done))
        XCTAssertTrue(UpdateTaskStatusUseCase.canTransition(from: .inProgress, to: .blocked))
        XCTAssertTrue(UpdateTaskStatusUseCase.canTransition(from: .blocked, to: .inProgress))
        XCTAssertTrue(UpdateTaskStatusUseCase.canTransition(from: .backlog, to: .cancelled))

        // 無効な遷移
        XCTAssertFalse(UpdateTaskStatusUseCase.canTransition(from: .done, to: .inProgress))
        XCTAssertFalse(UpdateTaskStatusUseCase.canTransition(from: .cancelled, to: .todo))
        XCTAssertFalse(UpdateTaskStatusUseCase.canTransition(from: .backlog, to: .done))
        XCTAssertFalse(UpdateTaskStatusUseCase.canTransition(from: .todo, to: .todo)) // Same status
    }

    // MARK: - Task Assignment Tests (PRD: TASK_MANAGEMENT.md)

    func testAssignTaskUseCaseSuccess() throws {
        // PRD: タスクの割り当て
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task")
        taskRepo.tasks[task.id] = task

        let useCase = AssignTaskUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo
        )

        let updatedTask = try useCase.execute(
            taskId: task.id,
            assigneeId: agent.id,
            actorAgentId: nil,
            sessionId: nil
        )

        XCTAssertEqual(updatedTask.assigneeId, agent.id)
        XCTAssertFalse(eventRepo.events.isEmpty, "Assignment event should be recorded")
    }

    func testAssignTaskUseCaseUnassign() throws {
        // PRD: タスクの割り当て解除
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", assigneeId: agent.id)
        taskRepo.tasks[task.id] = task

        let useCase = AssignTaskUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo
        )

        let updatedTask = try useCase.execute(
            taskId: task.id,
            assigneeId: nil,
            actorAgentId: nil,
            sessionId: nil
        )

        XCTAssertNil(updatedTask.assigneeId)
    }

    func testAssignTaskUseCaseAgentNotFoundFails() throws {
        // PRD: 存在しないエージェントへの割り当てはエラー
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task")
        taskRepo.tasks[task.id] = task

        let useCase = AssignTaskUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo
        )

        XCTAssertThrowsError(try useCase.execute(
            taskId: task.id,
            assigneeId: AgentID.generate(),
            actorAgentId: nil,
            sessionId: nil
        )) { error in
            if case UseCaseError.agentNotFound = error {
                // Expected
            } else {
                XCTFail("Expected agentNotFound error")
            }
        }
    }

    // MARK: - Session UseCase Tests (PRD: AGENT_CONCEPT.md - Session)

    func testStartSessionUseCaseSuccess() throws {
        // PRD: セッション開始
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        agentRepo.agents[agent.id] = agent

        let useCase = StartSessionUseCase(
            sessionRepository: sessionRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo
        )

        let session = try useCase.execute(projectId: project.id, agentId: agent.id)

        XCTAssertEqual(session.status, .active)
        XCTAssertEqual(session.agentId, agent.id)
        XCTAssertNotNil(session.startedAt)
        XCTAssertNil(session.endedAt)
    }

    func testStartSessionUseCaseAlreadyActiveSessionFails() throws {
        // PRD: 既にアクティブなセッションがある場合はエラー
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        agentRepo.agents[agent.id] = agent

        let existingSession = Session(id: SessionID.generate(), projectId: project.id, agentId: agent.id, status: .active)
        sessionRepo.sessions[existingSession.id] = existingSession

        let useCase = StartSessionUseCase(
            sessionRepository: sessionRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo
        )

        XCTAssertThrowsError(try useCase.execute(projectId: project.id, agentId: agent.id)) { error in
            if case UseCaseError.sessionAlreadyActive = error {
                // Expected
            } else {
                XCTFail("Expected sessionAlreadyActive error")
            }
        }
    }

    func testEndSessionUseCaseSuccess() throws {
        // PRD: セッション終了
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        agentRepo.agents[agent.id] = agent

        let session = Session(id: SessionID.generate(), projectId: project.id, agentId: agent.id, status: .active)
        sessionRepo.sessions[session.id] = session

        let useCase = EndSessionUseCase(
            sessionRepository: sessionRepo,
            eventRepository: eventRepo
        )

        let endedSession = try useCase.execute(sessionId: session.id, status: .completed)

        XCTAssertEqual(endedSession.status, .completed)
        XCTAssertNotNil(endedSession.endedAt)
    }

    func testEndSessionUseCaseNotActiveFails() throws {
        // PRD: アクティブでないセッションは終了できない
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let session = Session(id: SessionID.generate(), projectId: project.id, agentId: AgentID.generate(), status: .completed)
        sessionRepo.sessions[session.id] = session

        let useCase = EndSessionUseCase(
            sessionRepository: sessionRepo,
            eventRepository: eventRepo
        )

        XCTAssertThrowsError(try useCase.execute(sessionId: session.id)) { error in
            if case UseCaseError.sessionNotActive = error {
                // Expected
            } else {
                XCTFail("Expected sessionNotActive error")
            }
        }
    }

    func testGetActiveSessionUseCase() throws {
        // PRD: アクティブセッション取得
        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        agentRepo.agents[agent.id] = agent

        let session = Session(id: SessionID.generate(), projectId: ProjectID.generate(), agentId: agent.id, status: .active)
        sessionRepo.sessions[session.id] = session

        let useCase = GetActiveSessionUseCase(sessionRepository: sessionRepo)
        let found = try useCase.execute(agentId: agent.id)

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, session.id)
    }

    // MARK: - Context UseCase Tests (PRD: AGENT_CONCEPT.md - コンテキスト)

    func testSaveContextUseCaseSuccess() throws {
        // PRD: コンテキストの保存
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task")
        taskRepo.tasks[task.id] = task

        let session = Session(id: SessionID.generate(), projectId: project.id, agentId: agent.id, status: .active)
        sessionRepo.sessions[session.id] = session

        let useCase = SaveContextUseCase(
            contextRepository: contextRepo,
            taskRepository: taskRepo,
            sessionRepository: sessionRepo,
            eventRepository: eventRepo
        )

        let context = try useCase.execute(
            taskId: task.id,
            sessionId: session.id,
            agentId: agent.id,
            progress: "JWT認証を実装中",
            findings: "Rate limit: 100 req/min",
            blockers: nil,
            nextSteps: "テスト作成"
        )

        XCTAssertEqual(context.progress, "JWT認証を実装中")
        XCTAssertEqual(context.findings, "Rate limit: 100 req/min")
    }

    func testSaveContextUseCaseSessionNotActiveFails() throws {
        // PRD: セッションがアクティブでない場合はコンテキスト保存不可
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task")
        taskRepo.tasks[task.id] = task

        let session = Session(id: SessionID.generate(), projectId: project.id, agentId: AgentID.generate(), status: .completed)
        sessionRepo.sessions[session.id] = session

        let useCase = SaveContextUseCase(
            contextRepository: contextRepo,
            taskRepository: taskRepo,
            sessionRepository: sessionRepo,
            eventRepository: eventRepo
        )

        XCTAssertThrowsError(try useCase.execute(
            taskId: task.id,
            sessionId: session.id,
            agentId: AgentID.generate()
        )) { error in
            if case UseCaseError.sessionNotActive = error {
                // Expected
            } else {
                XCTFail("Expected sessionNotActive error")
            }
        }
    }

    func testGetTaskContextUseCase() throws {
        // PRD: タスクコンテキスト取得
        let taskId = TaskID.generate()

        let ctx1 = Context(
            id: ContextID.generate(),
            taskId: taskId,
            sessionId: SessionID.generate(),
            agentId: AgentID.generate(),
            progress: "Step 1",
            createdAt: Date().addingTimeInterval(-3600)
        )
        let ctx2 = Context(
            id: ContextID.generate(),
            taskId: taskId,
            sessionId: SessionID.generate(),
            agentId: AgentID.generate(),
            progress: "Step 2",
            createdAt: Date()
        )
        contextRepo.contexts[ctx1.id] = ctx1
        contextRepo.contexts[ctx2.id] = ctx2

        let useCase = GetTaskContextUseCase(contextRepository: contextRepo)

        // 最新のコンテキスト
        let latest = try useCase.executeLatest(taskId: taskId)
        XCTAssertEqual(latest?.progress, "Step 2")

        // 全コンテキスト
        let all = try useCase.executeAll(taskId: taskId)
        XCTAssertEqual(all.count, 2)
    }

    // MARK: - Task Detail UseCase Tests

    func testGetTaskDetailUseCase() throws {
        // PRD: タスク詳細取得（コンテキスト、依存タスク含む）
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        // 依存元タスク
        let depTask = Task(id: TaskID.generate(), projectId: project.id, title: "設計")
        taskRepo.tasks[depTask.id] = depTask

        // メインタスク（依存タスクを設定）
        let task = Task(id: TaskID.generate(), projectId: project.id, title: "API実装", dependencies: [depTask.id])
        taskRepo.tasks[task.id] = task

        let context = Context(
            id: ContextID.generate(),
            taskId: task.id,
            sessionId: SessionID.generate(),
            agentId: AgentID.generate(),
            progress: "進行中"
        )
        contextRepo.contexts[context.id] = context

        let useCase = GetTaskDetailUseCase(
            taskRepository: taskRepo,
            contextRepository: contextRepo
        )

        let result = try useCase.execute(taskId: task.id)

        XCTAssertEqual(result.task.title, "API実装")
        XCTAssertEqual(result.contexts.count, 1)
        XCTAssertEqual(result.dependentTasks.count, 1)
        XCTAssertEqual(result.dependentTasks.first?.title, "設計")
    }

    // MARK: - Event Recording Tests (PRD: STATE_HISTORY.md)

    func testEventRecordingOnTaskCreation() throws {
        // PRD: タスク作成時にイベントが記録される
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let useCase = CreateTaskUseCase(
            taskRepository: taskRepo,
            projectRepository: projectRepo,
            eventRepository: eventRepo
        )

        let task = try useCase.execute(
            projectId: project.id,
            title: "New Task",
            actorAgentId: nil,
            sessionId: nil
        )

        let events = try eventRepo.findByEntity(type: .task, id: task.id.value)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.eventType, .created)
    }

    func testEventRecordingOnStatusChange() throws {
        // PRD: ステータス変更時にイベントが記録される
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", status: .backlog)
        taskRepo.tasks[task.id] = task

        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo
        )

        _ = try useCase.execute(
            taskId: task.id,
            newStatus: .todo,
            agentId: nil,
            sessionId: nil,
            reason: "Ready to start"
        )

        let events = try eventRepo.findByEntity(type: .task, id: task.id.value)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.eventType, .statusChanged)
        XCTAssertEqual(events.first?.previousState, "backlog")
        XCTAssertEqual(events.first?.newState, "todo")
    }

    // MARK: - Workflow Template UseCase Tests (参照: WORKFLOW_TEMPLATES.md)

    func testCreateTemplateUseCase() throws {
        // テンプレート作成ユースケース
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        projectRepo.projects[project.id] = project

        let useCase = CreateTemplateUseCase(
            templateRepository: templateRepo,
            templateTaskRepository: templateTaskRepo,
            projectRepository: projectRepo
        )

        let input = CreateTemplateUseCase.Input(
            projectId: project.id,
            name: "Feature Development",
            description: "機能開発のワークフロー",
            variables: ["feature_name", "module"],
            tasks: [
                CreateTemplateUseCase.Input.TaskInput(
                    title: "{{feature_name}} - 要件確認",
                    order: 1,
                    defaultPriority: .high
                ),
                CreateTemplateUseCase.Input.TaskInput(
                    title: "{{feature_name}} - 実装",
                    order: 2,
                    dependsOnOrders: [1]
                )
            ]
        )

        let template = try useCase.execute(input: input)

        XCTAssertEqual(template.name, "Feature Development")
        XCTAssertEqual(template.variables, ["feature_name", "module"])

        let tasks = try templateTaskRepo.findByTemplate(template.id)
        XCTAssertEqual(tasks.count, 2)
    }

    func testCreateTemplateUseCaseValidatesEmptyName() throws {
        // 空の名前でエラー
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        projectRepo.projects[project.id] = project

        let useCase = CreateTemplateUseCase(
            templateRepository: templateRepo,
            templateTaskRepository: templateTaskRepo,
            projectRepository: projectRepo
        )

        let input = CreateTemplateUseCase.Input(projectId: project.id, name: "   ")

        XCTAssertThrowsError(try useCase.execute(input: input)) { error in
            XCTAssertTrue(error is UseCaseError)
        }
    }

    func testCreateTemplateUseCaseValidatesInvalidVariableName() throws {
        // 無効な変数名でエラー
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        projectRepo.projects[project.id] = project

        let useCase = CreateTemplateUseCase(
            templateRepository: templateRepo,
            templateTaskRepository: templateTaskRepo,
            projectRepository: projectRepo
        )

        let input = CreateTemplateUseCase.Input(
            projectId: project.id,
            name: "Test",
            variables: ["123invalid"]
        )

        XCTAssertThrowsError(try useCase.execute(input: input)) { error in
            XCTAssertTrue(error is UseCaseError)
        }
    }

    func testInstantiateTemplateUseCase() throws {
        // インスタンス化ユースケース
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        projectRepo.projects[project.id] = project

        let template = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: project.id,
            name: "Feature Development",
            variables: ["feature_name"]
        )
        templateRepo.templates[template.id] = template

        let task1 = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: template.id,
            title: "{{feature_name}} - 要件確認",
            order: 1
        )
        let task2 = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: template.id,
            title: "{{feature_name}} - 実装",
            order: 2,
            dependsOnOrders: [1]
        )
        templateTaskRepo.tasks[task1.id] = task1
        templateTaskRepo.tasks[task2.id] = task2

        let useCase = InstantiateTemplateUseCase(
            templateRepository: templateRepo,
            templateTaskRepository: templateTaskRepo,
            taskRepository: taskRepo,
            projectRepository: projectRepo,
            eventRepository: eventRepo
        )

        let input = InstantiateTemplateUseCase.Input(
            templateId: template.id,
            projectId: project.id,
            variableValues: ["feature_name": "ログイン機能"]
        )

        let result = try useCase.execute(input: input)

        XCTAssertEqual(result.taskCount, 2)
        XCTAssertEqual(result.createdTasks[0].title, "ログイン機能 - 要件確認")
        XCTAssertEqual(result.createdTasks[1].title, "ログイン機能 - 実装")

        // 依存関係が正しく設定されていること
        XCTAssertTrue(result.createdTasks[1].dependencies.contains(result.createdTasks[0].id))
    }

    func testInstantiateTemplateUseCaseRejectsArchivedTemplate() throws {
        // アーカイブ済みテンプレートはインスタンス化不可
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        projectRepo.projects[project.id] = project

        var template = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: project.id,
            name: "Archived Template"
        )
        template.status = .archived
        templateRepo.templates[template.id] = template

        let useCase = InstantiateTemplateUseCase(
            templateRepository: templateRepo,
            templateTaskRepository: templateTaskRepo,
            taskRepository: taskRepo,
            projectRepository: projectRepo,
            eventRepository: eventRepo
        )

        let input = InstantiateTemplateUseCase.Input(
            templateId: template.id,
            projectId: project.id
        )

        XCTAssertThrowsError(try useCase.execute(input: input))
    }

    func testUpdateTemplateUseCase() throws {
        // テンプレート更新ユースケース
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: projectId,
            name: "Original"
        )
        templateRepo.templates[template.id] = template

        let useCase = UpdateTemplateUseCase(templateRepository: templateRepo)

        let updated = try useCase.execute(
            templateId: template.id,
            name: "Updated",
            description: "New description"
        )

        XCTAssertEqual(updated.name, "Updated")
        XCTAssertEqual(updated.description, "New description")
    }

    func testArchiveTemplateUseCase() throws {
        // テンプレートアーカイブユースケース
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: projectId,
            name: "To Archive"
        )
        templateRepo.templates[template.id] = template

        let useCase = ArchiveTemplateUseCase(templateRepository: templateRepo)

        let archived = try useCase.execute(templateId: template.id)

        XCTAssertEqual(archived.status, .archived)
    }

    func testListTemplatesUseCase() throws {
        // テンプレート一覧取得ユースケース
        let projectId = ProjectID.generate()
        let template1 = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Template1")
        var template2 = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Template2")
        template2.status = .archived

        templateRepo.templates[template1.id] = template1
        templateRepo.templates[template2.id] = template2

        let useCase = ListTemplatesUseCase(templateRepository: templateRepo)

        let activeOnly = try useCase.execute(projectId: projectId, includeArchived: false)
        XCTAssertEqual(activeOnly.count, 1)

        let all = try useCase.execute(projectId: projectId, includeArchived: true)
        XCTAssertEqual(all.count, 2)
    }

    func testGetTemplateWithTasksUseCase() throws {
        // テンプレートとタスク取得ユースケース
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: projectId,
            name: "Feature Development"
        )
        templateRepo.templates[template.id] = template

        let task1 = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: template.id,
            title: "Task 1",
            order: 1
        )
        let task2 = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: template.id,
            title: "Task 2",
            order: 2
        )
        templateTaskRepo.tasks[task1.id] = task1
        templateTaskRepo.tasks[task2.id] = task2

        let useCase = GetTemplateWithTasksUseCase(
            templateRepository: templateRepo,
            templateTaskRepository: templateTaskRepo
        )

        let result = try useCase.execute(templateId: template.id)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.template.name, "Feature Development")
        XCTAssertEqual(result?.tasks.count, 2)
    }

    // MARK: - Internal Audit UseCase Tests (参照: AUDIT.md)

    func testCreateInternalAuditUseCaseSuccess() throws {
        // Internal Audit作成ユースケース
        let useCase = CreateInternalAuditUseCase(internalAuditRepository: internalAuditRepo)

        let audit = try useCase.execute(name: "QA Audit", description: "品質監査")

        XCTAssertEqual(audit.name, "QA Audit")
        XCTAssertEqual(audit.description, "品質監査")
        XCTAssertEqual(audit.status, .active)
        XCTAssertNotNil(internalAuditRepo.audits[audit.id])
    }

    func testCreateInternalAuditUseCaseEmptyNameFails() throws {
        // 空の名前でエラー
        let useCase = CreateInternalAuditUseCase(internalAuditRepository: internalAuditRepo)

        XCTAssertThrowsError(try useCase.execute(name: "   ")) { error in
            if case UseCaseError.validationFailed = error {
                // Expected
            } else {
                XCTFail("Expected validationFailed error")
            }
        }
    }

    func testListInternalAuditsUseCase() throws {
        // Internal Audit一覧取得ユースケース
        let audit1 = InternalAudit(id: InternalAuditID.generate(), name: "Audit1")
        var audit2 = InternalAudit(id: InternalAuditID.generate(), name: "Audit2")
        audit2.status = .inactive

        internalAuditRepo.audits[audit1.id] = audit1
        internalAuditRepo.audits[audit2.id] = audit2

        let useCase = ListInternalAuditsUseCase(internalAuditRepository: internalAuditRepo)

        let activeOnly = try useCase.execute(includeInactive: false)
        XCTAssertEqual(activeOnly.count, 1)

        let all = try useCase.execute(includeInactive: true)
        XCTAssertEqual(all.count, 2)
    }

    func testUpdateInternalAuditUseCaseSuccess() throws {
        // Internal Audit更新ユースケース
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Original")
        internalAuditRepo.audits[audit.id] = audit

        let useCase = UpdateInternalAuditUseCase(internalAuditRepository: internalAuditRepo)

        let updated = try useCase.execute(
            auditId: audit.id,
            name: "Updated",
            description: "New description"
        )

        XCTAssertEqual(updated.name, "Updated")
        XCTAssertEqual(updated.description, "New description")
    }

    func testSuspendInternalAuditUseCase() throws {
        // Internal Audit一時停止ユースケース
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Active Audit")
        internalAuditRepo.audits[audit.id] = audit

        let useCase = SuspendInternalAuditUseCase(internalAuditRepository: internalAuditRepo)

        let suspended = try useCase.execute(auditId: audit.id)

        XCTAssertEqual(suspended.status, .suspended)
    }

    func testActivateInternalAuditUseCase() throws {
        // Internal Audit有効化ユースケース
        var audit = InternalAudit(id: InternalAuditID.generate(), name: "Suspended Audit")
        audit.status = .suspended
        internalAuditRepo.audits[audit.id] = audit

        let useCase = ActivateInternalAuditUseCase(internalAuditRepository: internalAuditRepo)

        let activated = try useCase.execute(auditId: audit.id)

        XCTAssertEqual(activated.status, .active)
    }

    // MARK: - Audit Rule UseCase Tests (参照: AUDIT.md)
    // 設計変更: AuditRuleはauditTasksをインラインで保持（WorkflowTemplateはプロジェクトスコープのため）

    func testCreateAuditRuleUseCaseSuccess() throws {
        // Audit Rule作成ユースケース
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        internalAuditRepo.audits[audit.id] = audit

        let useCase = CreateAuditRuleUseCase(
            auditRuleRepository: auditRuleRepo,
            internalAuditRepository: internalAuditRepo
        )

        let rule = try useCase.execute(
            auditId: audit.id,
            name: "タスク完了時チェック",
            triggerType: .taskCompleted,
            triggerConfig: nil,
            auditTasks: []
        )

        XCTAssertEqual(rule.name, "タスク完了時チェック")
        XCTAssertEqual(rule.triggerType, .taskCompleted)
        XCTAssertTrue(rule.isEnabled)
        XCTAssertNotNil(auditRuleRepo.rules[rule.id])
    }

    func testCreateAuditRuleUseCaseAuditNotFoundFails() throws {
        // 存在しないAuditへのルール作成はエラー
        let useCase = CreateAuditRuleUseCase(
            auditRuleRepository: auditRuleRepo,
            internalAuditRepository: internalAuditRepo
        )

        XCTAssertThrowsError(try useCase.execute(
            auditId: InternalAuditID.generate(),
            name: "Rule",
            triggerType: .taskCompleted,
            triggerConfig: nil,
            auditTasks: []
        )) { error in
            if case UseCaseError.internalAuditNotFound = error {
                // Expected
            } else {
                XCTFail("Expected internalAuditNotFound error")
            }
        }
    }

    func testCreateAuditRuleUseCaseWithAuditTasks() throws {
        // auditTasksを含むAudit Rule作成
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        internalAuditRepo.audits[audit.id] = audit

        let agent = Agent(id: AgentID.generate(), name: "QA Agent", role: "QA", type: .ai, roleType: .developer)
        agentRepo.agents[agent.id] = agent

        let useCase = CreateAuditRuleUseCase(
            auditRuleRepository: auditRuleRepo,
            internalAuditRepository: internalAuditRepo
        )

        let auditTasks = [
            AuditTask(order: 1, title: "Run Tests", description: "Execute all tests", assigneeId: agent.id, priority: .high, dependsOnOrders: [])
        ]

        let rule = try useCase.execute(
            auditId: audit.id,
            name: "QA Check",
            triggerType: .taskCompleted,
            triggerConfig: nil,
            auditTasks: auditTasks
        )

        XCTAssertEqual(rule.auditTasks.count, 1)
        XCTAssertEqual(rule.auditTasks.first?.title, "Run Tests")
        XCTAssertEqual(rule.auditTasks.first?.assigneeId, agent.id)
    }

    func testListAuditRulesUseCase() throws {
        // Audit Rule一覧取得ユースケース
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        internalAuditRepo.audits[audit.id] = audit

        let rule1 = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "Rule1", triggerType: .taskCompleted, auditTasks: [])
        var rule2 = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "Rule2", triggerType: .statusChanged, auditTasks: [], isEnabled: false)

        auditRuleRepo.rules[rule1.id] = rule1
        auditRuleRepo.rules[rule2.id] = rule2

        let useCase = ListAuditRulesUseCase(auditRuleRepository: auditRuleRepo)

        let allRules = try useCase.execute(auditId: audit.id, enabledOnly: false)
        XCTAssertEqual(allRules.count, 2)

        let enabledOnly = try useCase.execute(auditId: audit.id, enabledOnly: true)
        XCTAssertEqual(enabledOnly.count, 1)
    }

    func testEnableDisableAuditRuleUseCase() throws {
        // Audit Rule有効/無効化ユースケース
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        internalAuditRepo.audits[audit.id] = audit

        let rule = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "Rule", triggerType: .taskCompleted, auditTasks: [], isEnabled: true)
        auditRuleRepo.rules[rule.id] = rule

        let useCase = EnableDisableAuditRuleUseCase(auditRuleRepository: auditRuleRepo)

        // 無効化
        let disabled = try useCase.execute(ruleId: rule.id, isEnabled: false)
        XCTAssertFalse(disabled.isEnabled)

        // 有効化
        let enabled = try useCase.execute(ruleId: rule.id, isEnabled: true)
        XCTAssertTrue(enabled.isEnabled)
    }

    func testGetAuditWithRulesUseCase() throws {
        // Audit詳細（ルール含む）取得ユースケース
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        internalAuditRepo.audits[audit.id] = audit

        let rule1 = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "Rule1", triggerType: .taskCompleted, auditTasks: [])
        let rule2 = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "Rule2", triggerType: .statusChanged, auditTasks: [])

        auditRuleRepo.rules[rule1.id] = rule1
        auditRuleRepo.rules[rule2.id] = rule2

        let useCase = GetAuditWithRulesUseCase(
            internalAuditRepository: internalAuditRepo,
            auditRuleRepository: auditRuleRepo
        )

        let result = try useCase.execute(auditId: audit.id)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.audit.name, "Test Audit")
        XCTAssertEqual(result?.rules.count, 2)
    }

    func testDeleteAuditRuleUseCase() throws {
        // Audit Rule削除ユースケース
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        internalAuditRepo.audits[audit.id] = audit

        let rule = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "ToDelete", triggerType: .taskCompleted, auditTasks: [])
        auditRuleRepo.rules[rule.id] = rule

        let useCase = DeleteAuditRuleUseCase(auditRuleRepository: auditRuleRepo)

        try useCase.execute(ruleId: rule.id)

        XCTAssertNil(auditRuleRepo.rules[rule.id])
    }

    // 注: testCreateAuditRuleWithTaskAssignments は testCreateAuditRuleUseCaseWithAuditTasks に置き換え済み

    // MARK: - Task Lock Tests (参照: AUDIT.md - タスクロック)

    func testLockedTaskCannotChangeStatus() throws {
        // ロック中のタスクはステータス変更不可
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        // ロックされたタスクを作成
        var task = Task(id: TaskID.generate(), projectId: project.id, title: "Locked Task", status: .inProgress)
        task.isLocked = true
        task.lockedByAuditId = InternalAuditID.generate()
        task.lockedAt = Date()
        taskRepo.tasks[task.id] = task

        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo
        )

        XCTAssertThrowsError(try useCase.execute(
            taskId: task.id,
            newStatus: .done,
            agentId: nil,
            sessionId: nil,
            reason: nil
        )) { error in
            if case UseCaseError.validationFailed(let message) = error {
                XCTAssertTrue(message.contains("locked"))
            } else {
                XCTFail("Expected validationFailed error with 'locked' message")
            }
        }
    }

    func testUnlockedTaskCanChangeStatus() throws {
        // ロックされていないタスクはステータス変更可能
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Unlocked Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo
        )

        let updatedTask = try useCase.execute(
            taskId: task.id,
            newStatus: .done,
            agentId: nil,
            sessionId: nil,
            reason: nil
        )

        XCTAssertEqual(updatedTask.status, .done)
    }

    // MARK: - Audit Trigger Tests (参照: AUDIT.md - 自動トリガー機能)

    func testAuditTriggerFiresOnTaskCompletion() throws {
        // タスク完了時にAudit Ruleトリガーが発火する
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        // エージェント（auditTasks用）
        let qaAgent = Agent(id: AgentID.generate(), name: "QA Agent", role: "QA", type: .ai, roleType: .developer)
        agentRepo.agents[qaAgent.id] = qaAgent

        // アクティブなInternal Audit
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "QA Audit")
        internalAuditRepo.audits[audit.id] = audit

        // Audit Rule（タスク完了トリガー）- auditTasksをインラインで定義
        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: audit.id,
            name: "タスク完了時チェック",
            triggerType: .taskCompleted,
            auditTasks: [
                AuditTask(order: 1, title: "チェック項目", description: "", assigneeId: qaAgent.id, priority: .medium, dependsOnOrders: [])
            ],
            isEnabled: true
        )
        auditRuleRepo.rules[rule.id] = rule

        // 対象タスク（inProgress状態）
        let task = Task(id: TaskID.generate(), projectId: project.id, title: "API実装", status: .inProgress)
        taskRepo.tasks[task.id] = task

        // Audit機能付きユースケース
        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo,
            internalAuditRepository: internalAuditRepo,
            auditRuleRepository: auditRuleRepo
        )

        // タスク完了
        let result = try useCase.executeWithResult(
            taskId: task.id,
            newStatus: .done,
            agentId: nil,
            sessionId: nil,
            reason: nil
        )

        // 結果検証
        XCTAssertEqual(result.task.status, .done)
        XCTAssertEqual(result.firedAuditRules.count, 1)
        XCTAssertEqual(result.firedAuditRules[0].ruleName, "タスク完了時チェック")
        XCTAssertEqual(result.firedAuditRules[0].createdTaskCount, 1)

        // 新規タスクが作成されたことを確認
        let allTasks = try taskRepo.findAll(projectId: project.id)
        XCTAssertEqual(allTasks.count, 2) // 元タスク + 生成タスク
    }

    func testAuditTriggerDoesNotFireForInactiveAudit() throws {
        // 非アクティブなAuditではトリガーが発火しない
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        // 非アクティブなInternal Audit
        var audit = InternalAudit(id: InternalAuditID.generate(), name: "Inactive Audit")
        audit.status = .inactive
        internalAuditRepo.audits[audit.id] = audit

        // Audit Rule
        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: audit.id,
            name: "Rule",
            triggerType: .taskCompleted,
            auditTasks: [],
            isEnabled: true
        )
        auditRuleRepo.rules[rule.id] = rule

        // 対象タスク
        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo,
            internalAuditRepository: internalAuditRepo,
            auditRuleRepository: auditRuleRepo
        )

        let result = try useCase.executeWithResult(
            taskId: task.id,
            newStatus: .done,
            agentId: nil,
            sessionId: nil,
            reason: nil
        )

        // トリガーが発火していないことを確認
        XCTAssertTrue(result.firedAuditRules.isEmpty)
    }

    func testAuditTriggerDoesNotFireForDisabledRule() throws {
        // 無効化されたルールではトリガーが発火しない
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        // アクティブなInternal Audit
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Active Audit")
        internalAuditRepo.audits[audit.id] = audit

        // 無効化されたAudit Rule
        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: audit.id,
            name: "Disabled Rule",
            triggerType: .taskCompleted,
            auditTasks: [],
            isEnabled: false
        )
        auditRuleRepo.rules[rule.id] = rule

        // 対象タスク
        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo,
            internalAuditRepository: internalAuditRepo,
            auditRuleRepository: auditRuleRepo
        )

        let result = try useCase.executeWithResult(
            taskId: task.id,
            newStatus: .done,
            agentId: nil,
            sessionId: nil,
            reason: nil
        )

        // トリガーが発火していないことを確認
        XCTAssertTrue(result.firedAuditRules.isEmpty)
    }

    func testAuditTriggerDoesNotFireForSuspendedAudit() throws {
        // サスペンド中のAuditではトリガーが発火しない
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        // サスペンド中のInternal Audit
        var audit = InternalAudit(id: InternalAuditID.generate(), name: "Suspended Audit")
        audit.status = .suspended
        internalAuditRepo.audits[audit.id] = audit

        // Audit Rule
        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: audit.id,
            name: "Rule",
            triggerType: .taskCompleted,
            auditTasks: [],
            isEnabled: true
        )
        auditRuleRepo.rules[rule.id] = rule

        // 対象タスク
        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo,
            internalAuditRepository: internalAuditRepo,
            auditRuleRepository: auditRuleRepo
        )

        let result = try useCase.executeWithResult(
            taskId: task.id,
            newStatus: .done,
            agentId: nil,
            sessionId: nil,
            reason: nil
        )

        // トリガーが発火していないことを確認
        XCTAssertTrue(result.firedAuditRules.isEmpty)
    }

    func testAuditTriggerDoesNotFireForNonCompletionStatus() throws {
        // タスク完了以外のステータス変更ではトリガーが発火しない
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        // アクティブなInternal Audit
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "QA Audit")
        internalAuditRepo.audits[audit.id] = audit

        // Audit Rule（タスク完了トリガー）
        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: audit.id,
            name: "タスク完了時チェック",
            triggerType: .taskCompleted,
            auditTasks: [],
            isEnabled: true
        )
        auditRuleRepo.rules[rule.id] = rule

        // 対象タスク（backlog状態）
        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", status: .backlog)
        taskRepo.tasks[task.id] = task

        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo,
            internalAuditRepository: internalAuditRepo,
            auditRuleRepository: auditRuleRepo
        )

        // backlog → todo（完了ではない）
        let result = try useCase.executeWithResult(
            taskId: task.id,
            newStatus: .todo,
            agentId: nil,
            sessionId: nil,
            reason: nil
        )

        // トリガーが発火していないことを確認
        XCTAssertTrue(result.firedAuditRules.isEmpty)
    }

    func testAuditTriggerWithoutAuditRepositoriesSkipsTrigger() throws {
        // Audit機能なしのユースケースではトリガー処理がスキップされる
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        // Audit機能なしのユースケース（後方互換性）
        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo
        )

        let result = try useCase.executeWithResult(
            taskId: task.id,
            newStatus: .done,
            agentId: nil,
            sessionId: nil,
            reason: nil
        )

        // 正常に完了し、トリガーは空
        XCTAssertEqual(result.task.status, .done)
        XCTAssertTrue(result.firedAuditRules.isEmpty)
    }

    func testAuditTriggerWithMultipleRules() throws {
        // 複数のルールがマッチする場合、全て発火する
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        // QAエージェント
        let qaAgent = Agent(id: AgentID.generate(), name: "QA Agent", role: "QA", type: .ai, roleType: .developer)
        agentRepo.agents[qaAgent.id] = qaAgent

        // アクティブなInternal Audit
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "QA Audit")
        internalAuditRepo.audits[audit.id] = audit

        // Audit Rule 1（auditTasksをインラインで定義）
        let rule1 = AuditRule(
            id: AuditRuleID.generate(),
            auditId: audit.id,
            name: "Rule 1",
            triggerType: .taskCompleted,
            auditTasks: [AuditTask(order: 1, title: "Task1", assigneeId: qaAgent.id)],
            isEnabled: true
        )
        auditRuleRepo.rules[rule1.id] = rule1

        // Audit Rule 2（auditTasksをインラインで定義）
        let rule2 = AuditRule(
            id: AuditRuleID.generate(),
            auditId: audit.id,
            name: "Rule 2",
            triggerType: .taskCompleted,
            auditTasks: [AuditTask(order: 1, title: "Task2", assigneeId: qaAgent.id)],
            isEnabled: true
        )
        auditRuleRepo.rules[rule2.id] = rule2

        // 対象タスク
        let task = Task(id: TaskID.generate(), projectId: project.id, title: "API実装", status: .inProgress)
        taskRepo.tasks[task.id] = task

        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo,
            internalAuditRepository: internalAuditRepo,
            auditRuleRepository: auditRuleRepo
        )

        let result = try useCase.executeWithResult(
            taskId: task.id,
            newStatus: .done,
            agentId: nil,
            sessionId: nil,
            reason: nil
        )

        // 2つのルールが発火
        XCTAssertEqual(result.firedAuditRules.count, 2)

        // 3つのタスクが存在（元タスク + 2つの生成タスク）
        let allTasks = try taskRepo.findAll(projectId: project.id)
        XCTAssertEqual(allTasks.count, 3)
    }

    // MARK: - FireAuditRuleUseCase Tests

    func testFireAuditRuleUseCaseSuccess() throws {
        // Audit Rule発火ユースケース
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        // QAエージェント
        let qaAgent = Agent(id: AgentID.generate(), name: "QA Agent", role: "QA", type: .ai, roleType: .developer)
        agentRepo.agents[qaAgent.id] = qaAgent

        // ソースタスク
        let sourceTask = Task(id: TaskID.generate(), projectId: project.id, title: "API実装", status: .done)
        taskRepo.tasks[sourceTask.id] = sourceTask

        // Audit
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "QA Audit")
        internalAuditRepo.audits[audit.id] = audit

        // Audit Rule（auditTasksをインラインで定義）
        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: audit.id,
            name: "コードレビュー",
            triggerType: .taskCompleted,
            auditTasks: [
                AuditTask(order: 1, title: "レビュー", assigneeId: qaAgent.id),
                AuditTask(order: 2, title: "修正確認", assigneeId: qaAgent.id, dependsOnOrders: [1])
            ]
        )
        auditRuleRepo.rules[rule.id] = rule

        let useCase = FireAuditRuleUseCase(
            auditRuleRepository: auditRuleRepo,
            taskRepository: taskRepo,
            eventRepository: eventRepo
        )

        let result = try useCase.execute(ruleId: rule.id, sourceTask: sourceTask)

        // 結果検証
        XCTAssertEqual(result.rule.id, rule.id)
        XCTAssertEqual(result.sourceTask.id, sourceTask.id)
        XCTAssertEqual(result.createdTasks.count, 2)

        // タスクタイトルにソースタスク情報が含まれる
        XCTAssertTrue(result.createdTasks[0].title.contains("[Audit:"))
        XCTAssertTrue(result.createdTasks[0].title.contains("API実装"))
    }

    func testFireAuditRuleUseCaseWithAgentAssignment() throws {
        // エージェント割り当て付きでルール発火
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        // エージェント
        let agent = Agent(id: AgentID.generate(), name: "Reviewer", role: "レビュアー")
        agentRepo.agents[agent.id] = agent

        // ソースタスク
        let sourceTask = Task(id: TaskID.generate(), projectId: project.id, title: "実装完了", status: .done)
        taskRepo.tasks[sourceTask.id] = sourceTask

        // Audit
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "QA")
        internalAuditRepo.audits[audit.id] = audit

        // エージェント割り当て付きルール（auditTasksをインラインで定義）
        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: audit.id,
            name: "レビュールール",
            triggerType: .taskCompleted,
            auditTasks: [
                AuditTask(order: 1, title: "レビュー", assigneeId: agent.id)
            ]
        )
        auditRuleRepo.rules[rule.id] = rule

        let useCase = FireAuditRuleUseCase(
            auditRuleRepository: auditRuleRepo,
            taskRepository: taskRepo,
            eventRepository: eventRepo
        )

        let result = try useCase.execute(ruleId: rule.id, sourceTask: sourceTask)

        // エージェントが割り当てられていることを確認
        XCTAssertEqual(result.createdTasks.count, 1)
        XCTAssertEqual(result.createdTasks[0].assigneeId, agent.id)
    }

    // MARK: - CheckAuditTriggersUseCase Tests

    func testCheckAuditTriggersUseCaseSuccess() throws {
        // トリガーチェックユースケース
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        // アクティブなInternal Audit
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "QA Audit")
        internalAuditRepo.audits[audit.id] = audit

        // Audit Rule with inline auditTasks
        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: audit.id,
            name: "完了時チェック",
            triggerType: .taskCompleted,
            auditTasks: [
                AuditTask(order: 1, title: "確認")
            ]
        )
        auditRuleRepo.rules[rule.id] = rule

        // ソースタスク
        let sourceTask = Task(id: TaskID.generate(), projectId: project.id, title: "実装", status: .done)
        taskRepo.tasks[sourceTask.id] = sourceTask

        let fireUseCase = FireAuditRuleUseCase(
            auditRuleRepository: auditRuleRepo,
            taskRepository: taskRepo,
            eventRepository: eventRepo
        )

        let checkUseCase = CheckAuditTriggersUseCase(
            internalAuditRepository: internalAuditRepo,
            auditRuleRepository: auditRuleRepo,
            fireAuditRuleUseCase: fireUseCase
        )

        let result = try checkUseCase.execute(triggerType: .taskCompleted, sourceTask: sourceTask)

        XCTAssertEqual(result.triggerType, .taskCompleted)
        XCTAssertEqual(result.sourceTask.id, sourceTask.id)
        XCTAssertEqual(result.firedRules.count, 1)
        XCTAssertEqual(result.firedRules[0].rule.name, "完了時チェック")
    }

    func testCheckAuditTriggersUseCaseNoMatchingRules() throws {
        // マッチするルールがない場合
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        // アクティブなInternal Audit
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "QA Audit")
        internalAuditRepo.audits[audit.id] = audit

        // statusChangedトリガーのルール（taskCompletedではマッチしない）
        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: audit.id,
            name: "ステータス変更時",
            triggerType: .statusChanged,
            auditTasks: []
        )
        auditRuleRepo.rules[rule.id] = rule

        // ソースタスク
        let sourceTask = Task(id: TaskID.generate(), projectId: project.id, title: "実装", status: .done)
        taskRepo.tasks[sourceTask.id] = sourceTask

        let fireUseCase = FireAuditRuleUseCase(
            auditRuleRepository: auditRuleRepo,
            taskRepository: taskRepo,
            eventRepository: eventRepo
        )

        let checkUseCase = CheckAuditTriggersUseCase(
            internalAuditRepository: internalAuditRepo,
            auditRuleRepository: auditRuleRepo,
            fireAuditRuleUseCase: fireUseCase
        )

        // taskCompletedトリガーで実行
        let result = try checkUseCase.execute(triggerType: .taskCompleted, sourceTask: sourceTask)

        // マッチするルールがないので空
        XCTAssertTrue(result.firedRules.isEmpty)
    }

    // MARK: - AuthenticateUseCase Tests (Phase 3-1: 認証基盤)

    func testAuthenticateUseCaseSuccess() throws {
        // 正しい認証情報でセッションを取得
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let credential = AgentCredential(agentId: agent.id, rawPasskey: "secret123")
        agentCredentialRepo.credentials[credential.id] = credential

        let useCase = AuthenticateUseCase(
            credentialRepository: agentCredentialRepo,
            sessionRepository: agentSessionRepo,
            agentRepository: agentRepo
        )

        let result = try useCase.execute(agentId: agent.id.value, passkey: "secret123", projectId: project.id.value)

        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.sessionToken)
        XCTAssertEqual(result.agentName, "TestAgent")
        XCTAssertNotNil(result.expiresIn)
        XCTAssertGreaterThan(result.expiresIn ?? 0, 0)
    }

    func testAuthenticateUseCaseInvalidPasskey() throws {
        // 誤ったパスキーでエラーを返す
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let credential = AgentCredential(agentId: agent.id, rawPasskey: "secret123")
        agentCredentialRepo.credentials[credential.id] = credential

        let useCase = AuthenticateUseCase(
            credentialRepository: agentCredentialRepo,
            sessionRepository: agentSessionRepo,
            agentRepository: agentRepo
        )

        let result = try useCase.execute(agentId: agent.id.value, passkey: "wrongpassword", projectId: project.id.value)

        XCTAssertFalse(result.success)
        XCTAssertNil(result.sessionToken)
        XCTAssertEqual(result.error, "Invalid agent_id or passkey")
    }

    func testAuthenticateUseCaseUnknownAgentId() throws {
        // 存在しないエージェントIDでエラーを返す
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let useCase = AuthenticateUseCase(
            credentialRepository: agentCredentialRepo,
            sessionRepository: agentSessionRepo,
            agentRepository: agentRepo
        )

        let result = try useCase.execute(agentId: "unknown_agent", passkey: "anypasskey", projectId: project.id.value)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "Invalid agent_id or passkey")
    }

    func testAuthenticateUseCaseNoCredential() throws {
        // 認証情報が設定されていないエージェント
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent
        // 認証情報は追加しない

        let useCase = AuthenticateUseCase(
            credentialRepository: agentCredentialRepo,
            sessionRepository: agentSessionRepo,
            agentRepository: agentRepo
        )

        let result = try useCase.execute(agentId: agent.id.value, passkey: "anypasskey", projectId: project.id.value)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "Invalid agent_id or passkey")
    }

    func testAuthenticateUseCaseSavesSession() throws {
        // 認証成功時にセッションが保存される
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let credential = AgentCredential(agentId: agent.id, rawPasskey: "secret123")
        agentCredentialRepo.credentials[credential.id] = credential

        let useCase = AuthenticateUseCase(
            credentialRepository: agentCredentialRepo,
            sessionRepository: agentSessionRepo,
            agentRepository: agentRepo
        )

        let result = try useCase.execute(agentId: agent.id.value, passkey: "secret123", projectId: project.id.value)

        XCTAssertTrue(result.success)
        XCTAssertEqual(agentSessionRepo.sessions.count, 1)
    }

    // MARK: - ValidateSessionUseCase Tests

    func testValidateSessionUseCaseValid() throws {
        // 有効なセッションでエージェントIDを返す
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let session = AgentSession(agentId: agent.id, projectId: project.id)
        agentSessionRepo.sessions[session.id] = session

        let useCase = ValidateSessionUseCase(
            sessionRepository: agentSessionRepo,
            agentRepository: agentRepo
        )

        let result = try useCase.execute(sessionToken: session.token)

        XCTAssertEqual(result, agent.id)
    }

    func testValidateSessionUseCaseExpired() throws {
        // 期限切れセッションでnilを返す
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let expiredSession = AgentSession(
            agentId: agent.id,
            projectId: project.id,
            expiresAt: Date().addingTimeInterval(-100)
        )
        agentSessionRepo.sessions[expiredSession.id] = expiredSession

        let useCase = ValidateSessionUseCase(
            sessionRepository: agentSessionRepo,
            agentRepository: agentRepo
        )

        let result = try useCase.execute(sessionToken: expiredSession.token)

        XCTAssertNil(result)
    }

    func testValidateSessionUseCaseInvalidToken() throws {
        // 無効なトークンでnilを返す
        let useCase = ValidateSessionUseCase(
            sessionRepository: agentSessionRepo,
            agentRepository: agentRepo
        )

        let result = try useCase.execute(sessionToken: "invalid_token")

        XCTAssertNil(result)
    }

    // MARK: - LogoutUseCase Tests

    func testLogoutUseCaseSuccess() throws {
        // セッションを削除してログアウト
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let session = AgentSession(agentId: agent.id, projectId: project.id)
        agentSessionRepo.sessions[session.id] = session

        let useCase = LogoutUseCase(sessionRepository: agentSessionRepo)

        let result = try useCase.execute(sessionToken: session.token)

        XCTAssertTrue(result)
        XCTAssertTrue(agentSessionRepo.sessions.isEmpty)
    }

    func testLogoutUseCaseInvalidToken() throws {
        // 無効なトークンでfalseを返す
        let useCase = LogoutUseCase(sessionRepository: agentSessionRepo)

        let result = try useCase.execute(sessionToken: "invalid_token")

        XCTAssertFalse(result)
    }

    // MARK: - CreateCredentialUseCase Tests

    func testCreateCredentialUseCaseSuccess() throws {
        // 認証情報を作成
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let useCase = CreateCredentialUseCase(
            credentialRepository: agentCredentialRepo,
            agentRepository: agentRepo
        )

        let credential = try useCase.execute(agentId: agent.id, passkey: "newsecret123")

        XCTAssertEqual(credential.agentId, agent.id)
        XCTAssertEqual(agentCredentialRepo.credentials.count, 1)
    }

    func testCreateCredentialUseCaseShortPasskey() throws {
        // 短すぎるパスキーでエラー
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let useCase = CreateCredentialUseCase(
            credentialRepository: agentCredentialRepo,
            agentRepository: agentRepo
        )

        XCTAssertThrowsError(try useCase.execute(agentId: agent.id, passkey: "short")) { error in
            if case UseCaseError.validationFailed = error {
                // Expected
            } else {
                XCTFail("Expected validationFailed error")
            }
        }
    }

    func testCreateCredentialUseCaseReplacesExisting() throws {
        // 既存の認証情報を置き換え
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let oldCredential = AgentCredential(agentId: agent.id, rawPasskey: "oldsecret123")
        agentCredentialRepo.credentials[oldCredential.id] = oldCredential

        let useCase = CreateCredentialUseCase(
            credentialRepository: agentCredentialRepo,
            agentRepository: agentRepo
        )

        let newCredential = try useCase.execute(agentId: agent.id, passkey: "newsecret123")

        XCTAssertEqual(agentCredentialRepo.credentials.count, 1)
        XCTAssertNotEqual(newCredential.id, oldCredential.id)
    }

    // MARK: - CleanupExpiredSessionsUseCase Tests

    func testCleanupExpiredSessionsUseCase() throws {
        // 期限切れセッションをクリーンアップ
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let expiredSession = AgentSession(
            agentId: agent.id,
            projectId: project.id,
            expiresAt: Date().addingTimeInterval(-100)
        )
        let validSession = AgentSession(agentId: agent.id, projectId: project.id)
        agentSessionRepo.sessions[expiredSession.id] = expiredSession
        agentSessionRepo.sessions[validSession.id] = validSession

        let useCase = CleanupExpiredSessionsUseCase(sessionRepository: agentSessionRepo)

        try useCase.execute()

        XCTAssertEqual(agentSessionRepo.sessions.count, 1)
        XCTAssertNotNil(agentSessionRepo.sessions[validSession.id])
    }

    // MARK: - RecordExecutionStartUseCase Tests (Phase 3-3)

    func testRecordExecutionStartUseCaseSuccess() throws {
        // 正常系：実行開始を記録
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        let useCase = RecordExecutionStartUseCase(
            executionLogRepository: executionLogRepo,
            taskRepository: taskRepo,
            agentRepository: agentRepo
        )

        let log = try useCase.execute(taskId: task.id, agentId: agent.id)

        XCTAssertEqual(log.taskId, task.id)
        XCTAssertEqual(log.agentId, agent.id)
        XCTAssertEqual(log.status, .running)
        XCTAssertNil(log.completedAt)
        XCTAssertNotNil(executionLogRepo.logs[log.id])
    }

    func testRecordExecutionStartUseCaseTaskNotFound() throws {
        // タスクが見つからない場合
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let useCase = RecordExecutionStartUseCase(
            executionLogRepository: executionLogRepo,
            taskRepository: taskRepo,
            agentRepository: agentRepo
        )

        let nonExistentTaskId = TaskID.generate()

        XCTAssertThrowsError(try useCase.execute(taskId: nonExistentTaskId, agentId: agent.id)) { error in
            if case UseCaseError.taskNotFound = error {
                // Expected
            } else {
                XCTFail("Expected taskNotFound error")
            }
        }
    }

    func testRecordExecutionStartUseCaseAgentNotFound() throws {
        // エージェントが見つからない場合
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        let useCase = RecordExecutionStartUseCase(
            executionLogRepository: executionLogRepo,
            taskRepository: taskRepo,
            agentRepository: agentRepo
        )

        let nonExistentAgentId = AgentID.generate()

        XCTAssertThrowsError(try useCase.execute(taskId: task.id, agentId: nonExistentAgentId)) { error in
            if case UseCaseError.agentNotFound = error {
                // Expected
            } else {
                XCTFail("Expected agentNotFound error")
            }
        }
    }

    // MARK: - RecordExecutionCompleteUseCase Tests (Phase 3-3)

    func testRecordExecutionCompleteUseCaseSuccess() throws {
        // 正常系：実行完了を記録（exitCode=0で完了）
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        let log = ExecutionLog(taskId: task.id, agentId: agent.id)
        executionLogRepo.logs[log.id] = log

        let useCase = RecordExecutionCompleteUseCase(executionLogRepository: executionLogRepo)

        let updatedLog = try useCase.execute(
            executionLogId: log.id,
            exitCode: 0,
            durationSeconds: 120.5,
            logFilePath: "/tmp/log.txt"
        )

        XCTAssertEqual(updatedLog.status, .completed)
        XCTAssertEqual(updatedLog.exitCode, 0)
        XCTAssertEqual(updatedLog.durationSeconds, 120.5)
        XCTAssertEqual(updatedLog.logFilePath, "/tmp/log.txt")
        XCTAssertNotNil(updatedLog.completedAt)
    }

    func testRecordExecutionCompleteUseCaseFailedStatus() throws {
        // 正常系：実行失敗を記録（exitCode≠0で失敗）
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        let log = ExecutionLog(taskId: task.id, agentId: agent.id)
        executionLogRepo.logs[log.id] = log

        let useCase = RecordExecutionCompleteUseCase(executionLogRepository: executionLogRepo)

        let updatedLog = try useCase.execute(
            executionLogId: log.id,
            exitCode: 1,
            durationSeconds: 45.0,
            logFilePath: "/tmp/error.log",
            errorMessage: "Command failed"
        )

        XCTAssertEqual(updatedLog.status, .failed)
        XCTAssertEqual(updatedLog.exitCode, 1)
        XCTAssertEqual(updatedLog.errorMessage, "Command failed")
    }

    func testRecordExecutionCompleteUseCaseNotFound() throws {
        // 実行ログが見つからない場合
        let useCase = RecordExecutionCompleteUseCase(executionLogRepository: executionLogRepo)

        let nonExistentId = ExecutionLogID.generate()

        XCTAssertThrowsError(try useCase.execute(
            executionLogId: nonExistentId,
            exitCode: 0,
            durationSeconds: 10.0
        )) { error in
            if case UseCaseError.executionLogNotFound = error {
                // Expected
            } else {
                XCTFail("Expected executionLogNotFound error")
            }
        }
    }

    func testRecordExecutionCompleteUseCaseAlreadyCompleted() throws {
        // 既に完了している実行ログに対するエラー
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        var log = ExecutionLog(taskId: task.id, agentId: agent.id)
        log.complete(exitCode: 0, durationSeconds: 60.0)  // 既に完了
        executionLogRepo.logs[log.id] = log

        let useCase = RecordExecutionCompleteUseCase(executionLogRepository: executionLogRepo)

        XCTAssertThrowsError(try useCase.execute(
            executionLogId: log.id,
            exitCode: 0,
            durationSeconds: 10.0
        )) { error in
            if case UseCaseError.invalidStateTransition = error {
                // Expected
            } else {
                XCTFail("Expected invalidStateTransition error")
            }
        }
    }

    // MARK: - GetExecutionLogsUseCase Tests (Phase 3-3)

    func testGetExecutionLogsByTaskId() throws {
        // タスクIDで実行ログを取得
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task")
        taskRepo.tasks[task.id] = task

        let log1 = ExecutionLog(taskId: task.id, agentId: agent.id)
        let log2 = ExecutionLog(taskId: task.id, agentId: agent.id)
        executionLogRepo.logs[log1.id] = log1
        executionLogRepo.logs[log2.id] = log2

        let useCase = GetExecutionLogsUseCase(executionLogRepository: executionLogRepo)

        let logs = try useCase.executeByTaskId(task.id)

        XCTAssertEqual(logs.count, 2)
    }

    func testGetExecutionLogsByAgentId() throws {
        // エージェントIDで実行ログを取得
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let task1 = Task(id: TaskID.generate(), projectId: project.id, title: "Task 1")
        let task2 = Task(id: TaskID.generate(), projectId: project.id, title: "Task 2")
        taskRepo.tasks[task1.id] = task1
        taskRepo.tasks[task2.id] = task2

        let log1 = ExecutionLog(taskId: task1.id, agentId: agent.id)
        let log2 = ExecutionLog(taskId: task2.id, agentId: agent.id)
        executionLogRepo.logs[log1.id] = log1
        executionLogRepo.logs[log2.id] = log2

        let useCase = GetExecutionLogsUseCase(executionLogRepository: executionLogRepo)

        let logs = try useCase.executeByAgentId(agent.id)

        XCTAssertEqual(logs.count, 2)
    }

    func testGetRunningExecutionLogs() throws {
        // 実行中のログを取得
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task")
        taskRepo.tasks[task.id] = task

        let runningLog = ExecutionLog(taskId: task.id, agentId: agent.id)
        var completedLog = ExecutionLog(taskId: task.id, agentId: agent.id)
        completedLog.complete(exitCode: 0, durationSeconds: 60.0)

        executionLogRepo.logs[runningLog.id] = runningLog
        executionLogRepo.logs[completedLog.id] = completedLog

        let useCase = GetExecutionLogsUseCase(executionLogRepository: executionLogRepo)

        let logs = try useCase.executeRunning(agentId: agent.id)

        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.status, .running)
    }

    // MARK: - Session Lifecycle Tests (セッション管理問題修正)

    func testSessionRepositoryDeleteMethod() throws {
        // SessionRepositoryProtocolにdeleteメソッドが存在すること
        let session = Session(
            id: SessionID.generate(),
            projectId: ProjectID.generate(),
            agentId: AgentID.generate()
        )
        sessionRepo.sessions[session.id] = session

        // deleteメソッドが呼べること
        try sessionRepo.delete(session.id)

        // 削除後はnilになること
        XCTAssertNil(sessionRepo.sessions[session.id])
    }

    func testSessionRepositoryFindActiveByProject() throws {
        // プロジェクトIDでアクティブセッションを検索できること
        let projectId = ProjectID.generate()
        let agent1 = AgentID.generate()
        let agent2 = AgentID.generate()

        let session1 = Session(id: SessionID.generate(), projectId: projectId, agentId: agent1)
        var session2 = Session(id: SessionID.generate(), projectId: projectId, agentId: agent2)
        session2.end(status: .completed)

        sessionRepo.sessions[session1.id] = session1
        sessionRepo.sessions[session2.id] = session2

        // findActiveByProjectメソッドが存在すること
        let activeSessions = try sessionRepo.findActiveByProject(projectId)

        XCTAssertEqual(activeSessions.count, 1)
        XCTAssertEqual(activeSessions.first?.agentId, agent1)
    }

    func testEndActiveSessionsForAgent() throws {
        // エージェントのアクティブセッションを全て終了できること
        let projectId = ProjectID.generate()
        let agentId = AgentID.generate()

        // 複数のアクティブセッション
        let session1 = Session(id: SessionID.generate(), projectId: projectId, agentId: agentId)
        let session2 = Session(id: SessionID.generate(), projectId: projectId, agentId: agentId)
        sessionRepo.sessions[session1.id] = session1
        sessionRepo.sessions[session2.id] = session2

        // EndActiveSessionsUseCaseでエージェントの全アクティブセッションを終了
        let useCase = EndActiveSessionsUseCase(sessionRepository: sessionRepo)
        let endedCount = try useCase.execute(agentId: agentId, projectId: projectId, status: .completed)

        XCTAssertEqual(endedCount, 2)

        // 全てのセッションが終了していること
        let remaining = try sessionRepo.findActiveByProject(projectId)
        XCTAssertEqual(remaining.count, 0)
    }

    func testReportCompletedEndsSession() throws {
        // reportCompleted相当の処理でセッションが終了されること
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Worker")
        agentRepo.agents[agent.id] = agent

        // タスク（in_progress状態）
        var task = Task(
            id: TaskID.generate(),
            projectId: project.id,
            title: "Test Task",
            status: .inProgress
        )
        task.assigneeId = agent.id
        taskRepo.tasks[task.id] = task

        // アクティブセッション
        let session = Session(
            id: SessionID.generate(),
            projectId: project.id,
            agentId: agent.id
        )
        sessionRepo.sessions[session.id] = session

        // CompleteTaskWithSessionCleanupUseCaseでタスク完了とセッション終了を同時に行う
        let useCase = CompleteTaskWithSessionCleanupUseCase(
            taskRepository: taskRepo,
            sessionRepository: sessionRepo,
            eventRepository: eventRepo
        )

        let result = try useCase.execute(taskId: task.id, agentId: agent.id, result: .success)

        // タスクがdoneになっていること
        XCTAssertEqual(result.task.status, .done)

        // セッションが終了していること
        let remainingSession = try sessionRepo.findActive(agentId: agent.id)
        XCTAssertNil(remainingSession, "タスク完了後、アクティブセッションは残らないはず")
    }

    func testReportBlockedEndsSession() throws {
        // blocked報告でセッションが終了されること
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Worker")
        agentRepo.agents[agent.id] = agent

        var task = Task(
            id: TaskID.generate(),
            projectId: project.id,
            title: "Test Task",
            status: .inProgress
        )
        task.assigneeId = agent.id
        taskRepo.tasks[task.id] = task

        let session = Session(
            id: SessionID.generate(),
            projectId: project.id,
            agentId: agent.id
        )
        sessionRepo.sessions[session.id] = session

        let useCase = CompleteTaskWithSessionCleanupUseCase(
            taskRepository: taskRepo,
            sessionRepository: sessionRepo,
            eventRepository: eventRepo
        )

        let result = try useCase.execute(taskId: task.id, agentId: agent.id, result: .blocked)

        // タスクがblockedになっていること
        XCTAssertEqual(result.task.status, .blocked)

        // セッションが終了していること
        let remainingSession = try sessionRepo.findActive(agentId: agent.id)
        XCTAssertNil(remainingSession, "タスクblocked後、アクティブセッションは残らないはず")
    }
}
