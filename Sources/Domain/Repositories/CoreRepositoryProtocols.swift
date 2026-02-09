// Sources/Domain/Repositories/CoreRepositoryProtocols.swift
// コアエンティティのリポジトリプロトコル（Project, Agent, Task, Session, AppSettings）
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
    func findAllDescendants(_ parentAgentId: AgentID) throws -> [Agent]
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
    /// Phase 3-2: 作業中タスクを取得（特定エージェント）
    func findPendingByAssignee(_ agentId: AgentID) throws -> [Task]
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
    /// セッションを削除
    func delete(_ id: SessionID) throws
    /// プロジェクト内のアクティブセッションを検索
    func findActiveByProject(_ projectId: ProjectID) throws -> [Session]
    /// エージェント×プロジェクトのアクティブセッションを検索
    func findActiveByAgentAndProject(agentId: AgentID, projectId: ProjectID) throws -> [Session]
}

// MARK: - AppSettingsRepositoryProtocol

/// アプリケーション設定リポジトリのプロトコル
/// シングルトンパターン: 設定は1つのみ存在
public protocol AppSettingsRepositoryProtocol: Sendable {
    /// アプリケーション設定を取得（存在しない場合はデフォルトを作成）
    func get() throws -> AppSettings

    /// アプリケーション設定を保存
    func save(_ settings: AppSettings) throws
}
