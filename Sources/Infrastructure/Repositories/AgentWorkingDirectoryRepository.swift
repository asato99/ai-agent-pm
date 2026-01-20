// Sources/Infrastructure/Repositories/AgentWorkingDirectoryRepository.swift
// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.1

import Foundation
import GRDB
import Domain

// MARK: - AgentWorkingDirectoryRecord

/// GRDB用のAgentWorkingDirectoryレコード
struct AgentWorkingDirectoryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_working_directories"

    var id: String
    var agentId: String
    var projectId: String
    var workingDirectory: String
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case agentId = "agent_id"
        case projectId = "project_id"
        case workingDirectory = "working_directory"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> AgentWorkingDirectory {
        AgentWorkingDirectory(
            id: AgentWorkingDirectoryID(value: id),
            agentId: AgentID(value: agentId),
            projectId: ProjectID(value: projectId),
            workingDirectory: workingDirectory,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func fromDomain(_ awd: AgentWorkingDirectory) -> AgentWorkingDirectoryRecord {
        AgentWorkingDirectoryRecord(
            id: awd.id.value,
            agentId: awd.agentId.value,
            projectId: awd.projectId.value,
            workingDirectory: awd.workingDirectory,
            createdAt: awd.createdAt,
            updatedAt: awd.updatedAt
        )
    }
}

// MARK: - AgentWorkingDirectoryRepository

/// エージェントワーキングディレクトリのリポジトリ
public final class AgentWorkingDirectoryRepository: AgentWorkingDirectoryRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: AgentWorkingDirectoryID) throws -> AgentWorkingDirectory? {
        try db.read { db in
            try AgentWorkingDirectoryRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findByAgentAndProject(agentId: AgentID, projectId: ProjectID) throws -> AgentWorkingDirectory? {
        try db.read { db in
            try AgentWorkingDirectoryRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("project_id") == projectId.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findByAgent(_ agentId: AgentID) throws -> [AgentWorkingDirectory] {
        try db.read { db in
            try AgentWorkingDirectoryRecord
                .filter(Column("agent_id") == agentId.value)
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findByProject(_ projectId: ProjectID) throws -> [AgentWorkingDirectory] {
        try db.read { db in
            try AgentWorkingDirectoryRecord
                .filter(Column("project_id") == projectId.value)
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func save(_ workingDirectory: AgentWorkingDirectory) throws {
        try db.write { db in
            try AgentWorkingDirectoryRecord.fromDomain(workingDirectory).save(db)
        }
    }

    public func delete(_ id: AgentWorkingDirectoryID) throws {
        try db.write { db in
            _ = try AgentWorkingDirectoryRecord.deleteOne(db, key: id.value)
        }
    }

    public func deleteByAgentAndProject(agentId: AgentID, projectId: ProjectID) throws {
        try db.write { db in
            _ = try AgentWorkingDirectoryRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("project_id") == projectId.value)
                .deleteAll(db)
        }
    }
}
