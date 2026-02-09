// Tests/UseCaseTests/SessionUseCaseTests.swift
// Session-related UseCase tests extracted from UseCaseTests.swift
// PRD仕様に基づくセッション関連テスト
// 参照: docs/prd/AGENT_CONCEPT.md

import XCTest
@testable import UseCase
@testable import Domain

// MARK: - Session UseCase Tests

final class SessionUseCaseTests: XCTestCase {

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

    // MARK: - Session Start/End Tests (PRD: AGENT_CONCEPT.md - Session)

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

    // MARK: - Context Save Tests (PRD: AGENT_CONCEPT.md - コンテキスト)

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

    // MARK: - Session Repository Tests (セッション管理問題修正)

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
}
