// Tests/DomainTests/DomainTests.swift
// PRD仕様に基づくDomain層テスト

import XCTest
@testable import Domain

final class DomainTests: XCTestCase {

    // MARK: - ID Generation Tests (PRD: AGENT_CONCEPT.md - Agent ID)

    func testAgentIDGeneration() {
        // PRD: 形式: agt_[ランダム12文字]
        let id = AgentID.generate()
        XCTAssertTrue(id.value.hasPrefix("agt_"), "Agent ID must start with 'agt_'")
        XCTAssertGreaterThan(id.value.count, 4, "Agent ID must have characters after prefix")
    }

    func testTaskIDGeneration() {
        let id = TaskID.generate()
        XCTAssertTrue(id.value.hasPrefix("tsk_"), "Task ID must start with 'tsk_'")
    }

    func testProjectIDGeneration() {
        let id = ProjectID.generate()
        XCTAssertTrue(id.value.hasPrefix("prj_"), "Project ID must start with 'prj_'")
    }

    func testSessionIDGeneration() {
        // PRD: ses_xxx
        let id = SessionID.generate()
        XCTAssertTrue(id.value.hasPrefix("ses_"), "Session ID must start with 'ses_'")
    }

    func testEventIDGeneration() {
        // PRD: evt_xxx
        let id = EventID.generate()
        XCTAssertTrue(id.value.hasPrefix("evt_"), "Event ID must start with 'evt_'")
    }

    func testContextIDGeneration() {
        let id = ContextID.generate()
        XCTAssertTrue(id.value.hasPrefix("ctx_"), "Context ID must start with 'ctx_'")
    }

    func testHandoffIDGeneration() {
        let id = HandoffID.generate()
        XCTAssertTrue(id.value.hasPrefix("hnd_"), "Handoff ID must start with 'hnd_'")
    }

    // MARK: - Agent Tests (PRD: AGENT_CONCEPT.md)

    func testAgentCreation() {
        // PRD: Agent { id, name, role, type, roleType, capabilities, systemPrompt, status }
        let agent = Agent(
            id: AgentID.generate(),
            name: "frontend-dev",
            role: "フロントエンド開発担当",
            type: .ai
        )

        XCTAssertEqual(agent.name, "frontend-dev")
        XCTAssertEqual(agent.role, "フロントエンド開発担当")
        XCTAssertEqual(agent.type, AgentType.ai)
        XCTAssertEqual(agent.status, AgentStatus.active, "New agent should be active by default")
    }

    func testAgentTypes() {
        // PRD: AIエージェント (.ai) / 人間エージェント (.human)
        XCTAssertEqual(AgentType.ai.rawValue, "ai")
        XCTAssertEqual(AgentType.human.rawValue, "human")
    }

    func testAgentStatus() {
        // PRD: Active / Inactive / Archived
        XCTAssertEqual(AgentStatus.active.rawValue, "active")
        XCTAssertEqual(AgentStatus.inactive.rawValue, "inactive")
        XCTAssertEqual(AgentStatus.archived.rawValue, "archived")
    }

    // MARK: - Task Tests (PRD: TASK_MANAGEMENT.md)

    func testTaskCreation() {
        // PRD: Task { id, projectId, title, description, status, priority, assigneeId, dependencies }
        let task = Task(
            id: TaskID.generate(),
            projectId: ProjectID.generate(),
            title: "API実装"
        )

        XCTAssertEqual(task.title, "API実装")
        XCTAssertEqual(task.status, .backlog, "New task should be in backlog by default")
        XCTAssertEqual(task.priority, .medium, "New task should have medium priority by default")
        XCTAssertNil(task.assigneeId, "New task should be unassigned")
        XCTAssertFalse(task.isCompleted, "New task should not be completed")
    }

    func testTaskStatusValues() {
        // 要件: TaskStatus { backlog, todo, inProgress, blocked, done, cancelled }
        XCTAssertEqual(TaskStatus.backlog.rawValue, "backlog")
        XCTAssertEqual(TaskStatus.todo.rawValue, "todo")
        XCTAssertEqual(TaskStatus.inProgress.rawValue, "in_progress")
        XCTAssertEqual(TaskStatus.blocked.rawValue, "blocked")
        XCTAssertEqual(TaskStatus.done.rawValue, "done")
        XCTAssertEqual(TaskStatus.cancelled.rawValue, "cancelled")
    }

    func testTaskStatusIsActive() {
        // 要件: inProgress のみが「アクティブ」な状態
        XCTAssertTrue(TaskStatus.inProgress.isActive)
        XCTAssertFalse(TaskStatus.todo.isActive)
        XCTAssertFalse(TaskStatus.backlog.isActive)
        XCTAssertFalse(TaskStatus.done.isActive)
        XCTAssertFalse(TaskStatus.blocked.isActive)
        XCTAssertFalse(TaskStatus.cancelled.isActive)
    }

    func testTaskStatusIsCompleted() {
        // PRD: done と cancelled は「完了」状態
        XCTAssertTrue(TaskStatus.done.isCompleted)
        XCTAssertTrue(TaskStatus.cancelled.isCompleted)
        XCTAssertFalse(TaskStatus.inProgress.isCompleted)
        XCTAssertFalse(TaskStatus.todo.isCompleted)
        XCTAssertFalse(TaskStatus.blocked.isCompleted)
    }

    func testTaskPriorityValues() {
        // PRD: Priority { low, medium, high, urgent }
        XCTAssertEqual(TaskPriority.low.rawValue, "low")
        XCTAssertEqual(TaskPriority.medium.rawValue, "medium")
        XCTAssertEqual(TaskPriority.high.rawValue, "high")
        XCTAssertEqual(TaskPriority.urgent.rawValue, "urgent")
    }

    func testTaskIsCompletedProperty() {
        // PRD: タスクが完了状態かどうか
        var task = Task(
            id: TaskID.generate(),
            projectId: ProjectID.generate(),
            title: "Test"
        )

        task.status = .done
        XCTAssertTrue(task.isCompleted)

        task.status = .cancelled
        XCTAssertTrue(task.isCompleted)

        task.status = .inProgress
        XCTAssertFalse(task.isCompleted)
    }

    // MARK: - Project Tests (PRD: UI 01_project_list.md)

    func testProjectCreation() {
        let project = Project(
            id: ProjectID.generate(),
            name: "ECサイト開発",
            description: "ECサイトの開発プロジェクト"
        )

        XCTAssertEqual(project.name, "ECサイト開発")
        XCTAssertEqual(project.description, "ECサイトの開発プロジェクト")
        XCTAssertEqual(project.status, .active, "New project should be active by default")
    }

    func testProjectStatusValues() {
        // 要件: Active / Archived のみ（Completed は削除）
        XCTAssertEqual(ProjectStatus.active.rawValue, "active")
        XCTAssertEqual(ProjectStatus.archived.rawValue, "archived")
    }

    // MARK: - Session Tests (PRD: AGENT_CONCEPT.md - Session)

    func testSessionCreation() {
        // PRD: Session { id, agentId, toolType, status, startedAt, endedAt, summary }
        let session = Session(
            id: SessionID.generate(),
            projectId: ProjectID.generate(),
            agentId: AgentID.generate()
        )

        XCTAssertEqual(session.status, .active, "New session should be active")
        XCTAssertNil(session.endedAt, "New session should not have end time")
    }

    func testSessionIsActive() {
        let session = Session(
            id: SessionID.generate(),
            projectId: ProjectID.generate(),
            agentId: AgentID.generate(),
            status: .active
        )

        XCTAssertTrue(session.isActive)
    }

    func testSessionDuration() {
        // PRD: セッションの継続時間
        let startTime = Date().addingTimeInterval(-3600) // 1 hour ago
        let session = Session(
            id: SessionID.generate(),
            projectId: ProjectID.generate(),
            agentId: AgentID.generate(),
            startedAt: startTime
        )

        let duration = session.duration
        XCTAssertNotNil(duration)
        XCTAssertGreaterThanOrEqual(duration!, 3599) // ~1 hour, allowing for small timing variance
    }

    func testSessionStatusValues() {
        // PRD: active / completed / abandoned
        XCTAssertEqual(SessionStatus.active.rawValue, "active")
        XCTAssertEqual(SessionStatus.completed.rawValue, "completed")
        XCTAssertEqual(SessionStatus.abandoned.rawValue, "abandoned")
    }

    // MARK: - Context Tests (PRD: AGENT_CONCEPT.md - コンテキスト)

    func testContextCreation() {
        // PRD: Context { id, taskId, agentId, sessionId, content, type }
        let context = Context(
            id: ContextID.generate(),
            taskId: TaskID.generate(),
            sessionId: SessionID.generate(),
            agentId: AgentID.generate(),
            progress: "JWT認証を採用、有効期限1時間",
            findings: "Rate limit: 100 req/min"
        )

        XCTAssertEqual(context.progress, "JWT認証を採用、有効期限1時間")
        XCTAssertEqual(context.findings, "Rate limit: 100 req/min")
    }

    func testContextIsEmpty() {
        // PRD: コンテキストが空かどうか
        let emptyContext = Context(
            id: ContextID.generate(),
            taskId: TaskID.generate(),
            sessionId: SessionID.generate(),
            agentId: AgentID.generate()
        )

        XCTAssertTrue(emptyContext.isEmpty)

        let nonEmptyContext = Context(
            id: ContextID.generate(),
            taskId: TaskID.generate(),
            sessionId: SessionID.generate(),
            agentId: AgentID.generate(),
            progress: "Some progress"
        )

        XCTAssertFalse(nonEmptyContext.isEmpty)
    }

    func testContextHasBlockers() {
        // PRD: ブロッカーがあるかどうか
        let contextWithBlocker = Context(
            id: ContextID.generate(),
            taskId: TaskID.generate(),
            sessionId: SessionID.generate(),
            agentId: AgentID.generate(),
            blockers: "Waiting for API design"
        )

        XCTAssertTrue(contextWithBlocker.hasBlockers)

        let contextWithoutBlocker = Context(
            id: ContextID.generate(),
            taskId: TaskID.generate(),
            sessionId: SessionID.generate(),
            agentId: AgentID.generate()
        )

        XCTAssertFalse(contextWithoutBlocker.hasBlockers)
    }

    // MARK: - Handoff Tests (PRD: AGENT_CONCEPT.md - ハンドオフ)

    func testHandoffCreation() {
        // PRD: Handoff { id, taskId, fromAgentId, toAgentId, summary, context, recommendations }
        let handoff = Handoff(
            id: HandoffID.generate(),
            taskId: TaskID.generate(),
            fromAgentId: AgentID.generate(),
            toAgentId: AgentID.generate(),
            summary: "API仕様の確認お願いします"
        )

        XCTAssertEqual(handoff.summary, "API仕様の確認お願いします")
        XCTAssertNil(handoff.acceptedAt, "New handoff should not be accepted")
    }

    func testHandoffIsAccepted() {
        // PRD: ハンドオフが承認済みかどうか
        var handoff = Handoff(
            id: HandoffID.generate(),
            taskId: TaskID.generate(),
            fromAgentId: AgentID.generate(),
            summary: "Test handoff"
        )

        XCTAssertFalse(handoff.isAccepted)

        handoff.acceptedAt = Date()

        XCTAssertTrue(handoff.isAccepted)
    }

    func testHandoffIsTargeted() {
        // PRD: ハンドオフが特定のエージェント宛かどうか
        let targetedHandoff = Handoff(
            id: HandoffID.generate(),
            taskId: TaskID.generate(),
            fromAgentId: AgentID.generate(),
            toAgentId: AgentID.generate(),
            summary: "Test"
        )

        XCTAssertTrue(targetedHandoff.isTargeted)

        let untargetedHandoff = Handoff(
            id: HandoffID.generate(),
            taskId: TaskID.generate(),
            fromAgentId: AgentID.generate(),
            toAgentId: nil,
            summary: "Test"
        )

        XCTAssertFalse(untargetedHandoff.isTargeted)
    }

    func testHandoffIsPending() {
        // PRD: ハンドオフが保留中かどうか
        let pendingHandoff = Handoff(
            id: HandoffID.generate(),
            taskId: TaskID.generate(),
            fromAgentId: AgentID.generate(),
            summary: "Test"
        )

        XCTAssertTrue(pendingHandoff.isPending)
    }

    // MARK: - StateChangeEvent Tests (PRD: STATE_HISTORY.md)

    func testStateChangeEventCreation() {
        // PRD: StateChangeEvent { id, entityType, entityId, eventType, changes, actorId, sessionId, reason, metadata, timestamp }
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: ProjectID.generate(),
            entityType: .task,
            entityId: "tsk_xyz789",
            eventType: .statusChanged,
            agentId: AgentID.generate(),
            previousState: "todo",
            newState: "in_progress",
            reason: "開始しました"
        )

        XCTAssertEqual(event.entityType, .task)
        XCTAssertEqual(event.eventType, .statusChanged)
        XCTAssertEqual(event.previousState, "todo")
        XCTAssertEqual(event.newState, "in_progress")
    }

    func testEntityTypeValues() {
        // PRD: EntityType { project, task, agent, session, handoff, context }
        XCTAssertEqual(EntityType.project.rawValue, "project")
        XCTAssertEqual(EntityType.task.rawValue, "task")
        XCTAssertEqual(EntityType.agent.rawValue, "agent")
        XCTAssertEqual(EntityType.session.rawValue, "session")
        XCTAssertEqual(EntityType.handoff.rawValue, "handoff")
        XCTAssertEqual(EntityType.context.rawValue, "context")
    }

    func testEventTypeValues() {
        // PRD: EventType { created, updated, deleted, statusChanged, assigned, unassigned, etc. }
        XCTAssertEqual(EventType.created.rawValue, "created")
        XCTAssertEqual(EventType.updated.rawValue, "updated")
        XCTAssertEqual(EventType.deleted.rawValue, "deleted")
        XCTAssertEqual(EventType.statusChanged.rawValue, "status_changed")
        XCTAssertEqual(EventType.assigned.rawValue, "assigned")
        XCTAssertEqual(EventType.unassigned.rawValue, "unassigned")
        XCTAssertEqual(EventType.started.rawValue, "started")
        XCTAssertEqual(EventType.completed.rawValue, "completed")
    }

    // MARK: - Display Name Tests (PRD UI仕様)

    func testTaskStatusDisplayNames() {
        // 要件: ステータスの表示名（inReview削除済み）
        XCTAssertFalse(TaskStatus.backlog.displayName.isEmpty)
        XCTAssertFalse(TaskStatus.todo.displayName.isEmpty)
        XCTAssertFalse(TaskStatus.inProgress.displayName.isEmpty)
        XCTAssertFalse(TaskStatus.blocked.displayName.isEmpty)
        XCTAssertFalse(TaskStatus.done.displayName.isEmpty)
        XCTAssertFalse(TaskStatus.cancelled.displayName.isEmpty)
    }

    func testTaskPriorityDisplayNames() {
        // PRD UI: 優先度の表示名
        XCTAssertFalse(TaskPriority.low.displayName.isEmpty)
        XCTAssertFalse(TaskPriority.medium.displayName.isEmpty)
        XCTAssertFalse(TaskPriority.high.displayName.isEmpty)
        XCTAssertFalse(TaskPriority.urgent.displayName.isEmpty)
    }

    func testProjectStatusDisplayNames() {
        // 要件: completed削除済み
        XCTAssertFalse(ProjectStatus.active.displayName.isEmpty)
        XCTAssertFalse(ProjectStatus.archived.displayName.isEmpty)
    }

    func testSessionStatusDisplayNames() {
        XCTAssertFalse(SessionStatus.active.displayName.isEmpty)
        XCTAssertFalse(SessionStatus.completed.displayName.isEmpty)
        XCTAssertFalse(SessionStatus.abandoned.displayName.isEmpty)
    }

    func testEntityTypeDisplayNames() {
        XCTAssertFalse(EntityType.project.displayName.isEmpty)
        XCTAssertFalse(EntityType.task.displayName.isEmpty)
        XCTAssertFalse(EntityType.agent.displayName.isEmpty)
    }

    func testEventTypeDisplayNames() {
        XCTAssertFalse(EventType.created.displayName.isEmpty)
        XCTAssertFalse(EventType.updated.displayName.isEmpty)
        XCTAssertFalse(EventType.statusChanged.displayName.isEmpty)
    }

    // MARK: - WorkflowTemplate ID Tests

    func testWorkflowTemplateIDGeneration() {
        let id = WorkflowTemplateID.generate()
        XCTAssertTrue(id.value.hasPrefix("wft_"), "WorkflowTemplate ID must start with 'wft_'")
        XCTAssertGreaterThan(id.value.count, 4, "WorkflowTemplate ID must have characters after prefix")
    }

    func testTemplateTaskIDGeneration() {
        let id = TemplateTaskID.generate()
        XCTAssertTrue(id.value.hasPrefix("ttk_"), "TemplateTask ID must start with 'ttk_'")
    }

    // MARK: - WorkflowTemplate Tests (要件: WORKFLOW_TEMPLATES.md)

    func testWorkflowTemplateCreation() {
        // 要件: WorkflowTemplate はプロジェクトに紐づく
        let projectId = ProjectID.generate()
        let template = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: projectId,
            name: "機能開発フロー",
            description: "標準的な機能開発のワークフロー",
            variables: ["feature_name", "module"]
        )

        XCTAssertEqual(template.name, "機能開発フロー")
        XCTAssertEqual(template.description, "標準的な機能開発のワークフロー")
        XCTAssertEqual(template.projectId, projectId)
        XCTAssertEqual(template.variables.count, 2)
        XCTAssertEqual(template.status, .active, "New template should be active by default")
        XCTAssertTrue(template.isActive)
    }

    func testTemplateStatusValues() {
        // 要件: active / archived
        XCTAssertEqual(TemplateStatus.active.rawValue, "active")
        XCTAssertEqual(TemplateStatus.archived.rawValue, "archived")
    }

    func testTemplateIsActive() {
        var template = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: ProjectID.generate(),
            name: "Test"
        )

        XCTAssertTrue(template.isActive)

        template.status = .archived
        XCTAssertFalse(template.isActive)
    }

    func testValidVariableNames() {
        // 要件: 英字またはアンダースコアで始まり、英数字とアンダースコアのみ
        XCTAssertTrue(WorkflowTemplate.isValidVariableName("feature_name"))
        XCTAssertTrue(WorkflowTemplate.isValidVariableName("module"))
        XCTAssertTrue(WorkflowTemplate.isValidVariableName("_private"))
        XCTAssertTrue(WorkflowTemplate.isValidVariableName("Feature123"))
        XCTAssertTrue(WorkflowTemplate.isValidVariableName("A"))

        // 無効な変数名
        XCTAssertFalse(WorkflowTemplate.isValidVariableName("123invalid"))
        XCTAssertFalse(WorkflowTemplate.isValidVariableName("has-dash"))
        XCTAssertFalse(WorkflowTemplate.isValidVariableName("has space"))
        XCTAssertFalse(WorkflowTemplate.isValidVariableName(""))
    }

    func testTemplateHasValidVariables() {
        let validTemplate = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: ProjectID.generate(),
            name: "Test",
            variables: ["feature_name", "module_name"]
        )
        XCTAssertTrue(validTemplate.hasValidVariables)

        let invalidTemplate = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: ProjectID.generate(),
            name: "Test",
            variables: ["feature-name", "123invalid"]
        )
        XCTAssertFalse(invalidTemplate.hasValidVariables)

        let emptyVariablesTemplate = WorkflowTemplate(
            id: WorkflowTemplateID.generate(),
            projectId: ProjectID.generate(),
            name: "Test",
            variables: []
        )
        XCTAssertTrue(emptyVariablesTemplate.hasValidVariables)
    }

    // MARK: - TemplateTask Tests

    func testTemplateTaskCreation() {
        let templateId = WorkflowTemplateID.generate()
        let task = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: templateId,
            title: "{{feature_name}} - 要件確認",
            description: "{{module}}の要件を確認する",
            order: 1,
            dependsOnOrders: [],
            defaultPriority: .high,
            estimatedMinutes: 60
        )

        XCTAssertEqual(task.title, "{{feature_name}} - 要件確認")
        XCTAssertEqual(task.order, 1)
        XCTAssertEqual(task.defaultPriority, .high)
        XCTAssertEqual(task.estimatedMinutes, 60)
        XCTAssertTrue(task.dependsOnOrders.isEmpty)
    }

    func testTemplateTaskDependencies() {
        let templateId = WorkflowTemplateID.generate()

        // 正常な依存関係
        let validTask = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: templateId,
            title: "実装",
            order: 2,
            dependsOnOrders: [1]
        )
        XCTAssertTrue(validTask.hasValidDependencies)

        // 自己参照は無効
        let selfReferenceTask = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: templateId,
            title: "実装",
            order: 2,
            dependsOnOrders: [2]
        )
        XCTAssertFalse(selfReferenceTask.hasValidDependencies)
    }

    func testTemplateTaskVariableResolution() {
        let templateId = WorkflowTemplateID.generate()
        let task = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: templateId,
            title: "{{feature_name}} - 要件確認",
            description: "{{module}}モジュールの{{feature_name}}について要件を確認する",
            order: 1
        )

        let values = ["feature_name": "ログイン機能", "module": "認証"]

        let resolvedTitle = task.resolveTitle(with: values)
        XCTAssertEqual(resolvedTitle, "ログイン機能 - 要件確認")

        let resolvedDescription = task.resolveDescription(with: values)
        XCTAssertEqual(resolvedDescription, "認証モジュールのログイン機能について要件を確認する")
    }

    func testTemplateTaskVariableResolutionWithMissingValues() {
        let templateId = WorkflowTemplateID.generate()
        let task = TemplateTask(
            id: TemplateTaskID.generate(),
            templateId: templateId,
            title: "{{feature_name}} - {{step}}",
            order: 1
        )

        // 一部の変数のみ提供
        let values = ["feature_name": "ログイン"]
        let resolvedTitle = task.resolveTitle(with: values)

        // 未置換の変数はそのまま残る
        XCTAssertEqual(resolvedTitle, "ログイン - {{step}}")
    }

    // MARK: - InstantiationResult Tests

    func testInstantiationResultCreation() {
        let templateId = WorkflowTemplateID.generate()
        let projectId = ProjectID.generate()
        let tasks = [
            Task(id: TaskID.generate(), projectId: projectId, title: "Task 1"),
            Task(id: TaskID.generate(), projectId: projectId, title: "Task 2")
        ]

        let result = InstantiationResult(
            templateId: templateId,
            projectId: projectId,
            createdTasks: tasks
        )

        XCTAssertEqual(result.taskCount, 2)
        XCTAssertEqual(result.createdTasks.count, 2)
    }

    // MARK: - Internal Audit ID Tests (要件: AUDIT.md)

    func testInternalAuditIDGeneration() {
        // 要件: aud_[ランダム文字列]
        let id = InternalAuditID.generate()
        XCTAssertTrue(id.value.hasPrefix("aud_"), "Internal Audit ID must start with 'aud_'")
        XCTAssertGreaterThan(id.value.count, 4, "Internal Audit ID must have characters after prefix")
    }

    func testAuditRuleIDGeneration() {
        // 要件: arl_[ランダム文字列]
        let id = AuditRuleID.generate()
        XCTAssertTrue(id.value.hasPrefix("arl_"), "Audit Rule ID must start with 'arl_'")
        XCTAssertGreaterThan(id.value.count, 4, "Audit Rule ID must have characters after prefix")
    }

    // MARK: - Internal Audit Tests (要件: AUDIT.md)

    func testInternalAuditCreation() {
        // 要件: InternalAudit { id, name, description, status, createdAt, updatedAt }
        let audit = InternalAudit(
            id: InternalAuditID.generate(),
            name: "QA Audit",
            description: "品質監査"
        )

        XCTAssertEqual(audit.name, "QA Audit")
        XCTAssertEqual(audit.description, "品質監査")
        XCTAssertEqual(audit.status, .active, "New Internal Audit should be active by default")
    }

    func testAuditStatusValues() {
        // 要件: active / inactive / suspended
        XCTAssertEqual(AuditStatus.active.rawValue, "active")
        XCTAssertEqual(AuditStatus.inactive.rawValue, "inactive")
        XCTAssertEqual(AuditStatus.suspended.rawValue, "suspended")
    }

    func testAuditStatusDisplayNames() {
        XCTAssertFalse(AuditStatus.active.displayName.isEmpty)
        XCTAssertFalse(AuditStatus.inactive.displayName.isEmpty)
        XCTAssertFalse(AuditStatus.suspended.displayName.isEmpty)
    }

    func testInternalAuditIsActive() {
        var audit = InternalAudit(
            id: InternalAuditID.generate(),
            name: "Test Audit"
        )

        XCTAssertTrue(audit.isActive)

        audit.status = .inactive
        XCTAssertFalse(audit.isActive)

        audit.status = .suspended
        XCTAssertFalse(audit.isActive)
    }

    // MARK: - Trigger Type Tests (要件: AUDIT.md)

    func testTriggerTypeValues() {
        // 要件: task_completed, status_changed, handoff_completed, deadline_exceeded
        XCTAssertEqual(TriggerType.taskCompleted.rawValue, "task_completed")
        XCTAssertEqual(TriggerType.statusChanged.rawValue, "status_changed")
        XCTAssertEqual(TriggerType.handoffCompleted.rawValue, "handoff_completed")
        XCTAssertEqual(TriggerType.deadlineExceeded.rawValue, "deadline_exceeded")
    }

    func testTriggerTypeDisplayNames() {
        XCTAssertFalse(TriggerType.taskCompleted.displayName.isEmpty)
        XCTAssertFalse(TriggerType.statusChanged.displayName.isEmpty)
        XCTAssertFalse(TriggerType.handoffCompleted.displayName.isEmpty)
        XCTAssertFalse(TriggerType.deadlineExceeded.displayName.isEmpty)
    }

    // MARK: - Audit Rule Tests (要件: AUDIT.md)

    func testAuditRuleCreation() {
        // 要件: AuditRule { id, auditId, name, triggerType, triggerConfig, auditTasks, isEnabled }
        // 設計方針: WorkflowTemplateはプロジェクトスコープのため、
        // プロジェクト横断で動作するInternal Auditはタスク定義をインラインで保持
        let auditId = InternalAuditID.generate()

        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: auditId,
            name: "タスク完了時チェック",
            triggerType: .taskCompleted,
            auditTasks: []
        )

        XCTAssertEqual(rule.name, "タスク完了時チェック")
        XCTAssertEqual(rule.triggerType, .taskCompleted)
        XCTAssertEqual(rule.auditId, auditId)
        XCTAssertTrue(rule.isEnabled, "New Audit Rule should be enabled by default")
        XCTAssertTrue(rule.auditTasks.isEmpty)
    }

    func testAuditRuleWithAuditTasks() {
        // 要件: AuditRule内で監査タスクをインライン定義
        let auditId = InternalAuditID.generate()
        let agentId1 = AgentID.generate()
        let agentId2 = AgentID.generate()

        let auditTasks = [
            AuditTask(order: 1, title: "要件確認", description: "要件を確認する", assigneeId: agentId1, priority: .high),
            AuditTask(order: 2, title: "実装レビュー", description: "実装をレビューする", assigneeId: agentId2, priority: .medium, dependsOnOrders: [1])
        ]

        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: auditId,
            name: "レビューフロー",
            triggerType: .statusChanged,
            auditTasks: auditTasks
        )

        XCTAssertEqual(rule.auditTasks.count, 2)
        XCTAssertEqual(rule.auditTasks[0].order, 1)
        XCTAssertEqual(rule.auditTasks[0].title, "要件確認")
        XCTAssertEqual(rule.auditTasks[0].assigneeId, agentId1)
        XCTAssertEqual(rule.auditTasks[1].order, 2)
        XCTAssertEqual(rule.auditTasks[1].title, "実装レビュー")
        XCTAssertEqual(rule.auditTasks[1].assigneeId, agentId2)
        XCTAssertEqual(rule.auditTasks[1].dependsOnOrders, [1])
    }

    func testAuditRuleToggleEnabled() {
        var rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: InternalAuditID.generate(),
            name: "Test Rule",
            triggerType: .taskCompleted,
            auditTasks: []
        )

        XCTAssertTrue(rule.isEnabled)

        rule.isEnabled = false
        XCTAssertFalse(rule.isEnabled)
    }

    func testAuditRuleTriggerConfig() {
        // 要件: triggerConfig は追加設定用のJSON（オプショナル）
        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: InternalAuditID.generate(),
            name: "ステータス変更チェック",
            triggerType: .statusChanged,
            triggerConfig: ["fromStatus": "todo", "toStatus": "in_progress"],
            auditTasks: []
        )

        XCTAssertNotNil(rule.triggerConfig)
        XCTAssertEqual(rule.triggerConfig?["fromStatus"] as? String, "todo")
        XCTAssertEqual(rule.triggerConfig?["toStatus"] as? String, "in_progress")
    }

    // MARK: - AuditTask Tests (要件: AUDIT.md)

    func testAuditTaskCreation() {
        // 要件: AuditTask { order, title, description, assigneeId, priority, dependsOnOrders }
        let agentId = AgentID.generate()
        let task = AuditTask(
            order: 1,
            title: "品質チェック",
            description: "品質基準を満たしているか確認",
            assigneeId: agentId,
            priority: .high
        )

        XCTAssertEqual(task.order, 1)
        XCTAssertEqual(task.title, "品質チェック")
        XCTAssertEqual(task.description, "品質基準を満たしているか確認")
        XCTAssertEqual(task.assigneeId, agentId)
        XCTAssertEqual(task.priority, .high)
        XCTAssertTrue(task.dependsOnOrders.isEmpty)
    }

    func testAuditTaskEquality() {
        let agentId = AgentID.generate()
        let task1 = AuditTask(order: 1, title: "Test", assigneeId: agentId)
        let task2 = AuditTask(order: 1, title: "Test", assigneeId: agentId)

        XCTAssertEqual(task1, task2)
    }

    func testAuditTaskValidDependencies() {
        // 要件: 自己参照は無効
        let agentId = AgentID.generate()

        // 正常な依存関係
        let validTask = AuditTask(
            order: 2,
            title: "後続タスク",
            assigneeId: agentId,
            dependsOnOrders: [1]
        )
        XCTAssertTrue(validTask.hasValidDependencies)

        // 自己参照は無効
        let selfReferenceTask = AuditTask(
            order: 2,
            title: "自己参照タスク",
            assigneeId: agentId,
            dependsOnOrders: [2]
        )
        XCTAssertFalse(selfReferenceTask.hasValidDependencies)
    }

    func testAuditRuleHasTasks() {
        // 要件: 監査タスクがあるかどうかチェック
        let agentId = AgentID.generate()

        // タスクあり
        let ruleWithTasks = AuditRule(
            id: AuditRuleID.generate(),
            auditId: InternalAuditID.generate(),
            name: "Test",
            triggerType: .taskCompleted,
            auditTasks: [AuditTask(order: 1, title: "確認", assigneeId: agentId)]
        )
        XCTAssertTrue(ruleWithTasks.hasTasks)

        // タスクなし
        let ruleWithoutTasks = AuditRule(
            id: AuditRuleID.generate(),
            auditId: InternalAuditID.generate(),
            name: "Test",
            triggerType: .taskCompleted,
            auditTasks: []
        )
        XCTAssertFalse(ruleWithoutTasks.hasTasks)
    }

    // MARK: - AgentCredential Tests (Phase 3-1: 認証基盤)
    // 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md

    func testAgentCredentialIDGeneration() {
        let id = AgentCredentialID.generate()
        XCTAssertTrue(id.value.hasPrefix("crd_"), "AgentCredential ID must start with 'crd_'")
    }

    func testAgentSessionIDGeneration() {
        let id = AgentSessionID.generate()
        XCTAssertTrue(id.value.hasPrefix("asn_"), "AgentSession ID must start with 'asn_'")
    }

    func testAgentCredentialCreation_HashesPasskey() {
        // Given
        let agentId = AgentID(value: "agt_test")
        let rawPasskey = "secret123"

        // When
        let credential = AgentCredential(
            agentId: agentId,
            rawPasskey: rawPasskey
        )

        // Then
        XCTAssertNotEqual(credential.passkeyHash, rawPasskey, "Passkey should be hashed")
        XCTAssertFalse(credential.passkeyHash.isEmpty, "Hash should not be empty")
        XCTAssertFalse(credential.salt.isEmpty, "Salt should not be empty")
    }

    func testAgentCredentialVerify_WithCorrectPasskey_ReturnsTrue() {
        // Given
        let credential = AgentCredential(
            agentId: AgentID(value: "agt_test"),
            rawPasskey: "secret123"
        )

        // When
        let result = credential.verify(passkey: "secret123")

        // Then
        XCTAssertTrue(result, "Should verify correct passkey")
    }

    func testAgentCredentialVerify_WithWrongPasskey_ReturnsFalse() {
        // Given
        let credential = AgentCredential(
            agentId: AgentID(value: "agt_test"),
            rawPasskey: "secret123"
        )

        // When
        let result = credential.verify(passkey: "wrongpassword")

        // Then
        XCTAssertFalse(result, "Should not verify wrong passkey")
    }

    func testAgentCredentialVerify_WithEmptyPasskey_ReturnsFalse() {
        // Given
        let credential = AgentCredential(
            agentId: AgentID(value: "agt_test"),
            rawPasskey: "secret123"
        )

        // When
        let result = credential.verify(passkey: "")

        // Then
        XCTAssertFalse(result, "Should not verify empty passkey")
    }

    func testAgentCredential_DifferentCredentialsHaveDifferentSalts() {
        // Given
        let agentId = AgentID(value: "agt_test")
        let passkey = "secret123"

        // When
        let credential1 = AgentCredential(agentId: agentId, rawPasskey: passkey)
        let credential2 = AgentCredential(agentId: agentId, rawPasskey: passkey)

        // Then
        XCTAssertNotEqual(credential1.salt, credential2.salt, "Different credentials should have different salts")
        XCTAssertNotEqual(credential1.passkeyHash, credential2.passkeyHash, "Different salts should produce different hashes")
    }

    func testAgentCredentialWithLastUsedAt() {
        // Given
        let credential = AgentCredential(
            agentId: AgentID(value: "agt_test"),
            rawPasskey: "secret123"
        )
        let now = Date()

        // When
        let updated = credential.withLastUsedAt(now)

        // Then
        XCTAssertEqual(updated.lastUsedAt, now)
        XCTAssertEqual(updated.id, credential.id)
        XCTAssertEqual(updated.agentId, credential.agentId)
        XCTAssertEqual(updated.passkeyHash, credential.passkeyHash)
    }

    // MARK: - AgentSession Tests (Phase 3-1: 認証基盤)

    func testAgentSessionCreation_GeneratesUniqueToken() {
        // Given/When
        let session1 = AgentSession(agentId: AgentID(value: "agt_1"), projectId: ProjectID(value: "prj_1"))
        let session2 = AgentSession(agentId: AgentID(value: "agt_1"), projectId: ProjectID(value: "prj_1"))

        // Then
        XCTAssertNotEqual(session1.token, session2.token, "Each session should have unique token")
        XCTAssertTrue(session1.token.hasPrefix("sess_"), "Token should start with 'sess_'")
    }

    func testAgentSessionCreation_ExpiresInOneHour() {
        // Given
        let now = Date()

        // When
        let session = AgentSession(agentId: AgentID(value: "agt_1"), projectId: ProjectID(value: "prj_1"), createdAt: now)

        // Then
        let expectedExpiry = now.addingTimeInterval(3600)
        XCTAssertEqual(
            session.expiresAt.timeIntervalSince1970,
            expectedExpiry.timeIntervalSince1970,
            accuracy: 1.0,
            "Session should expire in 1 hour"
        )
    }

    func testAgentSessionIsExpired_BeforeExpiry_ReturnsFalse() {
        // Given
        let session = AgentSession(agentId: AgentID(value: "agt_1"), projectId: ProjectID(value: "prj_1"))

        // When/Then
        XCTAssertFalse(session.isExpired, "Newly created session should not be expired")
    }

    func testAgentSessionIsExpired_AfterExpiry_ReturnsTrue() {
        // Given
        let session = AgentSession(
            agentId: AgentID(value: "agt_1"),
            projectId: ProjectID(value: "prj_1"),
            expiresAt: Date().addingTimeInterval(-1)  // 1秒前に期限切れ
        )

        // When/Then
        XCTAssertTrue(session.isExpired, "Session past expiry should be expired")
    }

    func testAgentSessionRemainingSeconds_ValidSession() {
        // Given
        let now = Date()
        let session = AgentSession(
            agentId: AgentID(value: "agt_1"),
            projectId: ProjectID(value: "prj_1"),
            createdAt: now
        )

        // When
        let remaining = session.remainingSeconds

        // Then
        XCTAssertGreaterThan(remaining, 3500, "Should have ~1 hour remaining")
        XCTAssertLessThanOrEqual(remaining, 3600, "Should not exceed 1 hour")
    }

    func testAgentSessionRemainingSeconds_ExpiredSession() {
        // Given
        let session = AgentSession(
            agentId: AgentID(value: "agt_1"),
            projectId: ProjectID(value: "prj_1"),
            expiresAt: Date().addingTimeInterval(-100)
        )

        // When
        let remaining = session.remainingSeconds

        // Then
        XCTAssertEqual(remaining, 0, "Expired session should have 0 remaining seconds")
    }

    func testAgentSessionCustomExpiry() {
        // Given
        let customExpiry = Date().addingTimeInterval(7200) // 2 hours

        // When
        let session = AgentSession(
            agentId: AgentID(value: "agt_1"),
            projectId: ProjectID(value: "prj_1"),
            expiresAt: customExpiry
        )

        // Then
        XCTAssertEqual(session.expiresAt, customExpiry, "Should use custom expiry")
    }

    // MARK: - ExecutionLog Tests (Phase 3-3)

    func testExecutionLogCreation_SetsStatusToRunning() {
        // Given
        let taskId = TaskID(value: "tsk_test123")
        let agentId = AgentID(value: "agt_test456")

        // When
        let log = ExecutionLog(taskId: taskId, agentId: agentId)

        // Then
        XCTAssertEqual(log.status, .running, "New execution log should have running status")
        XCTAssertEqual(log.taskId, taskId)
        XCTAssertEqual(log.agentId, agentId)
        XCTAssertNil(log.completedAt, "New log should not have completedAt")
        XCTAssertNil(log.exitCode, "New log should not have exitCode")
        XCTAssertNil(log.durationSeconds, "New log should not have durationSeconds")
        XCTAssertNil(log.logFilePath, "New log should not have logFilePath")
        XCTAssertNil(log.errorMessage, "New log should not have errorMessage")
    }

    func testExecutionLogComplete_WithZeroExitCode_SetsStatusToCompleted() {
        // Given
        var log = ExecutionLog(
            taskId: TaskID(value: "tsk_test123"),
            agentId: AgentID(value: "agt_test456")
        )

        // When
        log.complete(exitCode: 0, durationSeconds: 120.5, logFilePath: "/tmp/log.txt")

        // Then
        XCTAssertEqual(log.status, .completed, "Exit code 0 should set status to completed")
        XCTAssertEqual(log.exitCode, 0)
        XCTAssertEqual(log.durationSeconds, 120.5)
        XCTAssertEqual(log.logFilePath, "/tmp/log.txt")
        XCTAssertNotNil(log.completedAt, "completedAt should be set")
        XCTAssertNil(log.errorMessage, "errorMessage should be nil for successful completion")
    }

    func testExecutionLogComplete_WithNonZeroExitCode_SetsStatusToFailed() {
        // Given
        var log = ExecutionLog(
            taskId: TaskID(value: "tsk_test123"),
            agentId: AgentID(value: "agt_test456")
        )

        // When
        log.complete(
            exitCode: 1,
            durationSeconds: 45.0,
            logFilePath: "/tmp/error.log",
            errorMessage: "Command failed with exit code 1"
        )

        // Then
        XCTAssertEqual(log.status, .failed, "Non-zero exit code should set status to failed")
        XCTAssertEqual(log.exitCode, 1)
        XCTAssertEqual(log.durationSeconds, 45.0)
        XCTAssertEqual(log.logFilePath, "/tmp/error.log")
        XCTAssertEqual(log.errorMessage, "Command failed with exit code 1")
        XCTAssertNotNil(log.completedAt, "completedAt should be set")
    }

    func testExecutionLogIDGeneration() {
        // When
        let id1 = ExecutionLogID.generate()
        let id2 = ExecutionLogID.generate()

        // Then
        XCTAssertTrue(id1.value.hasPrefix("exec_"), "ExecutionLogID should have exec_ prefix")
        XCTAssertNotEqual(id1, id2, "Generated IDs should be unique")
    }

    func testExecutionLogFromDB_RestoresAllFields() {
        // Given
        let id = ExecutionLogID(value: "exec_test123")
        let taskId = TaskID(value: "tsk_abc")
        let agentId = AgentID(value: "agt_xyz")
        let startedAt = Date()
        let completedAt = Date().addingTimeInterval(60)

        // When
        let log = ExecutionLog(
            id: id,
            taskId: taskId,
            agentId: agentId,
            status: .completed,
            startedAt: startedAt,
            completedAt: completedAt,
            exitCode: 0,
            durationSeconds: 60.0,
            logFilePath: "/var/log/exec.log",
            errorMessage: nil
        )

        // Then
        XCTAssertEqual(log.id, id)
        XCTAssertEqual(log.taskId, taskId)
        XCTAssertEqual(log.agentId, agentId)
        XCTAssertEqual(log.status, .completed)
        XCTAssertEqual(log.startedAt, startedAt)
        XCTAssertEqual(log.completedAt, completedAt)
        XCTAssertEqual(log.exitCode, 0)
        XCTAssertEqual(log.durationSeconds, 60.0)
        XCTAssertEqual(log.logFilePath, "/var/log/exec.log")
        XCTAssertNil(log.errorMessage)
    }

    func testExecutionStatusCases() {
        // Then
        XCTAssertEqual(ExecutionStatus.running.rawValue, "running")
        XCTAssertEqual(ExecutionStatus.completed.rawValue, "completed")
        XCTAssertEqual(ExecutionStatus.failed.rawValue, "failed")
        XCTAssertEqual(ExecutionStatus.allCases.count, 3)
    }

    // MARK: - ChatMessage Tests (Chat Feature)

    func testChatMessageIDGeneration() {
        // 要件: msg_[ランダム文字列] 形式
        let id = ChatMessageID.generate()
        XCTAssertTrue(id.value.hasPrefix("msg_"), "ChatMessage ID must start with 'msg_'")
        XCTAssertGreaterThan(id.value.count, 4, "ChatMessage ID must have characters after prefix")
    }

    func testChatMessageCreation() {
        // 要件: ChatMessage { id, senderId, receiverId?, content, createdAt, relatedTaskId?, relatedHandoffId? }
        let ownerAgentId = AgentID(value: "owner")
        let targetAgentId = AgentID(value: "target-agent")
        let message = ChatMessage(
            id: ChatMessageID.generate(),
            senderId: ownerAgentId,
            receiverId: targetAgentId,
            content: "タスクAの進捗を教えてください",
            createdAt: Date()
        )

        XCTAssertEqual(message.senderId, ownerAgentId)
        XCTAssertEqual(message.receiverId, targetAgentId)
        XCTAssertEqual(message.content, "タスクAの進捗を教えてください")
        XCTAssertNil(message.relatedTaskId, "New message should not have related task by default")
        XCTAssertNil(message.relatedHandoffId, "New message should not have related handoff by default")
    }

    func testChatMessageWithRelatedTask() {
        let taskId = TaskID.generate()
        let agentId = AgentID(value: "test-agent")
        let ownerAgentId = AgentID(value: "owner")
        let message = ChatMessage(
            id: ChatMessageID.generate(),
            senderId: agentId,
            receiverId: ownerAgentId,
            content: "タスクは50%完了しています",
            createdAt: Date(),
            relatedTaskId: taskId
        )

        XCTAssertEqual(message.senderId, agentId)
        XCTAssertEqual(message.relatedTaskId, taskId)
    }

    func testChatMessageIsSentBy() {
        // 要件: senderId/receiverId model での送信者判定
        let ownerAgentId = AgentID(value: "owner")
        let agentId = AgentID(value: "agent")
        let message = ChatMessage(
            id: ChatMessageID.generate(),
            senderId: ownerAgentId,
            content: "Hello",
            createdAt: Date()
        )

        XCTAssertTrue(message.isSentBy(ownerAgentId))
        XCTAssertFalse(message.isSentBy(agentId))
    }

    func testChatMessageEquality() {
        let id = ChatMessageID.generate()
        let now = Date()
        let ownerAgentId = AgentID(value: "owner")
        let targetAgentId = AgentID(value: "target")

        let message1 = ChatMessage(
            id: id,
            senderId: ownerAgentId,
            receiverId: targetAgentId,
            content: "Hello",
            createdAt: now
        )

        let message2 = ChatMessage(
            id: id,
            senderId: ownerAgentId,
            receiverId: targetAgentId,
            content: "Hello",
            createdAt: now
        )

        XCTAssertEqual(message1, message2, "Messages with same properties should be equal")
    }

    func testChatMessageCodable() throws {
        let agentId = AgentID(value: "test-agent")
        let ownerAgentId = AgentID(value: "owner")
        let message = ChatMessage(
            id: ChatMessageID(value: "msg_test123"),
            senderId: agentId,
            receiverId: ownerAgentId,
            content: "テストメッセージ",
            createdAt: Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.id, message.id)
        XCTAssertEqual(decoded.senderId, message.senderId)
        XCTAssertEqual(decoded.receiverId, message.receiverId)
        XCTAssertEqual(decoded.content, message.content)
        XCTAssertEqual(decoded.createdAt, message.createdAt)
    }

    // MARK: - AgentPurpose Tests (Chat Feature - 起動理由管理)

    func testAgentPurposeValues() {
        // 要件: task (タスク実行) / chat (チャット応答)
        XCTAssertEqual(AgentPurpose.task.rawValue, "task")
        XCTAssertEqual(AgentPurpose.chat.rawValue, "chat")
    }

    // MARK: - ChatCommandMarker Tests (参照: docs/design/CHAT_COMMAND_MARKER.md)

    func testChatCommandMarker_DetectsHalfWidthTaskCreateMarker() {
        let content = "@@タスク作成: ログイン機能を実装"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should detect half-width @@ task create marker"
        )
    }

    func testChatCommandMarker_DetectsFullWidthTaskCreateMarker() {
        let content = "＠＠タスク作成: ログイン機能を実装"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should detect full-width ＠＠ task create marker"
        )
    }

    func testChatCommandMarker_DetectsMixedWidthTaskCreateMarker() {
        let content1 = "@＠タスク作成: ログイン機能を実装"
        let content2 = "＠@タスク作成: ログイン機能を実装"
        XCTAssertTrue(ChatCommandMarker.containsTaskCreateMarker(content1))
        XCTAssertTrue(ChatCommandMarker.containsTaskCreateMarker(content2))
    }

    func testChatCommandMarker_RejectsMessageWithoutMarker() {
        let content = "ログイン機能を実装してください"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should reject message without marker"
        )
    }

    func testChatCommandMarker_RejectsSingleAtSign() {
        let content = "@タスク作成: ログイン機能を実装"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should reject single @ sign"
        )
    }

    func testChatCommandMarker_RejectsMarkerWithoutColon() {
        let content = "@@タスク作成 ログイン機能を実装"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should reject marker without colon"
        )
    }

    func testChatCommandMarker_DetectsMarkerInMiddleOfMessage() {
        let content = "お願いします @@タスク作成: ログイン機能を実装 よろしく"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should detect marker in middle of message"
        )
    }

    func testChatCommandMarker_DetectsTaskNotifyMarker() {
        let content = "@@タスク通知: レビュー完了しました"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskNotifyMarker(content),
            "Should detect task notify marker"
        )
    }

    func testChatCommandMarker_DetectsFullWidthTaskNotifyMarker() {
        let content = "＠＠タスク通知: レビュー完了しました"
        XCTAssertTrue(
            ChatCommandMarker.containsTaskNotifyMarker(content),
            "Should detect full-width task notify marker"
        )
    }

    func testChatCommandMarker_DoesNotConfuseCreateWithNotify() {
        let content = "@@タスク作成: ログイン機能を実装"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskNotifyMarker(content),
            "Should not confuse task create marker with notify marker"
        )
    }

    func testChatCommandMarker_DoesNotConfuseNotifyWithCreate() {
        let content = "@@タスク通知: レビュー完了しました"
        XCTAssertFalse(
            ChatCommandMarker.containsTaskCreateMarker(content),
            "Should not confuse task notify marker with create marker"
        )
    }

    func testChatCommandMarker_ExtractsTaskTitle() {
        let content = "@@タスク作成: ログイン機能を実装"
        let title = ChatCommandMarker.extractTaskTitle(from: content)
        XCTAssertEqual(title, "ログイン機能を実装")
    }

    func testChatCommandMarker_ExtractsTaskTitleFromFullWidthMarker() {
        let content = "＠＠タスク作成: 決済機能のバグ修正"
        let title = ChatCommandMarker.extractTaskTitle(from: content)
        XCTAssertEqual(title, "決済機能のバグ修正")
    }

    func testChatCommandMarker_ReturnsNilForMessageWithoutMarker() {
        let content = "ログイン機能を実装してください"
        let title = ChatCommandMarker.extractTaskTitle(from: content)
        XCTAssertNil(title)
    }

    func testChatCommandMarker_TrimsWhitespaceFromTitle() {
        let content = "@@タスク作成:   ログイン機能を実装   "
        let title = ChatCommandMarker.extractTaskTitle(from: content)
        XCTAssertEqual(title, "ログイン機能を実装")
    }

    func testChatCommandMarker_ExtractsNotifyMessage() {
        let content = "@@タスク通知: レビュー完了しました"
        let message = ChatCommandMarker.extractNotifyMessage(from: content)
        XCTAssertEqual(message, "レビュー完了しました")
    }

    func testChatCommandMarker_ReturnsNilForMessageWithoutNotifyMarker() {
        let content = "レビュー完了しました"
        let message = ChatCommandMarker.extractNotifyMessage(from: content)
        XCTAssertNil(message)
    }
}
