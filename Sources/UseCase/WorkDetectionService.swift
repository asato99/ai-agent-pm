// Sources/UseCase/WorkDetectionService.swift
// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md - 共通ロジック
// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md - タスク/チャット分離
//
// getAgentAction と authenticate で使用する共通の仕事判定サービス
// - 一貫性: 両者で同じ判定ロジックを使用し、不一致を防止
// - 責務分離: 仕事判定ロジックを独立したサービスとして切り出し
// - テスト容易性: 共通ロジックを単体でテスト可能

import Foundation
import Domain

/// 仕事の有無を判定する共通サービス
/// getAgentAction と authenticate で同一のロジックを使用する
public struct WorkDetectionService: Sendable {
    private let chatRepository: any ChatRepositoryProtocol
    private let sessionRepository: any AgentSessionRepositoryProtocol
    private let taskRepository: any TaskRepositoryProtocol
    private let chatDelegationRepository: (any ChatDelegationRepositoryProtocol)?

    public init(
        chatRepository: any ChatRepositoryProtocol,
        sessionRepository: any AgentSessionRepositoryProtocol,
        taskRepository: any TaskRepositoryProtocol
    ) {
        self.chatRepository = chatRepository
        self.sessionRepository = sessionRepository
        self.taskRepository = taskRepository
        self.chatDelegationRepository = nil
    }

    /// 委譲リポジトリを含む初期化
    /// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
    public init(
        chatRepository: any ChatRepositoryProtocol,
        sessionRepository: any AgentSessionRepositoryProtocol,
        taskRepository: any TaskRepositoryProtocol,
        chatDelegationRepository: any ChatDelegationRepositoryProtocol
    ) {
        self.chatRepository = chatRepository
        self.sessionRepository = sessionRepository
        self.taskRepository = taskRepository
        self.chatDelegationRepository = chatDelegationRepository
    }

    /// チャットの仕事があるか判定
    /// - 未読チャットメッセージがある
    /// - または、pending状態の委譲リクエストがある
    /// - かつ、アクティブなチャットセッションがない
    /// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
    public func hasChatWork(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        // 未読メッセージをチェック
        let unreadMessages = try chatRepository.findUnreadMessages(projectId: projectId, agentId: agentId)
        let hasUnread = !unreadMessages.isEmpty

        // pending状態の委譲リクエストをチェック
        let hasPendingDelegation: Bool
        if let delegationRepo = chatDelegationRepository {
            hasPendingDelegation = try delegationRepo.hasPending(agentId: agentId, projectId: projectId)
        } else {
            hasPendingDelegation = false
        }

        // 仕事がなければfalse
        guard hasUnread || hasPendingDelegation else {
            return false
        }

        // アクティブなチャットセッションがあればfalse（既に処理中）
        let sessions = try sessionRepository.findByAgentIdAndProjectId(agentId, projectId: projectId)
        let hasActiveChat = sessions.contains { session in
            session.purpose == .chat && session.expiresAt > Date()
        }

        return !hasActiveChat
    }

    /// タスクの仕事があるか判定（基本条件のみ）
    /// - in_progress タスクがある（assignee = 対象エージェント）
    /// - かつ、アクティブなタスクセッションがない
    /// 注意: 階層タイプ別の追加条件は呼び出し元で判定する
    public func hasTaskWork(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        return try findTaskWork(agentId: agentId, projectId: projectId) != nil
    }

    /// タスクの仕事を検出し、該当タスクIDを返す
    /// - in_progress タスクがある（assignee = 対象エージェント）
    /// - かつ、アクティブなタスクセッションがない
    /// - Returns: 対象タスクID（仕事がない場合はnil）
    /// 参照: docs/design/TASK_CONVERSATION_AWAIT.md - タスクセッションへのtaskId紐付け
    public func findTaskWork(agentId: AgentID, projectId: ProjectID) throws -> TaskID? {
        let inProgressTasks = try taskRepository.findByProject(projectId, status: .inProgress)
        let assignedTask = inProgressTasks.first { $0.assigneeId == agentId }
        guard let task = assignedTask else {
            return nil
        }

        let sessions = try sessionRepository.findByAgentIdAndProjectId(agentId, projectId: projectId)
        let hasActiveTask = sessions.contains { session in
            session.purpose == .task && session.expiresAt > Date()
        }

        return hasActiveTask ? nil : task.id
    }

    // MARK: - Raw Work Detection (Session-independent)
    // セッション存在チェックを除外した純粋な仕事判定
    // reportProcessExit での孤児セッション判定に使用
    // 参照: docs/design/SESSION_INVALIDATION_IMPROVEMENT.md

    /// セッション存在チェック除外版: 純粋なタスク仕事判定
    public func hasRawTaskWork(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        let inProgressTasks = try taskRepository.findByProject(projectId, status: .inProgress)
        return inProgressTasks.contains { $0.assigneeId == agentId }
    }

    /// セッション存在チェック除外版: 純粋なチャット仕事判定
    public func hasRawChatWork(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        let unreadMessages = try chatRepository.findUnreadMessages(projectId: projectId, agentId: agentId)
        let hasUnread = !unreadMessages.isEmpty
        let hasPendingDelegation: Bool
        if let delegationRepo = chatDelegationRepository {
            hasPendingDelegation = try delegationRepo.hasPending(agentId: agentId, projectId: projectId)
        } else {
            hasPendingDelegation = false
        }
        return hasUnread || hasPendingDelegation
    }
}
