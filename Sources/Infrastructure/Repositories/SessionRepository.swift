// Sources/Infrastructure/Repositories/SessionRepository.swift
// 参照: docs/prd/AGENT_CONCEPT.md - セッション管理

import Foundation
import GRDB
import Domain

// MARK: - SessionRecord

struct SessionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sessions"

    var id: String
    var projectId: String
    var agentId: String
    var startedAt: Date
    var endedAt: Date?
    var status: String

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case agentId = "agent_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case status
    }

    func toDomain() -> Session {
        Session(
            id: SessionID(value: id),
            projectId: ProjectID(value: projectId),
            agentId: AgentID(value: agentId),
            startedAt: startedAt,
            endedAt: endedAt,
            status: SessionStatus(rawValue: status) ?? .active
        )
    }

    static func fromDomain(_ session: Session) -> SessionRecord {
        SessionRecord(
            id: session.id.value,
            projectId: session.projectId.value,
            agentId: session.agentId.value,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            status: session.status.rawValue
        )
    }
}

// MARK: - SessionRepository

public final class SessionRepository: SessionRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: SessionID) throws -> Session? {
        try db.read { db in
            try SessionRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findActive(agentId: AgentID) throws -> Session? {
        try db.read { db in
            try SessionRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("status") == SessionStatus.active.rawValue)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findByProject(_ projectId: ProjectID) throws -> [Session] {
        try db.read { db in
            try SessionRecord
                .filter(Column("project_id") == projectId.value)
                .order(Column("started_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findByAgent(_ agentId: AgentID) throws -> [Session] {
        try db.read { db in
            try SessionRecord
                .filter(Column("agent_id") == agentId.value)
                .order(Column("started_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func save(_ session: Session) throws {
        try db.write { db in
            try SessionRecord.fromDomain(session).save(db)
        }
    }
}
