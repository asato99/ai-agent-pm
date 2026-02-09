// Auto-extracted from MCPServer.swift - Phase 0 Refactoring
import Foundation
import Domain
import Infrastructure
import GRDB
import UseCase

// MARK: - Self-Status Tools

extension MCPServer {

    // MARK: - Self-Status Tools
    // 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 2

    /// get_my_execution_history - 自分の実行履歴を取得
    /// 認証済みエージェントが自分の過去の実行履歴を確認するために使用
    func getMyExecutionHistory(session: AgentSession, taskId: String?, limit: Int?) throws -> [String: Any] {
        Self.log("[MCP] getMyExecutionHistory called: agentId='\(session.agentId.value)', taskId='\(taskId ?? "nil")', limit=\(limit ?? 10)")

        let effectiveLimit = limit ?? 10

        // Get execution logs for this agent
        let logs: [ExecutionLog]
        if let taskIdStr = taskId {
            // Filter by task ID
            let allLogs = try executionLogRepository.findByAgentId(session.agentId, limit: effectiveLimit, offset: nil)
            logs = allLogs.filter { $0.taskId.value == taskIdStr }
        } else {
            logs = try executionLogRepository.findByAgentId(session.agentId, limit: effectiveLimit, offset: nil)
        }

        // Get task titles for better context
        var taskTitles: [String: String] = [:]
        for log in logs {
            if taskTitles[log.taskId.value] == nil {
                if let task = try taskRepository.findById(log.taskId) {
                    taskTitles[log.taskId.value] = task.title
                }
            }
        }

        let executions = logs.map { log -> [String: Any] in
            [
                "execution_id": log.id.value,
                "task_id": log.taskId.value,
                "task_title": taskTitles[log.taskId.value] ?? "",
                "status": log.status.rawValue,
                "started_at": ISO8601DateFormatter().string(from: log.startedAt),
                "completed_at": log.completedAt.map { ISO8601DateFormatter().string(from: $0) } as Any,
                "duration_seconds": log.durationSeconds as Any,
                "exit_code": log.exitCode as Any,
                "has_log": log.logFilePath != nil
            ]
        }

        return [
            "success": true,
            "agent_id": session.agentId.value,
            "executions": executions,
            "total_count": executions.count,
            "instruction": "ログ内容を確認するには get_execution_log(execution_id) を呼び出してください。"
        ]
    }

    /// get_execution_log - 実行ログの詳細を取得
    /// 認証済みエージェントが特定の実行ログの詳細を確認するために使用
    func getExecutionLog(session: AgentSession, executionId: String) throws -> [String: Any] {
        Self.log("[MCP] getExecutionLog called: agentId='\(session.agentId.value)', executionId='\(executionId)'")

        // Find the execution log
        guard let log = try executionLogRepository.findById(ExecutionLogID(value: executionId)) else {
            throw MCPError.executionLogNotFound(executionId)
        }

        // Verify ownership - only allow access to own execution logs
        guard log.agentId == session.agentId else {
            throw MCPError.permissionDenied("この実行ログにアクセスする権限がありません。自分の実行ログのみ確認できます。")
        }

        // Read log file if available
        var logContent: [String] = []
        var totalLines = 0
        var truncated = false

        if let logFilePath = log.logFilePath {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: logFilePath) {
                do {
                    let content = try String(contentsOfFile: logFilePath, encoding: .utf8)
                    let lines = content.components(separatedBy: .newlines)
                    totalLines = lines.count

                    // Return last 100 lines by default
                    let maxLines = 100
                    if lines.count > maxLines {
                        logContent = Array(lines.suffix(maxLines))
                        truncated = true
                    } else {
                        logContent = lines
                    }
                } catch {
                    Self.log("[MCP] Failed to read log file: \(error)")
                    logContent = ["[ログファイルの読み取りに失敗しました: \(error.localizedDescription)]"]
                }
            } else {
                logContent = ["[ログファイルが見つかりません: \(logFilePath)]"]
            }
        } else {
            logContent = ["[ログファイルパスが登録されていません]"]
        }

        var result: [String: Any] = [
            "success": true,
            "execution_id": executionId,
            "task_id": log.taskId.value,
            "status": log.status.rawValue,
            "log_file_path": log.logFilePath as Any,
            "log_content": logContent,
            "total_lines": totalLines,
            "returned_lines": logContent.count,
            "truncated": truncated
        ]

        if truncated {
            result["instruction"] = "ログが切り詰められています。先頭から確認するには offset パラメータを使用してください。"
        } else {
            result["instruction"] = "上記が実行ログの内容です。"
        }

        return result
    }


}
