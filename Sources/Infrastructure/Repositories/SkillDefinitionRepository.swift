// Sources/Infrastructure/Repositories/SkillDefinitionRepository.swift
// 参照: docs/design/AGENT_SKILLS.md - スキル定義リポジトリ

import Foundation
import GRDB
import Domain

// MARK: - SkillDefinitionRecord

/// GRDB用のSkillDefinitionレコード
struct SkillDefinitionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "skill_definitions"

    var id: String
    var name: String
    var description: String
    var directoryName: String
    var content: String
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case directoryName = "directory_name"
        case content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> SkillDefinition {
        SkillDefinition(
            id: SkillID(value: id),
            name: name,
            description: description,
            directoryName: directoryName,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func fromDomain(_ skill: SkillDefinition) -> SkillDefinitionRecord {
        SkillDefinitionRecord(
            id: skill.id.value,
            name: skill.name,
            description: skill.description,
            directoryName: skill.directoryName,
            content: skill.content,
            createdAt: skill.createdAt,
            updatedAt: skill.updatedAt
        )
    }
}

// MARK: - SkillDefinitionRepository

/// スキル定義のリポジトリ
public final class SkillDefinitionRepository: SkillDefinitionRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findAll() throws -> [SkillDefinition] {
        try db.read { db in
            try SkillDefinitionRecord
                .order(Column("name").asc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findById(_ id: SkillID) throws -> SkillDefinition? {
        try db.read { db in
            try SkillDefinitionRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findByDirectoryName(_ directoryName: String) throws -> SkillDefinition? {
        try db.read { db in
            try SkillDefinitionRecord
                .filter(Column("directory_name") == directoryName)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func save(_ skill: SkillDefinition) throws {
        try db.write { db in
            try SkillDefinitionRecord.fromDomain(skill).save(db)
        }
    }

    public func delete(_ id: SkillID) throws {
        try db.write { db in
            _ = try SkillDefinitionRecord.deleteOne(db, key: id.value)
        }
    }

    public func isInUse(_ id: SkillID) throws -> Bool {
        try db.read { db in
            let count = try AgentSkillAssignmentRecord
                .filter(Column("skill_id") == id.value)
                .fetchCount(db)
            return count > 0
        }
    }
}
