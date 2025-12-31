// Sources/Infrastructure/Repositories/AgentRepository.swift
// 参照: docs/architecture/DATABASE_SCHEMA.md - agents テーブル

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
    var roleType: String
    var capabilities: String?
    var systemPrompt: String?
    var status: String
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case name
        case role
        case type
        case roleType = "role_type"
        case capabilities
        case systemPrompt = "system_prompt"
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
            projectId: ProjectID(value: projectId),
            name: name,
            role: role,
            type: AgentType(rawValue: type) ?? .ai,
            roleType: AgentRoleType(rawValue: roleType) ?? .developer,
            capabilities: caps,
            systemPrompt: systemPrompt,
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
            projectId: agent.projectId.value,
            name: agent.name,
            role: agent.role,
            type: agent.type.rawValue,
            roleType: agent.roleType.rawValue,
            capabilities: capsJson,
            systemPrompt: agent.systemPrompt,
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

    public func findByProject(_ projectId: ProjectID) throws -> [Agent] {
        try db.read { db in
            try AgentRecord
                .filter(Column("project_id") == projectId.value)
                .order(Column("name"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findAll(projectId: ProjectID) throws -> [Agent] {
        try findByProject(projectId)
    }

    public func findByType(_ type: AgentType, projectId: ProjectID) throws -> [Agent] {
        try db.read { db in
            try AgentRecord
                .filter(Column("project_id") == projectId.value)
                .filter(Column("type") == type.rawValue)
                .order(Column("name"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
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
