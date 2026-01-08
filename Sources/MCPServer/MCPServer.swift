// Sources/MCPServer/MCPServer.swift
// 参照: docs/architecture/MCP_SERVER.md - MCPサーバー設計
// 参照: docs/prd/MCP_DESIGN.md - MCP Tool/Resource/Prompt設計

import Foundation
import GRDB
import Domain
import Infrastructure
import UseCase

/// MCPサーバーのメイン実装（ステートレス設計）
/// 参照: docs/architecture/MCP_SERVER.md - ステートレス設計
///
/// IDはサーバー起動時ではなく、各ツール呼び出し時に引数として受け取る。
/// キック時にプロンプトでID情報を提供し、LLM（Claude Code）が橋渡しする。
final class MCPServer {
    private let transport: MCPTransport

    // Repositories
    private let agentRepository: AgentRepository
    private let taskRepository: TaskRepository
    private let projectRepository: ProjectRepository
    private let sessionRepository: SessionRepository
    private let contextRepository: ContextRepository
    private let handoffRepository: HandoffRepository
    private let eventRepository: EventRepository

    // Phase 3-1: Authentication Repositories
    private let agentCredentialRepository: AgentCredentialRepository
    private let agentSessionRepository: AgentSessionRepository

    // Phase 3-3: Execution Log Repository
    private let executionLogRepository: ExecutionLogRepository

    // Phase 4: Project-Agent Assignment Repository
    private let projectAgentAssignmentRepository: ProjectAgentAssignmentRepository

    private let debugMode: Bool

    /// ステートレス設計: DBパスのみで初期化（stdio用）
    convenience init(database: DatabaseQueue) {
        self.init(database: database, transport: StdioTransport())
    }

    /// カスタムトランスポートで初期化（デーモンモード用）
    init(database: DatabaseQueue, transport: MCPTransport) {
        self.transport = transport
        self.agentRepository = AgentRepository(database: database)
        self.taskRepository = TaskRepository(database: database)
        self.projectRepository = ProjectRepository(database: database)
        self.sessionRepository = SessionRepository(database: database)
        self.contextRepository = ContextRepository(database: database)
        self.handoffRepository = HandoffRepository(database: database)
        self.eventRepository = EventRepository(database: database)
        // Phase 3-1: Authentication Repositories
        self.agentCredentialRepository = AgentCredentialRepository(database: database)
        self.agentSessionRepository = AgentSessionRepository(database: database)
        // Phase 3-3: Execution Log Repository
        self.executionLogRepository = ExecutionLogRepository(database: database)
        // Phase 4: Project-Agent Assignment Repository
        self.projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: database)
        self.debugMode = ProcessInfo.processInfo.environment["MCP_DEBUG"] == "1"

        // 起動時ログ（常に出力）- ファイルとstderrの両方に出力
        let dbPath = AppConfig.databasePath
        Self.log("[MCP] Started. DB Path: \(dbPath)")

        // DB内のエージェント一覧をログ
        do {
            let agents = try agentRepository.findAll()
            Self.log("[MCP] Agents in DB: \(agents.map { "\($0.id.value) (\($0.name))" })")
        } catch {
            Self.log("[MCP] Failed to list agents: \(error)")
        }
    }

    /// ログ出力（ファイルとstderrの両方）
    private static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"

        // stderrに出力
        FileHandle.standardError.write(logLine.data(using: .utf8)!)

        // ファイルにも出力
        let logPath = AppConfig.appSupportDirectory.appendingPathComponent("mcp-server.log").path
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(logLine.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: logLine.data(using: .utf8))
        }
    }

    /// デバッグモード時のみログ出力
    private func logDebug(_ message: String) {
        if debugMode {
            transport.log(message)
        }
    }

    /// サーバーを起動してリクエストをループ処理（stdio用）
    func run() throws {
        logDebug("MCP Server started (stateless mode)")

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

    /// 単一リクエストを処理（デーモンモード用）
    /// Unixソケット経由の場合、1接続につき複数リクエストを処理
    func runOnce() throws {
        logDebug("MCP Server handling connection (daemon mode)")

        // 接続中はリクエストをループ処理
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
                // エラーが発生しても接続を維持
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
            return nil
        case "notifications/cancelled":
            return nil
        case "tools/list":
            return handleToolsList(request)
        case "tools/call":
            return handleToolsCall(request)
        case "resources/list":
            return handleResourcesList(request)
        case "resources/read":
            return handleResourcesRead(request)
        case "prompts/list":
            return handlePromptsList(request)
        case "prompts/get":
            return handlePromptsGet(request)
        default:
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
                "version": "0.2.0"
            ],
            "capabilities": [
                "tools": [:] as [String: Any],
                "resources": [:] as [String: Any],
                "prompts": [:] as [String: Any]
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
    /// ステートレス設計: 必要なIDは全て引数として受け取る
    private func executeTool(name: String, arguments: [String: Any]) throws -> Any {
        switch name {
        // Phase 4: Runner API
        case "health_check":
            return try healthCheck()

        case "list_managed_agents":
            return try listManagedAgents()

        case "should_start":
            guard let agentId = arguments["agent_id"] as? String,
                  let projectId = arguments["project_id"] as? String else {
                throw MCPError.missingArguments(["agent_id", "project_id"])
            }
            return try shouldStart(agentId: agentId, projectId: projectId)

        // Authentication (Phase 4: project_id 必須)
        case "authenticate":
            guard let agentId = arguments["agent_id"] as? String,
                  let passkey = arguments["passkey"] as? String,
                  let projectId = arguments["project_id"] as? String else {
                throw MCPError.missingArguments(["agent_id", "passkey", "project_id"])
            }
            return try authenticate(agentId: agentId, passkey: passkey, projectId: projectId)

        // Agent
        case "get_my_profile":
            // 後方互換性のため維持（非推奨）
            // 新しいコードは get_agent_profile を使用すべき
            guard let agentId = arguments["agent_id"] as? String else {
                throw MCPError.missingArguments(["agent_id"])
            }
            return try getAgentProfile(agentId: agentId)
        case "get_agent_profile":
            guard let agentId = arguments["agent_id"] as? String else {
                throw MCPError.missingArguments(["agent_id"])
            }
            return try getAgentProfile(agentId: agentId)
        case "list_agents":
            return try listAgents()

        // Project
        case "list_projects":
            return try listProjects()
        case "get_project":
            guard let projectId = arguments["project_id"] as? String else {
                throw MCPError.missingArguments(["project_id"])
            }
            return try getProject(projectId: projectId)
        case "list_active_projects_with_agents":
            // Phase 4: Runner用API - アクティブプロジェクトと割り当てエージェント一覧
            return try listActiveProjectsWithAgents()

        // Tasks
        case "list_tasks":
            let status = arguments["status"] as? String
            let assigneeId = arguments["assignee_id"] as? String
            return try listTasks(status: status, assigneeId: assigneeId)
        case "get_my_tasks":
            // 後方互換性のため維持（非推奨）
            // 新しいコードは list_tasks(assignee_id=...) を使用すべき
            guard let agentId = arguments["agent_id"] as? String else {
                throw MCPError.missingArguments(["agent_id"])
            }
            return try listTasks(status: nil, assigneeId: agentId)
        case "get_pending_tasks":
            // Phase 3-2: 作業中タスク取得（Phase 3-4: セッション検証必須）
            // Phase 4: 非推奨 - get_my_task を使用してください
            guard let sessionToken = arguments["session_token"] as? String else {
                throw MCPError.sessionTokenRequired
            }
            // セッションからエージェントIDを取得（引数のagent_idは信頼しない）
            let session = try validateSession(token: sessionToken)
            return try getPendingTasks(agentId: session.agentId.value)

        // Phase 4: Agent API
        case "get_my_task":
            guard let sessionToken = arguments["session_token"] as? String else {
                throw MCPError.sessionTokenRequired
            }
            // Phase 4: セッションからprojectIdも取得してタスクをフィルタリング
            let session = try validateSession(token: sessionToken)
            return try getMyTask(agentId: session.agentId.value, projectId: session.projectId.value)

        case "report_completed":
            guard let sessionToken = arguments["session_token"] as? String else {
                throw MCPError.sessionTokenRequired
            }
            guard let result = arguments["result"] as? String else {
                throw MCPError.missingArguments(["result"])
            }
            // Phase 4: セッションからprojectIdも取得してタスクをフィルタリング
            let session = try validateSession(token: sessionToken)
            let summary = arguments["summary"] as? String
            let nextSteps = arguments["next_steps"] as? String
            return try reportCompleted(
                agentId: session.agentId.value,
                projectId: session.projectId.value,
                sessionToken: sessionToken,
                result: result,
                summary: summary,
                nextSteps: nextSteps
            )
        case "get_task":
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            return try getTask(taskId: taskId)
        case "update_task_status":
            guard let taskId = arguments["task_id"] as? String,
                  let status = arguments["status"] as? String else {
                throw MCPError.missingArguments(["task_id", "status"])
            }
            let reason = arguments["reason"] as? String
            return try updateTaskStatus(taskId: taskId, status: status, reason: reason)
        case "assign_task":
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            let assigneeId = arguments["assignee_id"] as? String
            return try assignTask(taskId: taskId, assigneeId: assigneeId)

        // Context
        case "save_context":
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            return try saveContext(taskId: taskId, arguments: arguments)
        case "get_task_context":
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            let includeHistory = arguments["include_history"] as? Bool ?? false
            return try getTaskContext(taskId: taskId, includeHistory: includeHistory)

        // Handoff
        case "create_handoff":
            guard let taskId = arguments["task_id"] as? String,
                  let fromAgentId = arguments["from_agent_id"] as? String,
                  let summary = arguments["summary"] as? String else {
                throw MCPError.missingArguments(["task_id", "from_agent_id", "summary"])
            }
            return try createHandoff(taskId: taskId, fromAgentId: fromAgentId, summary: summary, arguments: arguments)
        case "accept_handoff":
            guard let handoffId = arguments["handoff_id"] as? String,
                  let agentId = arguments["agent_id"] as? String else {
                throw MCPError.missingArguments(["handoff_id", "agent_id"])
            }
            return try acceptHandoff(handoffId: handoffId, agentId: agentId)
        case "get_pending_handoffs":
            let agentId = arguments["agent_id"] as? String
            return try getPendingHandoffs(agentId: agentId)

        // Execution Log (Phase 3-3, Phase 3-4: セッション検証必須)
        case "report_execution_start":
            guard let sessionToken = arguments["session_token"] as? String else {
                throw MCPError.sessionTokenRequired
            }
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            // セッションからエージェントIDを取得（引数のagent_idは信頼しない）
            let session = try validateSession(token: sessionToken)
            return try reportExecutionStart(taskId: taskId, agentId: session.agentId.value)
        case "report_execution_complete":
            // Phase 3-4: セッション検証必須
            guard let sessionToken = arguments["session_token"] as? String else {
                throw MCPError.sessionTokenRequired
            }
            guard let executionLogId = arguments["execution_log_id"] as? String,
                  let exitCode = arguments["exit_code"] as? Int,
                  let durationSeconds = arguments["duration_seconds"] as? Double else {
                throw MCPError.missingArguments(["execution_log_id", "exit_code", "duration_seconds"])
            }
            // セッションを検証（エージェントIDを取得）
            let session = try validateSession(token: sessionToken)
            let logFilePath = arguments["log_file_path"] as? String
            let errorMessage = arguments["error_message"] as? String
            return try reportExecutionComplete(
                executionLogId: executionLogId,
                exitCode: exitCode,
                durationSeconds: durationSeconds,
                logFilePath: logFilePath,
                errorMessage: errorMessage,
                validatedAgentId: session.agentId.value
            )

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

    // MARK: - Resources List

    /// ステートレス設計: リソースURIにはIDを動的に指定
    /// 例: project://{project_id}/overview, agent://{agent_id}/profile
    private func handleResourcesList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let resources: [[String: Any]] = [
            [
                "uri": "project://{project_id}/overview",
                "name": "Project Overview",
                "description": "指定プロジェクトの概要情報。{project_id}を実際のIDに置換して使用",
                "mimeType": "application/json"
            ],
            [
                "uri": "project://{project_id}/tasks",
                "name": "Project Tasks",
                "description": "指定プロジェクト内の全タスク一覧。{project_id}を実際のIDに置換して使用",
                "mimeType": "application/json"
            ],
            [
                "uri": "project://{project_id}/agents",
                "name": "Project Agents",
                "description": "全エージェント一覧",
                "mimeType": "application/json"
            ],
            [
                "uri": "agent://{agent_id}/profile",
                "name": "Agent Profile",
                "description": "指定エージェントのプロファイル。{agent_id}を実際のIDに置換して使用",
                "mimeType": "application/json"
            ],
            [
                "uri": "agent://{agent_id}/tasks",
                "name": "Agent Tasks",
                "description": "指定エージェントに割り当てられたタスク。{agent_id}を実際のIDに置換して使用",
                "mimeType": "application/json"
            ],
            [
                "uri": "task://{task_id}/detail",
                "name": "Task Detail",
                "description": "指定タスクの詳細情報。{task_id}を実際のIDに置換して使用",
                "mimeType": "application/json"
            ],
            [
                "uri": "task://{task_id}/context",
                "name": "Task Context",
                "description": "指定タスクのコンテキスト情報。{task_id}を実際のIDに置換して使用",
                "mimeType": "application/json"
            ]
        ]

        return JSONRPCResponse(id: request.id, result: ["resources": resources])
    }

    // MARK: - Resources Read

    private func handleResourcesRead(_ request: JSONRPCRequest) -> JSONRPCResponse {
        guard let params = request.params,
              let uri = params["uri"]?.stringValue else {
            return JSONRPCResponse(id: request.id, error: JSONRPCError.invalidParams)
        }

        do {
            let content = try readResource(uri: uri)
            return JSONRPCResponse(id: request.id, result: [
                "contents": [
                    [
                        "uri": uri,
                        "mimeType": "application/json",
                        "text": formatResult(content)
                    ]
                ]
            ])
        } catch {
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32000, message: error.localizedDescription))
        }
    }

    private func readResource(uri: String) throws -> Any {
        // Parse URI
        if uri.hasPrefix("project://") {
            return try readProjectResource(uri: uri)
        } else if uri.hasPrefix("agent://") {
            return try readAgentResource(uri: uri)
        } else if uri.hasPrefix("task://") {
            return try readTaskResource(uri: uri)
        } else {
            throw MCPError.invalidResourceURI(uri)
        }
    }

    private func readProjectResource(uri: String) throws -> Any {
        let path = uri.replacingOccurrences(of: "project://", with: "")
        let components = path.split(separator: "/")

        guard components.count >= 2 else {
            throw MCPError.invalidResourceURI(uri)
        }

        let projectIdStr = String(components[0])
        let resource = String(components[1])

        switch resource {
        case "overview":
            guard let project = try projectRepository.findById(ProjectID(value: projectIdStr)) else {
                throw MCPError.projectNotFound(projectIdStr)
            }
            let tasks = try taskRepository.findAll(projectId: project.id)
            let agents = try agentRepository.findAll()

            let projectDict: [String: Any] = [
                "id": project.id.value,
                "name": project.name,
                "description": project.description,
                "status": project.status.rawValue
            ]

            let summaryDict: [String: Any] = [
                "total_tasks": tasks.count,
                "completed_tasks": tasks.filter { $0.status == .done }.count,
                "in_progress_tasks": tasks.filter { $0.status == .inProgress }.count,
                "blocked_tasks": tasks.filter { $0.status == .blocked }.count,
                "total_agents": agents.count,
                "ai_agents": agents.filter { $0.type == .ai }.count,
                "human_agents": agents.filter { $0.type == .human }.count
            ]

            return ["project": projectDict, "summary": summaryDict]
        case "tasks":
            let tasks = try taskRepository.findAll(projectId: ProjectID(value: projectIdStr))
            return tasks.map { taskToDict($0) }
        case "agents":
            let agents = try agentRepository.findAll()
            return agents.map { agentToDict($0) }
        default:
            throw MCPError.invalidResourceURI(uri)
        }
    }

    private func readAgentResource(uri: String) throws -> Any {
        let path = uri.replacingOccurrences(of: "agent://", with: "")
        let components = path.split(separator: "/")

        guard components.count >= 2 else {
            throw MCPError.invalidResourceURI(uri)
        }

        let agentIdStr = String(components[0])
        let resource = String(components[1])
        let targetAgentId = AgentID(value: agentIdStr)

        switch resource {
        case "profile":
            guard let agent = try agentRepository.findById(targetAgentId) else {
                throw MCPError.agentNotFound(agentIdStr)
            }
            return agentToDict(agent)
        case "tasks":
            let tasks = try taskRepository.findByAssignee(targetAgentId)
            return tasks.map { taskToDict($0) }
        case "sessions":
            let sessions = try sessionRepository.findByAgent(targetAgentId)
            return sessions.map { sessionToDict($0) }
        default:
            throw MCPError.invalidResourceURI(uri)
        }
    }

    private func readTaskResource(uri: String) throws -> Any {
        let path = uri.replacingOccurrences(of: "task://", with: "")
        let components = path.split(separator: "/")

        guard components.count >= 2 else {
            throw MCPError.invalidResourceURI(uri)
        }

        let taskIdStr = String(components[0])
        let resource = String(components[1])
        let taskId = TaskID(value: taskIdStr)

        guard let task = try taskRepository.findById(taskId) else {
            throw MCPError.taskNotFound(taskIdStr)
        }

        switch resource {
        case "detail":
            let latestContext = try contextRepository.findLatest(taskId: taskId)
            var result = taskToDict(task)
            if let ctx = latestContext {
                result["latest_context"] = contextToDict(ctx)
            }
            return result
        case "history":
            let events = try eventRepository.findByEntity(type: .task, id: taskIdStr)
            return events.map { eventToDict($0) }
        case "context":
            let contexts = try contextRepository.findByTask(taskId)
            return contexts.map { contextToDict($0) }
        default:
            throw MCPError.invalidResourceURI(uri)
        }
    }

    // MARK: - Prompts List

    private func handlePromptsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let prompts: [[String: Any]] = [
            [
                "name": "handoff",
                "description": "タスクのハンドオフを作成するための支援プロンプト。現在の進捗を整理し、次のエージェントへの引き継ぎ内容を生成します。",
                "arguments": [
                    [
                        "name": "task_id",
                        "description": "ハンドオフするタスクのID",
                        "required": true
                    ]
                ]
            ],
            [
                "name": "context-summary",
                "description": "タスクのコンテキストを要約するプロンプト。これまでの作業内容を整理して記録します。",
                "arguments": [
                    [
                        "name": "task_id",
                        "description": "コンテキストを要約するタスクのID",
                        "required": true
                    ]
                ]
            ],
            [
                "name": "task-breakdown",
                "description": "大きなタスクをサブタスクに分解するための支援プロンプト。",
                "arguments": [
                    [
                        "name": "task_id",
                        "description": "分解するタスクのID",
                        "required": true
                    ]
                ]
            ],
            [
                "name": "status-report",
                "description": "プロジェクトの状況報告を生成するプロンプト。",
                "arguments": [
                    [
                        "name": "project_id",
                        "description": "状況報告するプロジェクトのID",
                        "required": true
                    ]
                ]
            ]
        ]

        return JSONRPCResponse(id: request.id, result: ["prompts": prompts])
    }

    // MARK: - Prompts Get

    private func handlePromptsGet(_ request: JSONRPCRequest) -> JSONRPCResponse {
        guard let params = request.params,
              let name = params["name"]?.stringValue else {
            return JSONRPCResponse(id: request.id, error: JSONRPCError.invalidParams)
        }

        let arguments = params["arguments"]?.dictionaryValue ?? [:]

        do {
            let messages = try getPrompt(name: name, arguments: arguments)
            return JSONRPCResponse(id: request.id, result: [
                "messages": messages
            ])
        } catch {
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32000, message: error.localizedDescription))
        }
    }

    private func getPrompt(name: String, arguments: [String: Any]) throws -> [[String: Any]] {
        switch name {
        case "handoff":
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            return try generateHandoffPrompt(taskId: taskId)
        case "context-summary":
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            return try generateContextSummaryPrompt(taskId: taskId)
        case "task-breakdown":
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            return try generateTaskBreakdownPrompt(taskId: taskId)
        case "status-report":
            guard let projectId = arguments["project_id"] as? String else {
                throw MCPError.missingArguments(["project_id"])
            }
            return try generateStatusReportPrompt(projectId: projectId)
        default:
            throw MCPError.unknownPrompt(name)
        }
    }

    private func generateHandoffPrompt(taskId: String) throws -> [[String: Any]] {
        guard let task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        let contexts = try contextRepository.findByTask(task.id)

        var contextInfo = ""
        if let latestContext = contexts.last {
            contextInfo = """
            最新のコンテキスト:
            - 進捗: \(latestContext.progress ?? "なし")
            - 発見事項: \(latestContext.findings ?? "なし")
            - ブロッカー: \(latestContext.blockers ?? "なし")
            - 次のステップ: \(latestContext.nextSteps ?? "なし")
            """
        }

        let prompt = """
        以下のタスクについてハンドオフを作成してください。

        タスク情報:
        - ID: \(task.id.value)
        - タイトル: \(task.title)
        - 説明: \(task.description)
        - ステータス: \(task.status.rawValue)
        - 優先度: \(task.priority.rawValue)

        \(contextInfo)

        ハンドオフには以下を含めてください:
        1. これまでの作業のサマリー
        2. 現在の状態と残りの作業
        3. 次のエージェントへの推奨事項
        4. 注意すべき点やリスク
        """

        return [
            ["role": "user", "content": ["type": "text", "text": prompt]]
        ]
    }

    private func generateContextSummaryPrompt(taskId: String) throws -> [[String: Any]] {
        guard let task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        let prompt = """
        以下のタスクの作業コンテキストを要約してください。

        タスク情報:
        - ID: \(task.id.value)
        - タイトル: \(task.title)
        - 説明: \(task.description)
        - ステータス: \(task.status.rawValue)

        以下の形式で要約を作成してください:
        1. 進捗状況 (progress): 現在の進捗を簡潔に
        2. 発見事項 (findings): 作業中に得た重要な発見や学び
        3. ブロッカー (blockers): 現在の障害や課題（あれば）
        4. 次のステップ (next_steps): 次に行うべきアクション
        """

        return [
            ["role": "user", "content": ["type": "text", "text": prompt]]
        ]
    }

    private func generateTaskBreakdownPrompt(taskId: String) throws -> [[String: Any]] {
        guard let task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        let prompt = """
        以下のタスクを実行可能なステップに分解してください。

        タスク情報:
        - ID: \(task.id.value)
        - タイトル: \(task.title)
        - 説明: \(task.description)
        - 優先度: \(task.priority.rawValue)

        以下の観点でステップを提案してください:
        1. 各ステップは1つの具体的なアクションであること
        2. 完了の判断が明確であること
        3. 依存関係がある場合は順序を考慮すること

        提案するステップのリストを作成してください。
        """

        return [
            ["role": "user", "content": ["type": "text", "text": prompt]]
        ]
    }

    private func generateStatusReportPrompt(projectId: String) throws -> [[String: Any]] {
        let pid = ProjectID(value: projectId)
        guard let project = try projectRepository.findById(pid) else {
            throw MCPError.projectNotFound(projectId)
        }

        let tasks = try taskRepository.findAll(projectId: pid)
        let agents = try agentRepository.findAll()

        let tasksByStatus = Dictionary(grouping: tasks) { $0.status }

        var statusSummary = "タスク状況:\n"
        for status in TaskStatus.allCases {
            let count = tasksByStatus[status]?.count ?? 0
            if count > 0 {
                statusSummary += "- \(status.rawValue): \(count)件\n"
            }
        }

        let prompt = """
        以下のプロジェクトの状況報告を作成してください。

        プロジェクト情報:
        - 名前: \(project.name)
        - 説明: \(project.description)
        - ステータス: \(project.status.rawValue)

        チーム:
        - エージェント数: \(agents.count)名
        - AIエージェント: \(agents.filter { $0.type == .ai }.count)名
        - 人間: \(agents.filter { $0.type == .human }.count)名

        \(statusSummary)

        状況報告には以下を含めてください:
        1. 全体の進捗サマリー
        2. 主な成果
        3. 課題とリスク
        4. 次のマイルストーン
        """

        return [
            ["role": "user", "content": ["type": "text", "text": prompt]]
        ]
    }

    // MARK: - Tool Implementations (Stateless Design)
    // 参照: docs/prd/MCP_DESIGN.md
    // 全てのツールは必要なIDを引数として受け取る

    // MARK: Session Validation (Phase 3-4)

    /// セッショントークンを検証し、関連するエージェントIDを返す
    /// 参照: セキュリティ改善 - セッショントークン検証の実装
    /// Phase 4: セッションを検証し、agentIdとprojectIdの両方を返す
    private func validateSession(token: String) throws -> (agentId: AgentID, projectId: ProjectID) {
        guard let session = try agentSessionRepository.findByToken(token) else {
            // findByToken は期限切れセッションを除外するので、
            // トークンが見つからない = 無効または期限切れ
            Self.log("[MCP] Session validation failed: token not found or expired")
            throw MCPError.sessionTokenInvalid
        }

        Self.log("[MCP] Session validated for agent: \(session.agentId.value), project: \(session.projectId.value)")
        return (agentId: session.agentId, projectId: session.projectId)
    }

    /// セッショントークンを検証し、指定されたエージェントIDとの一致も確認
    private func validateSessionWithAgent(token: String, expectedAgentId: String) throws -> AgentID {
        let session = try validateSession(token: token)

        // セッションに紐づくエージェントIDと、リクエストのエージェントIDが一致するか確認
        if session.agentId.value != expectedAgentId {
            Self.log("[MCP] Session agent mismatch: session=\(session.agentId.value), requested=\(expectedAgentId)")
            throw MCPError.sessionAgentMismatch(expected: expectedAgentId, actual: session.agentId.value)
        }

        return session.agentId
    }

    // MARK: Phase 4: Runner API

    /// health_check - サーバー起動確認
    /// Runnerが最初に呼び出す。サーバーが応答可能かを確認。
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    private func healthCheck() throws -> [String: Any] {
        Self.log("[MCP] healthCheck called")

        // DBアクセスの疎通確認
        let agentCount = try agentRepository.findAll().count
        let projectCount = try projectRepository.findAll().count

        return [
            "success": true,
            "status": "ok",
            "agent_count": agentCount,
            "project_count": projectCount
        ]
    }

    /// list_managed_agents - 管理対象エージェント一覧を取得
    /// Runnerがポーリング対象のエージェントIDを取得。詳細は隠蔽。
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    private func listManagedAgents() throws -> [String: Any] {
        Self.log("[MCP] listManagedAgents called")

        let agents = try agentRepository.findAll()

        // AIタイプのエージェントのみをRunnerの管理対象とする
        let aiAgents = agents.filter { $0.type == .ai }
        let agentIds = aiAgents.map { $0.id.value }

        Self.log("[MCP] listManagedAgents returning \(agentIds.count) agents")

        return [
            "success": true,
            "agent_ids": agentIds
        ]
    }

    /// should_start - エージェントを起動すべきかどうかを返す
    /// Runnerはタスクの詳細を知らない。bool と ai_type を返す。
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// 参照: docs/plan/MULTI_AGENT_USE_CASES.md - AIタイプ
    /// Phase 4: (agent_id, project_id)単位で起動判断
    private func shouldStart(agentId: String, projectId: String) throws -> [String: Any] {
        Self.log("[MCP] shouldStart called for agent: '\(agentId)', project: '\(projectId)'")

        let id = AgentID(value: agentId)
        let projId = ProjectID(value: projectId)

        // エージェントの存在確認
        guard let agent = try agentRepository.findById(id) else {
            Self.log("[MCP] shouldStart: Agent '\(agentId)' not found")
            throw MCPError.agentNotFound(agentId)
        }

        // プロジェクトの存在確認
        guard try projectRepository.findById(projId) != nil else {
            Self.log("[MCP] shouldStart: Project '\(projectId)' not found")
            throw MCPError.projectNotFound(projectId)
        }

        // エージェントがプロジェクトに割り当てられているか確認
        let isAssigned = try projectAgentAssignmentRepository.isAgentAssignedToProject(
            agentId: id,
            projectId: projId
        )
        if !isAssigned {
            Self.log("[MCP] shouldStart: Agent '\(agentId)' is not assigned to project '\(projectId)'")
            return [
                "should_start": false,
                "reason": "agent_not_assigned"
            ]
        }

        // Phase 4: (agent_id, project_id)単位でアクティブセッションをチェック
        let allSessions = try agentSessionRepository.findByAgentIdAndProjectId(id, projectId: projId)
        let activeSessions = allSessions.filter { $0.expiresAt > Date() }
        if !activeSessions.isEmpty {
            Self.log("[MCP] shouldStart for '\(agentId)/\(projectId)': false (already running - active session exists)")
            return [
                "should_start": false,
                "reason": "already_running"
            ]
        }

        // 該当プロジェクトで該当エージェントにアサインされた in_progress タスクがあるか確認
        let tasks = try taskRepository.findByAssignee(id)
        let hasInProgressTask = tasks.contains { task in
            task.status == .inProgress && task.projectId == projId
        }

        Self.log("[MCP] shouldStart for '\(agentId)/\(projectId)': \(hasInProgressTask)")

        // ai_type を返す（RunnerがCLIコマンドを選択するため）
        // kickCommand があればそれを優先
        var result: [String: Any] = [
            "should_start": hasInProgressTask
        ]

        // kickCommand があれば ai_type より優先
        if let kickCommand = agent.kickCommand, !kickCommand.isEmpty {
            result["kick_command"] = kickCommand
        }

        // ai_type があれば追加（デフォルトは claude）
        result["ai_type"] = agent.aiType?.rawValue ?? "claude"

        return result
    }

    // MARK: Phase 4: Agent API

    /// get_my_task - 認証済みエージェントの現在のタスクを取得
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// Phase 4: projectId でフィルタリング（同一エージェントが複数プロジェクトで同時稼働可能）
    private func getMyTask(agentId: String, projectId: String) throws -> [String: Any] {
        Self.log("[MCP] getMyTask called for agent: '\(agentId)', project: '\(projectId)'")

        let id = AgentID(value: agentId)
        let projId = ProjectID(value: projectId)

        // Phase 4: in_progress 状態のタスクを該当プロジェクトでフィルタリング
        let tasks = try taskRepository.findByAssignee(id)
        let inProgressTasks = tasks.filter { $0.status == .inProgress && $0.projectId == projId }

        if let task = inProgressTasks.first {
            // タスクのコンテキストを取得
            let latestContext = try contextRepository.findLatest(taskId: task.id)

            // ハンドオフ情報を取得
            let handoffs = try handoffRepository.findByTask(task.id)
            let latestHandoff = handoffs.last

            // プロジェクトから作業ディレクトリを取得
            let project = try projectRepository.findById(task.projectId)
            let workingDirectory = project?.workingDirectory

            var taskDict: [String: Any] = [
                "task_id": task.id.value,
                "title": task.title,
                "description": task.description
            ]

            if let workDir = workingDirectory {
                taskDict["working_directory"] = workDir
            }

            if let ctx = latestContext {
                taskDict["context"] = contextToDict(ctx)
            }

            if let handoff = latestHandoff {
                taskDict["handoff"] = handoffToDict(handoff)
            }

            Self.log("[MCP] getMyTask returning task: \(task.id.value)")

            return [
                "success": true,
                "has_task": true,
                "task": taskDict,
                "instruction": "タスクを完了したら report_completed を呼び出してください"
            ]
        } else {
            Self.log("[MCP] getMyTask: No in_progress task for agent '\(agentId)' in project '\(projectId)'")

            return [
                "success": true,
                "has_task": false,
                "instruction": "現在割り当てられたタスクはありません"
            ]
        }
    }

    /// report_completed - タスク完了を報告
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// Phase 4: セッション終了処理を追加
    /// Phase 4: projectId でタスクをフィルタリング（同一エージェントが複数プロジェクトで同時稼働可能）
    private func reportCompleted(
        agentId: String,
        projectId: String,
        sessionToken: String,
        result: String,
        summary: String?,
        nextSteps: String?
    ) throws -> [String: Any] {
        Self.log("[MCP] reportCompleted called for agent: '\(agentId)', project: '\(projectId)', result: '\(result)'")

        let id = AgentID(value: agentId)
        let projId = ProjectID(value: projectId)

        // Phase 4: in_progress 状態のタスクを該当プロジェクトでフィルタリング
        let tasks = try taskRepository.findByAssignee(id)
        guard var task = tasks.first(where: { $0.status == .inProgress && $0.projectId == projId }) else {
            Self.log("[MCP] reportCompleted: No in_progress task for agent '\(agentId)' in project '\(projectId)'")
            return [
                "success": false,
                "error": "No in_progress task found for this agent"
            ]
        }

        // 結果に基づいてステータスを更新
        let newStatus: TaskStatus
        switch result {
        case "success":
            newStatus = .done
        case "failed":
            newStatus = .blocked
        case "blocked":
            newStatus = .blocked
        default:
            Self.log("[MCP] reportCompleted: Invalid result '\(result)'")
            return [
                "success": false,
                "error": "Invalid result value. Use 'success', 'failed', or 'blocked'"
            ]
        }

        let previousStatus = task.status
        task.status = newStatus
        task.updatedAt = Date()
        if newStatus == .done {
            task.completedAt = Date()
        }

        try taskRepository.save(task)

        // コンテキストを保存（サマリーや次のステップがあれば）
        if summary != nil || nextSteps != nil {
            let context = Context(
                id: ContextID.generate(),
                taskId: task.id,
                sessionId: SessionID.generate(),
                agentId: id,
                progress: summary,
                findings: nil,
                blockers: result == "blocked" ? summary : nil,
                nextSteps: nextSteps
            )
            try contextRepository.save(context)
        }

        // イベントを記録
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: .statusChanged,
            agentId: id,
            sessionId: nil,
            previousState: previousStatus.rawValue,
            newState: newStatus.rawValue,
            reason: summary
        )
        try eventRepository.save(event)

        // Phase 4: セッションを無効化（削除）
        try agentSessionRepository.deleteByToken(sessionToken)
        Self.log("[MCP] reportCompleted: Session invalidated for agent '\(agentId)'")

        Self.log("[MCP] reportCompleted: Task \(task.id.value) status changed to \(newStatus.rawValue)")

        return [
            "success": true,
            "instruction": "タスクが完了しました。セッションを終了しました。"
        ]
    }

    // MARK: Authentication (Phase 4)

    /// authenticate - エージェント認証
    /// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md, PHASE4_COORDINATOR_ARCHITECTURE.md
    /// Phase 4: project_id 必須、instruction フィールドを追加、二重起動防止
    private func authenticate(agentId: String, passkey: String, projectId: String) throws -> [String: Any] {
        Self.log("[MCP] authenticate called for agent: '\(agentId)', project: '\(projectId)'")

        let id = AgentID(value: agentId)
        let projId = ProjectID(value: projectId)

        // Phase 4: プロジェクト存在確認
        guard try projectRepository.findById(projId) != nil else {
            Self.log("[MCP] authenticate failed: Project '\(projectId)' not found")
            return [
                "success": false,
                "error": "Project not found"
            ]
        }

        // Phase 4: エージェントがプロジェクトに割り当てられているか確認
        let isAssigned = try projectAgentAssignmentRepository.isAgentAssignedToProject(
            agentId: id,
            projectId: projId
        )
        if !isAssigned {
            Self.log("[MCP] authenticate failed: Agent '\(agentId)' not assigned to project '\(projectId)'")
            return [
                "success": false,
                "error": "Agent not assigned to project"
            ]
        }

        // Phase 4: 二重起動防止 - (agent_id, project_id)単位でアクティブセッションがあればエラー
        let allSessions = try agentSessionRepository.findByAgentIdAndProjectId(id, projectId: projId)
        let activeSessions = allSessions.filter { $0.expiresAt > Date() }
        if !activeSessions.isEmpty {
            Self.log("[MCP] authenticate failed for agent: '\(agentId)' on project '\(projectId)' - Agent already running")
            return [
                "success": false,
                "error": "Agent already running on this project"
            ]
        }

        // AuthenticateUseCaseを使用して認証
        let useCase = AuthenticateUseCase(
            credentialRepository: agentCredentialRepository,
            sessionRepository: agentSessionRepository,
            agentRepository: agentRepository
        )

        let result = try useCase.execute(agentId: agentId, passkey: passkey, projectId: projectId)

        if result.success {
            Self.log("[MCP] Authentication successful for agent: \(result.agentName ?? agentId)")
            var response: [String: Any] = [
                "success": true,
                "session_token": result.sessionToken ?? "",
                "expires_in": result.expiresIn ?? 0,
                "agent_name": result.agentName ?? "",
                // Phase 4: 次のアクション指示を追加
                "instruction": "get_my_task を呼び出してタスク詳細を取得してください"
            ]
            // system_prompt があれば追加（エージェントの役割を定義）
            // 参照: docs/plan/MULTI_AGENT_USE_CASES.md
            if let systemPrompt = result.systemPrompt {
                response["system_prompt"] = systemPrompt
            }
            return response
        } else {
            Self.log("[MCP] Authentication failed for agent: \(agentId) - \(result.error ?? "Unknown error")")
            return [
                "success": false,
                "error": result.error ?? "Authentication failed"
            ]
        }
    }

    // MARK: Agent Tools

    /// get_agent_profile - エージェント情報を取得
    private func getAgentProfile(agentId: String) throws -> [String: Any] {
        Self.log("[MCP] getAgentProfile called with: '\(agentId)'")

        let id = AgentID(value: agentId)
        guard let agent = try agentRepository.findById(id) else {
            // 見つからない場合、全エージェントをログ
            let allAgents = try? agentRepository.findAll()
            Self.log("[MCP] Agent '\(agentId)' not found. Available: \(allAgents?.map { $0.id.value } ?? [])")
            throw MCPError.agentNotFound(agentId)
        }
        Self.log("[MCP] Found agent: \(agent.name)")
        return agentToDict(agent)
    }

    /// list_agents - 全エージェント一覧を取得
    private func listAgents() throws -> [[String: Any]] {
        let agents = try agentRepository.findAll()
        return agents.map { agentToDict($0) }
    }

    /// list_projects - 全プロジェクト一覧を取得
    private func listProjects() throws -> [[String: Any]] {
        let projects = try projectRepository.findAll()
        return projects.map { projectToDict($0) }
    }

    /// get_project - プロジェクト詳細を取得
    private func getProject(projectId: String) throws -> [String: Any] {
        let id = ProjectID(value: projectId)
        guard let project = try projectRepository.findById(id) else {
            throw MCPError.projectNotFound(projectId)
        }
        return projectToDict(project)
    }

    /// list_active_projects_with_agents - アクティブプロジェクトと割り当てエージェント一覧
    /// 参照: docs/requirements/PROJECTS.md - MCP API
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// Runnerがポーリング対象を決定するために使用
    private func listActiveProjectsWithAgents() throws -> [String: Any] {
        // アクティブなプロジェクトのみ取得
        let allProjects = try projectRepository.findAll()
        let activeProjects = allProjects.filter { $0.status == .active }

        var projectsWithAgents: [[String: Any]] = []

        for project in activeProjects {
            // 各プロジェクトに割り当てられたエージェントを取得
            let agents = try projectAgentAssignmentRepository.findAgentsByProject(project.id)
            let agentIds = agents.map { $0.id.value }

            let projectEntry: [String: Any] = [
                "project_id": project.id.value,
                "project_name": project.name,
                "working_directory": project.workingDirectory ?? "",
                "agents": agentIds
            ]
            projectsWithAgents.append(projectEntry)
        }

        return ["projects": projectsWithAgents]
    }

    /// list_tasks - タスク一覧を取得（フィルタ可能）
    /// ステートレス設計: project_idは不要、全プロジェクトのタスクを返す
    private func listTasks(status: String?, assigneeId: String?) throws -> [[String: Any]] {
        var tasks: [Task]

        // まず全タスクを取得（全プロジェクト）
        tasks = try taskRepository.findAllTasks()

        // ステータスでフィルタ
        if let statusString = status,
           let taskStatus = TaskStatus(rawValue: statusString) {
            tasks = tasks.filter { $0.status == taskStatus }
        }

        // アサイニーでフィルタ
        if let assigneeIdString = assigneeId {
            let targetAgentId = AgentID(value: assigneeIdString)
            tasks = tasks.filter { $0.assigneeId == targetAgentId }
        }

        return tasks.map { taskToDict($0) }
    }

    /// Phase 3-2: get_pending_tasks - 作業中タスク取得
    /// 外部Runnerが作業継続のため現在進行中のタスクを取得
    private func getPendingTasks(agentId: String) throws -> [String: Any] {
        let useCase = GetPendingTasksUseCase(taskRepository: taskRepository)
        let tasks = try useCase.execute(agentId: AgentID(value: agentId))

        // タスクごとにプロジェクトのworking_directoryを取得して含める
        let tasksWithWorkingDir = try tasks.map { task -> [String: Any] in
            var dict = taskToDict(task)
            // プロジェクトのworking_directoryを取得
            if let project = try projectRepository.findById(task.projectId) {
                if let workingDir = project.workingDirectory {
                    dict["working_directory"] = workingDir
                }
            }
            return dict
        }

        return [
            "success": true,
            "tasks": tasksWithWorkingDir
        ]
    }

    /// get_task - タスク詳細を取得
    private func getTask(taskId: String) throws -> [String: Any] {
        let id = TaskID(value: taskId)
        guard let task = try taskRepository.findById(id) else {
            throw MCPError.taskNotFound(taskId)
        }

        let latestContext = try contextRepository.findLatest(taskId: id)

        var result = taskToDict(task)
        if let ctx = latestContext {
            result["latest_context"] = contextToDict(ctx)
        }

        return result
    }

    /// update_task_status - タスクのステータスを更新
    private func updateTaskStatus(taskId: String, status: String, reason: String?) throws -> [String: Any] {
        guard var task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        guard let newStatus = TaskStatus(rawValue: status) else {
            throw MCPError.invalidStatus(status)
        }

        let previousStatus = task.status

        // Validate transition
        guard UpdateTaskStatusUseCase.canTransition(from: previousStatus, to: newStatus) else {
            throw MCPError.invalidStatusTransition(from: previousStatus.rawValue, to: newStatus.rawValue)
        }

        task.status = newStatus
        task.updatedAt = Date()
        if newStatus == .done {
            task.completedAt = Date()
        }

        try taskRepository.save(task)

        // Record event (agentId is not available in stateless design, use nil)
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: .statusChanged,
            agentId: nil,
            sessionId: nil,
            previousState: previousStatus.rawValue,
            newState: newStatus.rawValue,
            reason: reason
        )
        try eventRepository.save(event)

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

    /// assign_task - タスクをエージェントに割り当て
    private func assignTask(taskId: String, assigneeId: String?) throws -> [String: Any] {
        Self.log("[MCP] assignTask called: taskId='\(taskId)', assigneeId='\(assigneeId ?? "nil")'")

        guard var task = try taskRepository.findById(TaskID(value: taskId)) else {
            Self.log("[MCP] Task '\(taskId)' not found")
            throw MCPError.taskNotFound(taskId)
        }

        // Validate assignee exists if provided
        if let assigneeIdStr = assigneeId {
            let targetAgentId = AgentID(value: assigneeIdStr)
            guard try agentRepository.findById(targetAgentId) != nil else {
                let allAgents = try? agentRepository.findAll()
                Self.log("[MCP] assignTask: Agent '\(assigneeIdStr)' not found. Available: \(allAgents?.map { $0.id.value } ?? [])")
                throw MCPError.agentNotFound(assigneeIdStr)
            }

            // Validate agent is assigned to the project
            // 参照: docs/requirements/PROJECTS.md - エージェント割り当て制約
            let isAssigned = try projectAgentAssignmentRepository.isAgentAssignedToProject(
                agentId: targetAgentId,
                projectId: task.projectId
            )
            if !isAssigned {
                Self.log("[MCP] assignTask: Agent '\(assigneeIdStr)' is not assigned to project '\(task.projectId.value)'")
                throw MCPError.agentNotAssignedToProject(agentId: assigneeIdStr, projectId: task.projectId.value)
            }
        }

        let previousAssignee = task.assigneeId
        task.assigneeId = assigneeId.map { AgentID(value: $0) }
        task.updatedAt = Date()

        try taskRepository.save(task)

        // Record event
        let eventType: EventType = assigneeId != nil ? .assigned : .unassigned
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: eventType,
            agentId: nil,
            sessionId: nil,
            previousState: previousAssignee?.value,
            newState: assigneeId
        )
        try eventRepository.save(event)

        return [
            "success": true,
            "task": taskToDict(task)
        ]
    }

    /// save_context - タスクのコンテキストを保存
    /// ステートレス設計: セッションは不要
    private func saveContext(taskId: String, arguments: [String: Any]) throws -> [String: Any] {
        let id = TaskID(value: taskId)
        guard let task = try taskRepository.findById(id) else {
            throw MCPError.taskNotFound(taskId)
        }

        // ステートレス設計: セッションIDとエージェントIDは引数から取得（オプション）
        let sessionIdStr = arguments["session_id"] as? String
        let agentIdStr = arguments["agent_id"] as? String

        let context = Context(
            id: ContextID.generate(),
            taskId: id,
            sessionId: sessionIdStr.map { SessionID(value: $0) } ?? SessionID.generate(),
            agentId: agentIdStr.map { AgentID(value: $0) } ?? AgentID(value: "unknown"),
            progress: arguments["progress"] as? String,
            findings: arguments["findings"] as? String,
            blockers: arguments["blockers"] as? String,
            nextSteps: arguments["next_steps"] as? String
        )

        try contextRepository.save(context)

        // Record event
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .context,
            entityId: context.id.value,
            eventType: .created,
            agentId: agentIdStr.map { AgentID(value: $0) },
            sessionId: sessionIdStr.map { SessionID(value: $0) }
        )
        try eventRepository.save(event)

        return [
            "success": true,
            "context": contextToDict(context)
        ]
    }

    /// get_task_context - タスクのコンテキストを取得
    private func getTaskContext(taskId: String, includeHistory: Bool) throws -> [String: Any] {
        let id = TaskID(value: taskId)
        guard try taskRepository.findById(id) != nil else {
            throw MCPError.taskNotFound(taskId)
        }

        if includeHistory {
            let contexts = try contextRepository.findByTask(id)
            return [
                "task_id": taskId,
                "contexts": contexts.map { contextToDict($0) }
            ]
        } else {
            if let context = try contextRepository.findLatest(taskId: id) {
                return [
                    "task_id": taskId,
                    "latest_context": contextToDict(context)
                ]
            } else {
                return [
                    "task_id": taskId,
                    "latest_context": NSNull()
                ]
            }
        }
    }

    /// create_handoff - ハンドオフを作成
    /// ステートレス設計: from_agent_idは必須引数
    private func createHandoff(taskId: String, fromAgentId: String, summary: String, arguments: [String: Any]) throws -> [String: Any] {
        let id = TaskID(value: taskId)
        guard let task = try taskRepository.findById(id) else {
            throw MCPError.taskNotFound(taskId)
        }

        let fromAgent = AgentID(value: fromAgentId)
        let toAgentId = (arguments["to_agent_id"] as? String).map { AgentID(value: $0) }

        // Validate from agent exists
        guard try agentRepository.findById(fromAgent) != nil else {
            throw MCPError.agentNotFound(fromAgentId)
        }

        // Validate target agent if specified
        if let targetId = toAgentId {
            guard try agentRepository.findById(targetId) != nil else {
                throw MCPError.agentNotFound(targetId.value)
            }
        }

        let handoff = Handoff(
            id: HandoffID.generate(),
            taskId: id,
            fromAgentId: fromAgent,
            toAgentId: toAgentId,
            summary: summary,
            context: arguments["context"] as? String,
            recommendations: arguments["recommendations"] as? String
        )

        try handoffRepository.save(handoff)

        // Record event
        var metadata: [String: String] = [:]
        if let to = toAgentId {
            metadata["to_agent_id"] = to.value
        }

        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .handoff,
            entityId: handoff.id.value,
            eventType: .created,
            agentId: fromAgent,
            sessionId: nil,
            metadata: metadata.isEmpty ? nil : metadata
        )
        try eventRepository.save(event)

        return [
            "success": true,
            "handoff": handoffToDict(handoff)
        ]
    }

    /// accept_handoff - ハンドオフを受領
    /// ステートレス設計: agent_idは必須引数
    private func acceptHandoff(handoffId: String, agentId: String) throws -> [String: Any] {
        guard var handoff = try handoffRepository.findById(HandoffID(value: handoffId)) else {
            throw MCPError.handoffNotFound(handoffId)
        }

        let acceptingAgent = AgentID(value: agentId)

        // Check if already accepted
        guard handoff.acceptedAt == nil else {
            throw MCPError.handoffAlreadyAccepted(handoffId)
        }

        // Check if targeted to specific agent
        if let targetAgentId = handoff.toAgentId {
            guard targetAgentId == acceptingAgent else {
                throw MCPError.handoffNotForYou(handoffId)
            }
        }

        handoff.acceptedAt = Date()
        try handoffRepository.save(handoff)

        // Get task for project ID
        guard let task = try taskRepository.findById(handoff.taskId) else {
            throw MCPError.taskNotFound(handoff.taskId.value)
        }

        // Record event
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .handoff,
            entityId: handoff.id.value,
            eventType: .completed,
            agentId: acceptingAgent,
            sessionId: nil,
            previousState: "pending",
            newState: "accepted"
        )
        try eventRepository.save(event)

        return [
            "success": true,
            "handoff": handoffToDict(handoff)
        ]
    }

    /// get_pending_handoffs - 未処理のハンドオフ一覧を取得
    /// ステートレス設計: agent_idがあればそのエージェント向けのみ、なければ全て
    private func getPendingHandoffs(agentId: String?) throws -> [[String: Any]] {
        let handoffs: [Handoff]
        if let agentIdStr = agentId {
            let targetAgentId = AgentID(value: agentIdStr)
            handoffs = try handoffRepository.findPending(agentId: targetAgentId)
        } else {
            handoffs = try handoffRepository.findAllPending()
        }
        return handoffs.map { handoffToDict($0) }
    }

    // MARK: - Execution Log (Phase 3-3)

    /// report_execution_start - 実行開始を報告
    /// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-3
    private func reportExecutionStart(taskId: String, agentId: String) throws -> [String: Any] {
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
    private func reportExecutionComplete(
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

    // MARK: - Helper Methods

    private func agentToDict(_ agent: Agent) -> [String: Any] {
        var dict: [String: Any] = [
            "id": agent.id.value,
            "name": agent.name,
            "role": agent.role,
            "type": agent.type.rawValue,
            "role_type": agent.roleType.rawValue,
            "capabilities": agent.capabilities,
            "status": agent.status.rawValue,
            "created_at": ISO8601DateFormatter().string(from: agent.createdAt)
        ]

        // AIタイプがあれば追加
        if let aiType = agent.aiType {
            dict["ai_type"] = aiType.rawValue
        }

        return dict
    }

    private func projectToDict(_ project: Project) -> [String: Any] {
        var dict: [String: Any] = [
            "id": project.id.value,
            "name": project.name,
            "description": project.description,
            "status": project.status.rawValue,
            "created_at": ISO8601DateFormatter().string(from: project.createdAt),
            "updated_at": ISO8601DateFormatter().string(from: project.updatedAt)
        ]

        if let workingDirectory = project.workingDirectory {
            dict["working_directory"] = workingDirectory
        }

        return dict
    }

    private func taskToDict(_ task: Task) -> [String: Any] {
        var dict: [String: Any] = [
            "id": task.id.value,
            "project_id": task.projectId.value,
            "title": task.title,
            "description": task.description,
            "status": task.status.rawValue,
            "priority": task.priority.rawValue,
            "created_at": ISO8601DateFormatter().string(from: task.createdAt),
            "updated_at": ISO8601DateFormatter().string(from: task.updatedAt)
        ]

        if let assigneeId = task.assigneeId {
            dict["assignee_id"] = assigneeId.value
        }
        if let estimatedMinutes = task.estimatedMinutes {
            dict["estimated_minutes"] = estimatedMinutes
        }
        if let actualMinutes = task.actualMinutes {
            dict["actual_minutes"] = actualMinutes
        }
        if let completedAt = task.completedAt {
            dict["completed_at"] = ISO8601DateFormatter().string(from: completedAt)
        }

        return dict
    }

    private func sessionToDict(_ session: Session) -> [String: Any] {
        var dict: [String: Any] = [
            "id": session.id.value,
            "project_id": session.projectId.value,
            "agent_id": session.agentId.value,
            "status": session.status.rawValue,
            "started_at": ISO8601DateFormatter().string(from: session.startedAt)
        ]

        if let endedAt = session.endedAt {
            dict["ended_at"] = ISO8601DateFormatter().string(from: endedAt)
        }

        return dict
    }

    private func contextToDict(_ context: Context) -> [String: Any] {
        var dict: [String: Any] = [
            "id": context.id.value,
            "task_id": context.taskId.value,
            "session_id": context.sessionId.value,
            "agent_id": context.agentId.value,
            "created_at": ISO8601DateFormatter().string(from: context.createdAt)
        ]

        if let progress = context.progress {
            dict["progress"] = progress
        }
        if let findings = context.findings {
            dict["findings"] = findings
        }
        if let blockers = context.blockers {
            dict["blockers"] = blockers
        }
        if let nextSteps = context.nextSteps {
            dict["next_steps"] = nextSteps
        }

        return dict
    }

    private func handoffToDict(_ handoff: Handoff) -> [String: Any] {
        var dict: [String: Any] = [
            "id": handoff.id.value,
            "task_id": handoff.taskId.value,
            "from_agent_id": handoff.fromAgentId.value,
            "summary": handoff.summary,
            "created_at": ISO8601DateFormatter().string(from: handoff.createdAt)
        ]

        if let toAgentId = handoff.toAgentId {
            dict["to_agent_id"] = toAgentId.value
        }
        if let context = handoff.context {
            dict["context"] = context
        }
        if let recommendations = handoff.recommendations {
            dict["recommendations"] = recommendations
        }
        if let acceptedAt = handoff.acceptedAt {
            dict["accepted_at"] = ISO8601DateFormatter().string(from: acceptedAt)
        }

        return dict
    }

    private func eventToDict(_ event: StateChangeEvent) -> [String: Any] {
        var dict: [String: Any] = [
            "id": event.id.value,
            "project_id": event.projectId.value,
            "entity_type": event.entityType.rawValue,
            "entity_id": event.entityId,
            "event_type": event.eventType.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: event.timestamp)
        ]

        if let agentId = event.agentId {
            dict["agent_id"] = agentId.value
        }
        if let sessionId = event.sessionId {
            dict["session_id"] = sessionId.value
        }
        if let previousState = event.previousState {
            dict["previous_state"] = previousState
        }
        if let newState = event.newState {
            dict["new_state"] = newState
        }
        if let reason = event.reason {
            dict["reason"] = reason
        }
        if let metadata = event.metadata {
            dict["metadata"] = metadata
        }

        return dict
    }
}

// MARK: - MCPError

enum MCPError: Error, CustomStringConvertible {
    case agentNotFound(String)
    case taskNotFound(String)
    case projectNotFound(String)
    case sessionNotFound(String)
    case handoffNotFound(String)
    case invalidStatus(String)
    case invalidStatusTransition(from: String, to: String)
    case unknownTool(String)
    case unknownPrompt(String)
    case missingArguments([String])
    case sessionAlreadyActive(String)
    case noActiveSession
    case handoffAlreadyAccepted(String)
    case handoffNotForYou(String)
    case invalidResourceURI(String)
    case invalidCredentials  // Phase 3-1: 認証エラー
    case sessionTokenRequired  // Phase 3-4: セッショントークン必須
    case sessionTokenInvalid  // Phase 3-4: セッショントークン無効
    case sessionTokenExpired  // Phase 3-4: セッショントークン期限切れ
    case sessionAgentMismatch(expected: String, actual: String)  // Phase 3-4: エージェントID不一致
    case agentNotAssignedToProject(agentId: String, projectId: String)  // Phase 4: エージェント未割り当て

    var description: String {
        switch self {
        case .agentNotFound(let id):
            return "Agent not found: \(id)"
        case .taskNotFound(let id):
            return "Task not found: \(id)"
        case .projectNotFound(let id):
            return "Project not found: \(id)"
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .handoffNotFound(let id):
            return "Handoff not found: \(id)"
        case .invalidStatus(let status):
            return "Invalid status: \(status). Valid values: backlog, todo, in_progress, in_review, blocked, done, cancelled"
        case .invalidStatusTransition(let from, let to):
            return "Invalid status transition from \(from) to \(to)"
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .unknownPrompt(let name):
            return "Unknown prompt: \(name)"
        case .missingArguments(let args):
            return "Missing required arguments: \(args.joined(separator: ", "))"
        case .sessionAlreadyActive(let id):
            return "Session already active: \(id). End current session before starting a new one."
        case .noActiveSession:
            return "No active session. Start a session first using start_session."
        case .handoffAlreadyAccepted(let id):
            return "Handoff already accepted: \(id)"
        case .handoffNotForYou(let id):
            return "Handoff \(id) is not addressed to you"
        case .invalidResourceURI(let uri):
            return "Invalid resource URI: \(uri)"
        case .invalidCredentials:
            return "Invalid agent_id or passkey"
        case .sessionTokenRequired:
            return "session_token is required for this operation. Authenticate first using the authenticate tool."
        case .sessionTokenInvalid:
            return "Invalid session_token. Please re-authenticate."
        case .sessionTokenExpired:
            return "Session token has expired. Please re-authenticate."
        case .sessionAgentMismatch(let expected, let actual):
            return "Session belongs to agent '\(actual)' but operation requested for agent '\(expected)'"
        case .agentNotAssignedToProject(let agentId, let projectId):
            return "Agent '\(agentId)' is not assigned to project '\(projectId)'. Assign the agent to the project first."
        }
    }
}
