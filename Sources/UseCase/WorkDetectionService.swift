// Sources/UseCase/WorkDetectionService.swift
// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md - 共通ロジック
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

    public init(
        chatRepository: any ChatRepositoryProtocol,
        sessionRepository: any AgentSessionRepositoryProtocol,
        taskRepository: any TaskRepositoryProtocol
    ) {
        self.chatRepository = chatRepository
        self.sessionRepository = sessionRepository
        self.taskRepository = taskRepository
    }

    /// チャットの仕事があるか判定
    /// - 未読チャットメッセージがある
    /// - かつ、アクティブなチャットセッションがない
    public func hasChatWork(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        let unreadMessages = try chatRepository.findUnreadMessages(projectId: projectId, agentId: agentId)
        guard !unreadMessages.isEmpty else {
            return false
        }

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
        let inProgressTasks = try taskRepository.findByProject(projectId, status: .inProgress)
        let hasInProgressTask = inProgressTasks.contains { $0.assigneeId == agentId }
        guard hasInProgressTask else {
            return false
        }

        let sessions = try sessionRepository.findByAgentIdAndProjectId(agentId, projectId: projectId)
        let hasActiveTask = sessions.contains { session in
            session.purpose == .task && session.expiresAt > Date()
        }

        return !hasActiveTask
    }
}
