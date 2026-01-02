// Sources/Infrastructure/Repositories/AgentRepository.swift
// 参照: docs/architecture/DATABASE_SCHEMA.md - agents テーブル
// 要件: エージェントはプロジェクト非依存、階層構造をサポート

import Foundation
import GRDB
import Domain

// MARK: - AgentRecord

/// GRDB用のAgentレコード
struct AgentRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agents"

    var id: String
    var name: String
    var role: String
    var type: String
    var roleType: String
    var parentAgentId: String?
    var maxParallelTasks: Int
    var capabilities: String?
    var systemPrompt: String?
    var kickMethod: String
    var kickCommand: String?
    var authLevel: String
    var passkey: String?
    var status: String
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case role
        case type
        case roleType = "role_type"
        case parentAgentId = "parent_agent_id"
        case maxParallelTasks = "max_parallel_tasks"
        case capabilities
        case systemPrompt = "system_prompt"
        case kickMethod = "kick_method"
        case kickCommand = "kick_command"
        case authLevel = "auth_level"
        case passkey
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> Agent {
        var caps: [String] = []
        if let capabilitiesJson = capabilities,
           let data = capabilitiesJson.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String].self, from: data) {
            caps = parsed
        }

        return Agent(
            id: AgentID(value: id),
            name: name,
            role: role,
            type: AgentType(rawValue: type) ?? .ai,
            roleType: AgentRoleType(rawValue: roleType) ?? .developer,
            parentAgentId: parentAgentId.map { AgentID(value: $0) },
            maxParallelTasks: maxParallelTasks,
            capabilities: caps,
            systemPrompt: systemPrompt,
            kickMethod: KickMethod(rawValue: kickMethod) ?? .cli,
            kickCommand: kickCommand,
            authLevel: AuthLevel(rawValue: authLevel) ?? .level0,
            passkey: passkey,
            status: AgentStatus(rawValue: status) ?? .active,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func fromDomain(_ agent: Agent) -> AgentRecord {
        var capsJson: String?
        if !agent.capabilities.isEmpty,
           let data = try? JSONEncoder().encode(agent.capabilities) {
            capsJson = String(data: data, encoding: .utf8)
        }

        return AgentRecord(
            id: agent.id.value,
            name: agent.name,
            role: agent.role,
            type: agent.type.rawValue,
            roleType: agent.roleType.rawValue,
            parentAgentId: agent.parentAgentId?.value,
            maxParallelTasks: agent.maxParallelTasks,
            capabilities: capsJson,
            systemPrompt: agent.systemPrompt,
            kickMethod: agent.kickMethod.rawValue,
            kickCommand: agent.kickCommand,
            authLevel: agent.authLevel.rawValue,
            passkey: agent.passkey,
            status: agent.status.rawValue,
            createdAt: agent.createdAt,
            updatedAt: agent.updatedAt
        )
    }
}

// MARK: - AgentRepository

/// エージェントのリポジトリ
public final class AgentRepository: AgentRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: AgentID) throws -> Agent? {
        try db.read { db in
            try AgentRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findAll() throws -> [Agent] {
        try db.read { db in
            try AgentRecord
                .order(Column("name"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findByType(_ type: AgentType) throws -> [Agent] {
        try db.read { db in
            try AgentRecord
                .filter(Column("type") == type.rawValue)
                .order(Column("name"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findByParent(_ parentAgentId: AgentID?) throws -> [Agent] {
        try db.read { db in
            if let parentId = parentAgentId {
                return try AgentRecord
                    .filter(Column("parent_agent_id") == parentId.value)
                    .order(Column("name"))
                    .fetchAll(db)
                    .map { $0.toDomain() }
            } else {
                return try AgentRecord
                    .filter(Column("parent_agent_id") == nil)
                    .order(Column("name"))
                    .fetchAll(db)
                    .map { $0.toDomain() }
            }
        }
    }

    public func findRootAgents() throws -> [Agent] {
        try findByParent(nil)
    }

    public func save(_ agent: Agent) throws {
        try db.write { db in
            try AgentRecord.fromDomain(agent).save(db)
        }
    }

    public func delete(_ id: AgentID) throws {
        try db.write { db in
            _ = try AgentRecord.deleteOne(db, key: id.value)
        }
    }
}
