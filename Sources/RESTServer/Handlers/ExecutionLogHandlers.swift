import Foundation
import Hummingbird
import GRDB
import Infrastructure
import UseCase
import Domain

extension RESTServer {

    // MARK: - Execution Log Handlers

    // 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md

    /// GET /tasks/:taskId/execution-logs
    /// Returns execution logs for a task with agent names
    func listTaskExecutionLogs(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard context.agentId != nil else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let taskIdStr = context.parameters.get("taskId") else {
            return errorResponse(status: .badRequest, message: "Missing task ID")
        }

        let taskId = TaskID(value: taskIdStr)
        guard try taskRepository.findById(taskId) != nil else {
            return errorResponse(status: .notFound, message: "Task not found")
        }

        let logs = try executionLogRepository.findByTaskId(taskId)

        // Resolve agent names for each log
        var agentNameCache: [String: String] = [:]
        let dtos = logs.map { log -> ExecutionLogDTO in
            let agentIdValue = log.agentId.value
            if agentNameCache[agentIdValue] == nil {
                agentNameCache[agentIdValue] = (try? agentRepository.findById(log.agentId))?.name ?? "Unknown"
            }
            return ExecutionLogDTO(from: log, agentName: agentNameCache[agentIdValue]!)
        }

        return jsonResponse(ExecutionLogsResponseDTO(executionLogs: dtos))
    }

    /// GET /execution-logs/:logId/content
    /// Returns the content of a log file
    func getExecutionLogContent(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard context.agentId != nil else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let logIdStr = context.parameters.get("logId") else {
            return errorResponse(status: .badRequest, message: "Missing log ID")
        }

        let logId = ExecutionLogID(value: logIdStr)
        guard let log = try executionLogRepository.findById(logId) else {
            return errorResponse(status: .notFound, message: "Execution log not found")
        }

        guard let logFilePath = log.logFilePath else {
            return errorResponse(status: .notFound, message: "No log file associated with this execution")
        }

        // Read log file content
        let fileURL = URL(fileURLWithPath: logFilePath)
        guard FileManager.default.fileExists(atPath: logFilePath) else {
            return errorResponse(status: .notFound, message: "Log file not found on disk")
        }

        let content: String
        let fileSize: Int
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
            let attributes = try FileManager.default.attributesOfItem(atPath: logFilePath)
            fileSize = attributes[.size] as? Int ?? content.utf8.count
        } catch {
            return errorResponse(status: .internalServerError, message: "Failed to read log file: \(error.localizedDescription)")
        }

        let filename = fileURL.lastPathComponent
        return jsonResponse(ExecutionLogContentDTO(content: content, filename: filename, fileSize: fileSize))
    }

    /// GET /tasks/:taskId/contexts
    /// Returns contexts for a task with agent names
    func listTaskContexts(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard context.agentId != nil else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let taskIdStr = context.parameters.get("taskId") else {
            return errorResponse(status: .badRequest, message: "Missing task ID")
        }

        let taskId = TaskID(value: taskIdStr)
        guard try taskRepository.findById(taskId) != nil else {
            return errorResponse(status: .notFound, message: "Task not found")
        }

        let contexts = try contextRepository.findByTask(taskId)

        // Resolve agent names for each context
        var agentNameCache: [String: String] = [:]
        let dtos = contexts.map { ctx -> ContextDTO in
            let agentIdValue = ctx.agentId.value
            if agentNameCache[agentIdValue] == nil {
                agentNameCache[agentIdValue] = (try? agentRepository.findById(ctx.agentId))?.name ?? "Unknown"
            }
            return ContextDTO(from: ctx, agentName: agentNameCache[agentIdValue]!)
        }

        return jsonResponse(ContextsResponseDTO(contexts: dtos))
    }

}
