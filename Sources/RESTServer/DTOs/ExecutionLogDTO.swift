// Sources/RESTServer/DTOs/ExecutionLogDTO.swift
// AI Agent PM - REST API Server
//
// 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md

import Foundation
import Domain

/// Execution log data transfer object for REST API
/// Note: Uses Swift's default camelCase JSON encoding
public struct ExecutionLogDTO: Codable {
    let id: String
    let taskId: String
    let agentId: String
    let agentName: String
    let status: String
    let startedAt: String
    let completedAt: String?
    let exitCode: Int?
    let durationSeconds: Double?
    let hasLogFile: Bool
    let errorMessage: String?
    let reportedProvider: String?
    let reportedModel: String?

    /// Create DTO from domain model
    /// - Parameters:
    ///   - executionLog: The domain execution log
    ///   - agentName: The name of the agent (resolved separately)
    init(from executionLog: ExecutionLog, agentName: String) {
        self.id = executionLog.id.value
        self.taskId = executionLog.taskId.value
        self.agentId = executionLog.agentId.value
        self.agentName = agentName
        self.status = executionLog.status.rawValue
        self.startedAt = ISO8601DateFormatter().string(from: executionLog.startedAt)
        self.completedAt = executionLog.completedAt.map { ISO8601DateFormatter().string(from: $0) }
        self.exitCode = executionLog.exitCode
        self.durationSeconds = executionLog.durationSeconds
        self.hasLogFile = executionLog.logFilePath != nil
        self.errorMessage = executionLog.errorMessage
        self.reportedProvider = executionLog.reportedProvider
        self.reportedModel = executionLog.reportedModel
    }
}

/// Response wrapper for execution logs list
public struct ExecutionLogsResponseDTO: Codable {
    let executionLogs: [ExecutionLogDTO]
}

/// Response for execution log file content
public struct ExecutionLogContentDTO: Codable {
    let content: String
    let filename: String
    let fileSize: Int
}
