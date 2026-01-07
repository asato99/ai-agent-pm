// Sources/Infrastructure/Repositories/ProjectAgentAssignmentRepository.swift
// 参照: docs/requirements/PROJECTS.md - エージェント割り当て
// 参照: docs/usecase/UC004_MultiProjectSameAgent.md

import Foundation
import GRDB
import Domain

// MARK: - ProjectAgentAssignmentRecord

/// GRDB用のProjectAgentAssignmentレコード
struct ProjectAgentAssignmentRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "project_agents"

    var projectId: String
    var agentId: String
    var assignedAt: Date

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case agentId = "agent_id"
        case assignedAt = "assigned_at"
    }

    func toDomain() -> ProjectAgentAssignment {
        ProjectAgentAssignment(
            projectId: ProjectID(value: projectId),
            agentId: AgentID(value: agentId),
            assignedAt: assignedAt
        )
    }

    static func fromDomain(_ assignment: ProjectAgentAssignment) -> ProjectAgentAssignmentRecord {
        ProjectAgentAssignmentRecord(
            projectId: assignment.projectId.value,
            agentId: assignment.agentId.value,
            assignedAt: assignment.assignedAt
        )
    }
}

// MARK: - ProjectAgentAssignmentRepository

/// プロジェクト×エージェント割り当てのリポジトリ
public final class ProjectAgentAssignmentRepository: ProjectAgentAssignmentRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func assign(projectId: ProjectID, agentId: AgentID) throws -> ProjectAgentAssignment {
        try db.write { db in
            // 既存の割り当てを確認
            if let existing = try ProjectAgentAssignmentRecord
                .filter(Column("project_id") == projectId.value && Column("agent_id") == agentId.value)
                .fetchOne(db) {
                return existing.toDomain()
            }

            // 新規割り当てを作成
            let assignment = ProjectAgentAssignment(
                projectId: projectId,
                agentId: agentId,
                assignedAt: Date()
            )
            try ProjectAgentAssignmentRecord.fromDomain(assignment).insert(db)
            return assignment
        }
    }

    public func remove(projectId: ProjectID, agentId: AgentID) throws {
        try db.write { db in
            _ = try ProjectAgentAssignmentRecord
                .filter(Column("project_id") == projectId.value && Column("agent_id") == agentId.value)
                .deleteAll(db)
        }
    }

    public func findAgentsByProject(_ projectId: ProjectID) throws -> [Agent] {
        try db.read { db in
            // project_agents から agent_id を取得し、agents テーブルと結合
            let sql = """
                SELECT a.*
                FROM agents a
                INNER JOIN project_agents pa ON a.id = pa.agent_id
                WHERE pa.project_id = ?
                ORDER BY a.name
            """
            return try AgentRecord.fetchAll(db, sql: sql, arguments: [projectId.value])
                .map { $0.toDomain() }
        }
    }

    public func findProjectsByAgent(_ agentId: AgentID) throws -> [Project] {
        try db.read { db in
            // project_agents から project_id を取得し、projects テーブルと結合
            let sql = """
                SELECT p.*
                FROM projects p
                INNER JOIN project_agents pa ON p.id = pa.project_id
                WHERE pa.agent_id = ?
                ORDER BY p.name
            """
            return try ProjectRecord.fetchAll(db, sql: sql, arguments: [agentId.value])
                .map { $0.toDomain() }
        }
    }

    public func isAgentAssignedToProject(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        try db.read { db in
            let count = try ProjectAgentAssignmentRecord
                .filter(Column("project_id") == projectId.value && Column("agent_id") == agentId.value)
                .fetchCount(db)
            return count > 0
        }
    }

    public func findAll() throws -> [ProjectAgentAssignment] {
        try db.read { db in
            try ProjectAgentAssignmentRecord
                .order(Column("assigned_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }
}
