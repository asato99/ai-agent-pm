// Sources/Infrastructure/Repositories/ContextRepository.swift
// 参照: docs/prd/STATE_HISTORY.md - コンテキスト管理

import Foundation
import GRDB
import Domain

// MARK: - ContextRecord

struct ContextRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "contexts"

    var id: String
    var taskId: String
    var sessionId: String
    var agentId: String
    var progress: String?
    var findings: String?
    var blockers: String?
    var nextSteps: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case sessionId = "session_id"
        case agentId = "agent_id"
        case progress
        case findings
        case blockers
        case nextSteps = "next_steps"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> Context {
        Context(
            id: ContextID(value: id),
            taskId: TaskID(value: taskId),
            sessionId: SessionID(value: sessionId),
            agentId: AgentID(value: agentId),
            progress: progress,
            findings: findings,
            blockers: blockers,
            nextSteps: nextSteps,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func fromDomain(_ context: Context) -> ContextRecord {
        ContextRecord(
            id: context.id.value,
            taskId: context.taskId.value,
            sessionId: context.sessionId.value,
            agentId: context.agentId.value,
            progress: context.progress,
            findings: context.findings,
            blockers: context.blockers,
            nextSteps: context.nextSteps,
            createdAt: context.createdAt,
            updatedAt: context.updatedAt
        )
    }
}

// MARK: - ContextRepository

public final class ContextRepository: ContextRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: ContextID) throws -> Context? {
        try db.read { db in
            try ContextRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findByTask(_ taskId: TaskID) throws -> [Context] {
        try db.read { db in
            try ContextRecord
                .filter(Column("task_id") == taskId.value)
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findBySession(_ sessionId: SessionID) throws -> [Context] {
        try db.read { db in
            try ContextRecord
                .filter(Column("session_id") == sessionId.value)
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findLatest(taskId: TaskID) throws -> Context? {
        try db.read { db in
            try ContextRecord
                .filter(Column("task_id") == taskId.value)
                .order(Column("created_at").desc)
                .limit(1)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func save(_ context: Context) throws {
        try db.write { db in
            try ContextRecord.fromDomain(context).save(db)
        }
    }

    public func delete(_ id: ContextID) throws {
        try db.write { db in
            _ = try ContextRecord.deleteOne(db, key: id.value)
        }
    }
}
