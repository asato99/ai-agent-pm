// Sources/Infrastructure/Repositories/HandoffRepository.swift
// 参照: docs/prd/AGENT_CONCEPT.md - ハンドオフ

import Foundation
import GRDB
import Domain

// MARK: - HandoffRecord

struct HandoffRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "handoffs"

    var id: String
    var taskId: String
    var fromAgentId: String
    var toAgentId: String?
    var summary: String
    var context: String?
    var recommendations: String?
    var acceptedAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case fromAgentId = "from_agent_id"
        case toAgentId = "to_agent_id"
        case summary
        case context
        case recommendations
        case acceptedAt = "accepted_at"
        case createdAt = "created_at"
    }

    func toDomain() -> Handoff {
        Handoff(
            id: HandoffID(value: id),
            taskId: TaskID(value: taskId),
            fromAgentId: AgentID(value: fromAgentId),
            toAgentId: toAgentId.map { AgentID(value: $0) },
            summary: summary,
            context: context,
            recommendations: recommendations,
            acceptedAt: acceptedAt,
            createdAt: createdAt
        )
    }

    static func fromDomain(_ handoff: Handoff) -> HandoffRecord {
        HandoffRecord(
            id: handoff.id.value,
            taskId: handoff.taskId.value,
            fromAgentId: handoff.fromAgentId.value,
            toAgentId: handoff.toAgentId?.value,
            summary: handoff.summary,
            context: handoff.context,
            recommendations: handoff.recommendations,
            acceptedAt: handoff.acceptedAt,
            createdAt: handoff.createdAt
        )
    }
}

// MARK: - HandoffRepository

public final class HandoffRepository: HandoffRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: HandoffID) throws -> Handoff? {
        try db.read { db in
            try HandoffRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findByTask(_ taskId: TaskID) throws -> [Handoff] {
        try db.read { db in
            try HandoffRecord
                .filter(Column("task_id") == taskId.value)
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findPending(agentId: AgentID?) throws -> [Handoff] {
        try db.read { db in
            var request = HandoffRecord
                .filter(Column("accepted_at") == nil)

            if let agentId = agentId {
                request = request.filter(
                    Column("to_agent_id") == agentId.value ||
                    Column("to_agent_id") == nil
                )
            }

            return try request
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// 全ての未処理ハンドオフを取得
    /// ステートレスMCPサーバー用
    public func findAllPending() throws -> [Handoff] {
        try db.read { db in
            try HandoffRecord
                .filter(Column("accepted_at") == nil)
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findByFromAgent(_ agentId: AgentID) throws -> [Handoff] {
        try db.read { db in
            try HandoffRecord
                .filter(Column("from_agent_id") == agentId.value)
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func save(_ handoff: Handoff) throws {
        try db.write { db in
            try HandoffRecord.fromDomain(handoff).save(db)
        }
    }
}
