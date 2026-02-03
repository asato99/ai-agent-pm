// Sources/Infrastructure/Repositories/AgentSessionRepository.swift
// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-1 認証基盤
// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md - (agent_id, project_id) 単位のセッション管理
// 参照: docs/design/CHAT_FEATURE.md - セッションの起動理由(purpose)管理
// 参照: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 6: セッション終了フロー

import Foundation
import GRDB
import Domain

// MARK: - AgentSessionRecord

/// GRDB用のAgentSessionレコード
/// Phase 4: project_id を追加して (agent_id, project_id) 単位でセッション管理
/// Chat機能: purpose フィールドで起動理由を管理
struct AgentSessionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_sessions"

    var id: String
    var token: String
    var agentId: String
    /// Phase 4: セッションが紐づくプロジェクトID
    var projectId: String
    /// タスクセッションの場合、処理対象のタスクID
    var taskId: String?
    /// Chat機能: 起動理由（task=タスク実行, chat=チャット応答）
    var purpose: String?
    /// UC015: セッション状態（active, terminating, ended）
    var state: String?
    var expiresAt: Date
    var createdAt: Date
    /// アイドルタイムアウト管理用: 最終アクティビティ日時
    var lastActivityAt: Date?
    // Model verification fields
    var reportedProvider: String?
    var reportedModel: String?
    var modelVerified: Bool?
    var modelVerifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case token
        case agentId = "agent_id"
        case projectId = "project_id"
        case taskId = "task_id"
        case purpose
        case state
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case lastActivityAt = "last_activity_at"
        case reportedProvider = "reported_provider"
        case reportedModel = "reported_model"
        case modelVerified = "model_verified"
        case modelVerifiedAt = "model_verified_at"
    }

    func toDomain() -> AgentSession {
        AgentSession(
            id: AgentSessionID(value: id),
            token: token,
            agentId: AgentID(value: agentId),
            projectId: ProjectID(value: projectId),
            taskId: taskId.map { TaskID(value: $0) },
            purpose: AgentPurpose(rawValue: purpose ?? "task") ?? .task,
            state: SessionState(rawValue: state ?? "active") ?? .active,
            expiresAt: expiresAt,
            createdAt: createdAt,
            lastActivityAt: lastActivityAt,
            reportedProvider: reportedProvider,
            reportedModel: reportedModel,
            modelVerified: modelVerified,
            modelVerifiedAt: modelVerifiedAt
        )
    }

    static func fromDomain(_ session: AgentSession) -> AgentSessionRecord {
        AgentSessionRecord(
            id: session.id.value,
            token: session.token,
            agentId: session.agentId.value,
            projectId: session.projectId.value,
            taskId: session.taskId?.value,
            purpose: session.purpose.rawValue,
            state: session.state.rawValue,
            expiresAt: session.expiresAt,
            createdAt: session.createdAt,
            lastActivityAt: session.lastActivityAt,
            reportedProvider: session.reportedProvider,
            reportedModel: session.reportedModel,
            modelVerified: session.modelVerified,
            modelVerifiedAt: session.modelVerifiedAt
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

    /// Phase 4: (agent_id, project_id) 単位でセッションを検索
    public func findByAgentIdAndProjectId(_ agentId: AgentID, projectId: ProjectID) throws -> [AgentSession] {
        try db.read { db in
            try AgentSessionRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("project_id") == projectId.value)
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// Feature 14: プロジェクトIDでセッションを検索（一時停止時のセッション有効期限短縮用）
    public func findByProjectId(_ projectId: ProjectID) throws -> [AgentSession] {
        try db.read { db in
            try AgentSessionRecord
                .filter(Column("project_id") == projectId.value)
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

    /// Phase 4: セッショントークンでセッションを削除
    public func deleteByToken(_ token: String) throws {
        try db.write { db in
            _ = try AgentSessionRecord
                .filter(Column("token") == token)
                .deleteAll(db)
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

    /// アクティブなセッション数をカウント（有効期限内のもの）
    public func countActiveSessions(agentId: AgentID) throws -> Int {
        try db.read { db in
            try AgentSessionRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("expires_at") > Date())
                .fetchCount(db)
        }
    }

    /// アクティブなセッション一覧を取得（有効期限内のもの）
    public func findActiveSessions(agentId: AgentID) throws -> [AgentSession] {
        try db.read { db in
            try AgentSessionRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("expires_at") > Date())
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// アクティブなセッション数をpurpose別にカウント（Chat Session Maintenance Mode用）
    /// 参照: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md
    public func countActiveSessionsByPurpose(agentId: AgentID) throws -> [AgentPurpose: Int] {
        try db.read { db in
            let sessions = try AgentSessionRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("expires_at") > Date())
                .fetchAll(db)

            var counts: [AgentPurpose: Int] = [.chat: 0, .task: 0]
            for session in sessions {
                // purpose is optional in DB, default to .task if nil or invalid
                let purposeStr = session.purpose ?? "task"
                let purpose = AgentPurpose(rawValue: purposeStr) ?? .task
                counts[purpose, default: 0] += 1
            }
            return counts
        }
    }

    /// 最終アクティビティ日時を更新（アイドルタイムアウト管理用）
    public func updateLastActivity(token: String, at date: Date = Date()) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE agent_sessions SET last_activity_at = ? WHERE token = ?",
                arguments: [date, token]
            )
        }
    }

    /// セッション状態を更新（UC015: チャットセッション終了）
    /// 参照: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 6
    public func updateState(token: String, state: SessionState) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE agent_sessions SET state = ? WHERE token = ?",
                arguments: [state.rawValue, token]
            )
        }
    }
}
