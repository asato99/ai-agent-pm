// Sources/MCPServer/MCPServer.swift
// 参照: docs/architecture/MCP_SERVER.md - MCPサーバー設計
// 参照: docs/prd/MCP_DESIGN.md - MCP Tool/Resource/Prompt設計

import Foundation
import GRDB
import Domain
import Infrastructure

/// MCPサーバーのメイン実装
final class MCPServer {
    private let transport: StdioTransport
    private let agentRepository: AgentRepository
    private let taskRepository: TaskRepository
    private let projectRepository: ProjectRepository
    private let agentId: AgentID
    private let projectId: ProjectID

    private let debugMode: Bool

    init(database: DatabaseQueue, agentId: String, projectId: String) {
        self.transport = StdioTransport()
        self.agentRepository = AgentRepository(database: database)
        self.taskRepository = TaskRepository(database: database)
        self.projectRepository = ProjectRepository(database: database)
        self.agentId = AgentID(value: agentId)
        self.projectId = ProjectID(value: projectId)
        self.debugMode = ProcessInfo.processInfo.environment["MCP_DEBUG"] == "1"
    }

    /// デバッグモード時のみログ出力
    private func logDebug(_ message: String) {
        if debugMode {
            transport.log(message)
        }
    }

    /// サーバーを起動してリクエストをループ処理
    func run() throws {
        logDebug("MCP Server started (agent: \(agentId.value), project: \(projectId.value))")

        while true {
            do {
                let request = try transport.readMessage()
                // 通知（id == nil）にはレスポンスを返さない
                if let response = handleRequest(request) {
                    try transport.writeMessage(response)
                }
            } catch TransportError.endOfInput {
                logDebug("Client disconnected")
                break
            } catch {
                logDebug("Error: \(error)")
                // エラーが発生してもループは継続
            }
        }
    }

    // MARK: - Request Handling

    /// リクエストをハンドリング
    /// 通知（id == nil）の場合は nil を返す
    private func handleRequest(_ request: JSONRPCRequest) -> JSONRPCResponse? {
        logDebug("Received: \(request.method)")

        switch request.method {
        case "initialize":
            return handleInitialize(request)
        case "initialized":
            // 通知なのでレスポンス不要
            return nil
        case "notifications/cancelled":
            // キャンセル通知
            return nil
        case "tools/list":
            return handleToolsList(request)
        case "tools/call":
            return handleToolsCall(request)
        default:
            // 通知（id == nil）の場合はレスポンスを返さない
            guard request.id != nil else { return nil }
            return JSONRPCResponse(
                id: request.id,
                error: JSONRPCError(code: -32601, message: "Method not found: \(request.method)")
            )
        }
    }

    // MARK: - Initialize

    private func handleInitialize(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let result: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "serverInfo": [
                "name": "mcp-server-pm",
                "version": "0.1.0"
            ],
            "capabilities": [
                "tools": [:] as [String: Any]
            ]
        ]
        return JSONRPCResponse(id: request.id, result: result)
    }

    // MARK: - Tools List

    private func handleToolsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let result: [String: Any] = [
            "tools": ToolDefinitions.all()
        ]
        return JSONRPCResponse(id: request.id, result: result)
    }

    // MARK: - Tools Call

    private func handleToolsCall(_ request: JSONRPCRequest) -> JSONRPCResponse {
        guard let params = request.params,
              let name = params["name"]?.stringValue else {
            return JSONRPCResponse(
                id: request.id,
                error: JSONRPCError.invalidParams
            )
        }

        let arguments = params["arguments"]?.dictionaryValue ?? [:]

        do {
            let result = try executeTool(name: name, arguments: arguments)
            return JSONRPCResponse(id: request.id, result: [
                "content": [
                    ["type": "text", "text": formatResult(result)]
                ]
            ])
        } catch {
            return JSONRPCResponse(id: request.id, result: [
                "content": [
                    ["type": "text", "text": "Error: \(error)"]
                ],
                "isError": true
            ])
        }
    }

    /// Toolを実行
    private func executeTool(name: String, arguments: [String: Any]) throws -> Any {
        switch name {
        case "get_my_profile":
            return try getMyProfile()
        case "list_tasks":
            let status = arguments["status"] as? String
            return try listTasks(status: status)
        case "get_my_tasks":
            return try getMyTasks()
        case "update_task_status":
            guard let taskId = arguments["task_id"] as? String,
                  let status = arguments["status"] as? String else {
                throw MCPError.missingArguments(["task_id", "status"])
            }
            return try updateTaskStatus(taskId: taskId, status: status)
        default:
            throw MCPError.unknownTool(name)
        }
    }

    /// 結果をJSON文字列にフォーマット
    private func formatResult(_ result: Any) -> String {
        if let data = try? JSONSerialization.data(
            withJSONObject: result,
            options: [.prettyPrinted, .sortedKeys]
        ),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: result)
    }

    // MARK: - Tool Implementations

    /// get_my_profile: 自分のエージェント情報を取得
    private func getMyProfile() throws -> [String: Any] {
        guard let agent = try agentRepository.findById(agentId) else {
            throw MCPError.agentNotFound(agentId.value)
        }
        return [
            "id": agent.id.value,
            "name": agent.name,
            "role": agent.role,
            "type": agent.type.rawValue
        ]
    }

    /// list_tasks: プロジェクト内のタスク一覧
    private func listTasks(status: String?) throws -> [[String: Any]] {
        let tasks: [Task]
        if let statusString = status,
           let taskStatus = TaskStatus(rawValue: statusString) {
            tasks = try taskRepository.findByStatus(taskStatus, projectId: projectId)
        } else {
            tasks = try taskRepository.findAll(projectId: projectId)
        }

        return tasks.map { task in
            [
                "id": task.id.value,
                "title": task.title,
                "status": task.status.rawValue,
                "assignee_id": task.assigneeId?.value as Any
            ]
        }
    }

    /// get_my_tasks: 自分に割り当てられたタスク
    private func getMyTasks() throws -> [[String: Any]] {
        let tasks = try taskRepository.findByAssignee(agentId)
        return tasks.map { task in
            [
                "id": task.id.value,
                "title": task.title,
                "status": task.status.rawValue
            ]
        }
    }

    /// update_task_status: タスクのステータス更新
    private func updateTaskStatus(taskId: String, status: String) throws -> [String: Any] {
        guard var task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        guard let newStatus = TaskStatus(rawValue: status) else {
            throw MCPError.invalidStatus(status)
        }

        let previousStatus = task.status
        task.status = newStatus
        try taskRepository.save(task)

        logDebug("Task \(taskId) status changed: \(previousStatus.rawValue) -> \(newStatus.rawValue)")

        return [
            "success": true,
            "task": [
                "id": task.id.value,
                "title": task.title,
                "previous_status": previousStatus.rawValue,
                "new_status": task.status.rawValue
            ]
        ]
    }
}

// MARK: - MCPError

enum MCPError: Error, CustomStringConvertible {
    case agentNotFound(String)
    case taskNotFound(String)
    case projectNotFound(String)
    case invalidStatus(String)
    case unknownTool(String)
    case missingArguments([String])

    var description: String {
        switch self {
        case .agentNotFound(let id):
            return "Agent not found: \(id)"
        case .taskNotFound(let id):
            return "Task not found: \(id)"
        case .projectNotFound(let id):
            return "Project not found: \(id)"
        case .invalidStatus(let status):
            return "Invalid status: \(status). Valid values: backlog, todo, in_progress, done"
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .missingArguments(let args):
            return "Missing required arguments: \(args.joined(separator: ", "))"
        }
    }
}
