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

    func findByStatus(_ status: TaskStatus, projectId: ProjectID) throws -> [Task] {
        tasks.values.filter { $0.projectId == projectId && $0.status == status }
    }

    func findByParent(_ parentTaskId: TaskID) throws -> [Task] {
        tasks.values.filter { $0.parentTaskId == parentTaskId }
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

// MARK: - UseCase Tests

final class UseCaseTests: XCTestCase {

    var projectRepo: MockProjectRepository!
    var agentRepo: MockAgentRepository!
    var taskRepo: MockTaskRepository!
    var sessionRepo: MockSessionRepository!
    var contextRepo: MockContextRepository!
    var eventRepo: MockEventRepository!

    override func setUp() {
        projectRepo = MockProjectRepository()
        agentRepo = MockAgentRepository()
        taskRepo = MockTaskRepository()
        sessionRepo = MockSessionRepository()
        contextRepo = MockContextRepository()
        eventRepo = MockEventRepository()
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

    // MARK: - Task Status Transition Tests (要件: ステータスフロー - inReview削除済み)

    func testUpdateTaskStatusValidTransitions() throws {
        // 要件: 有効なステータス遷移（inReview削除後: backlog → todo → inProgress → done）
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        var task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", status: .backlog)
        taskRepo.tasks[task.id] = task

        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepo,
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
}
