// Sources/Infrastructure/Repositories/ExecutionLogRepository.swift
// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-3 実行ログ

import Foundation
import GRDB
import Domain

// MARK: - ExecutionLogRecord

/// GRDB用のExecutionLogレコード
struct ExecutionLogRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "execution_logs"

    var id: String
    var taskId: String
    var agentId: String
    var status: String
    var startedAt: Date
    var completedAt: Date?
    var exitCode: Int?
    var durationSeconds: Double?
    var logFilePath: String?
    var errorMessage: String?
    // Model verification fields
    var reportedProvider: String?
    var reportedModel: String?
    var modelVerified: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case agentId = "agent_id"
        case status
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case exitCode = "exit_code"
        case durationSeconds = "duration_seconds"
        case logFilePath = "log_file_path"
        case errorMessage = "error_message"
        case reportedProvider = "reported_provider"
        case reportedModel = "reported_model"
        case modelVerified = "model_verified"
    }

    func toDomain() -> ExecutionLog {
        ExecutionLog(
            id: ExecutionLogID(value: id),
            taskId: TaskID(value: taskId),
            agentId: AgentID(value: agentId),
            status: ExecutionStatus(rawValue: status) ?? .running,
            startedAt: startedAt,
            completedAt: completedAt,
            exitCode: exitCode,
            durationSeconds: durationSeconds,
            logFilePath: logFilePath,
            errorMessage: errorMessage,
            reportedProvider: reportedProvider,
            reportedModel: reportedModel,
            modelVerified: modelVerified
        )
    }

    static func fromDomain(_ log: ExecutionLog) -> ExecutionLogRecord {
        ExecutionLogRecord(
            id: log.id.value,
            taskId: log.taskId.value,
            agentId: log.agentId.value,
            status: log.status.rawValue,
            startedAt: log.startedAt,
            completedAt: log.completedAt,
            exitCode: log.exitCode,
            durationSeconds: log.durationSeconds,
            logFilePath: log.logFilePath,
            errorMessage: log.errorMessage,
            reportedProvider: log.reportedProvider,
            reportedModel: log.reportedModel,
            modelVerified: log.modelVerified
        )
    }
}

// MARK: - ExecutionLogRepository

/// 実行ログのリポジトリ
public final class ExecutionLogRepository: ExecutionLogRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: ExecutionLogID) throws -> ExecutionLog? {
        try db.read { db in
            try ExecutionLogRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findByTaskId(_ taskId: TaskID) throws -> [ExecutionLog] {
        try db.read { db in
            try ExecutionLogRecord
                .filter(Column("task_id") == taskId.value)
                .order(Column("started_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findByAgentId(_ agentId: AgentID) throws -> [ExecutionLog] {
        try db.read { db in
            try ExecutionLogRecord
                .filter(Column("agent_id") == agentId.value)
                .order(Column("started_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findRunning(agentId: AgentID) throws -> [ExecutionLog] {
        try db.read { db in
            try ExecutionLogRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("status") == ExecutionStatus.running.rawValue)
                .order(Column("started_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findLatestByAgentAndTask(agentId: AgentID, taskId: TaskID) throws -> ExecutionLog? {
        try db.read { db in
            try ExecutionLogRecord
                .filter(Column("agent_id") == agentId.value)
                .filter(Column("task_id") == taskId.value)
                .order(Column("started_at").desc)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func save(_ log: ExecutionLog) throws {
        try db.write { db in
            try ExecutionLogRecord.fromDomain(log).save(db)
        }
    }

    public func delete(_ id: ExecutionLogID) throws {
        try db.write { db in
            _ = try ExecutionLogRecord.deleteOne(db, key: id.value)
        }
    }
}
