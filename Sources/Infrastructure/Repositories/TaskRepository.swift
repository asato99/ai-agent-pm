// Sources/Infrastructure/Repositories/TaskRepository.swift
// 参照: docs/architecture/DATABASE_SCHEMA.md - tasks テーブル

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
    var description: String
    var status: String
    var priority: String
    var assigneeId: String?
    var dependencies: String?
    var estimatedMinutes: Int?
    var actualMinutes: Int?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    // Lock fields
    var isLocked: Bool
    var lockedByAuditId: String?
    var lockedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case title
        case description
        case status
        case priority
        case assigneeId = "assignee_id"
        case dependencies
        case estimatedMinutes = "estimated_minutes"
        case actualMinutes = "actual_minutes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case isLocked = "is_locked"
        case lockedByAuditId = "locked_by_audit_id"
        case lockedAt = "locked_at"
    }

    func toDomain() -> Task {
        var deps: [TaskID] = []
        if let depsJson = dependencies,
           let data = depsJson.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String].self, from: data) {
            deps = parsed.map { TaskID(value: $0) }
        }

        return Task(
            id: TaskID(value: id),
            projectId: ProjectID(value: projectId),
            title: title,
            description: description,
            status: TaskStatus(rawValue: status) ?? .backlog,
            priority: TaskPriority(rawValue: priority) ?? .medium,
            assigneeId: assigneeId.map { AgentID(value: $0) },
            dependencies: deps,
            estimatedMinutes: estimatedMinutes,
            actualMinutes: actualMinutes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt,
            isLocked: isLocked,
            lockedByAuditId: lockedByAuditId.map { InternalAuditID(value: $0) },
            lockedAt: lockedAt
        )
    }

    static func fromDomain(_ task: Task) -> TaskRecord {
        var depsJson: String?
        if !task.dependencies.isEmpty {
            let depIds = task.dependencies.map { $0.value }
            if let data = try? JSONEncoder().encode(depIds) {
                depsJson = String(data: data, encoding: .utf8)
            }
        }

        return TaskRecord(
            id: task.id.value,
            projectId: task.projectId.value,
            title: task.title,
            description: task.description,
            status: task.status.rawValue,
            priority: task.priority.rawValue,
            assigneeId: task.assigneeId?.value,
            dependencies: depsJson,
            estimatedMinutes: task.estimatedMinutes,
            actualMinutes: task.actualMinutes,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            completedAt: task.completedAt,
            isLocked: task.isLocked,
            lockedByAuditId: task.lockedByAuditId?.value,
            lockedAt: task.lockedAt
        )
    }
}

// MARK: - TaskRepository

/// タスクのリポジトリ
public final class TaskRepository: TaskRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: TaskID) throws -> Task? {
        try db.read { db in
            try TaskRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findAll(projectId: ProjectID) throws -> [Task] {
        try db.read { db in
            try TaskRecord
                .filter(Column("project_id") == projectId.value)
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findByProject(_ projectId: ProjectID, status: TaskStatus?) throws -> [Task] {
        try db.read { db in
            var request = TaskRecord.filter(Column("project_id") == projectId.value)
            if let status = status {
                request = request.filter(Column("status") == status.rawValue)
            }
            return try request
                .order(Column("priority"), Column("updated_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findByAssignee(_ agentId: AgentID) throws -> [Task] {
        try db.read { db in
            try TaskRecord
                .filter(Column("assignee_id") == agentId.value)
                .order(Column("priority"), Column("updated_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// 全タスクを取得（プロジェクト横断）
    /// ステートレスMCPサーバー用
    public func findAllTasks() throws -> [Task] {
        try db.read { db in
            try TaskRecord
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findByStatus(_ status: TaskStatus, projectId: ProjectID) throws -> [Task] {
        try db.read { db in
            try TaskRecord
                .filter(Column("project_id") == projectId.value)
                .filter(Column("status") == status.rawValue)
                .order(Column("priority"), Column("updated_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findLocked(byAuditId auditId: InternalAuditID?) throws -> [Task] {
        try db.read { db in
            var request = TaskRecord.filter(Column("is_locked") == true)
            if let auditId = auditId {
                request = request.filter(Column("locked_by_audit_id") == auditId.value)
            }
            return try request
                .order(Column("locked_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func save(_ task: Task) throws {
        try db.write { db in
            try TaskRecord.fromDomain(task).save(db)
        }
    }

    public func delete(_ id: TaskID) throws {
        try db.write { db in
            _ = try TaskRecord.deleteOne(db, key: id.value)
        }
    }
}
