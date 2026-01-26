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
    var startedAt: Date?
    var conversationId: String?

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case projectId = "project_id"
        case purpose
        case createdAt = "created_at"
        case startedAt = "started_at"
        case conversationId = "conversation_id"
    }

    func toDomain() -> PendingAgentPurpose {
        PendingAgentPurpose(
            agentId: AgentID(value: agentId),
            projectId: ProjectID(value: projectId),
            purpose: AgentPurpose(rawValue: purpose) ?? .task,
            createdAt: createdAt,
            startedAt: startedAt,
            conversationId: conversationId.map { ConversationID(value: $0) }
        )
    }

    static func fromDomain(_ entity: PendingAgentPurpose) -> PendingAgentPurposeRecord {
        PendingAgentPurposeRecord(
            agentId: entity.agentId.value,
            projectId: entity.projectId.value,
            purpose: entity.purpose.rawValue,
            createdAt: entity.createdAt,
            startedAt: entity.startedAt,
            conversationId: entity.conversationId?.value
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

    public func find(agentId: AgentID, projectId: ProjectID, purpose: AgentPurpose) throws -> PendingAgentPurpose? {
        try db.read { db in
            try PendingAgentPurposeRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("project_id") == projectId.value)
                .filter(Column("purpose") == purpose.rawValue)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func find(agentId: AgentID, projectId: ProjectID) throws -> PendingAgentPurpose? {
        // 最も最近startedAtが設定されたものを優先的に返す
        // これにより、複数のpurpose（chat/task）が同時に存在する場合、
        // 最後に起動されたエージェントに対応するpurposeが返される
        // 参照: docs/design/CHAT_FEATURE.md - 同時セッション対応
        //
        // ORDER BY:
        //   1. started_atがある（起動済み）レコードを優先
        //   2. started_at DESC（最近起動されたものを優先）
        //   3. created_at DESC（最近作成されたものを優先）
        try db.read { db in
            try PendingAgentPurposeRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("project_id") == projectId.value)
                .order(
                    // CASE WHEN started_at IS NULL THEN 1 ELSE 0 END - NULLを後ろに
                    SQL("CASE WHEN started_at IS NULL THEN 1 ELSE 0 END"),
                    Column("started_at").desc,
                    Column("created_at").desc
                )
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

    public func delete(agentId: AgentID, projectId: ProjectID, purpose: AgentPurpose) throws {
        _ = try db.write { db in
            try PendingAgentPurposeRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("project_id") == projectId.value)
                .filter(Column("purpose") == purpose.rawValue)
                .deleteAll(db)
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

    /// 起動済みとしてマーク（started_atを更新）
    public func markAsStarted(agentId: AgentID, projectId: ProjectID, purpose: AgentPurpose, startedAt: Date) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE pending_agent_purposes
                    SET started_at = ?
                    WHERE agent_id = ? AND project_id = ? AND purpose = ?
                """,
                arguments: [startedAt, agentId.value, projectId.value, purpose.rawValue]
            )
        }

        // WAL mode: 他プロセスからの可視性を確保
        do {
            try db.write { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE)")
            }
        } catch {
            NSLog("[PendingAgentPurposeRepository] WAL checkpoint failed (non-fatal): \(error)")
        }
    }

    /// started_atをクリア（スポーンタイムアウト時の再スポーン用）
    public func clearStartedAt(agentId: AgentID, projectId: ProjectID, purpose: AgentPurpose) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE pending_agent_purposes
                    SET started_at = NULL
                    WHERE agent_id = ? AND project_id = ? AND purpose = ?
                """,
                arguments: [agentId.value, projectId.value, purpose.rawValue]
            )
        }

        // WAL mode: 他プロセスからの可視性を確保
        do {
            try db.write { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE)")
            }
        } catch {
            NSLog("[PendingAgentPurposeRepository] WAL checkpoint failed (non-fatal): \(error)")
        }
    }

    /// デバッグ用: 全レコードをダンプ
    public func dumpAllForDebug() throws -> [[String: Any]] {
        try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM pending_agent_purposes")
            return rows.map { row in
                var dict: [String: Any] = [:]
                for (column, value) in row {
                    dict[column] = value.databaseValue.storage.value
                }
                return dict
            }
        }
    }
}
