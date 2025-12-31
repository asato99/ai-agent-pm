// Sources/Infrastructure/Repositories/TaskRepository.swift
// 参照: docs/architecture/DATABASE_SCHEMA.md - tasks テーブル
// 参照: docs/prd/TASK_MANAGEMENT.md - タスク管理

import Foundation
import GRDB
import Domain

// MARK: - TaskRecord

/// GRDB用のTaskレコード
struct TaskRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tasks"

    var id: String
    var projectId: String
    var title: String
    var status: String
    var assigneeId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case title
        case status
        case assigneeId = "assignee_id"
    }

    // Domain Entityへの変換
    func toDomain() -> Task {
        Task(
            id: TaskID(value: id),
            projectId: ProjectID(value: projectId),
            title: title,
            status: TaskStatus(rawValue: status) ?? .backlog,
            assigneeId: assigneeId.map { AgentID(value: $0) }
        )
    }

    // Domain EntityからRecordへの変換
    static func fromDomain(_ task: Task) -> TaskRecord {
        TaskRecord(
            id: task.id.value,
            projectId: task.projectId.value,
            title: task.title,
            status: task.status.rawValue,
            assigneeId: task.assigneeId?.value
        )
    }
}

// MARK: - TaskRepository

/// タスクのリポジトリ
public final class TaskRepository: Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    /// IDでタスクを取得
    public func findById(_ id: TaskID) throws -> Task? {
        try db.read { db in
            try TaskRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    /// プロジェクト内の全タスクを取得
    public func findAll(projectId: ProjectID) throws -> [Task] {
        try db.read { db in
            try TaskRecord
                .filter(Column("project_id") == projectId.value)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// 担当者でタスクを取得
    public func findByAssignee(_ agentId: AgentID) throws -> [Task] {
        try db.read { db in
            try TaskRecord
                .filter(Column("assignee_id") == agentId.value)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// ステータスでタスクを取得
    public func findByStatus(_ status: TaskStatus, projectId: ProjectID) throws -> [Task] {
        try db.read { db in
            try TaskRecord
                .filter(Column("project_id") == projectId.value)
                .filter(Column("status") == status.rawValue)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// タスクを保存（作成または更新）
    public func save(_ task: Task) throws {
        try db.write { db in
            try TaskRecord.fromDomain(task).save(db)
        }
    }

    /// タスクを削除
    public func delete(_ id: TaskID) throws {
        try db.write { db in
            _ = try TaskRecord.deleteOne(db, key: id.value)
        }
    }
}
