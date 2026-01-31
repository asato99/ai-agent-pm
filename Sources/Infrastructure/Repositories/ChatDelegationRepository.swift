// Sources/Infrastructure/Repositories/ChatDelegationRepository.swift
// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md

import Foundation
import GRDB
import Domain

// MARK: - ChatDelegationRecord

/// GRDB用のChatDelegationレコード
struct ChatDelegationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "chat_delegations"

    var id: String
    var agentId: String
    var projectId: String
    var targetAgentId: String
    var purpose: String
    var context: String?
    var status: String
    var createdAt: Date
    var processedAt: Date?
    var result: String?

    enum CodingKeys: String, CodingKey {
        case id
        case agentId = "agent_id"
        case projectId = "project_id"
        case targetAgentId = "target_agent_id"
        case purpose
        case context
        case status
        case createdAt = "created_at"
        case processedAt = "processed_at"
        case result
    }

    func toDomain() -> ChatDelegation {
        ChatDelegation(
            id: ChatDelegationID(value: id),
            agentId: AgentID(value: agentId),
            projectId: ProjectID(value: projectId),
            targetAgentId: AgentID(value: targetAgentId),
            purpose: purpose,
            context: context,
            status: ChatDelegationStatus(rawValue: status) ?? .pending,
            createdAt: createdAt,
            processedAt: processedAt,
            result: result
        )
    }

    static func fromDomain(_ entity: ChatDelegation) -> ChatDelegationRecord {
        ChatDelegationRecord(
            id: entity.id.value,
            agentId: entity.agentId.value,
            projectId: entity.projectId.value,
            targetAgentId: entity.targetAgentId.value,
            purpose: entity.purpose,
            context: entity.context,
            status: entity.status.rawValue,
            createdAt: entity.createdAt,
            processedAt: entity.processedAt,
            result: entity.result
        )
    }
}

// MARK: - ChatDelegationRepository

/// チャットセッション委譲リポジトリ
public final class ChatDelegationRepository: ChatDelegationRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func save(_ delegation: ChatDelegation) throws {
        try db.write { db in
            try ChatDelegationRecord.fromDomain(delegation)
                .save(db, onConflict: .replace)
        }

        // WAL mode: 他プロセスからの可視性を確保
        try? db.write { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE)")
        }
    }

    public func findById(_ id: ChatDelegationID) throws -> ChatDelegation? {
        try db.read { db in
            try ChatDelegationRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findPendingByAgentId(_ agentId: AgentID, projectId: ProjectID) throws -> [ChatDelegation] {
        try db.read { db in
            try ChatDelegationRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("project_id") == projectId.value)
                .filter(Column("status") == ChatDelegationStatus.pending.rawValue)
                .order(Column("created_at").asc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func hasPending(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        try db.read { db in
            let count = try ChatDelegationRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("project_id") == projectId.value)
                .filter(Column("status") == ChatDelegationStatus.pending.rawValue)
                .fetchCount(db)
            return count > 0
        }
    }

    public func updateStatus(_ id: ChatDelegationID, status: ChatDelegationStatus) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE chat_delegations
                    SET status = ?
                    WHERE id = ?
                """,
                arguments: [status.rawValue, id.value]
            )
        }

        // WAL mode: 他プロセスからの可視性を確保
        try? db.write { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE)")
        }
    }

    public func markCompleted(_ id: ChatDelegationID, result: String?) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE chat_delegations
                    SET status = ?, processed_at = ?, result = ?
                    WHERE id = ?
                """,
                arguments: [
                    ChatDelegationStatus.completed.rawValue,
                    Date(),
                    result,
                    id.value
                ]
            )
        }

        // WAL mode: 他プロセスからの可視性を確保
        try? db.write { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE)")
        }
    }

    public func markFailed(_ id: ChatDelegationID, result: String?) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE chat_delegations
                    SET status = ?, processed_at = ?, result = ?
                    WHERE id = ?
                """,
                arguments: [
                    ChatDelegationStatus.failed.rawValue,
                    Date(),
                    result,
                    id.value
                ]
            )
        }

        // WAL mode: 他プロセスからの可視性を確保
        try? db.write { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE)")
        }
    }
}
