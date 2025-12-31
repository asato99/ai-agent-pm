// Sources/Infrastructure/Repositories/AgentRepository.swift
// 参照: docs/architecture/DATABASE_SCHEMA.md - agents テーブル
// 参照: docs/prd/AGENT_CONCEPT.md - エージェント管理

import Foundation
import GRDB
import Domain

// MARK: - AgentRecord

/// GRDB用のAgentレコード
struct AgentRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agents"

    var id: String
    var projectId: String
    var name: String
    var role: String
    var type: String

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case name
        case role
        case type
    }

    // Domain Entityへの変換
    func toDomain() -> Agent {
        Agent(
            id: AgentID(value: id),
            name: name,
            role: role,
            type: AgentType(rawValue: type) ?? .ai
        )
    }

    // Domain EntityからRecordへの変換
    static func fromDomain(_ agent: Agent, projectId: ProjectID) -> AgentRecord {
        AgentRecord(
            id: agent.id.value,
            projectId: projectId.value,
            name: agent.name,
            role: agent.role,
            type: agent.type.rawValue
        )
    }
}

// MARK: - AgentRepository

/// エージェントのリポジトリ
public final class AgentRepository: Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    /// IDでエージェントを取得
    public func findById(_ id: AgentID) throws -> Agent? {
        try db.read { db in
            try AgentRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    /// プロジェクト内の全エージェントを取得
    public func findAll(projectId: ProjectID) throws -> [Agent] {
        try db.read { db in
            try AgentRecord
                .filter(Column("project_id") == projectId.value)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// エージェントを保存（作成または更新）
    public func save(_ agent: Agent, projectId: ProjectID) throws {
        try db.write { db in
            try AgentRecord.fromDomain(agent, projectId: projectId).save(db)
        }
    }

    /// エージェントを削除
    public func delete(_ id: AgentID) throws {
        try db.write { db in
            _ = try AgentRecord.deleteOne(db, key: id.value)
        }
    }
}
