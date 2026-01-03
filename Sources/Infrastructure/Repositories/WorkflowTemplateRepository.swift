// Sources/Infrastructure/Repositories/WorkflowTemplateRepository.swift
// 参照: docs/requirements/WORKFLOW_TEMPLATES.md

import Foundation
import GRDB
import Domain

// MARK: - WorkflowTemplateRecord

/// GRDB用のWorkflowTemplateレコード
struct WorkflowTemplateRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workflow_templates"

    var id: String
    var name: String
    var description: String
    var variables: String? // JSON array
    var status: String
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case variables
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> WorkflowTemplate {
        var variablesList: [String] = []
        if let variablesJson = variables,
           let data = variablesJson.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            variablesList = decoded
        }

        return WorkflowTemplate(
            id: WorkflowTemplateID(value: id),
            name: name,
            description: description,
            variables: variablesList,
            status: TemplateStatus(rawValue: status) ?? .active,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func fromDomain(_ template: WorkflowTemplate) -> WorkflowTemplateRecord {
        var variablesJson: String?
        if !template.variables.isEmpty,
           let data = try? JSONEncoder().encode(template.variables) {
            variablesJson = String(data: data, encoding: .utf8)
        }

        return WorkflowTemplateRecord(
            id: template.id.value,
            name: template.name,
            description: template.description,
            variables: variablesJson,
            status: template.status.rawValue,
            createdAt: template.createdAt,
            updatedAt: template.updatedAt
        )
    }
}

// MARK: - WorkflowTemplateRepository

/// ワークフローテンプレートのリポジトリ
public final class WorkflowTemplateRepository: WorkflowTemplateRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: WorkflowTemplateID) throws -> WorkflowTemplate? {
        try db.read { db in
            try WorkflowTemplateRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findAll(includeArchived: Bool) throws -> [WorkflowTemplate] {
        try db.read { db in
            var query = WorkflowTemplateRecord.all()
            if !includeArchived {
                query = query.filter(Column("status") == TemplateStatus.active.rawValue)
            }
            return try query
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findActive() throws -> [WorkflowTemplate] {
        try findAll(includeArchived: false)
    }

    public func save(_ template: WorkflowTemplate) throws {
        try db.write { db in
            try WorkflowTemplateRecord.fromDomain(template).save(db)
        }
    }

    public func delete(_ id: WorkflowTemplateID) throws {
        try db.write { db in
            _ = try WorkflowTemplateRecord.deleteOne(db, key: id.value)
        }
    }
}
