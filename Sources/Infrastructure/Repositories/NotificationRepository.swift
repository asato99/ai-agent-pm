// Sources/Infrastructure/Repositories/NotificationRepository.swift
// 参照: docs/design/NOTIFICATION_SYSTEM.md
// 参照: docs/usecase/UC010_TaskInterruptByStatusChange.md

import Foundation
import GRDB
import Domain

// MARK: - AgentNotificationRecord

/// GRDB用のAgentNotificationレコード
/// 参照: docs/plan/CHAT_TASK_EXECUTION.md - conversationId 追加
struct AgentNotificationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "notifications"

    var id: String
    var targetAgentId: String
    var targetProjectId: String
    var type: String
    var action: String
    var taskId: String?
    var conversationId: String?
    var message: String
    var instruction: String
    var createdAt: Date
    var isRead: Bool
    var readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case targetAgentId = "target_agent_id"
        case targetProjectId = "target_project_id"
        case type
        case action
        case taskId = "task_id"
        case conversationId = "conversation_id"
        case message
        case instruction
        case createdAt = "created_at"
        case isRead = "is_read"
        case readAt = "read_at"
    }

    func toDomain() -> AgentNotification {
        AgentNotification(
            id: NotificationID(value: id),
            targetAgentId: AgentID(value: targetAgentId),
            targetProjectId: ProjectID(value: targetProjectId),
            type: AgentNotificationType(rawValue: type) ?? .statusChange,
            action: action,
            taskId: taskId.map { TaskID(value: $0) },
            conversationId: conversationId.map { ConversationID(value: $0) },
            message: message,
            instruction: instruction,
            createdAt: createdAt,
            isRead: isRead,
            readAt: readAt
        )
    }

    static func fromDomain(_ notification: AgentNotification) -> AgentNotificationRecord {
        AgentNotificationRecord(
            id: notification.id.value,
            targetAgentId: notification.targetAgentId.value,
            targetProjectId: notification.targetProjectId.value,
            type: notification.type.rawValue,
            action: notification.action,
            taskId: notification.taskId?.value,
            conversationId: notification.conversationId?.value,
            message: notification.message,
            instruction: notification.instruction,
            createdAt: notification.createdAt,
            isRead: notification.isRead,
            readAt: notification.readAt
        )
    }
}

// MARK: - NotificationRepository

/// 通知リポジトリ
public final class NotificationRepository: NotificationRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: NotificationID) throws -> AgentNotification? {
        try db.read { db in
            try AgentNotificationRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findUnreadByAgentAndProject(
        agentId: AgentID,
        projectId: ProjectID
    ) throws -> [AgentNotification] {
        try db.read { db in
            try AgentNotificationRecord
                .filter(Column("target_agent_id") == agentId.value)
                .filter(Column("target_project_id") == projectId.value)
                .filter(Column("is_read") == false)
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func hasUnreadNotifications(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        try db.read { db in
            let count = try AgentNotificationRecord
                .filter(Column("target_agent_id") == agentId.value)
                .filter(Column("target_project_id") == projectId.value)
                .filter(Column("is_read") == false)
                .fetchCount(db)
            return count > 0
        }
    }

    public func save(_ notification: AgentNotification) throws {
        try db.write { db in
            try AgentNotificationRecord.fromDomain(notification).save(db)
        }
    }

    public func markAsRead(_ id: NotificationID) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE notifications SET is_read = 1, read_at = ? WHERE id = ?",
                arguments: [Date(), id.value]
            )
        }
    }

    public func markAllAsRead(agentId: AgentID, projectId: ProjectID) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE notifications
                    SET is_read = 1, read_at = ?
                    WHERE target_agent_id = ? AND target_project_id = ? AND is_read = 0
                """,
                arguments: [Date(), agentId.value, projectId.value]
            )
        }
    }

    public func deleteOlderThan(days: Int) throws -> Int {
        try db.write { db in
            let cutoffDate = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
            return try AgentNotificationRecord
                .filter(Column("created_at") < cutoffDate)
                .deleteAll(db)
        }
    }

    public func countAll() throws -> Int {
        try db.read { db in
            try AgentNotificationRecord.fetchCount(db)
        }
    }
}
