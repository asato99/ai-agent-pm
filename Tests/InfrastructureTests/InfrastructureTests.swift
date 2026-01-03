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

}
