// Sources/Infrastructure/Repositories/SubtaskRepository.swift
// 参照: docs/prd/TASK_MANAGEMENT.md - サブタスク

import Foundation
import GRDB
import Domain

// MARK: - SubtaskRecord

struct SubtaskRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "subtasks"

    var id: String
    var taskId: String
    var title: String
    var isCompleted: Bool
    var order: Int
    var createdAt: Date
    var completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case title
        case isCompleted = "is_completed"
        case order
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }

    func toDomain() -> Subtask {
        Subtask(
            id: SubtaskID(value: id),
            taskId: TaskID(value: taskId),
            title: title,
            isCompleted: isCompleted,
            order: order,
            createdAt: createdAt,
            completedAt: completedAt
        )
    }

    static func fromDomain(_ subtask: Subtask) -> SubtaskRecord {
        SubtaskRecord(
            id: subtask.id.value,
            taskId: subtask.taskId.value,
            title: subtask.title,
            isCompleted: subtask.isCompleted,
            order: subtask.order,
            createdAt: subtask.createdAt,
            completedAt: subtask.completedAt
        )
    }
}

// MARK: - SubtaskRepository

public final class SubtaskRepository: SubtaskRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: SubtaskID) throws -> Subtask? {
        try db.read { db in
            try SubtaskRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findByTask(_ taskId: TaskID) throws -> [Subtask] {
        try db.read { db in
            try SubtaskRecord
                .filter(Column("task_id") == taskId.value)
                .order(Column("order"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func save(_ subtask: Subtask) throws {
        try db.write { db in
            try SubtaskRecord.fromDomain(subtask).save(db)
        }
    }

    public func delete(_ id: SubtaskID) throws {
        try db.write { db in
            _ = try SubtaskRecord.deleteOne(db, key: id.value)
        }
    }
}
