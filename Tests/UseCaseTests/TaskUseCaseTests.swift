// Tests/UseCaseTests/TaskUseCaseTests.swift
// Task-related UseCase tests extracted from UseCaseTests.swift
// PRD仕様に基づくタスク関連テスト
// 参照: docs/requirements/TASKS.md, docs/prd/TASK_MANAGEMENT.md

import XCTest
@testable import UseCase
@testable import Domain

// MARK: - Task UseCase Tests

final class TaskUseCaseTests: XCTestCase {

    var projectRepo: MockProjectRepository!
    var agentRepo: MockAgentRepository!
    var taskRepo: MockTaskRepository!
    var eventRepo: MockEventRepository!
    var internalAuditRepo: MockInternalAuditRepository!
    var auditRuleRepo: MockAuditRuleRepository!
    var contextRepo: MockContextRepository!

    override func setUp() {
        projectRepo = MockProjectRepository()
        agentRepo = MockAgentRepository()
        taskRepo = MockTaskRepository()
        eventRepo = MockEventRepository()
        internalAuditRepo = MockInternalAuditRepository()
        auditRuleRepo = MockAuditRuleRepository()
        contextRepo = MockContextRepository()
    }

    // MARK: - Create Task Tests (PRD: TASK_MANAGEMENT.md)

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

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        agentRepo.agents[agent.id] = agent

        var task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", status: .backlog, assigneeId: agent.id)
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

    func testInProgressWithoutAssigneeFails() throws {
        // assigneeId なしのタスクを in_progress にしようとするとエラー
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", status: .todo)
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
            if case UseCaseError.validationFailed(let message) = error {
                XCTAssertTrue(message.contains("assignee_id"))
            } else {
                XCTFail("Expected validationFailed error, got \(error)")
            }
        }
    }

    func testUpdateTaskStatusBlockedTransition() throws {
        // PRD: inProgress → blocked への遷移
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        agentRepo.agents[agent.id] = agent

        var task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", status: .inProgress, assigneeId: agent.id)
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

        // Feature 12: 作業コンテキスト破棄防止のための遷移制限
        // in_progress/blocked → todo/backlog は禁止（ExecutionLog/BlockLogが作成済みのため）
        XCTAssertFalse(UpdateTaskStatusUseCase.canTransition(from: .inProgress, to: .todo),
                       "in_progress→todo: 作業開始後のtodoへの後退は禁止")
        XCTAssertFalse(UpdateTaskStatusUseCase.canTransition(from: .inProgress, to: .backlog),
                       "in_progress→backlog: 作業開始後のbacklogへの後退は禁止")
        XCTAssertFalse(UpdateTaskStatusUseCase.canTransition(from: .blocked, to: .todo),
                       "blocked→todo: ブロック状態からtodoへの後退は禁止")
        XCTAssertFalse(UpdateTaskStatusUseCase.canTransition(from: .blocked, to: .backlog),
                       "blocked→backlog: ブロック状態からbacklogへの後退は禁止")
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

    // Feature 13: 担当エージェント再割り当て制限
    // 要件: docs/requirements/TASKS.md - in_progress/blocked タスクは担当変更不可

    func testAssignTaskUseCaseInProgressReassignmentFails() throws {
        // Feature 13: in_progressタスクの担当変更は禁止
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let agent1 = Agent(id: AgentID.generate(), name: "Agent1", role: "Worker")
        let agent2 = Agent(id: AgentID.generate(), name: "Agent2", role: "Worker")
        agentRepo.agents[agent1.id] = agent1
        agentRepo.agents[agent2.id] = agent2

        // in_progressステータスのタスク（既に担当者あり）
        var task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", assigneeId: agent1.id)
        task.status = .inProgress
        taskRepo.tasks[task.id] = task

        let useCase = AssignTaskUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo
        )

        // 別のエージェントへの再割り当ては失敗すべき
        XCTAssertThrowsError(try useCase.execute(
            taskId: task.id,
            assigneeId: agent2.id,
            actorAgentId: nil,
            sessionId: nil
        ), "in_progressタスクの担当変更は禁止") { error in
            if case UseCaseError.reassignmentNotAllowed = error {
                // Expected
            } else {
                XCTFail("Expected reassignmentNotAllowed error, got: \(error)")
            }
        }
    }

    func testAssignTaskUseCaseBlockedReassignmentFails() throws {
        // Feature 13: blockedタスクの担当変更は禁止
        let project = Project(id: ProjectID.generate(), name: "Test")
        projectRepo.projects[project.id] = project

        let agent1 = Agent(id: AgentID.generate(), name: "Agent1", role: "Worker")
        let agent2 = Agent(id: AgentID.generate(), name: "Agent2", role: "Worker")
        agentRepo.agents[agent1.id] = agent1
        agentRepo.agents[agent2.id] = agent2

        // blockedステータスのタスク（既に担当者あり）
        var task = Task(id: TaskID.generate(), projectId: project.id, title: "Task", assigneeId: agent1.id)
        task.status = .blocked
        taskRepo.tasks[task.id] = task

        let useCase = AssignTaskUseCase(
            taskRepository: taskRepo,
            agentRepository: agentRepo,
            eventRepository: eventRepo
        )

        // 別のエージェントへの再割り当ては失敗すべき
        XCTAssertThrowsError(try useCase.execute(
            taskId: task.id,
            assigneeId: agent2.id,
            actorAgentId: nil,
            sessionId: nil
        ), "blockedタスクの担当変更は禁止") { error in
            if case UseCaseError.reassignmentNotAllowed = error {
                // Expected
            } else {
                XCTFail("Expected reassignmentNotAllowed error, got: \(error)")
            }
        }
    }

    // MARK: - Task Context Tests

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
}
