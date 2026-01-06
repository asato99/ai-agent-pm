// Sources/Infrastructure/Repositories/AgentSessionRepository.swift
// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-1 認証基盤

import Foundation
import GRDB
import Domain

// MARK: - AgentSessionRecord

/// GRDB用のAgentSessionレコード
struct AgentSessionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_sessions"

    var id: String
    var token: String
    var agentId: String
    var expiresAt: Date
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case token
        case agentId = "agent_id"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    func toDomain() -> AgentSession {
        AgentSession(
            id: AgentSessionID(value: id),
            token: token,
            agentId: AgentID(value: agentId),
            expiresAt: expiresAt,
            createdAt: createdAt
        )
    }

    static func fromDomain(_ session: AgentSession) -> AgentSessionRecord {
        AgentSessionRecord(
            id: session.id.value,
            token: session.token,
            agentId: session.agentId.value,
            expiresAt: session.expiresAt,
            createdAt: session.createdAt
        )
    }
}

// MARK: - AgentSessionRepository

/// エージェントセッションのリポジトリ
public final class AgentSessionRepository: AgentSessionRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: AgentSessionID) throws -> AgentSession? {
        try db.read { db in
            try AgentSessionRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findByToken(_ token: String) throws -> AgentSession? {
        try db.read { db in
            // 有効なセッションのみ返す（期限切れは除外）
            try AgentSessionRecord
                .filter(Column("token") == token)
                .filter(Column("expires_at") > Date())
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findByAgentId(_ agentId: AgentID) throws -> [AgentSession] {
        try db.read { db in
            try AgentSessionRecord
                .filter(Column("agent_id") == agentId.value)
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func save(_ session: AgentSession) throws {
        try db.write { db in
            try AgentSessionRecord.fromDomain(session).save(db)
        }
    }

    public func delete(_ id: AgentSessionID) throws {
        try db.write { db in
            _ = try AgentSessionRecord.deleteOne(db, key: id.value)
        }
    }

    public func deleteByAgentId(_ agentId: AgentID) throws {
        try db.write { db in
            _ = try AgentSessionRecord
                .filter(Column("agent_id") == agentId.value)
                .deleteAll(db)
        }
    }

    public func deleteExpired() throws {
        try db.write { db in
            _ = try AgentSessionRecord
                .filter(Column("expires_at") <= Date())
                .deleteAll(db)
        }
    }
}
