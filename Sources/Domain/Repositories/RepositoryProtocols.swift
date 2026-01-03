// Sources/Domain/Repositories/RepositoryProtocols.swift
// 参照: docs/guide/CLEAN_ARCHITECTURE.md - Repository Pattern

import Foundation

// MARK: - ProjectRepositoryProtocol

/// プロジェクトリポジトリのプロトコル
public protocol ProjectRepositoryProtocol: Sendable {
    func findById(_ id: ProjectID) throws -> Project?
    func findAll() throws -> [Project]
    func save(_ project: Project) throws
    func delete(_ id: ProjectID) throws
}

// MARK: - AgentRepositoryProtocol

/// エージェントリポジトリのプロトコル
/// 要件: エージェントはプロジェクト非依存のトップレベルエンティティ
public protocol AgentRepositoryProtocol: Sendable {
    func findById(_ id: AgentID) throws -> Agent?
    func findAll() throws -> [Agent]
    func findByType(_ type: AgentType) throws -> [Agent]
    func findByParent(_ parentAgentId: AgentID?) throws -> [Agent]
    func findRootAgents() throws -> [Agent]
    func findLocked(byAuditId: InternalAuditID?) throws -> [Agent]
    func save(_ agent: Agent) throws
    func delete(_ id: AgentID) throws
}

// MARK: - TaskRepositoryProtocol

/// タスクリポジトリのプロトコル
public protocol TaskRepositoryProtocol: Sendable {
    func findById(_ id: TaskID) throws -> Task?
    func findAll(projectId: ProjectID) throws -> [Task]
    func findByProject(_ projectId: ProjectID, status: TaskStatus?) throws -> [Task]
    func findByAssignee(_ agentId: AgentID) throws -> [Task]
    func findByStatus(_ status: TaskStatus, projectId: ProjectID) throws -> [Task]
    func findLocked(byAuditId: InternalAuditID?) throws -> [Task]
    func save(_ task: Task) throws
    func delete(_ id: TaskID) throws
}

// MARK: - SessionRepositoryProtocol

/// セッションリポジトリのプロトコル
public protocol SessionRepositoryProtocol: Sendable {
    func findById(_ id: SessionID) throws -> Session?
    func findActive(agentId: AgentID) throws -> Session?
    func findByProject(_ projectId: ProjectID) throws -> [Session]
    func findByAgent(_ agentId: AgentID) throws -> [Session]
    func save(_ session: Session) throws
}

// MARK: - ContextRepositoryProtocol

/// コンテキストリポジトリのプロトコル
public protocol ContextRepositoryProtocol: Sendable {
    func findById(_ id: ContextID) throws -> Context?
    func findByTask(_ taskId: TaskID) throws -> [Context]
    func findBySession(_ sessionId: SessionID) throws -> [Context]
    func findLatest(taskId: TaskID) throws -> Context?
    func save(_ context: Context) throws
    func delete(_ id: ContextID) throws
}

// MARK: - HandoffRepositoryProtocol

/// ハンドオフリポジトリのプロトコル
public protocol HandoffRepositoryProtocol: Sendable {
    func findById(_ id: HandoffID) throws -> Handoff?
    func findByTask(_ taskId: TaskID) throws -> [Handoff]
    func findPending(agentId: AgentID?) throws -> [Handoff]
    func findByFromAgent(_ agentId: AgentID) throws -> [Handoff]
    func save(_ handoff: Handoff) throws
}

// MARK: - EventRepositoryProtocol

/// イベントリポジトリのプロトコル
public protocol EventRepositoryProtocol: Sendable {
    func findByProject(_ projectId: ProjectID, limit: Int?) throws -> [StateChangeEvent]
    func findByEntity(type: EntityType, id: String) throws -> [StateChangeEvent]
    func findRecent(projectId: ProjectID, since: Date) throws -> [StateChangeEvent]
    func save(_ event: StateChangeEvent) throws
}

// MARK: - WorkflowTemplateRepositoryProtocol

/// ワークフローテンプレートリポジトリのプロトコル
/// 参照: docs/requirements/WORKFLOW_TEMPLATES.md
public protocol WorkflowTemplateRepositoryProtocol: Sendable {
    func findById(_ id: WorkflowTemplateID) throws -> WorkflowTemplate?
    func findAll(includeArchived: Bool) throws -> [WorkflowTemplate]
    func findActive() throws -> [WorkflowTemplate]
    func save(_ template: WorkflowTemplate) throws
    func delete(_ id: WorkflowTemplateID) throws
}

// MARK: - TemplateTaskRepositoryProtocol

/// テンプレートタスクリポジトリのプロトコル
/// 参照: docs/requirements/WORKFLOW_TEMPLATES.md
public protocol TemplateTaskRepositoryProtocol: Sendable {
    func findById(_ id: TemplateTaskID) throws -> TemplateTask?
    func findByTemplate(_ templateId: WorkflowTemplateID) throws -> [TemplateTask]
    func save(_ task: TemplateTask) throws
    func delete(_ id: TemplateTaskID) throws
    func deleteByTemplate(_ templateId: WorkflowTemplateID) throws
}

// MARK: - InternalAuditRepositoryProtocol

/// Internal Auditリポジトリのプロトコル
/// 参照: docs/requirements/AUDIT.md
public protocol InternalAuditRepositoryProtocol: Sendable {
    func findById(_ id: InternalAuditID) throws -> InternalAudit?
    func findAll(includeInactive: Bool) throws -> [InternalAudit]
    func findActive() throws -> [InternalAudit]
    func save(_ audit: InternalAudit) throws
    func delete(_ id: InternalAuditID) throws
}

// MARK: - AuditRuleRepositoryProtocol

/// Audit Ruleリポジトリのプロトコル
/// 参照: docs/requirements/AUDIT.md
public protocol AuditRuleRepositoryProtocol: Sendable {
    func findById(_ id: AuditRuleID) throws -> AuditRule?
    func findByAudit(_ auditId: InternalAuditID) throws -> [AuditRule]
    func findEnabled(auditId: InternalAuditID) throws -> [AuditRule]
    func findByTriggerType(_ triggerType: TriggerType) throws -> [AuditRule]
    func save(_ rule: AuditRule) throws
    func delete(_ id: AuditRuleID) throws
}
