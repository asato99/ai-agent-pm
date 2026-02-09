// Sources/Domain/Repositories/AgentServiceRepositoryProtocols.swift
// エージェントサービス関連のリポジトリプロトコル
// （AgentCredential, AgentSession, ExecutionLog, ProjectAgentAssignment, AgentWorkingDirectory）

import Foundation

// MARK: - AgentCredentialRepositoryProtocol

/// エージェント認証情報リポジトリのプロトコル
/// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md
public protocol AgentCredentialRepositoryProtocol: Sendable {
    func findById(_ id: AgentCredentialID) throws -> AgentCredential?
    func findByAgentId(_ agentId: AgentID) throws -> AgentCredential?
    func save(_ credential: AgentCredential) throws
    func delete(_ id: AgentCredentialID) throws
}

// MARK: - AgentSessionRepositoryProtocol

/// エージェントセッションリポジトリのプロトコル
/// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md
public protocol AgentSessionRepositoryProtocol: Sendable {
    func findById(_ id: AgentSessionID) throws -> AgentSession?
    func findByToken(_ token: String) throws -> AgentSession?
    func findByAgentId(_ agentId: AgentID) throws -> [AgentSession]
    /// Phase 4: (agent_id, project_id) 単位でセッションを検索
    func findByAgentIdAndProjectId(_ agentId: AgentID, projectId: ProjectID) throws -> [AgentSession]
    /// Feature 14: プロジェクトIDでセッションを検索（一時停止時のセッション有効期限短縮用）
    func findByProjectId(_ projectId: ProjectID) throws -> [AgentSession]
    func save(_ session: AgentSession) throws
    func delete(_ id: AgentSessionID) throws
    func deleteByToken(_ token: String) throws  // Phase 4: セッション終了用
    func deleteByAgentId(_ agentId: AgentID) throws
    func deleteExpired() throws
    /// アクティブなセッション数をカウント（有効期限内のもの）
    func countActiveSessions(agentId: AgentID) throws -> Int
    /// アクティブなセッション一覧を取得（有効期限内のもの）
    func findActiveSessions(agentId: AgentID) throws -> [AgentSession]
    /// アクティブなセッション数をpurpose別にカウント（Chat Session Maintenance Mode用）
    /// 参照: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md
    func countActiveSessionsByPurpose(agentId: AgentID) throws -> [AgentPurpose: Int]
    /// 最終アクティビティ日時を更新（アイドルタイムアウト管理用）
    func updateLastActivity(token: String, at date: Date) throws
    /// セッション状態を更新（UC015: チャットセッション終了）
    /// 参照: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 6
    func updateState(token: String, state: SessionState) throws
}

// MARK: - ExecutionLogRepositoryProtocol

/// 実行ログリポジトリのプロトコル
/// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-3
public protocol ExecutionLogRepositoryProtocol: Sendable {
    func findById(_ id: ExecutionLogID) throws -> ExecutionLog?
    func findByTaskId(_ taskId: TaskID) throws -> [ExecutionLog]
    func findByAgentId(_ agentId: AgentID) throws -> [ExecutionLog]
    /// ページネーション対応（UI実行履歴表示用）
    func findByAgentId(_ agentId: AgentID, limit: Int?, offset: Int?) throws -> [ExecutionLog]
    func findRunning(agentId: AgentID) throws -> [ExecutionLog]
    /// 最新の実行ログを取得（Coordinator用：ログファイルパス登録用）
    func findLatestByAgentAndTask(agentId: AgentID, taskId: TaskID) throws -> ExecutionLog?
    func save(_ log: ExecutionLog) throws
    func delete(_ id: ExecutionLogID) throws
}

// MARK: - ProjectAgentAssignmentRepositoryProtocol

/// プロジェクト×エージェント割り当てリポジトリのプロトコル
/// 参照: docs/requirements/PROJECTS.md - エージェント割り当て
/// 参照: docs/usecase/UC004_MultiProjectSameAgent.md
/// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md - スポーン管理
public protocol ProjectAgentAssignmentRepositoryProtocol: Sendable {
    /// エージェントをプロジェクトに割り当てる（既に割り当て済みの場合は既存を返す）
    func assign(projectId: ProjectID, agentId: AgentID) throws -> ProjectAgentAssignment
    /// プロジェクトからエージェントの割り当てを解除
    func remove(projectId: ProjectID, agentId: AgentID) throws
    /// プロジェクトに割り当てられたエージェント一覧を取得
    func findAgentsByProject(_ projectId: ProjectID) throws -> [Agent]
    /// エージェントが割り当てられたプロジェクト一覧を取得
    func findProjectsByAgent(_ agentId: AgentID) throws -> [Project]
    /// エージェントがプロジェクトに割り当てられているか確認
    func isAgentAssignedToProject(agentId: AgentID, projectId: ProjectID) throws -> Bool
    /// 全割り当て一覧を取得
    func findAll() throws -> [ProjectAgentAssignment]
    /// 特定のエージェント×プロジェクト割り当てを取得
    /// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
    func findAssignment(agentId: AgentID, projectId: ProjectID) throws -> ProjectAgentAssignment?
    /// スポーン開始時刻を更新（nil でクリア）
    /// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
    func updateSpawnStartedAt(agentId: AgentID, projectId: ProjectID, startedAt: Date?) throws
}

// MARK: - AgentWorkingDirectoryRepositoryProtocol

/// エージェントのワーキングディレクトリ設定リポジトリのプロトコル
/// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.1
/// マルチデバイス環境でエージェントごと、プロジェクトごとのワーキングディレクトリを管理
public protocol AgentWorkingDirectoryRepositoryProtocol: Sendable {
    /// IDで検索
    func findById(_ id: AgentWorkingDirectoryID) throws -> AgentWorkingDirectory?

    /// エージェント×プロジェクトで検索（一意）
    func findByAgentAndProject(agentId: AgentID, projectId: ProjectID) throws -> AgentWorkingDirectory?

    /// エージェントの全ワーキングディレクトリ設定を取得
    func findByAgent(_ agentId: AgentID) throws -> [AgentWorkingDirectory]

    /// プロジェクトの全ワーキングディレクトリ設定を取得
    func findByProject(_ projectId: ProjectID) throws -> [AgentWorkingDirectory]

    /// 保存（作成または更新）
    func save(_ workingDirectory: AgentWorkingDirectory) throws

    /// 削除
    func delete(_ id: AgentWorkingDirectoryID) throws

    /// エージェント×プロジェクトで削除
    func deleteByAgentAndProject(agentId: AgentID, projectId: ProjectID) throws
}
