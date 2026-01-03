// Sources/Infrastructure/Repositories/TemplateTaskRepository.swift
// 参照: docs/requirements/WORKFLOW_TEMPLATES.md

import Foundation
import GRDB
import Domain

// MARK: - TemplateTaskRecord

/// GRDB用のTemplateTaskレコード
struct TemplateTaskRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "template_tasks"

    var id: String
    var templateId: String
    var title: String
    var description: String
    var order: Int
    var dependsOnOrders: String? // JSON array
    var defaultAssigneeRole: String?
    var defaultPriority: String
    var estimatedMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case templateId = "template_id"
        case title
        case description
        case order
        case dependsOnOrders = "depends_on_orders"
        case defaultAssigneeRole = "default_assignee_role"
        case defaultPriority = "default_priority"
        case estimatedMinutes = "estimated_minutes"
    }

    func toDomain() -> TemplateTask {
        var dependsOnList: [Int] = []
        if let dependsOnJson = dependsOnOrders,
           let data = dependsOnJson.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Int].self, from: data) {
            dependsOnList = decoded
        }

        return TemplateTask(
            id: TemplateTaskID(value: id),
            templateId: WorkflowTemplateID(value: templateId),
            title: title,
            description: description,
            order: order,
            dependsOnOrders: dependsOnList,
            defaultAssigneeRole: defaultAssigneeRole.flatMap { AgentRoleType(rawValue: $0) },
            defaultPriority: TaskPriority(rawValue: defaultPriority) ?? .medium,
            estimatedMinutes: estimatedMinutes
        )
    }

    static func fromDomain(_ task: TemplateTask) -> TemplateTaskRecord {
        var dependsOnJson: String?
        if !task.dependsOnOrders.isEmpty,
           let data = try? JSONEncoder().encode(task.dependsOnOrders) {
            dependsOnJson = String(data: data, encoding: .utf8)
        }

        return TemplateTaskRecord(
            id: task.id.value,
            templateId: task.templateId.value,
            title: task.title,
            description: task.description,
            order: task.order,
            dependsOnOrders: dependsOnJson,
            defaultAssigneeRole: task.defaultAssigneeRole?.rawValue,
            defaultPriority: task.defaultPriority.rawValue,
            estimatedMinutes: task.estimatedMinutes
        )
    }
}

// MARK: - TemplateTaskRepository

/// テンプレートタスクのリポジトリ
public final class TemplateTaskRepository: TemplateTaskRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: TemplateTaskID) throws -> TemplateTask? {
        try db.read { db in
            try TemplateTaskRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findByTemplate(_ templateId: WorkflowTemplateID) throws -> [TemplateTask] {
        try db.read { db in
            try TemplateTaskRecord
                .filter(Column("template_id") == templateId.value)
                .order(Column("order").asc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func save(_ task: TemplateTask) throws {
        try db.write { db in
            try TemplateTaskRecord.fromDomain(task).save(db)
        }
    }

    public func delete(_ id: TemplateTaskID) throws {
        try db.write { db in
            _ = try TemplateTaskRecord.deleteOne(db, key: id.value)
        }
    }

    public func deleteByTemplate(_ templateId: WorkflowTemplateID) throws {
        try db.write { db in
            _ = try TemplateTaskRecord
                .filter(Column("template_id") == templateId.value)
                .deleteAll(db)
        }
    }
}
