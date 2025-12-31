// Sources/Infrastructure/Repositories/ProjectRepository.swift
// 参照: docs/architecture/DATABASE_SCHEMA.md - projects テーブル
// 参照: docs/guide/CLEAN_ARCHITECTURE.md - Repository パターン

import Foundation
import GRDB
import Domain

// MARK: - ProjectRecord

/// GRDB用のProjectレコード
struct ProjectRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projects"

    var id: String
    var name: String

    // Domain Entityへの変換
    func toDomain() -> Project {
        Project(
            id: ProjectID(value: id),
            name: name
        )
    }

    // Domain EntityからRecordへの変換
    static func fromDomain(_ project: Project) -> ProjectRecord {
        ProjectRecord(
            id: project.id.value,
            name: project.name
        )
    }
}

// MARK: - ProjectRepository

/// プロジェクトのリポジトリ
public final class ProjectRepository: Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    /// IDでプロジェクトを取得
    public func findById(_ id: ProjectID) throws -> Project? {
        try db.read { db in
            try ProjectRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    /// 全プロジェクトを取得
    public func findAll() throws -> [Project] {
        try db.read { db in
            try ProjectRecord
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// プロジェクトを保存（作成または更新）
    public func save(_ project: Project) throws {
        try db.write { db in
            try ProjectRecord.fromDomain(project).save(db)
        }
    }

    /// プロジェクトを削除
    public func delete(_ id: ProjectID) throws {
        try db.write { db in
            _ = try ProjectRecord.deleteOne(db, key: id.value)
        }
    }
}
