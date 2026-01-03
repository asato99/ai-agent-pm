// Sources/Infrastructure/Repositories/InternalAuditRepository.swift
// 参照: docs/requirements/AUDIT.md

import Foundation
import GRDB
import Domain

// MARK: - InternalAuditRecord

/// GRDB用のInternalAuditレコード
struct InternalAuditRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "internal_audits"

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

    func toDomain() -> InternalAudit {
        InternalAudit(
            id: InternalAuditID(value: id),
            name: name,
            description: description.isEmpty ? nil : description,
            status: AuditStatus(rawValue: status) ?? .active,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func fromDomain(_ audit: InternalAudit) -> InternalAuditRecord {
        InternalAuditRecord(
            id: audit.id.value,
            name: audit.name,
            description: audit.description ?? "",
            status: audit.status.rawValue,
            createdAt: audit.createdAt,
            updatedAt: audit.updatedAt
        )
    }
}

// MARK: - InternalAuditRepository

/// Internal Auditのリポジトリ
public final class InternalAuditRepository: InternalAuditRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: InternalAuditID) throws -> InternalAudit? {
        try db.read { db in
            try InternalAuditRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findAll(includeInactive: Bool) throws -> [InternalAudit] {
        try db.read { db in
            var query = InternalAuditRecord.all()
            if !includeInactive {
                query = query.filter(Column("status") == AuditStatus.active.rawValue)
            }
            return try query
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findActive() throws -> [InternalAudit] {
        try findAll(includeInactive: false)
    }

    public func save(_ audit: InternalAudit) throws {
        try db.write { db in
            try InternalAuditRecord.fromDomain(audit).save(db)
        }
    }

    public func delete(_ id: InternalAuditID) throws {
        try db.write { db in
            _ = try InternalAuditRecord.deleteOne(db, key: id.value)
        }
    }
}

// MARK: - AuditRuleRecord

/// GRDB用のAuditRuleレコード
struct AuditRuleRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "audit_rules"

    var id: String
    var auditId: String
    var name: String
    var triggerType: String
    var triggerConfig: String?
    var workflowTemplateId: String
    var taskAssignments: String?
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case auditId = "audit_id"
        case name
        case triggerType = "trigger_type"
        case triggerConfig = "trigger_config"
        case workflowTemplateId = "workflow_template_id"
        case taskAssignments = "task_assignments"
        case isEnabled = "is_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> AuditRule {
        // Parse task assignments from JSON
        var assignments: [TaskAssignment] = []
        if let assignmentsJson = taskAssignments,
           let data = assignmentsJson.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([TaskAssignmentDTO].self, from: data) {
            assignments = decoded.map { dto in
                TaskAssignment(
                    templateTaskOrder: dto.templateTaskOrder,
                    agentId: AgentID(value: dto.agentId)
                )
            }
        }

        // Parse trigger config from JSON (simplified - as dictionary keys)
        var config: [String: Any]?
        if let configJson = triggerConfig,
           let data = configJson.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = decoded
        }

        return AuditRule(
            id: AuditRuleID(value: id),
            auditId: InternalAuditID(value: auditId),
            name: name,
            triggerType: TriggerType(rawValue: triggerType) ?? .taskCompleted,
            triggerConfig: config,
            workflowTemplateId: WorkflowTemplateID(value: workflowTemplateId),
            taskAssignments: assignments,
            isEnabled: isEnabled,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func fromDomain(_ rule: AuditRule) -> AuditRuleRecord {
        // Encode task assignments to JSON
        var assignmentsJson: String?
        if !rule.taskAssignments.isEmpty {
            let dtos = rule.taskAssignments.map { assignment in
                TaskAssignmentDTO(
                    templateTaskOrder: assignment.templateTaskOrder,
                    agentId: assignment.agentId.value
                )
            }
            if let data = try? JSONEncoder().encode(dtos) {
                assignmentsJson = String(data: data, encoding: .utf8)
            }
        }

        // Encode trigger config to JSON
        var configJson: String?
        if let config = rule.triggerConfig,
           let data = try? JSONSerialization.data(withJSONObject: config) {
            configJson = String(data: data, encoding: .utf8)
        }

        return AuditRuleRecord(
            id: rule.id.value,
            auditId: rule.auditId.value,
            name: rule.name,
            triggerType: rule.triggerType.rawValue,
            triggerConfig: configJson,
            workflowTemplateId: rule.workflowTemplateId.value,
            taskAssignments: assignmentsJson,
            isEnabled: rule.isEnabled,
            createdAt: rule.createdAt,
            updatedAt: rule.updatedAt
        )
    }
}

/// TaskAssignment用のDTO（JSON エンコード/デコード用）
private struct TaskAssignmentDTO: Codable {
    let templateTaskOrder: Int
    let agentId: String
}

// MARK: - AuditRuleRepository

/// Audit Ruleのリポジトリ
public final class AuditRuleRepository: AuditRuleRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: AuditRuleID) throws -> AuditRule? {
        try db.read { db in
            try AuditRuleRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findByAudit(_ auditId: InternalAuditID) throws -> [AuditRule] {
        try db.read { db in
            try AuditRuleRecord
                .filter(Column("audit_id") == auditId.value)
                .order(Column("created_at"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findEnabled(auditId: InternalAuditID) throws -> [AuditRule] {
        try db.read { db in
            try AuditRuleRecord
                .filter(Column("audit_id") == auditId.value)
                .filter(Column("is_enabled") == true)
                .order(Column("created_at"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findByTriggerType(_ triggerType: TriggerType) throws -> [AuditRule] {
        try db.read { db in
            try AuditRuleRecord
                .filter(Column("trigger_type") == triggerType.rawValue)
                .order(Column("created_at"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func save(_ rule: AuditRule) throws {
        try db.write { db in
            try AuditRuleRecord.fromDomain(rule).save(db)
        }
    }

    public func delete(_ id: AuditRuleID) throws {
        try db.write { db in
            _ = try AuditRuleRecord.deleteOne(db, key: id.value)
        }
    }
}
