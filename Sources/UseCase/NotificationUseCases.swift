// Sources/UseCase/NotificationUseCases.swift
// 通知システム - ユースケース
// 参照: docs/design/NOTIFICATION_SYSTEM.md
// 参照: docs/usecase/UC010_TaskInterruptByStatusChange.md

import Foundation
import Domain

// MARK: - CreateNotificationUseCase

/// 通知作成ユースケース
/// UC010: タスクステータス変更時の通知作成などに使用
public struct CreateNotificationUseCase: Sendable {
    private let notificationRepository: any NotificationRepositoryProtocol

    public init(notificationRepository: any NotificationRepositoryProtocol) {
        self.notificationRepository = notificationRepository
    }

    /// ステータス変更通知を作成
    /// - Parameters:
    ///   - targetAgentId: 通知先エージェントID
    ///   - targetProjectId: 通知先プロジェクトID
    ///   - taskId: 対象タスクID
    ///   - newStatus: 新しいステータス
    /// - Returns: 作成された通知
    public func createStatusChange(
        targetAgentId: AgentID,
        targetProjectId: ProjectID,
        taskId: TaskID,
        newStatus: String
    ) throws -> AgentNotification {
        let notification = AgentNotification.createStatusChangeNotification(
            targetAgentId: targetAgentId,
            targetProjectId: targetProjectId,
            taskId: taskId,
            newStatus: newStatus
        )
        try notificationRepository.save(notification)
        return notification
    }

    /// 割り込み通知を作成
    /// - Parameters:
    ///   - targetAgentId: 通知先エージェントID
    ///   - targetProjectId: 通知先プロジェクトID
    ///   - action: アクション（cancel, pause等）
    ///   - taskId: 対象タスクID（オプション）
    ///   - instruction: エージェントへの指示
    /// - Returns: 作成された通知
    public func createInterrupt(
        targetAgentId: AgentID,
        targetProjectId: ProjectID,
        action: String,
        taskId: TaskID?,
        instruction: String
    ) throws -> AgentNotification {
        let notification = AgentNotification.createInterruptNotification(
            targetAgentId: targetAgentId,
            targetProjectId: targetProjectId,
            action: action,
            taskId: taskId,
            instruction: instruction
        )
        try notificationRepository.save(notification)
        return notification
    }

    /// メッセージ通知を作成
    /// - Parameters:
    ///   - targetAgentId: 通知先エージェントID
    ///   - targetProjectId: 通知先プロジェクトID
    /// - Returns: 作成された通知
    public func createMessage(
        targetAgentId: AgentID,
        targetProjectId: ProjectID
    ) throws -> AgentNotification {
        let notification = AgentNotification.createMessageNotification(
            targetAgentId: targetAgentId,
            targetProjectId: targetProjectId
        )
        try notificationRepository.save(notification)
        return notification
    }
}

// MARK: - CheckNotificationsUseCase

/// 未読通知チェックユースケース
/// MCPサーバーミドルウェアで使用: 全ツールレスポンスに通知有無を含める
public struct CheckNotificationsUseCase: Sendable {
    private let notificationRepository: any NotificationRepositoryProtocol

    public init(notificationRepository: any NotificationRepositoryProtocol) {
        self.notificationRepository = notificationRepository
    }

    /// 未読通知があるかチェック（高速）
    /// - Parameters:
    ///   - agentId: エージェントID
    ///   - projectId: プロジェクトID
    /// - Returns: 未読通知が存在する場合true
    public func execute(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        try notificationRepository.hasUnreadNotifications(agentId: agentId, projectId: projectId)
    }
}

// MARK: - GetNotificationsUseCase

/// 通知取得ユースケース
/// get_notifications MCPツールで使用
public struct GetNotificationsUseCase: Sendable {
    private let notificationRepository: any NotificationRepositoryProtocol

    public init(notificationRepository: any NotificationRepositoryProtocol) {
        self.notificationRepository = notificationRepository
    }

    /// 未読通知を取得
    /// - Parameters:
    ///   - agentId: エージェントID
    ///   - projectId: プロジェクトID
    ///   - markAsRead: 取得と同時に既読にするかどうか
    /// - Returns: 未読通知のリスト
    public func execute(
        agentId: AgentID,
        projectId: ProjectID,
        markAsRead: Bool = true
    ) throws -> [AgentNotification] {
        let notifications = try notificationRepository.findUnreadByAgentAndProject(
            agentId: agentId,
            projectId: projectId
        )

        if markAsRead && !notifications.isEmpty {
            try notificationRepository.markAllAsRead(agentId: agentId, projectId: projectId)
        }

        return notifications
    }
}

// MARK: - CleanupOldNotificationsUseCase

/// 古い通知のクリーンアップユースケース
/// 定期的なメンテナンスジョブで使用
public struct CleanupOldNotificationsUseCase: Sendable {
    private let notificationRepository: any NotificationRepositoryProtocol

    public init(notificationRepository: any NotificationRepositoryProtocol) {
        self.notificationRepository = notificationRepository
    }

    /// 指定日数より古い通知を削除
    /// - Parameter olderThanDays: 削除対象の日数
    /// - Returns: 削除された通知数
    public func execute(olderThanDays: Int = 30) throws -> Int {
        try notificationRepository.deleteOlderThan(days: olderThanDays)
    }
}
