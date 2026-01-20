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
}

// MARK: - ChatRepositoryProtocol

/// チャットメッセージリポジトリのプロトコル
/// 参照: docs/design/CHAT_FEATURE.md
/// ファイルベースストレージを想定（.ai-pm/agents/{id}/chat.jsonl）
public protocol ChatRepositoryProtocol: Sendable {
    /// メッセージ一覧を取得（時系列順）
    func findMessages(projectId: ProjectID, agentId: AgentID) throws -> [ChatMessage]

    /// メッセージを保存（追記）
    func saveMessage(_ message: ChatMessage, projectId: ProjectID, agentId: AgentID) throws

    /// 最新N件のメッセージを取得
    func getLastMessages(projectId: ProjectID, agentId: AgentID, limit: Int) throws -> [ChatMessage]

    /// 未読メッセージを取得（エージェントからの最後のメッセージ以降のユーザーメッセージ）
    /// MCP連携用: エージェントが応答すべきメッセージを取得
    func findUnreadUserMessages(projectId: ProjectID, agentId: AgentID) throws -> [ChatMessage]
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
