// Sources/Infrastructure/Repositories/AgentSkillAssignmentRepository.swift
// 参照: docs/design/AGENT_SKILLS.md - エージェントスキル割り当てリポジトリ

import Foundation
import GRDB
import Domain

// MARK: - AgentSkillAssignmentRecord

/// GRDB用のAgentSkillAssignmentレコード
struct AgentSkillAssignmentRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_skill_assignments"

    var agentId: String
    var skillId: String
    var assignedAt: Date

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case skillId = "skill_id"
        case assignedAt = "assigned_at"
    }

    func toDomain() -> AgentSkillAssignment {
        AgentSkillAssignment(
            agentId: AgentID(value: agentId),
            skillId: SkillID(value: skillId),
            assignedAt: assignedAt
        )
    }

    static func fromDomain(_ assignment: AgentSkillAssignment) -> AgentSkillAssignmentRecord {
        AgentSkillAssignmentRecord(
            agentId: assignment.agentId.value,
            skillId: assignment.skillId.value,
            assignedAt: assignment.assignedAt
        )
    }
}

// MARK: - AgentSkillAssignmentRepository

/// エージェントスキル割り当てのリポジトリ
public final class AgentSkillAssignmentRepository: AgentSkillAssignmentRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findByAgentId(_ agentId: AgentID) throws -> [SkillDefinition] {
        try db.read { db in
            // JOIN してスキル定義を取得
            let sql = """
                SELECT s.* FROM skill_definitions s
                INNER JOIN agent_skill_assignments a ON s.id = a.skill_id
                WHERE a.agent_id = ?
                ORDER BY s.name ASC
            """
            return try SkillDefinitionRecord
                .fetchAll(db, sql: sql, arguments: [agentId.value])
                .map { $0.toDomain() }
        }
    }

    public func findBySkillId(_ skillId: SkillID) throws -> [AgentID] {
        try db.read { db in
            try AgentSkillAssignmentRecord
                .filter(Column("skill_id") == skillId.value)
                .fetchAll(db)
                .map { AgentID(value: $0.agentId) }
        }
    }

    public func assignSkills(agentId: AgentID, skillIds: [SkillID]) throws {
        try db.write { db in
            // 既存の割り当てを削除
            try AgentSkillAssignmentRecord
                .filter(Column("agent_id") == agentId.value)
                .deleteAll(db)

            // 新しい割り当てを挿入
            let now = Date()
            for skillId in skillIds {
                let record = AgentSkillAssignmentRecord(
                    agentId: agentId.value,
                    skillId: skillId.value,
                    assignedAt: now
                )
                try record.insert(db)
            }
        }
    }

    public func removeAllSkills(agentId: AgentID) throws {
        try db.write { db in
            try AgentSkillAssignmentRecord
                .filter(Column("agent_id") == agentId.value)
                .deleteAll(db)
        }
    }

    public func isAssigned(agentId: AgentID, skillId: SkillID) throws -> Bool {
        try db.read { db in
            let count = try AgentSkillAssignmentRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("skill_id") == skillId.value)
                .fetchCount(db)
            return count > 0
        }
    }
}
