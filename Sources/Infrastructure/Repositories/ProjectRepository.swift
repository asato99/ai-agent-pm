// Sources/Infrastructure/Repositories/ProjectRepository.swift
// 参照: docs/architecture/DATABASE_SCHEMA.md - projects テーブル

import Foundation
import GRDB
import Domain

// MARK: - ProjectRecord

/// GRDB用のProjectレコード
struct ProjectRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projects"

    var id: String
    var name: String
    var description: String
    var status: String
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> Project {
        Project(
            id: ProjectID(value: id),
            name: name,
            description: description,
            status: ProjectStatus(rawValue: status) ?? .active,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func fromDomain(_ project: Project) -> ProjectRecord {
        ProjectRecord(
            id: project.id.value,
            name: project.name,
            description: project.description,
            status: project.status.rawValue,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
    }
}

// MARK: - ProjectRepository

/// プロジェクトのリポジトリ
public final class ProjectRepository: ProjectRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: ProjectID) throws -> Project? {
        try db.read { db in
            try ProjectRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findAll() throws -> [Project] {
        try db.read { db in
            try ProjectRecord
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func save(_ project: Project) throws {
        try db.write { db in
            try ProjectRecord.fromDomain(project).save(db)
        }
    }

    public func delete(_ id: ProjectID) throws {
        try db.write { db in
            _ = try ProjectRecord.deleteOne(db, key: id.value)
        }
    }
}
