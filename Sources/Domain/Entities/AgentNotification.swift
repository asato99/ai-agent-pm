// Sources/Domain/Entities/AgentNotification.swift
// エージェント通知エンティティ
// 参照: docs/design/NOTIFICATION_SYSTEM.md

import Foundation

// MARK: - AgentNotificationType

/// 通知の種類
/// 参照: docs/design/NOTIFICATION_SYSTEM.md - 通知タイプ
public enum AgentNotificationType: String, Codable, Sendable, CaseIterable {
    /// ステータス変更通知（タスクがblocked等に変更された場合）
    case statusChange = "status_change"
    /// 割り込み通知（キャンセル、一時停止等）
    case interrupt = "interrupt"
    /// メッセージ通知（ユーザーからのメッセージ）
    case message = "message"
}

// MARK: - AgentNotification

/// エージェントへの通知を表すエンティティ
/// 参照: docs/design/NOTIFICATION_SYSTEM.md
/// 参照: docs/usecase/UC010_TaskInterruptByStatusChange.md
/// 注意: Foundation.Notification との名前衝突を避けるため AgentNotification という名前を使用
public struct AgentNotification: Identifiable, Equatable, Codable, Sendable {
    /// 通知ID
    public let id: NotificationID
    /// 通知先エージェントID
    public let targetAgentId: AgentID
    /// 通知先プロジェクトID
    public let targetProjectId: ProjectID
    /// 通知タイプ
    public let type: AgentNotificationType
    /// アクション（blocked, cancel, pause 等）
    public let action: String
    /// 関連タスクID（オプション）
    public let taskId: TaskID?
    /// 通知メッセージ（人間可読）
    public let message: String
    /// エージェントへの指示
    public let instruction: String
    /// 作成日時
    public let createdAt: Date
    /// 既読フラグ
    public private(set) var isRead: Bool
    /// 既読日時
    public private(set) var readAt: Date?

    // MARK: - Initializer

    public init(
        id: NotificationID,
        targetAgentId: AgentID,
        targetProjectId: ProjectID,
        type: AgentNotificationType,
        action: String,
        taskId: TaskID?,
        message: String,
        instruction: String,
        createdAt: Date,
        isRead: Bool = false,
        readAt: Date? = nil
    ) {
        self.id = id
        self.targetAgentId = targetAgentId
        self.targetProjectId = targetProjectId
        self.type = type
        self.action = action
        self.taskId = taskId
        self.message = message
        self.instruction = instruction
        self.createdAt = createdAt
        self.isRead = isRead
        self.readAt = readAt
    }

    // MARK: - Methods

    /// 通知を既読としてマーク
    /// 冪等性: 既に既読の場合は何もしない
    public mutating func markAsRead() {
        guard !isRead else { return }
        isRead = true
        readAt = Date()
    }
}

// MARK: - AgentNotification Factory Methods

extension AgentNotification {
    /// ステータス変更通知を作成
    /// - Parameters:
    ///   - targetAgentId: 通知先エージェントID
    ///   - targetProjectId: 通知先プロジェクトID
    ///   - taskId: 対象タスクID
    ///   - newStatus: 新しいステータス
    /// - Returns: 通知エンティティ
    public static func createStatusChangeNotification(
        targetAgentId: AgentID,
        targetProjectId: ProjectID,
        taskId: TaskID,
        newStatus: String
    ) -> AgentNotification {
        AgentNotification(
            id: NotificationID.generate(),
            targetAgentId: targetAgentId,
            targetProjectId: targetProjectId,
            type: .statusChange,
            action: newStatus,
            taskId: taskId,
            message: "タスクのステータスが\(newStatus)に変更されました",
            instruction: "作業を中断し、report_completedをresult='\(newStatus)'で呼び出してください",
            createdAt: Date()
        )
    }

    /// 割り込み通知を作成
    /// - Parameters:
    ///   - targetAgentId: 通知先エージェントID
    ///   - targetProjectId: 通知先プロジェクトID
    ///   - action: アクション（cancel, pause等）
    ///   - taskId: 対象タスクID（オプション）
    ///   - instruction: エージェントへの指示
    /// - Returns: 通知エンティティ
    public static func createInterruptNotification(
        targetAgentId: AgentID,
        targetProjectId: ProjectID,
        action: String,
        taskId: TaskID?,
        instruction: String
    ) -> AgentNotification {
        AgentNotification(
            id: NotificationID.generate(),
            targetAgentId: targetAgentId,
            targetProjectId: targetProjectId,
            type: .interrupt,
            action: action,
            taskId: taskId,
            message: "\(action)の指示を受けました",
            instruction: instruction,
            createdAt: Date()
        )
    }

    /// メッセージ通知を作成
    /// - Parameters:
    ///   - targetAgentId: 通知先エージェントID
    ///   - targetProjectId: 通知先プロジェクトID
    /// - Returns: 通知エンティティ
    public static func createMessageNotification(
        targetAgentId: AgentID,
        targetProjectId: ProjectID
    ) -> AgentNotification {
        AgentNotification(
            id: NotificationID.generate(),
            targetAgentId: targetAgentId,
            targetProjectId: targetProjectId,
            type: .message,
            action: "user_message",
            taskId: nil,
            message: "ユーザーからのメッセージがあります",
            instruction: "get_pending_messagesを呼び出して確認してください",
            createdAt: Date()
        )
    }
}
