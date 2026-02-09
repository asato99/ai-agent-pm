// Sources/Domain/Repositories/WorkflowRepositoryProtocols.swift
// ワークフロー関連のリポジトリプロトコル（Context, Handoff, Event, WorkflowTemplate, TemplateTask）

import Foundation

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
/// 設計方針: テンプレートはプロジェクトに紐づく
public protocol WorkflowTemplateRepositoryProtocol: Sendable {
    func findById(_ id: WorkflowTemplateID) throws -> WorkflowTemplate?
    func findByProject(_ projectId: ProjectID, includeArchived: Bool) throws -> [WorkflowTemplate]
    func findActiveByProject(_ projectId: ProjectID) throws -> [WorkflowTemplate]
    /// 全プロジェクトのアクティブなテンプレートを取得（Internal Audit用）
    func findAllActive() throws -> [WorkflowTemplate]
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
