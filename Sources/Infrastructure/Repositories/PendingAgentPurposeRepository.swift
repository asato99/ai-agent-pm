// Sources/Infrastructure/Repositories/PendingAgentPurposeRepository.swift
// 参照: docs/design/CHAT_FEATURE.md - MCP連携設計

import Foundation
import GRDB
import Domain

// MARK: - PendingAgentPurposeRecord

/// GRDB用のPendingAgentPurposeレコード
struct PendingAgentPurposeRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pending_agent_purposes"

    var agentId: String
    var projectId: String
    var purpose: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case projectId = "project_id"
        case purpose
        case createdAt = "created_at"
    }

    func toDomain() -> PendingAgentPurpose {
        PendingAgentPurpose(
            agentId: AgentID(value: agentId),
            projectId: ProjectID(value: projectId),
            purpose: AgentPurpose(rawValue: purpose) ?? .task,
            createdAt: createdAt
        )
    }

    static func fromDomain(_ entity: PendingAgentPurpose) -> PendingAgentPurposeRecord {
        PendingAgentPurposeRecord(
            agentId: entity.agentId.value,
            projectId: entity.projectId.value,
            purpose: entity.purpose.rawValue,
            createdAt: entity.createdAt
        )
    }
}

// MARK: - PendingAgentPurposeRepository

/// 起動待ちエージェントの起動理由リポジトリ
public final class PendingAgentPurposeRepository: PendingAgentPurposeRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func find(agentId: AgentID, projectId: ProjectID) throws -> PendingAgentPurpose? {
        try db.read { db in
            try PendingAgentPurposeRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("project_id") == projectId.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func save(_ purpose: PendingAgentPurpose) throws {
        try db.write { db in
            // UPSERT: 既存があれば上書き
            try PendingAgentPurposeRecord.fromDomain(purpose)
                .save(db, onConflict: .replace)
        }

        // WAL mode: 他プロセスからの可視性を確保するためにチェックポイント実行
        // これにより、WALファイルの内容がメインDBファイルにフラッシュされる
        do {
            try db.write { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE)")
            }
        } catch {
            // チェックポイント失敗は致命的ではない（WALには既にコミット済み）
            NSLog("[PendingAgentPurposeRepository] WAL checkpoint failed (non-fatal): \(error)")
        }
    }

    public func delete(agentId: AgentID, projectId: ProjectID) throws {
        _ = try db.write { db in
            try PendingAgentPurposeRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("project_id") == projectId.value)
                .deleteAll(db)
        }
    }

    public func deleteExpired(olderThan date: Date) throws {
        _ = try db.write { db in
            try PendingAgentPurposeRecord
                .filter(Column("created_at") < date)
                .deleteAll(db)
        }
    }
}
