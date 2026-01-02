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
}
