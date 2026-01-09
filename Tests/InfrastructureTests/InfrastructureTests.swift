// Tests/InfrastructureTests/InfrastructureTests.swift
// PRD仕様に基づくInfrastructure層テスト
// 参照: docs/architecture/DATABASE_SCHEMA.md
// 参照: docs/prd/TASK_MANAGEMENT.md, AGENT_CONCEPT.md, STATE_HISTORY.md

import XCTest
import GRDB
@testable import Infrastructure
@testable import Domain

final class InfrastructureTests: XCTestCase {

    var db: DatabaseQueue!
    var projectRepo: ProjectRepository!
    var agentRepo: AgentRepository!
    var taskRepo: TaskRepository!
    var sessionRepo: SessionRepository!
    var contextRepo: ContextRepository!
    var handoffRepo: HandoffRepository!
    var eventRepo: EventRepository!
    var templateRepo: WorkflowTemplateRepository!
    var templateTaskRepo: TemplateTaskRepository!
    var internalAuditRepo: InternalAuditRepository!
    var auditRuleRepo: AuditRuleRepository!
    var agentCredentialRepo: AgentCredentialRepository!
    var agentSessionRepo: AgentSessionRepository!
    var executionLogRepo: ExecutionLogRepository!
    var projectAgentAssignmentRepo: ProjectAgentAssignmentRepository!

    override func setUpWithError() throws {
        // インメモリデータベースを使用
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        projectRepo = ProjectRepository(database: db)
        agentRepo = AgentRepository(database: db)
        taskRepo = TaskRepository(database: db)
        sessionRepo = SessionRepository(database: db)
        contextRepo = ContextRepository(database: db)
        handoffRepo = HandoffRepository(database: db)
        eventRepo = EventRepository(database: db)
        templateRepo = WorkflowTemplateRepository(database: db)
        templateTaskRepo = TemplateTaskRepository(database: db)
        internalAuditRepo = InternalAuditRepository(database: db)
        auditRuleRepo = AuditRuleRepository(database: db)
        agentCredentialRepo = AgentCredentialRepository(database: db)
        agentSessionRepo = AgentSessionRepository(database: db)
        executionLogRepo = ExecutionLogRepository(database: db)
        projectAgentAssignmentRepo = ProjectAgentAssignmentRepository(database: db)
    }

    override func tearDownWithError() throws {
        db = nil
    }

    // MARK: - DatabaseSetup Tests (PRD: DATABASE_SCHEMA.md)

    func testDatabaseSetupCreatesAllTables() throws {
        // PRD: 必要なテーブルがすべて作成されること
        try db.read { db in
            // 必須テーブルの存在確認
            XCTAssertTrue(try db.tableExists("projects"))
            XCTAssertTrue(try db.tableExists("agents"))
            XCTAssertTrue(try db.tableExists("tasks"))
            XCTAssertTrue(try db.tableExists("sessions"))
            XCTAssertTrue(try db.tableExists("contexts"))
            XCTAssertTrue(try db.tableExists("handoffs"))
            XCTAssertTrue(try db.tableExists("state_change_events"))
        }
    }

    func testDatabaseSetupCreatesIndexes() throws {
        // PRD: パフォーマンス用インデックスが作成されること
        try db.read { db in
            // tasks テーブルのインデックス確認
            let taskIndexes = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type='index' AND tbl_name='tasks'
            """)
            XCTAssertFalse(taskIndexes.isEmpty, "Tasks table should have indexes")
        }
    }

    // MARK: - ProjectRepository Tests (PRD: 01_project_list.md)

    func testProjectRepositorySaveAndFindById() throws {
        // PRD: プロジェクトの作成と取得
        let project = Project(
            id: ProjectID.generate(),
            name: "ECサイト開発",
            description: "ECサイトの開発プロジェクト"
        )

        try projectRepo.save(project)

        let found = try projectRepo.findById(project.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "ECサイト開発")
        XCTAssertEqual(found?.description, "ECサイトの開発プロジェクト")
        XCTAssertEqual(found?.status, .active)
    }

    func testProjectRepositoryFindAll() throws {
        // PRD: プロジェクト一覧取得
        let project1 = Project(id: ProjectID.generate(), name: "Project A")
        let project2 = Project(id: ProjectID.generate(), name: "Project B")

        try projectRepo.save(project1)
        try projectRepo.save(project2)

        let all = try projectRepo.findAll()
        XCTAssertEqual(all.count, 2)
    }

    func testProjectRepositoryUpdate() throws {
        // 要件: プロジェクトの更新（status: active/archived のみ）
        var project = Project(id: ProjectID.generate(), name: "Old Name")
        try projectRepo.save(project)

        project.name = "New Name"
        project.status = .archived
        try projectRepo.save(project)

        let found = try projectRepo.findById(project.id)
        XCTAssertEqual(found?.name, "New Name")
        XCTAssertEqual(found?.status, .archived)
    }

    func testProjectRepositoryDelete() throws {
        // PRD: プロジェクトの削除
        let project = Project(id: ProjectID.generate(), name: "To Delete")
        try projectRepo.save(project)

        try projectRepo.delete(project.id)

        let found = try projectRepo.findById(project.id)
        XCTAssertNil(found)
    }

    // MARK: - AgentRepository Tests (PRD: AGENT_CONCEPT.md)

    func testAgentRepositorySaveAndFindById() throws {
        // PRD: エージェントの作成と取得（プロジェクト非依存）
        let agent = Agent(
            id: AgentID.generate(),
            name: "frontend-dev",
            role: "フロントエンド開発",
            type: .ai,
            roleType: .developer
        )

        try agentRepo.save(agent)

        let found = try agentRepo.findById(agent.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "frontend-dev")
        XCTAssertEqual(found?.type, .ai)
        XCTAssertEqual(found?.roleType, .developer)
        XCTAssertEqual(found?.status, .active)
    }

    func testAgentRepositoryFindAll() throws {
        // PRD: エージェント一覧取得（プロジェクト非依存）
        let agent1 = Agent(id: AgentID.generate(), name: "Agent1", role: "Role1")
        let agent2 = Agent(id: AgentID.generate(), name: "Agent2", role: "Role2")
        try agentRepo.save(agent1)
        try agentRepo.save(agent2)

        let agents = try agentRepo.findAll()
        XCTAssertEqual(agents.count, 2)
    }

    func testAgentRepositoryFindByType() throws {
        // PRD: エージェントタイプ別の取得（AI/Human）
        let aiAgent = Agent(id: AgentID.generate(), name: "AI", role: "Role", type: .ai)
        let humanAgent = Agent(id: AgentID.generate(), name: "Human", role: "Role", type: .human)
        try agentRepo.save(aiAgent)
        try agentRepo.save(humanAgent)

        let aiAgents = try agentRepo.findByType(.ai)
        XCTAssertEqual(aiAgents.count, 1)
        XCTAssertEqual(aiAgents.first?.type, .ai)

        let humanAgents = try agentRepo.findByType(.human)
        XCTAssertEqual(humanAgents.count, 1)
        XCTAssertEqual(humanAgents.first?.type, .human)
    }

    func testAgentRepositoryFindByParent() throws {
        // PRD: 親エージェントによる階層構造
        let parentAgent = Agent(id: AgentID.generate(), name: "Parent", role: "Manager")
        try agentRepo.save(parentAgent)

        let child1 = Agent(id: AgentID.generate(), name: "Child1", role: "Developer", parentAgentId: parentAgent.id)
        let child2 = Agent(id: AgentID.generate(), name: "Child2", role: "Developer", parentAgentId: parentAgent.id)
        try agentRepo.save(child1)
        try agentRepo.save(child2)

        let children = try agentRepo.findByParent(parentAgent.id)
        XCTAssertEqual(children.count, 2)

        let rootAgents = try agentRepo.findRootAgents()
        XCTAssertEqual(rootAgents.count, 1)
        XCTAssertEqual(rootAgents.first?.name, "Parent")
    }

    func testAgentRepositoryStatusPersistence() throws {
        // PRD: エージェントステータスの永続化（active/inactive/archived）
        var agent = Agent(id: AgentID.generate(), name: "Test", role: "Role")
        try agentRepo.save(agent)

        // ステータス変更テスト
        agent.status = .archived
        try agentRepo.save(agent)

        let found = try agentRepo.findById(agent.id)
        XCTAssertEqual(found?.status, .archived)
    }

    // MARK: - TaskRepository Tests (PRD: TASK_MANAGEMENT.md)

    func testTaskRepositorySaveAndFindById() throws {
        // PRD: タスクの作成と取得
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let task = Task(
            id: TaskID.generate(),
            projectId: project.id,
            title: "API実装",
            description: "REST APIの実装",
            priority: .high
        )

        try taskRepo.save(task)

        let found = try taskRepo.findById(task.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.title, "API実装")
        XCTAssertEqual(found?.priority, .high)
        XCTAssertEqual(found?.status, .backlog)
    }

    func testTaskRepositoryFindByStatus() throws {
        // PRD: ステータス別タスク取得
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let task1 = Task(id: TaskID.generate(), projectId: project.id, title: "Task1", status: .todo)
        let task2 = Task(id: TaskID.generate(), projectId: project.id, title: "Task2", status: .inProgress)
        let task3 = Task(id: TaskID.generate(), projectId: project.id, title: "Task3", status: .todo)
        try taskRepo.save(task1)
        try taskRepo.save(task2)
        try taskRepo.save(task3)

        let todoTasks = try taskRepo.findByStatus(.todo, projectId: project.id)
        XCTAssertEqual(todoTasks.count, 2)

        let inProgressTasks = try taskRepo.findByStatus(.inProgress, projectId: project.id)
        XCTAssertEqual(inProgressTasks.count, 1)
    }

    func testTaskRepositoryFindByAssignee() throws {
        // PRD: 担当者別タスク取得（get_my_tasks）
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        try agentRepo.save(agent)

        let task1 = Task(id: TaskID.generate(), projectId: project.id, title: "Task1", assigneeId: agent.id)
        let task2 = Task(id: TaskID.generate(), projectId: project.id, title: "Task2", assigneeId: agent.id)
        let task3 = Task(id: TaskID.generate(), projectId: project.id, title: "Task3")
        try taskRepo.save(task1)
        try taskRepo.save(task2)
        try taskRepo.save(task3)

        let myTasks = try taskRepo.findByAssignee(agent.id)
        XCTAssertEqual(myTasks.count, 2)
    }

    // 注意: testTaskRepositoryFindByParent() は削除
    // 要件変更によりサブタスク（parentTaskId）は不要になり、
    // タスク間関係はdependenciesで表現（docs/requirements/TASKS.md参照）

    func testTaskRepositoryStatusTransition() throws {
        // PRD: タスクステータスの遷移（backlog → todo → inProgress → done）
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        var task = Task(id: TaskID.generate(), projectId: project.id, title: "Task")
        try taskRepo.save(task)

        // backlog → todo
        task.status = .todo
        try taskRepo.save(task)
        var found = try taskRepo.findById(task.id)
        XCTAssertEqual(found?.status, .todo)

        // todo → inProgress
        task.status = .inProgress
        try taskRepo.save(task)
        found = try taskRepo.findById(task.id)
        XCTAssertEqual(found?.status, .inProgress)

        // inProgress → done
        task.status = .done
        task.completedAt = Date()
        try taskRepo.save(task)
        found = try taskRepo.findById(task.id)
        XCTAssertEqual(found?.status, .done)
        XCTAssertNotNil(found?.completedAt)
    }

    func testTaskRepositoryPriorityPersistence() throws {
        // PRD: 優先度の永続化（low/medium/high/urgent）
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        for priority in TaskPriority.allCases {
            var task = Task(id: TaskID.generate(), projectId: project.id, title: "Task \(priority)", priority: priority)
            try taskRepo.save(task)

            let found = try taskRepo.findById(task.id)
            XCTAssertEqual(found?.priority, priority, "Priority \(priority) should be persisted correctly")
        }
    }

    func testTaskRepositoryDependencies() throws {
        // PRD: タスクの依存関係
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let dep1 = Task(id: TaskID.generate(), projectId: project.id, title: "Dep1")
        let dep2 = Task(id: TaskID.generate(), projectId: project.id, title: "Dep2")
        try taskRepo.save(dep1)
        try taskRepo.save(dep2)

        let task = Task(
            id: TaskID.generate(),
            projectId: project.id,
            title: "Task with deps",
            dependencies: [dep1.id, dep2.id]
        )
        try taskRepo.save(task)

        let found = try taskRepo.findById(task.id)
        XCTAssertEqual(found?.dependencies.count, 2)
        XCTAssertTrue(found?.dependencies.contains(dep1.id) ?? false)
        XCTAssertTrue(found?.dependencies.contains(dep2.id) ?? false)
    }

    // MARK: - Phase 3-2: findPendingByAssignee Tests

    /// Phase 3-2: 実行待ちタスク（in_progress）のみを返すことを確認
    func testTaskRepositoryFindPendingByAssignee() throws {
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let agent = Agent(id: AgentID.generate(), name: "Test Agent", role: "Developer")
        try agentRepo.save(agent)

        // in_progress タスク（実行待ち）
        let inProgressTask = Task(
            id: TaskID.generate(),
            projectId: project.id,
            title: "In Progress Task",
            status: .inProgress,
            assigneeId: agent.id
        )
        try taskRepo.save(inProgressTask)

        // done タスク（完了済み - 対象外）
        let doneTask = Task(
            id: TaskID.generate(),
            projectId: project.id,
            title: "Done Task",
            status: .done,
            assigneeId: agent.id
        )
        try taskRepo.save(doneTask)

        // todo タスク（未着手 - 対象外）
        let todoTask = Task(
            id: TaskID.generate(),
            projectId: project.id,
            title: "Todo Task",
            status: .todo,
            assigneeId: agent.id
        )
        try taskRepo.save(todoTask)

        // When
        let result = try taskRepo.findPendingByAssignee(agent.id)

        // Then: in_progressのタスクのみ返される
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, inProgressTask.id)
        XCTAssertEqual(result.first?.status, .inProgress)
    }

    /// Phase 3-2: 他のエージェントのタスクは含まれないことを確認
    func testTaskRepositoryFindPendingByAssigneeExcludesOtherAgents() throws {
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let agent1 = Agent(id: AgentID.generate(), name: "Agent 1", role: "Developer")
        let agent2 = Agent(id: AgentID.generate(), name: "Agent 2", role: "Developer")
        try agentRepo.save(agent1)
        try agentRepo.save(agent2)

        // Agent1のin_progressタスク
        let agent1Task = Task(
            id: TaskID.generate(),
            projectId: project.id,
            title: "Agent1 Task",
            status: .inProgress,
            assigneeId: agent1.id
        )
        try taskRepo.save(agent1Task)

        // Agent2のin_progressタスク
        let agent2Task = Task(
            id: TaskID.generate(),
            projectId: project.id,
            title: "Agent2 Task",
            status: .inProgress,
            assigneeId: agent2.id
        )
        try taskRepo.save(agent2Task)

        // When: Agent1のペンディングタスクを取得
        let result = try taskRepo.findPendingByAssignee(agent1.id)

        // Then: Agent1のタスクのみ
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, agent1Task.id)
    }

    /// Phase 3-2: 担当者がいないタスクは含まれないことを確認
    func testTaskRepositoryFindPendingByAssigneeExcludesUnassigned() throws {
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let agent = Agent(id: AgentID.generate(), name: "Test Agent", role: "Developer")
        try agentRepo.save(agent)

        // 未割り当てのin_progressタスク
        let unassignedTask = Task(
            id: TaskID.generate(),
            projectId: project.id,
            title: "Unassigned Task",
            status: .inProgress,
            assigneeId: nil
        )
        try taskRepo.save(unassignedTask)

        // When
        let result = try taskRepo.findPendingByAssignee(agent.id)

        // Then: 空の配列
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - SessionRepository Tests (PRD: AGENT_CONCEPT.md - Session)

    func testSessionRepositorySaveAndFindById() throws {
        // PRD: セッションの作成と取得
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        try agentRepo.save(agent)

        let session = Session(
            id: SessionID.generate(),
            projectId: project.id,
            agentId: agent.id
        )
        try sessionRepo.save(session)

        let found = try sessionRepo.findById(session.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.status, .active)
    }

    func testSessionRepositoryFindActive() throws {
        // PRD: アクティブセッションの取得
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        try agentRepo.save(agent)

        let activeSession = Session(
            id: SessionID.generate(),
            projectId: project.id,
            agentId: agent.id,
            status: .active
        )
        try sessionRepo.save(activeSession)

        let found = try sessionRepo.findActive(agentId: agent.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, activeSession.id)
    }

    func testSessionRepositoryFindActiveReturnsNilWhenNoActive() throws {
        // PRD: アクティブセッションがない場合はnil
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        try agentRepo.save(agent)

        let completedSession = Session(
            id: SessionID.generate(),
            projectId: project.id,
            agentId: agent.id,
            status: .completed
        )
        try sessionRepo.save(completedSession)

        let found = try sessionRepo.findActive(agentId: agent.id)
        XCTAssertNil(found)
    }

    // MARK: - ContextRepository Tests (PRD: AGENT_CONCEPT.md - コンテキスト)

    func testContextRepositorySaveAndFindById() throws {
        // PRD: コンテキストの作成と取得
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        try agentRepo.save(agent)

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task")
        try taskRepo.save(task)

        let session = Session(id: SessionID.generate(), projectId: project.id, agentId: agent.id)
        try sessionRepo.save(session)

        let context = Context(
            id: ContextID.generate(),
            taskId: task.id,
            sessionId: session.id,
            agentId: agent.id,
            progress: "JWT認証を実装中",
            findings: "Rate limit必要"
        )
        try contextRepo.save(context)

        let found = try contextRepo.findById(context.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.progress, "JWT認証を実装中")
    }

    func testContextRepositoryFindByTask() throws {
        // PRD: タスク別コンテキスト取得
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        try agentRepo.save(agent)

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task")
        try taskRepo.save(task)

        let session = Session(id: SessionID.generate(), projectId: project.id, agentId: agent.id)
        try sessionRepo.save(session)

        let ctx1 = Context(id: ContextID.generate(), taskId: task.id, sessionId: session.id, agentId: agent.id, progress: "Step 1")
        let ctx2 = Context(id: ContextID.generate(), taskId: task.id, sessionId: session.id, agentId: agent.id, progress: "Step 2")
        try contextRepo.save(ctx1)
        try contextRepo.save(ctx2)

        let contexts = try contextRepo.findByTask(task.id)
        XCTAssertEqual(contexts.count, 2)
    }

    func testContextRepositoryFindLatest() throws {
        // PRD: 最新コンテキスト取得
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let agent = Agent(id: AgentID.generate(), name: "Agent", role: "Role")
        try agentRepo.save(agent)

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task")
        try taskRepo.save(task)

        let session = Session(id: SessionID.generate(), projectId: project.id, agentId: agent.id)
        try sessionRepo.save(session)

        let oldContext = Context(
            id: ContextID.generate(),
            taskId: task.id,
            sessionId: session.id,
            agentId: agent.id,
            progress: "Old",
            createdAt: Date().addingTimeInterval(-3600)
        )
        let newContext = Context(
            id: ContextID.generate(),
            taskId: task.id,
            sessionId: session.id,
            agentId: agent.id,
            progress: "New",
            createdAt: Date()
        )
        try contextRepo.save(oldContext)
        try contextRepo.save(newContext)

        let latest = try contextRepo.findLatest(taskId: task.id)
        XCTAssertEqual(latest?.progress, "New")
    }

    // MARK: - HandoffRepository Tests (PRD: AGENT_CONCEPT.md - ハンドオフ)

    func testHandoffRepositorySaveAndFindById() throws {
        // PRD: ハンドオフの作成と取得
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let fromAgent = Agent(id: AgentID.generate(), name: "From", role: "Role")
        let toAgent = Agent(id: AgentID.generate(), name: "To", role: "Role")
        try agentRepo.save(fromAgent)
        try agentRepo.save(toAgent)

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task")
        try taskRepo.save(task)

        let handoff = Handoff(
            id: HandoffID.generate(),
            taskId: task.id,
            fromAgentId: fromAgent.id,
            toAgentId: toAgent.id,
            summary: "引き継ぎお願いします"
        )
        try handoffRepo.save(handoff)

        let found = try handoffRepo.findById(handoff.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.summary, "引き継ぎお願いします")
    }

    func testHandoffRepositoryFindPending() throws {
        // PRD: 保留中ハンドオフ取得
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let fromAgent = Agent(id: AgentID.generate(), name: "From", role: "Role")
        let toAgent = Agent(id: AgentID.generate(), name: "To", role: "Role")
        try agentRepo.save(fromAgent)
        try agentRepo.save(toAgent)

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task")
        try taskRepo.save(task)

        // 未承認のハンドオフ
        let pending = Handoff(
            id: HandoffID.generate(),
            taskId: task.id,
            fromAgentId: fromAgent.id,
            toAgentId: toAgent.id,
            summary: "Pending"
        )
        try handoffRepo.save(pending)

        // 承認済みのハンドオフ
        var accepted = Handoff(
            id: HandoffID.generate(),
            taskId: task.id,
            fromAgentId: fromAgent.id,
            toAgentId: toAgent.id,
            summary: "Accepted"
        )
        accepted.acceptedAt = Date()
        try handoffRepo.save(accepted)

        let pendings = try handoffRepo.findPending(agentId: toAgent.id)
        XCTAssertEqual(pendings.count, 1)
        XCTAssertEqual(pendings.first?.summary, "Pending")
    }

    // MARK: - EventRepository Tests (PRD: STATE_HISTORY.md)

    func testEventRepositorySave() throws {
        // PRD: イベントの記録
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: project.id,
            entityType: .task,
            entityId: "tsk_test123",
            eventType: .created,
            previousState: nil,
            newState: "backlog"
        )
        try eventRepo.save(event)

        let events = try eventRepo.findByProject(project.id, limit: nil)
        XCTAssertEqual(events.count, 1)
    }

    func testEventRepositoryFindByEntity() throws {
        // PRD: エンティティ別イベント取得
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let taskId = "tsk_test123"

        let event1 = StateChangeEvent(
            id: EventID.generate(),
            projectId: project.id,
            entityType: .task,
            entityId: taskId,
            eventType: .created,
            previousState: nil,
            newState: "backlog"
        )
        let event2 = StateChangeEvent(
            id: EventID.generate(),
            projectId: project.id,
            entityType: .task,
            entityId: taskId,
            eventType: .statusChanged,
            previousState: "backlog",
            newState: "todo"
        )
        try eventRepo.save(event1)
        try eventRepo.save(event2)

        let events = try eventRepo.findByEntity(type: .task, id: taskId)
        XCTAssertEqual(events.count, 2)
    }

    func testEventRepositoryFindRecent() throws {
        // PRD: 最近のイベント取得
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let oldEvent = StateChangeEvent(
            id: EventID.generate(),
            projectId: project.id,
            entityType: .task,
            entityId: "tsk_old",
            eventType: .created,
            timestamp: Date().addingTimeInterval(-7200) // 2時間前
        )
        let newEvent = StateChangeEvent(
            id: EventID.generate(),
            projectId: project.id,
            entityType: .task,
            entityId: "tsk_new",
            eventType: .created,
            timestamp: Date()
        )
        try eventRepo.save(oldEvent)
        try eventRepo.save(newEvent)

        let since = Date().addingTimeInterval(-3600) // 1時間前
        let recentEvents = try eventRepo.findRecent(projectId: project.id, since: since)
        XCTAssertEqual(recentEvents.count, 1)
    }

    // MARK: - Cascade Delete Tests (PRD: DATABASE_SCHEMA.md - 外部キー制約)

    func testProjectDeleteCascadesToTasks() throws {
        // PRD: プロジェクト削除時のカスケード削除
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Task")
        try taskRepo.save(task)

        // プロジェクト削除
        try projectRepo.delete(project.id)

        // タスクも削除されていること
        let foundTask = try taskRepo.findById(task.id)
        XCTAssertNil(foundTask)
    }

    // MARK: - WorkflowTemplateRepository Tests (参照: WORKFLOW_TEMPLATES.md)
    // 設計方針: テンプレートはプロジェクトに紐づく

    func testWorkflowTemplateRepositorySaveAndFindById() throws {
        // ワークフローテンプレートの作成と取得
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: projectId,
            name: "Feature Development",
            description: "機能開発のワークフロー",
            variables: ["feature_name", "module"]
        )

        try templateRepo.save(template)

        let found = try templateRepo.findById(template.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Feature Development")
        XCTAssertEqual(found?.description, "機能開発のワークフロー")
        XCTAssertEqual(found?.variables, ["feature_name", "module"])
        XCTAssertEqual(found?.status, .active)
        XCTAssertEqual(found?.projectId, projectId)
    }

    func testWorkflowTemplateRepositoryFindByProject() throws {
        // プロジェクト別テンプレート取得
        let projectId = ProjectID.generate()
        let template1 = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Template1")
        let template2 = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Template2")
        var archivedTemplate = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Archived")
        archivedTemplate.status = .archived

        try templateRepo.save(template1)
        try templateRepo.save(template2)
        try templateRepo.save(archivedTemplate)

        // アクティブのみ
        let activeTemplates = try templateRepo.findByProject(projectId, includeArchived: false)
        XCTAssertEqual(activeTemplates.count, 2)

        // 全て含む
        let allTemplates = try templateRepo.findByProject(projectId, includeArchived: true)
        XCTAssertEqual(allTemplates.count, 3)
    }

    func testWorkflowTemplateRepositoryFindActiveByProject() throws {
        // プロジェクト別アクティブテンプレートのみ取得
        let projectId = ProjectID.generate()
        let activeTemplate = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Active")
        var archivedTemplate = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Archived")
        archivedTemplate.status = .archived

        try templateRepo.save(activeTemplate)
        try templateRepo.save(archivedTemplate)

        let found = try templateRepo.findActiveByProject(projectId)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.name, "Active")
    }

    func testWorkflowTemplateRepositoryUpdate() throws {
        // テンプレートの更新
        let projectId = ProjectID.generate()
        var template = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Original")
        try templateRepo.save(template)

        template.name = "Updated"
        template.status = .archived
        try templateRepo.save(template)

        let found = try templateRepo.findById(template.id)
        XCTAssertEqual(found?.name, "Updated")
        XCTAssertEqual(found?.status, .archived)
    }

    func testWorkflowTemplateRepositoryDelete() throws {
        // テンプレートの削除
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "ToDelete")
        try templateRepo.save(template)

        try templateRepo.delete(template.id)

        let found = try templateRepo.findById(template.id)
        XCTAssertNil(found)
    }

    // MARK: - TemplateTaskRepository Tests (参照: WORKFLOW_TEMPLATES.md)

    func testTemplateTaskRepositorySaveAndFindById() throws {
        // テンプレートタスクの作成と取得
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Test")
        try templateRepo.save(template)

        let task = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: template.id,
            title: "{{feature_name}} - 要件確認",
            description: "要件を確認する",
            order: 1,
            defaultPriority: .high
        )
        try templateTaskRepo.save(task)

        let found = try templateTaskRepo.findById(task.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.title, "{{feature_name}} - 要件確認")
        XCTAssertEqual(found?.order, 1)
        XCTAssertEqual(found?.defaultPriority, .high)
    }

    func testTemplateTaskRepositoryFindByTemplate() throws {
        // テンプレート別タスク取得（order順）
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Test")
        try templateRepo.save(template)

        let task1 = TemplateTask(id: TemplateTaskID.generate(), templateId: template.id, title: "Task1", order: 2)
        let task2 = TemplateTask(id: TemplateTaskID.generate(), templateId: template.id, title: "Task2", order: 1)
        let task3 = TemplateTask(id: TemplateTaskID.generate(), templateId: template.id, title: "Task3", order: 3)
        try templateTaskRepo.save(task1)
        try templateTaskRepo.save(task2)
        try templateTaskRepo.save(task3)

        let tasks = try templateTaskRepo.findByTemplate(template.id)
        XCTAssertEqual(tasks.count, 3)
        XCTAssertEqual(tasks[0].title, "Task2") // order: 1
        XCTAssertEqual(tasks[1].title, "Task1") // order: 2
        XCTAssertEqual(tasks[2].title, "Task3") // order: 3
    }

    func testTemplateTaskRepositoryDependencies() throws {
        // 依存関係の永続化
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Test")
        try templateRepo.save(template)

        let task = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: template.id,
            title: "Dependent Task",
            order: 3,
            dependsOnOrders: [1, 2]
        )
        try templateTaskRepo.save(task)

        let found = try templateTaskRepo.findById(task.id)
        XCTAssertEqual(found?.dependsOnOrders, [1, 2])
    }

    func testTemplateTaskRepositoryDelete() throws {
        // テンプレートタスクの削除
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Test")
        try templateRepo.save(template)

        let task = TemplateTask(id: TemplateTaskID.generate(), templateId: template.id, title: "ToDelete", order: 1)
        try templateTaskRepo.save(task)

        try templateTaskRepo.delete(task.id)

        let found = try templateTaskRepo.findById(task.id)
        XCTAssertNil(found)
    }

    func testTemplateTaskRepositoryDeleteByTemplate() throws {
        // テンプレートに属する全タスクの削除
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Test")
        try templateRepo.save(template)

        let task1 = TemplateTask(id: TemplateTaskID.generate(), templateId: template.id, title: "Task1", order: 1)
        let task2 = TemplateTask(id: TemplateTaskID.generate(), templateId: template.id, title: "Task2", order: 2)
        try templateTaskRepo.save(task1)
        try templateTaskRepo.save(task2)

        try templateTaskRepo.deleteByTemplate(template.id)

        let tasks = try templateTaskRepo.findByTemplate(template.id)
        XCTAssertEqual(tasks.count, 0)
    }

    func testTemplateDeleteCascadesToTemplateTasks() throws {
        // テンプレート削除時のカスケード削除
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(id: WorkflowTemplateID.generate(), projectId: projectId, name: "Test")
        try templateRepo.save(template)

        let task = TemplateTask(id: TemplateTaskID.generate(), templateId: template.id, title: "Task", order: 1)
        try templateTaskRepo.save(task)

        // テンプレート削除
        try templateRepo.delete(template.id)

        // タスクも削除されていること
        let foundTask = try templateTaskRepo.findById(task.id)
        XCTAssertNil(foundTask)
    }

    func testDatabaseSetupCreatesWorkflowTemplateTables() throws {
        // ワークフローテンプレート関連テーブルが作成されること
        try db.read { db in
            XCTAssertTrue(try db.tableExists("workflow_templates"))
            XCTAssertTrue(try db.tableExists("template_tasks"))
        }
    }

    // MARK: - InternalAuditRepository Tests (参照: AUDIT.md)

    func testInternalAuditRepositorySaveAndFindById() throws {
        // Internal Auditの作成と取得
        let audit = InternalAudit(
            id: InternalAuditID.generate(),
            name: "QA Audit",
            description: "品質監査"
        )

        try internalAuditRepo.save(audit)

        let found = try internalAuditRepo.findById(audit.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "QA Audit")
        XCTAssertEqual(found?.description, "品質監査")
        XCTAssertEqual(found?.status, .active)
    }

    func testInternalAuditRepositoryFindAll() throws {
        // Internal Audit一覧取得
        let audit1 = InternalAudit(id: InternalAuditID.generate(), name: "Audit1")
        let audit2 = InternalAudit(id: InternalAuditID.generate(), name: "Audit2")
        var inactiveAudit = InternalAudit(id: InternalAuditID.generate(), name: "Inactive")
        inactiveAudit.status = .inactive

        try internalAuditRepo.save(audit1)
        try internalAuditRepo.save(audit2)
        try internalAuditRepo.save(inactiveAudit)

        // アクティブのみ
        let activeAudits = try internalAuditRepo.findAll(includeInactive: false)
        XCTAssertEqual(activeAudits.count, 2)

        // 全て含む
        let allAudits = try internalAuditRepo.findAll(includeInactive: true)
        XCTAssertEqual(allAudits.count, 3)
    }

    func testInternalAuditRepositoryFindActive() throws {
        // アクティブなInternal Auditのみ取得
        let activeAudit = InternalAudit(id: InternalAuditID.generate(), name: "Active")
        var suspendedAudit = InternalAudit(id: InternalAuditID.generate(), name: "Suspended")
        suspendedAudit.status = .suspended

        try internalAuditRepo.save(activeAudit)
        try internalAuditRepo.save(suspendedAudit)

        let found = try internalAuditRepo.findActive()
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.name, "Active")
    }

    func testInternalAuditRepositoryUpdate() throws {
        // Internal Auditの更新
        var audit = InternalAudit(id: InternalAuditID.generate(), name: "Original")
        try internalAuditRepo.save(audit)

        audit.name = "Updated"
        audit.status = .suspended
        try internalAuditRepo.save(audit)

        let found = try internalAuditRepo.findById(audit.id)
        XCTAssertEqual(found?.name, "Updated")
        XCTAssertEqual(found?.status, .suspended)
    }

    func testInternalAuditRepositoryDelete() throws {
        // Internal Auditの削除
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "ToDelete")
        try internalAuditRepo.save(audit)

        try internalAuditRepo.delete(audit.id)

        let found = try internalAuditRepo.findById(audit.id)
        XCTAssertNil(found)
    }

    // MARK: - AuditRuleRepository Tests (参照: AUDIT.md)

    func testAuditRuleRepositorySaveAndFindById() throws {
        // Audit Ruleの作成と取得
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        try internalAuditRepo.save(audit)

        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: audit.id,
            name: "タスク完了時チェック",
            triggerType: .taskCompleted,
            auditTasks: []
        )

        try auditRuleRepo.save(rule)

        let found = try auditRuleRepo.findById(rule.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "タスク完了時チェック")
        XCTAssertEqual(found?.triggerType, .taskCompleted)
        XCTAssertTrue(found?.isEnabled ?? false)
    }

    func testAuditRuleRepositoryFindByAudit() throws {
        // Audit別ルール取得
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        try internalAuditRepo.save(audit)

        let rule1 = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "Rule1", triggerType: .taskCompleted, auditTasks: [])
        let rule2 = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "Rule2", triggerType: .statusChanged, auditTasks: [])
        try auditRuleRepo.save(rule1)
        try auditRuleRepo.save(rule2)

        let rules = try auditRuleRepo.findByAudit(audit.id)
        XCTAssertEqual(rules.count, 2)
    }

    func testAuditRuleRepositoryFindEnabled() throws {
        // 有効なルールのみ取得
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        try internalAuditRepo.save(audit)

        let enabledRule = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "Enabled", triggerType: .taskCompleted, auditTasks: [], isEnabled: true)
        let disabledRule = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "Disabled", triggerType: .statusChanged, auditTasks: [], isEnabled: false)
        try auditRuleRepo.save(enabledRule)
        try auditRuleRepo.save(disabledRule)

        let enabledRules = try auditRuleRepo.findEnabled(auditId: audit.id)
        XCTAssertEqual(enabledRules.count, 1)
        XCTAssertEqual(enabledRules.first?.name, "Enabled")
    }

    func testAuditRuleRepositoryWithAuditTasks() throws {
        // 監査タスク付きルールの永続化
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        try internalAuditRepo.save(audit)

        let agent1 = Agent(id: AgentID.generate(), name: "Agent1", role: "Role1")
        let agent2 = Agent(id: AgentID.generate(), name: "Agent2", role: "Role2")
        try agentRepo.save(agent1)
        try agentRepo.save(agent2)

        let auditTasks = [
            AuditTask(order: 1, title: "Task1", assigneeId: agent1.id),
            AuditTask(order: 2, title: "Task2", assigneeId: agent2.id, dependsOnOrders: [1])
        ]

        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: audit.id,
            name: "Rule with audit tasks",
            triggerType: .statusChanged,
            auditTasks: auditTasks
        )
        try auditRuleRepo.save(rule)

        let found = try auditRuleRepo.findById(rule.id)
        XCTAssertEqual(found?.auditTasks.count, 2)
        XCTAssertEqual(found?.auditTasks[0].order, 1)
        XCTAssertEqual(found?.auditTasks[0].title, "Task1")
        XCTAssertEqual(found?.auditTasks[0].assigneeId, agent1.id)
        XCTAssertEqual(found?.auditTasks[1].order, 2)
        XCTAssertEqual(found?.auditTasks[1].title, "Task2")
        XCTAssertEqual(found?.auditTasks[1].assigneeId, agent2.id)
        XCTAssertEqual(found?.auditTasks[1].dependsOnOrders, [1])
    }

    func testAuditRuleRepositoryWithTriggerConfig() throws {
        // トリガー設定付きルールの永続化
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        try internalAuditRepo.save(audit)

        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: audit.id,
            name: "Status Change Rule",
            triggerType: .statusChanged,
            triggerConfig: ["fromStatus": "todo", "toStatus": "in_progress"],
            auditTasks: []
        )
        try auditRuleRepo.save(rule)

        let found = try auditRuleRepo.findById(rule.id)
        XCTAssertNotNil(found?.triggerConfig)
        XCTAssertEqual(found?.triggerConfig?["fromStatus"] as? String, "todo")
        XCTAssertEqual(found?.triggerConfig?["toStatus"] as? String, "in_progress")
    }

    func testAuditRuleRepositoryUpdate() throws {
        // Audit Ruleの更新
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        try internalAuditRepo.save(audit)

        var rule = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "Original", triggerType: .taskCompleted, auditTasks: [])
        try auditRuleRepo.save(rule)

        rule.name = "Updated"
        rule.isEnabled = false
        try auditRuleRepo.save(rule)

        let found = try auditRuleRepo.findById(rule.id)
        XCTAssertEqual(found?.name, "Updated")
        XCTAssertFalse(found?.isEnabled ?? true)
    }

    func testAuditRuleRepositoryDelete() throws {
        // Audit Ruleの削除
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        try internalAuditRepo.save(audit)

        let rule = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "ToDelete", triggerType: .taskCompleted, auditTasks: [])
        try auditRuleRepo.save(rule)

        try auditRuleRepo.delete(rule.id)

        let found = try auditRuleRepo.findById(rule.id)
        XCTAssertNil(found)
    }

    func testAuditDeleteCascadesToRules() throws {
        // Internal Audit削除時のカスケード削除
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        try internalAuditRepo.save(audit)

        let rule = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "Rule", triggerType: .taskCompleted, auditTasks: [])
        try auditRuleRepo.save(rule)

        // Audit削除
        try internalAuditRepo.delete(audit.id)

        // ルールも削除されていること
        let foundRule = try auditRuleRepo.findById(rule.id)
        XCTAssertNil(foundRule)
    }

    func testDatabaseSetupCreatesInternalAuditTables() throws {
        // Internal Audit関連テーブルが作成されること
        try db.read { db in
            XCTAssertTrue(try db.tableExists("internal_audits"))
            XCTAssertTrue(try db.tableExists("audit_rules"))
        }
    }

    func testAuditRuleRepositoryFindByTriggerType() throws {
        // トリガータイプ別ルール取得
        let audit = InternalAudit(id: InternalAuditID.generate(), name: "Test Audit")
        try internalAuditRepo.save(audit)

        let rule1 = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "Rule1", triggerType: .taskCompleted, auditTasks: [])
        let rule2 = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "Rule2", triggerType: .taskCompleted, auditTasks: [])
        let rule3 = AuditRule(id: AuditRuleID.generate(), auditId: audit.id, name: "Rule3", triggerType: .statusChanged, auditTasks: [])
        try auditRuleRepo.save(rule1)
        try auditRuleRepo.save(rule2)
        try auditRuleRepo.save(rule3)

        let taskCompletedRules = try auditRuleRepo.findByTriggerType(.taskCompleted)
        XCTAssertEqual(taskCompletedRules.count, 2)

        let statusChangedRules = try auditRuleRepo.findByTriggerType(.statusChanged)
        XCTAssertEqual(statusChangedRules.count, 1)
    }

    // MARK: - AgentCredentialRepository Tests (Phase 3-1: 認証基盤)

    func testDatabaseSetupCreatesAuthenticationTables() throws {
        // 認証関連テーブルが作成されること
        try db.read { db in
            XCTAssertTrue(try db.tableExists("agent_credentials"))
            XCTAssertTrue(try db.tableExists("agent_sessions"))
        }
    }

    func testAgentCredentialRepositorySaveAndFindById() throws {
        // エージェント認証情報の保存と取得
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)

        let credential = AgentCredential(agentId: agent.id, rawPasskey: "secret123")
        try agentCredentialRepo.save(credential)

        let found = try agentCredentialRepo.findById(credential.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.agentId, agent.id)
        XCTAssertEqual(found?.passkeyHash, credential.passkeyHash)
    }

    func testAgentCredentialRepositoryFindByAgentId() throws {
        // エージェントID別の認証情報取得
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)

        let credential = AgentCredential(agentId: agent.id, rawPasskey: "secret123")
        try agentCredentialRepo.save(credential)

        let found = try agentCredentialRepo.findByAgentId(agent.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, credential.id)
    }

    func testAgentCredentialRepositoryFindByAgentId_NotFound() throws {
        // 存在しないエージェントIDの場合nilを返す
        let found = try agentCredentialRepo.findByAgentId(AgentID(value: "nonexistent"))
        XCTAssertNil(found)
    }

    func testAgentCredentialRepositoryDelete() throws {
        // 認証情報の削除
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)

        let credential = AgentCredential(agentId: agent.id, rawPasskey: "secret123")
        try agentCredentialRepo.save(credential)

        try agentCredentialRepo.delete(credential.id)

        let found = try agentCredentialRepo.findByAgentId(agent.id)
        XCTAssertNil(found)
    }

    func testAgentCredentialCascadeDeleteOnAgentDelete() throws {
        // エージェント削除時のカスケード削除
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)

        let credential = AgentCredential(agentId: agent.id, rawPasskey: "secret123")
        try agentCredentialRepo.save(credential)

        // エージェント削除
        try agentRepo.delete(agent.id)

        // 認証情報も削除されていること
        let found = try agentCredentialRepo.findById(credential.id)
        XCTAssertNil(found)
    }

    // MARK: - AgentSessionRepository Tests (Phase 3-1: 認証基盤)

    func testAgentSessionRepositorySaveAndFindByToken() throws {
        // セッションの保存とトークンによる取得
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)

        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)
        let session = AgentSession(agentId: agent.id, projectId: project.id)
        try agentSessionRepo.save(session)

        let found = try agentSessionRepo.findByToken(session.token)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.agentId, agent.id)
        XCTAssertEqual(found?.token, session.token)
    }

    func testAgentSessionRepositoryFindByToken_ExpiredSession() throws {
        // 期限切れセッションはnilを返す
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let expiredSession = AgentSession(
            agentId: agent.id,
            projectId: project.id,
            expiresAt: Date().addingTimeInterval(-100) // 100秒前に期限切れ
        )
        try agentSessionRepo.save(expiredSession)

        let found = try agentSessionRepo.findByToken(expiredSession.token)
        XCTAssertNil(found, "Expired session should not be returned")
    }

    func testAgentSessionRepositoryFindByAgentId() throws {
        // エージェントID別のセッション取得
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let session1 = AgentSession(agentId: agent.id, projectId: project.id)
        let session2 = AgentSession(agentId: agent.id, projectId: project.id)
        try agentSessionRepo.save(session1)
        try agentSessionRepo.save(session2)

        let sessions = try agentSessionRepo.findByAgentId(agent.id)
        XCTAssertEqual(sessions.count, 2)
    }

    func testAgentSessionRepositoryDeleteExpired() throws {
        // 期限切れセッションの一括削除
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let expiredSession = AgentSession(
            agentId: agent.id,
            projectId: project.id,
            expiresAt: Date().addingTimeInterval(-100)
        )
        let validSession = AgentSession(agentId: agent.id, projectId: project.id)
        try agentSessionRepo.save(expiredSession)
        try agentSessionRepo.save(validSession)

        // 期限切れセッションを削除
        try agentSessionRepo.deleteExpired()

        // 期限切れセッションは削除されている
        let sessions = try agentSessionRepo.findByAgentId(agent.id)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.token, validSession.token)
    }

    func testAgentSessionRepositoryDeleteByAgentId() throws {
        // エージェント別のセッション一括削除
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let session1 = AgentSession(agentId: agent.id, projectId: project.id)
        let session2 = AgentSession(agentId: agent.id, projectId: project.id)
        try agentSessionRepo.save(session1)
        try agentSessionRepo.save(session2)

        try agentSessionRepo.deleteByAgentId(agent.id)

        let sessions = try agentSessionRepo.findByAgentId(agent.id)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testAgentSessionCascadeDeleteOnAgentDelete() throws {
        // エージェント削除時のカスケード削除
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)
        let project = Project(id: ProjectID.generate(), name: "Test Project")
        try projectRepo.save(project)

        let session = AgentSession(agentId: agent.id, projectId: project.id)
        try agentSessionRepo.save(session)

        // エージェント削除
        try agentRepo.delete(agent.id)

        // セッションも削除されていること
        let found = try agentSessionRepo.findById(session.id)
        XCTAssertNil(found)
    }

    // MARK: - ExecutionLogRepository Tests (Phase 3-3)

    func testExecutionLogRepositorySaveAndFindById() throws {
        // Given
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        try projectRepo.save(project)
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)
        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task")
        try taskRepo.save(task)

        let log = ExecutionLog(taskId: task.id, agentId: agent.id)

        // When
        try executionLogRepo.save(log)
        let found = try executionLogRepo.findById(log.id)

        // Then
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, log.id)
        XCTAssertEqual(found?.taskId, task.id)
        XCTAssertEqual(found?.agentId, agent.id)
        XCTAssertEqual(found?.status, .running)
    }

    func testExecutionLogRepositoryFindByTaskId() throws {
        // Given
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        try projectRepo.save(project)
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)
        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task")
        try taskRepo.save(task)

        let log1 = ExecutionLog(taskId: task.id, agentId: agent.id)
        let log2 = ExecutionLog(taskId: task.id, agentId: agent.id)
        try executionLogRepo.save(log1)
        try executionLogRepo.save(log2)

        // When
        let logs = try executionLogRepo.findByTaskId(task.id)

        // Then
        XCTAssertEqual(logs.count, 2)
    }

    func testExecutionLogRepositoryFindByAgentId() throws {
        // Given
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        try projectRepo.save(project)
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)
        let task1 = Task(id: TaskID.generate(), projectId: project.id, title: "Task 1")
        let task2 = Task(id: TaskID.generate(), projectId: project.id, title: "Task 2")
        try taskRepo.save(task1)
        try taskRepo.save(task2)

        let log1 = ExecutionLog(taskId: task1.id, agentId: agent.id)
        let log2 = ExecutionLog(taskId: task2.id, agentId: agent.id)
        try executionLogRepo.save(log1)
        try executionLogRepo.save(log2)

        // When
        let logs = try executionLogRepo.findByAgentId(agent.id)

        // Then
        XCTAssertEqual(logs.count, 2)
    }

    func testExecutionLogRepositoryFindRunning() throws {
        // Given
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        try projectRepo.save(project)
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)
        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task")
        try taskRepo.save(task)

        var runningLog = ExecutionLog(taskId: task.id, agentId: agent.id)
        var completedLog = ExecutionLog(taskId: task.id, agentId: agent.id)
        completedLog.complete(exitCode: 0, durationSeconds: 60.0)

        try executionLogRepo.save(runningLog)
        try executionLogRepo.save(completedLog)

        // When
        let runningLogs = try executionLogRepo.findRunning(agentId: agent.id)

        // Then
        XCTAssertEqual(runningLogs.count, 1)
        XCTAssertEqual(runningLogs.first?.status, .running)
    }

    func testExecutionLogRepositoryUpdateStatus() throws {
        // Given
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        try projectRepo.save(project)
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)
        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task")
        try taskRepo.save(task)

        var log = ExecutionLog(taskId: task.id, agentId: agent.id)
        try executionLogRepo.save(log)

        // When
        log.complete(exitCode: 0, durationSeconds: 120.5, logFilePath: "/tmp/log.txt")
        try executionLogRepo.save(log)

        // Then
        let found = try executionLogRepo.findById(log.id)
        XCTAssertEqual(found?.status, .completed)
        XCTAssertEqual(found?.exitCode, 0)
        XCTAssertEqual(found?.durationSeconds, 120.5)
        XCTAssertEqual(found?.logFilePath, "/tmp/log.txt")
        XCTAssertNotNil(found?.completedAt)
    }

    func testExecutionLogRepositoryCascadeDeleteOnTaskDelete() throws {
        // Given
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        try projectRepo.save(project)
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)
        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task")
        try taskRepo.save(task)

        let log = ExecutionLog(taskId: task.id, agentId: agent.id)
        try executionLogRepo.save(log)

        // When - タスク削除
        try taskRepo.delete(task.id)

        // Then - 実行ログも削除されていること
        let found = try executionLogRepo.findById(log.id)
        XCTAssertNil(found)
    }

    func testExecutionLogRepositoryCascadeDeleteOnAgentDelete() throws {
        // Given
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        try projectRepo.save(project)
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)
        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task")
        try taskRepo.save(task)

        let log = ExecutionLog(taskId: task.id, agentId: agent.id)
        try executionLogRepo.save(log)

        // When - エージェント削除
        try agentRepo.delete(agent.id)

        // Then - 実行ログも削除されていること
        let found = try executionLogRepo.findById(log.id)
        XCTAssertNil(found)
    }

    func testExecutionLogsTableExists() throws {
        // execution_logs テーブルが存在することを確認
        try db.read { db in
            XCTAssertTrue(try db.tableExists("execution_logs"))
        }
    }

    // MARK: - ProjectAgentAssignmentRepository Tests (UC004: 複数プロジェクト×同一エージェント)
    // 参照: docs/requirements/PROJECTS.md - エージェント割り当て

    func testProjectAgentsTableExists() throws {
        // project_agents テーブルが存在することを確認
        try db.read { db in
            XCTAssertTrue(try db.tableExists("project_agents"))
        }
    }

    func testProjectAgentAssignmentRepositoryAssign() throws {
        // PRD: プロジェクトへのエージェント割り当て
        let project = Project(id: ProjectID.generate(), name: "TestProject", workingDirectory: "/tmp/test")
        try projectRepo.save(project)

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)

        // When: エージェントをプロジェクトに割り当て
        let assignment = try projectAgentAssignmentRepo.assign(projectId: project.id, agentId: agent.id)

        // Then: 割り当てが正しく保存される
        XCTAssertEqual(assignment.projectId, project.id)
        XCTAssertEqual(assignment.agentId, agent.id)
        XCTAssertNotNil(assignment.assignedAt)
    }

    func testProjectAgentAssignmentRepositoryFindByProject() throws {
        // PRD: プロジェクト別エージェント取得
        let project = Project(id: ProjectID.generate(), name: "TestProject", workingDirectory: "/tmp/test")
        try projectRepo.save(project)

        let agent1 = Agent(id: AgentID.generate(), name: "Agent1", role: "Developer")
        let agent2 = Agent(id: AgentID.generate(), name: "Agent2", role: "Designer")
        try agentRepo.save(agent1)
        try agentRepo.save(agent2)

        // 2つのエージェントを割り当て
        _ = try projectAgentAssignmentRepo.assign(projectId: project.id, agentId: agent1.id)
        _ = try projectAgentAssignmentRepo.assign(projectId: project.id, agentId: agent2.id)

        // When: プロジェクトに割り当てられたエージェントを取得
        let agents = try projectAgentAssignmentRepo.findAgentsByProject(project.id)

        // Then: 2つのエージェントが返される
        XCTAssertEqual(agents.count, 2)
        XCTAssertTrue(agents.contains { $0.id == agent1.id })
        XCTAssertTrue(agents.contains { $0.id == agent2.id })
    }

    func testProjectAgentAssignmentRepositoryFindByAgent() throws {
        // PRD: エージェント別プロジェクト取得（同一エージェントが複数プロジェクトに参加）
        let project1 = Project(id: ProjectID.generate(), name: "Project1", workingDirectory: "/tmp/test1")
        let project2 = Project(id: ProjectID.generate(), name: "Project2", workingDirectory: "/tmp/test2")
        try projectRepo.save(project1)
        try projectRepo.save(project2)

        let agent = Agent(id: AgentID.generate(), name: "SharedAgent", role: "Developer")
        try agentRepo.save(agent)

        // 同一エージェントを2つのプロジェクトに割り当て
        _ = try projectAgentAssignmentRepo.assign(projectId: project1.id, agentId: agent.id)
        _ = try projectAgentAssignmentRepo.assign(projectId: project2.id, agentId: agent.id)

        // When: エージェントが参加するプロジェクトを取得
        let projects = try projectAgentAssignmentRepo.findProjectsByAgent(agent.id)

        // Then: 2つのプロジェクトが返される
        XCTAssertEqual(projects.count, 2)
        XCTAssertTrue(projects.contains { $0.id == project1.id })
        XCTAssertTrue(projects.contains { $0.id == project2.id })
    }

    func testProjectAgentAssignmentRepositoryIsAssigned() throws {
        // PRD: 割り当て確認
        let project = Project(id: ProjectID.generate(), name: "TestProject", workingDirectory: "/tmp/test")
        try projectRepo.save(project)

        let assignedAgent = Agent(id: AgentID.generate(), name: "AssignedAgent", role: "Developer")
        let unassignedAgent = Agent(id: AgentID.generate(), name: "UnassignedAgent", role: "Designer")
        try agentRepo.save(assignedAgent)
        try agentRepo.save(unassignedAgent)

        // assignedAgentのみ割り当て
        _ = try projectAgentAssignmentRepo.assign(projectId: project.id, agentId: assignedAgent.id)

        // When/Then: 割り当て済みエージェントはtrue
        XCTAssertTrue(try projectAgentAssignmentRepo.isAgentAssignedToProject(agentId: assignedAgent.id, projectId: project.id))

        // When/Then: 未割り当てエージェントはfalse
        XCTAssertFalse(try projectAgentAssignmentRepo.isAgentAssignedToProject(agentId: unassignedAgent.id, projectId: project.id))
    }

    func testProjectAgentAssignmentRepositoryRemove() throws {
        // PRD: 割り当て解除
        let project = Project(id: ProjectID.generate(), name: "TestProject", workingDirectory: "/tmp/test")
        try projectRepo.save(project)

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)

        // 割り当て
        _ = try projectAgentAssignmentRepo.assign(projectId: project.id, agentId: agent.id)
        XCTAssertTrue(try projectAgentAssignmentRepo.isAgentAssignedToProject(agentId: agent.id, projectId: project.id))

        // When: 割り当て解除
        try projectAgentAssignmentRepo.remove(projectId: project.id, agentId: agent.id)

        // Then: 割り当てが解除される
        XCTAssertFalse(try projectAgentAssignmentRepo.isAgentAssignedToProject(agentId: agent.id, projectId: project.id))
    }

    func testProjectAgentAssignmentRepositoryDuplicateAssignment() throws {
        // PRD: 重複割り当ての防止（同じ組み合わせを2回割り当てても問題ない）
        let project = Project(id: ProjectID.generate(), name: "TestProject", workingDirectory: "/tmp/test")
        try projectRepo.save(project)

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)

        // 2回割り当て
        _ = try projectAgentAssignmentRepo.assign(projectId: project.id, agentId: agent.id)
        _ = try projectAgentAssignmentRepo.assign(projectId: project.id, agentId: agent.id)

        // Then: エージェントは1つのみ
        let agents = try projectAgentAssignmentRepo.findAgentsByProject(project.id)
        XCTAssertEqual(agents.count, 1)
    }

    func testProjectAgentAssignmentCascadeDeleteOnProjectDelete() throws {
        // PRD: プロジェクト削除時のカスケード削除
        let project = Project(id: ProjectID.generate(), name: "TestProject", workingDirectory: "/tmp/test")
        try projectRepo.save(project)

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)

        _ = try projectAgentAssignmentRepo.assign(projectId: project.id, agentId: agent.id)

        // When: プロジェクト削除
        try projectRepo.delete(project.id)

        // Then: 割り当ても削除される
        let projects = try projectAgentAssignmentRepo.findProjectsByAgent(agent.id)
        XCTAssertEqual(projects.count, 0)
    }

    func testProjectAgentAssignmentCascadeDeleteOnAgentDelete() throws {
        // PRD: エージェント削除時のカスケード削除
        let project = Project(id: ProjectID.generate(), name: "TestProject", workingDirectory: "/tmp/test")
        try projectRepo.save(project)

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        try agentRepo.save(agent)

        _ = try projectAgentAssignmentRepo.assign(projectId: project.id, agentId: agent.id)

        // When: エージェント削除
        try agentRepo.delete(agent.id)

        // Then: 割り当ても削除される
        let agents = try projectAgentAssignmentRepo.findAgentsByProject(project.id)
        XCTAssertEqual(agents.count, 0)
    }

    func testProjectAgentAssignmentRepositoryFindAllAssignments() throws {
        // PRD: 全割り当て取得（list_active_projects_with_agents用）
        let project1 = Project(id: ProjectID.generate(), name: "Project1", workingDirectory: "/tmp/test1")
        let project2 = Project(id: ProjectID.generate(), name: "Project2", workingDirectory: "/tmp/test2")
        try projectRepo.save(project1)
        try projectRepo.save(project2)

        let agent1 = Agent(id: AgentID.generate(), name: "Agent1", role: "Developer")
        let agent2 = Agent(id: AgentID.generate(), name: "Agent2", role: "Designer")
        try agentRepo.save(agent1)
        try agentRepo.save(agent2)

        // 割り当て
        _ = try projectAgentAssignmentRepo.assign(projectId: project1.id, agentId: agent1.id)
        _ = try projectAgentAssignmentRepo.assign(projectId: project1.id, agentId: agent2.id)
        _ = try projectAgentAssignmentRepo.assign(projectId: project2.id, agentId: agent1.id)

        // When: 全割り当てを取得
        let assignments = try projectAgentAssignmentRepo.findAll()

        // Then: 3つの割り当てが返される
        XCTAssertEqual(assignments.count, 3)
    }

}
