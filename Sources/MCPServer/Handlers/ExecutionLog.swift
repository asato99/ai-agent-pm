// Auto-extracted from MCPServer.swift - Phase 0 Refactoring
import Foundation
import Domain
import Infrastructure
import GRDB
import UseCase

// MARK: - Execution Log

extension MCPServer {

    // MARK: - Execution Log (Phase 3-3)

    /// report_execution_start - 実行開始を報告
    /// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-3
    func reportExecutionStart(taskId: String, agentId: String) throws -> [String: Any] {
        Self.log("[MCP] reportExecutionStart called: taskId='\(taskId)', agentId='\(agentId)'")

        let useCase = RecordExecutionStartUseCase(
            executionLogRepository: executionLogRepository,
            taskRepository: taskRepository,
            agentRepository: agentRepository
        )

        let log = try useCase.execute(
            taskId: TaskID(value: taskId),
            agentId: AgentID(value: agentId)
        )

        Self.log("[MCP] ExecutionLog created: \(log.id.value)")

        return [
            "success": true,
            "execution_log_id": log.id.value,
            "task_id": log.taskId.value,
            "agent_id": log.agentId.value,
            "status": log.status.rawValue,
            "started_at": ISO8601DateFormatter().string(from: log.startedAt)
        ]
    }

    /// report_execution_complete - 実行完了を報告
    /// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-3
    /// Phase 3-4: セッション検証追加
    func reportExecutionComplete(
        executionLogId: String,
        exitCode: Int,
        durationSeconds: Double,
        logFilePath: String?,
        errorMessage: String?,
        validatedAgentId: String
    ) throws -> [String: Any] {
        Self.log("[MCP] reportExecutionComplete called: executionLogId='\(executionLogId)', exitCode=\(exitCode), validatedAgent='\(validatedAgentId)'")

        // Phase 3-4: まずExecutionLogを取得してエージェントを検証
        guard let existingLog = try executionLogRepository.findById(ExecutionLogID(value: executionLogId)) else {
            Self.log("[MCP] ExecutionLog not found: \(executionLogId)")
            throw MCPError.sessionNotFound(executionLogId)
        }

        // セッションのエージェントIDとExecutionLogのエージェントIDが一致するか確認
        if existingLog.agentId.value != validatedAgentId {
            Self.log("[MCP] Agent mismatch: log belongs to \(existingLog.agentId.value), but session is for \(validatedAgentId)")
            throw MCPError.sessionAgentMismatch(expected: existingLog.agentId.value, actual: validatedAgentId)
        }

        let useCase = RecordExecutionCompleteUseCase(
            executionLogRepository: executionLogRepository
        )

        let log = try useCase.execute(
            executionLogId: ExecutionLogID(value: executionLogId),
            exitCode: exitCode,
            durationSeconds: durationSeconds,
            logFilePath: logFilePath,
            errorMessage: errorMessage
        )

        Self.log("[MCP] ExecutionLog completed: \(log.id.value), status=\(log.status.rawValue)")

        var result: [String: Any] = [
            "success": true,
            "execution_log_id": log.id.value,
            "task_id": log.taskId.value,
            "agent_id": log.agentId.value,
            "status": log.status.rawValue,
            "started_at": ISO8601DateFormatter().string(from: log.startedAt),
            "exit_code": log.exitCode ?? 0,
            "duration_seconds": log.durationSeconds ?? 0.0
        ]

        if let completedAt = log.completedAt {
            result["completed_at"] = ISO8601DateFormatter().string(from: completedAt)
        }
        if let path = log.logFilePath {
            result["log_file_path"] = path
        }
        if let error = log.errorMessage {
            result["error_message"] = error
        }

        return result
    }


}
