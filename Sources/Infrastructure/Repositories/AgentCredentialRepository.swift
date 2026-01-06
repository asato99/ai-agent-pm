// Sources/Infrastructure/Repositories/AgentCredentialRepository.swift
// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-1 認証基盤

import Foundation
import GRDB
import Domain

// MARK: - AgentCredentialRecord

/// GRDB用のAgentCredentialレコード
struct AgentCredentialRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_credentials"

    var id: String
    var agentId: String
    var passkeyHash: String
    var salt: String
    var createdAt: Date
    var lastUsedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case agentId = "agent_id"
        case passkeyHash = "passkey_hash"
        case salt
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }

    func toDomain() -> AgentCredential {
        AgentCredential(
            id: AgentCredentialID(value: id),
            agentId: AgentID(value: agentId),
            passkeyHash: passkeyHash,
            salt: salt,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt
        )
    }

    static func fromDomain(_ credential: AgentCredential) -> AgentCredentialRecord {
        AgentCredentialRecord(
            id: credential.id.value,
            agentId: credential.agentId.value,
            passkeyHash: credential.passkeyHash,
            salt: credential.salt,
            createdAt: credential.createdAt,
            lastUsedAt: credential.lastUsedAt
        )
    }
}

// MARK: - AgentCredentialRepository

/// エージェント認証情報のリポジトリ
public final class AgentCredentialRepository: AgentCredentialRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: AgentCredentialID) throws -> AgentCredential? {
        try db.read { db in
            try AgentCredentialRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findByAgentId(_ agentId: AgentID) throws -> AgentCredential? {
        try db.read { db in
            try AgentCredentialRecord
                .filter(Column("agent_id") == agentId.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func save(_ credential: AgentCredential) throws {
        try db.write { db in
            try AgentCredentialRecord.fromDomain(credential).save(db)
        }
    }

    public func delete(_ id: AgentCredentialID) throws {
        try db.write { db in
            _ = try AgentCredentialRecord.deleteOne(db, key: id.value)
        }
    }
}
