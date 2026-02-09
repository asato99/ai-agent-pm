// Tests/UseCaseTests/AuditUseCaseTests.swift
// Internal Audit UseCase tests extracted from UseCaseTests.swift
// 参照: docs/requirements/AUDIT.md

import XCTest
@testable import UseCase
@testable import Domain

// MARK: - Audit UseCase Tests

final class AuditUseCaseTests: XCTestCase {

    var projectRepo: MockProjectRepository!
    var agentRepo: MockAgentRepository!
    var taskRepo: MockTaskRepository!
    var eventRepo: MockEventRepository!
    var internalAuditRepo: MockInternalAuditRepository!
    var auditRuleRepo: MockAuditRuleRepository!

    override func setUp() {
        projectRepo = MockProjectRepository()
        agentRepo = MockAgentRepository()
        taskRepo = MockTaskRepository()
        eventRepo = MockEventRepository()
        internalAuditRepo = MockInternalAuditRepository()
        auditRuleRepo = MockAuditRuleRepository()
    }

    // MARK: - Internal Audit CRUD Tests (参照: AUDIT.md)

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

    // MARK: - Audit Rule Tests (参照: AUDIT.md)
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
}
