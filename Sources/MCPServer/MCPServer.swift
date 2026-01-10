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
            // Phase 5: 認可チェック
            let caller = try identifyCaller(tool: name, arguments: arguments)
            try ToolAuthorization.authorize(tool: name, caller: caller)

            let result = try executeTool(name: name, arguments: arguments, caller: caller)
            return JSONRPCResponse(id: request.id, result: [
                "content": [
                    ["type": "text", "text": formatResult(result)]
                ]
            ])
        } catch let error as ToolAuthorizationError {
            // 認可エラーは専用のエラーメッセージで返す
            return JSONRPCResponse(id: request.id, result: [
                "content": [
                    ["type": "text", "text": "Authorization Error: \(error.errorDescription ?? error.localizedDescription)"]
                ],
                "isError": true
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

    // MARK: - Caller Identification (Phase 5: Authorization)

    /// 呼び出し元を識別
    /// 参照: Sources/MCPServer/Authorization/ToolAuthorization.swift
    private func identifyCaller(tool: String, arguments: [String: Any]) throws -> CallerType {
        // 1. Coordinator token チェック
        if let coordinatorToken = arguments["coordinator_token"] as? String {
            let expectedToken = ProcessInfo.processInfo.environment["MCP_COORDINATOR_TOKEN"] ?? ""
            if !expectedToken.isEmpty && coordinatorToken == expectedToken {
                return .coordinator
            }
            throw MCPError.invalidCoordinatorToken
        }

        // 2. Session token チェック
        if let sessionToken = arguments["session_token"] as? String {
            let session = try validateSession(token: sessionToken)
            let agent = try agentRepository.findById(session.agentId)
            guard let agent = agent else {
                throw MCPError.agentNotFound(session.agentId.value)
            }

            switch agent.hierarchyType {
            case .manager:
                return .manager(agentId: agent.id, session: session)
            case .worker:
                return .worker(agentId: agent.id, session: session)
            }
        }

        // 3. 未認証（authenticate ツールのみ許可）
        return .unauthenticated
    }

    /// Toolを実行
    /// ステートレス設計: 必要なIDは全て引数として受け取る
    /// Phase 5: caller で認可済みの呼び出し元情報を受け取る
    private func executeTool(name: String, arguments: [String: Any], caller: CallerType) throws -> Any {
        switch name {
        // ========================================
        // 未認証でも呼び出し可能
        // ========================================
        case "authenticate":
            guard let agentId = arguments["agent_id"] as? String,
                  let passkey = arguments["passkey"] as? String,
                  let projectId = arguments["project_id"] as? String else {
                throw MCPError.missingArguments(["agent_id", "passkey", "project_id"])
            }
            return try authenticate(agentId: agentId, passkey: passkey, projectId: projectId)

        // ========================================
        // Coordinator専用
        // ========================================
        case "health_check":
            return try healthCheck()

        case "list_managed_agents":
            return try listManagedAgents()

        case "list_active_projects_with_agents":
            return try listActiveProjectsWithAgents()

        case "should_start":
            guard let agentId = arguments["agent_id"] as? String,
                  let projectId = arguments["project_id"] as? String else {
                throw MCPError.missingArguments(["agent_id", "project_id"])
            }
            return try shouldStart(agentId: agentId, projectId: projectId)

        case "register_execution_log_file":
            guard let agentId = arguments["agent_id"] as? String,
                  let taskId = arguments["task_id"] as? String,
                  let logFilePath = arguments["log_file_path"] as? String else {
                throw MCPError.missingArguments(["agent_id", "task_id", "log_file_path"])
            }
            return try registerExecutionLogFile(agentId: agentId, taskId: taskId, logFilePath: logFilePath)

        case "invalidate_session":
            guard let agentId = arguments["agent_id"] as? String,
                  let projectId = arguments["project_id"] as? String else {
                throw MCPError.missingArguments(["agent_id", "project_id"])
            }
            return try invalidateSession(agentId: agentId, projectId: projectId)

        // ========================================
        // Manager専用
        // ========================================
        case "list_subordinates":
            guard case .manager(let agentId, _) = caller else {
                throw ToolAuthorizationError.managerRequired("list_subordinates")
            }
            return try listSubordinates(managerId: agentId.value)

        case "get_subordinate_profile":
            guard case .manager(let managerId, _) = caller else {
                throw ToolAuthorizationError.managerRequired("get_subordinate_profile")
            }
            guard let targetAgentId = arguments["agent_id"] as? String else {
                throw MCPError.missingArguments(["agent_id"])
            }
            return try getSubordinateProfile(managerId: managerId.value, targetAgentId: targetAgentId)

        case "create_task":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let title = arguments["title"] as? String,
                  let description = arguments["description"] as? String else {
                throw MCPError.missingArguments(["title", "description"])
            }
            let priority = arguments["priority"] as? String
            let parentTaskId = arguments["parent_task_id"] as? String
            let dependencies = arguments["dependencies"] as? [String]
            return try createTask(
                agentId: session.agentId,
                projectId: session.projectId,
                title: title,
                description: description,
                priority: priority,
                parentTaskId: parentTaskId,
                dependencies: dependencies
            )

        case "assign_task":
            guard case .manager(_, let session) = caller else {
                throw ToolAuthorizationError.managerRequired("assign_task")
            }
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            let assigneeId = arguments["assignee_id"] as? String
            return try assignTask(taskId: taskId, assigneeId: assigneeId, callingAgentId: session.agentId.value)

        // ========================================
        // Worker専用
        // ========================================
        case "report_completed":
            guard case .worker(_, let session) = caller else {
                throw ToolAuthorizationError.workerRequired("report_completed")
            }
            guard let result = arguments["result"] as? String else {
                throw MCPError.missingArguments(["result"])
            }
            let summary = arguments["summary"] as? String
            let nextSteps = arguments["next_steps"] as? String
            guard let sessionToken = arguments["session_token"] as? String else {
                throw MCPError.sessionTokenRequired
            }
            return try reportCompleted(
                agentId: session.agentId.value,
                projectId: session.projectId.value,
                sessionToken: sessionToken,
                result: result,
                summary: summary,
                nextSteps: nextSteps
            )

        // ========================================
        // 認証済み共通（Manager + Worker）
        // ========================================
        case "get_my_profile":
            guard let agentId = caller.agentId else {
                throw MCPError.sessionTokenRequired
            }
            return try getAgentProfile(agentId: agentId.value)

        case "get_my_task":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            return try getMyTask(agentId: session.agentId.value, projectId: session.projectId.value)

        case "get_next_action":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            return try getNextAction(session: session)

        case "report_model":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let provider = arguments["provider"] as? String,
                  let modelId = arguments["model_id"] as? String else {
                throw MCPError.missingArguments(["provider", "model_id"])
            }
            return try reportModel(session: session, provider: provider, modelId: modelId)

        case "update_task_status":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let taskId = arguments["task_id"] as? String,
                  let status = arguments["status"] as? String else {
                throw MCPError.missingArguments(["task_id", "status"])
            }
            _ = try validateTaskWriteAccess(taskId: TaskID(value: taskId), session: session)
            let reason = arguments["reason"] as? String
            return try updateTaskStatus(taskId: taskId, status: status, reason: reason)

        case "get_project":
            guard let projectId = arguments["project_id"] as? String else {
                throw MCPError.missingArguments(["project_id"])
            }
            return try getProject(projectId: projectId)

        case "list_tasks":
            let status = arguments["status"] as? String
            let assigneeId = arguments["assignee_id"] as? String
            return try listTasks(status: status, assigneeId: assigneeId)

        case "get_task":
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            return try getTask(taskId: taskId)

        case "report_execution_start":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            return try reportExecutionStart(taskId: taskId, agentId: session.agentId.value)

        case "report_execution_complete":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let executionLogId = arguments["execution_log_id"] as? String,
                  let exitCode = arguments["exit_code"] as? Int,
                  let durationSeconds = arguments["duration_seconds"] as? Double else {
                throw MCPError.missingArguments(["execution_log_id", "exit_code", "duration_seconds"])
            }
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

        // ========================================
        // 削除済み（エラーを返す）
        // ========================================
        case "list_agents":
            throw MCPError.unknownTool("list_agents (use list_subordinates instead)")
        case "get_agent_profile":
            throw MCPError.unknownTool("get_agent_profile (use get_subordinate_profile instead)")
        case "list_projects":
            throw MCPError.unknownTool("list_projects (use get_project instead)")

        case "get_my_tasks":
            throw MCPError.unknownTool("get_my_tasks (use list_tasks with assignee_id instead)")

        case "get_pending_tasks":
            throw MCPError.unknownTool("get_pending_tasks (use get_my_task instead)")

        case "save_context":
            throw MCPError.unknownTool("save_context")

        case "get_task_context":
            throw MCPError.unknownTool("get_task_context")

        case "create_handoff":
            throw MCPError.unknownTool("create_handoff")

        case "accept_handoff":
            throw MCPError.unknownTool("accept_handoff")

        case "get_pending_handoffs":
            throw MCPError.unknownTool("get_pending_handoffs")

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

    /// セッショントークンを検証し、AgentSessionを返す
    /// 参照: セキュリティ改善 - セッショントークン検証の実装
    /// Phase 4: セッションを検証し、完全なAgentSessionオブジェクトを返す（モデル検証用）
    private func validateSession(token: String) throws -> AgentSession {
        guard let session = try agentSessionRepository.findByToken(token) else {
            // findByToken は期限切れセッションを除外するので、
            // トークンが見つからない = 無効または期限切れ
            Self.log("[MCP] Session validation failed: token not found or expired")
            throw MCPError.sessionTokenInvalid
        }

        Self.log("[MCP] Session validated for agent: \(session.agentId.value), project: \(session.projectId.value)")
        return session
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

    /// タスクへのアクセス権限を検証
    /// エージェントが以下のいずれかの条件を満たす場合にアクセスを許可:
    /// 1. タスクの assigneeId が一致
    /// 2. タスクの parentTaskId を持つ親タスクの assigneeId が一致（サブタスク）
    /// 3. タスクが同じプロジェクトに属する（プロジェクト内のタスク参照）
    private func validateTaskAccess(taskId: TaskID, session: AgentSession) throws -> Task {
        guard let task = try taskRepository.findById(taskId) else {
            throw MCPError.taskNotFound(taskId.value)
        }

        // 同じプロジェクトのタスクであることを確認
        guard task.projectId == session.projectId else {
            Self.log("[MCP] Task access denied: task project=\(task.projectId.value), session project=\(session.projectId.value)")
            throw MCPError.taskAccessDenied(taskId.value)
        }

        // 直接の担当者、または親タスクの担当者であればアクセス許可
        if task.assigneeId == session.agentId {
            return task
        }

        // サブタスクの場合、親タスクの担当者かチェック
        if let parentId = task.parentTaskId,
           let parentTask = try taskRepository.findById(parentId),
           parentTask.assigneeId == session.agentId {
            return task
        }

        // 同じプロジェクト内であれば読み取りは許可（書き込みは別途チェック）
        return task
    }

    /// タスクへの書き込み権限を検証（より厳格）
    /// エージェントが担当者または親タスクの担当者である場合のみ許可
    private func validateTaskWriteAccess(taskId: TaskID, session: AgentSession) throws -> Task {
        guard let task = try taskRepository.findById(taskId) else {
            throw MCPError.taskNotFound(taskId.value)
        }

        // 同じプロジェクトのタスクであることを確認
        guard task.projectId == session.projectId else {
            Self.log("[MCP] Task write access denied: task project=\(task.projectId.value), session project=\(session.projectId.value)")
            throw MCPError.taskAccessDenied(taskId.value)
        }

        // 直接の担当者であればアクセス許可
        if task.assigneeId == session.agentId {
            return task
        }

        // サブタスクの場合、親タスクの担当者かチェック
        if let parentId = task.parentTaskId,
           let parentTask = try taskRepository.findById(parentId),
           parentTask.assigneeId == session.agentId {
            return task
        }

        Self.log("[MCP] Task write access denied: agent=\(session.agentId.value), task assignee=\(task.assigneeId?.value ?? "nil")")
        throw MCPError.taskAccessDenied(taskId.value)
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

        // Debug: log all tasks found for this agent with full details
        Self.log("[MCP] shouldStart: Agent '\(agentId)' checking for in_progress tasks in project '\(projectId)'")
        Self.log("[MCP] shouldStart: Found \(tasks.count) total assigned task(s)")
        for task in tasks {
            let matchesProject = task.projectId == projId
            let isInProgress = task.status == .inProgress
            Self.log("[MCP] shouldStart:   - Task '\(task.id.value)': status=\(task.status.rawValue), projectId=\(task.projectId.value), matchesProject=\(matchesProject), isInProgress=\(isInProgress)")
        }

        let inProgressTask = tasks.first { task in
            task.status == .inProgress && task.projectId == projId
        }
        let hasInProgressTask = inProgressTask != nil

        Self.log("[MCP] shouldStart for '\(agentId)/\(projectId)': \(hasInProgressTask) (in_progress task: \(inProgressTask?.id.value ?? "none"))")

        // Manager の待機状態チェック
        // Context.progress が "workflow:waiting_for_workers" の場合、動的計算で判断
        if agent.hierarchyType == .manager, let task = inProgressTask {
            let latestContext = try contextRepository.findLatest(taskId: task.id)

            if latestContext?.progress == "workflow:waiting_for_workers" {
                Self.log("[MCP] shouldStart: Manager is in waiting_for_workers state, checking subtasks")

                // サブタスクの状態を動的に確認
                let allTasks = try taskRepository.findByProject(projId, status: nil)
                let subTasks = allTasks.filter { $0.parentTaskId == task.id }
                let inProgressSubTasks = subTasks.filter { $0.status == .inProgress }
                let completedSubTasks = subTasks.filter { $0.status == .done }

                Self.log("[MCP] shouldStart: subtasks=\(subTasks.count), inProgress=\(inProgressSubTasks.count), completed=\(completedSubTasks.count)")

                // まだ Worker が実行中 → 起動しない
                if !inProgressSubTasks.isEmpty {
                    Self.log("[MCP] shouldStart: Manager should NOT start (waiting for \(inProgressSubTasks.count) workers)")
                    return [
                        "should_start": false,
                        "reason": "waiting_for_workers",
                        "progress": [
                            "completed": completedSubTasks.count,
                            "in_progress": inProgressSubTasks.count,
                            "total": subTasks.count
                        ]
                    ]
                }

                // 全サブタスク完了 → 起動して report_completion
                Self.log("[MCP] shouldStart: All subtasks completed, Manager should start for report_completion")
            }
        }

        // provider/model を返す（RunnerがCLIコマンドを選択するため）
        // kickCommand があればそれを優先
        var result: [String: Any] = [
            "should_start": hasInProgressTask
        ]

        // task_id を返す（Coordinatorがログファイルパスを登録するため）
        if let task = inProgressTask {
            result["task_id"] = task.id.value
        }

        // kickCommand があれば provider/model より優先
        if let kickCommand = agent.kickCommand, !kickCommand.isEmpty {
            result["kick_command"] = kickCommand
        }

        // provider と model を構造的に返す
        if let aiType = agent.aiType {
            result["provider"] = aiType.provider       // "claude", "gemini", "openai", "other"
            result["model"] = aiType.rawValue          // "claude-sonnet-4-5", "gemini-2.0-flash", etc.
        } else {
            result["provider"] = "claude"              // デフォルト
            result["model"] = "claude-sonnet-4-5"      // デフォルト
        }

        // 後方互換性のため ai_type も維持（非推奨）
        result["ai_type"] = agent.aiType?.rawValue ?? "claude-sonnet-4-5"

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
                "description": task.description ?? ""
            ]

            // ワークフロー指示を追加（Agent が description を直接実行せず、get_next_action に従うよう誘導）
            taskDict["workflow_instruction"] = """
                このタスク情報はコンテキスト理解用です。実際の作業を開始する前に、
                必ず get_next_action を呼び出して、システムからの指示に従ってください。
                タスクはサブタスクに分解してから実行する必要があります。
                """

            if let workDir = workingDirectory {
                taskDict["working_directory"] = workDir
            }

            if let ctx = latestContext {
                taskDict["context"] = contextToDict(ctx)
            }

            if let handoff = latestHandoff {
                taskDict["handoff"] = handoffToDict(handoff)
            }

            // Phase 4: 実行ログを自動作成（report_execution_startの代替）
            let executionLog = ExecutionLog(
                taskId: task.id,
                agentId: id,
                startedAt: Date()
            )
            try executionLogRepository.save(executionLog)
            Self.log("[MCP] ExecutionLog auto-created: \(executionLog.id.value)")

            // ワークフローフェーズを記録（get_next_action用）
            // 参照: docs/plan/STATE_DRIVEN_WORKFLOW.md
            // Note: Context.sessionId は sessions テーブルを参照するため、
            // 先に Session を作成してからその ID を使用する
            let workflowSession = Session(
                id: SessionID.generate(),
                projectId: projId,
                agentId: id,
                startedAt: Date(),
                status: .active
            )
            try sessionRepository.save(workflowSession)
            Self.log("[MCP] Workflow session created: \(workflowSession.id.value)")

            let workflowContext = Context(
                id: ContextID.generate(),
                taskId: task.id,
                sessionId: workflowSession.id,
                agentId: id,
                progress: "workflow:task_fetched"
            )
            try contextRepository.save(workflowContext)
            Self.log("[MCP] Workflow phase recorded: task_fetched")

            Self.log("[MCP] getMyTask returning task: \(task.id.value)")

            return [
                "success": true,
                "has_task": true,
                "task": taskDict,
                "instruction": """
                    タスクが割り当てられています。
                    get_next_action を呼び出してください。
                    システムが次の作業を指示します。
                    """
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

    /// report_model - Agent Instanceのモデル情報を申告・検証
    /// Agent Instanceが申告した provider/model_id をエージェント設定と照合し、
    /// 検証結果をセッションに記録する
    private func reportModel(
        session: AgentSession,
        provider: String,
        modelId: String
    ) throws -> [String: Any] {
        Self.log("[MCP] reportModel called: provider='\(provider)', model_id='\(modelId)'")

        // エージェント情報を取得（aiType との照合用）
        guard let agent = try agentRepository.findById(session.agentId) else {
            Self.log("[MCP] reportModel: Agent not found: \(session.agentId.value)")
            return [
                "success": false,
                "error": "agent_not_found",
                "message": "エージェントが見つかりません"
            ]
        }

        // 期待値との照合
        var verified = false
        var verificationMessage = ""

        if let expectedAiType = agent.aiType {
            // エージェントにAIType設定がある場合、照合
            let expectedProvider = expectedAiType.provider
            let expectedModelId = expectedAiType.modelId

            if provider == expectedProvider && modelId == expectedModelId {
                verified = true
                verificationMessage = "モデル検証成功: 期待通りのモデルが使用されています"
            } else if provider == expectedProvider {
                // プロバイダーは一致、モデルIDが異なる
                verified = false
                verificationMessage = "モデル不一致: プロバイダーは一致しますが、モデルIDが異なります（期待: \(expectedModelId), 申告: \(modelId)）"
            } else {
                verified = false
                verificationMessage = "モデル不一致: プロバイダーが異なります（期待: \(expectedProvider), 申告: \(provider)）"
            }
        } else {
            // AIType設定がない場合（custom または未設定）
            // 申告を受け入れ、記録のみ行う
            verified = true
            verificationMessage = "モデル申告記録: エージェントにAIType設定がないため、申告を記録しました"
        }

        // セッションを更新
        var updatedSession = session
        updatedSession.reportedProvider = provider
        updatedSession.reportedModel = modelId
        updatedSession.modelVerified = verified
        updatedSession.modelVerifiedAt = Date()

        try agentSessionRepository.save(updatedSession)
        Self.log("[MCP] reportModel: Session updated with verification result: verified=\(verified)")

        // 実行中のExecutionLogにもモデル情報を記録
        // in_progress タスクを取得し、対応するExecutionLogを更新
        let tasks = try taskRepository.findByAssignee(session.agentId)
        if let inProgressTask = tasks.first(where: { $0.status == .inProgress && $0.projectId == session.projectId }) {
            if var executionLog = try executionLogRepository.findLatestByAgentAndTask(
                agentId: session.agentId,
                taskId: inProgressTask.id
            ) {
                executionLog.setModelInfo(provider: provider, model: modelId, verified: verified)
                try executionLogRepository.save(executionLog)
                Self.log("[MCP] reportModel: ExecutionLog updated with model info: \(executionLog.id.value)")
            }
        }

        return [
            "success": true,
            "verified": verified,
            "message": verificationMessage,
            "instruction": verified
                ? "モデル検証が完了しました。get_next_action を呼び出して次の指示を受けてください。"
                : "モデルが期待と異なりますが、処理を続行できます。get_next_action を呼び出して次の指示を受けてください。"
        ]
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

        // サブタスク作成を強制: メインタスク（parentTaskId=nil）の場合、サブタスクが必要
        if task.parentTaskId == nil {
            let allTasks = try taskRepository.findByProject(projId, status: nil)
            let subTasks = allTasks.filter { $0.parentTaskId == task.id }
            if subTasks.isEmpty {
                Self.log("[MCP] reportCompleted: Subtasks required for main task. Task: \(task.id.value)")
                return [
                    "success": false,
                    "error": "サブタスクを作成してから完了報告してください。get_next_action を呼び出して指示に従ってください。",
                    "instruction": "get_next_action を呼び出してください。システムがサブタスク作成を指示します。"
                ]
            }

            // 全サブタスクが完了していることを確認
            let incompleteSubTasks = subTasks.filter { $0.status != TaskStatus.done && $0.status != TaskStatus.cancelled }
            if !incompleteSubTasks.isEmpty {
                Self.log("[MCP] reportCompleted: Incomplete subtasks exist. Count: \(incompleteSubTasks.count)")
                return [
                    "success": false,
                    "error": "未完了のサブタスクがあります。全てのサブタスクを完了してから報告してください。",
                    "incomplete_subtasks": incompleteSubTasks.map { ["id": $0.id.value, "title": $0.title, "status": $0.status.rawValue] }
                ]
            }
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

        // Phase 4: 実行ログを完了（report_execution_completeの代替）
        // 最新の実行ログを取得して完了状態に更新
        if var executionLog = try executionLogRepository.findLatestByAgentAndTask(agentId: id, taskId: task.id) {
            let exitCode = result == "success" ? 0 : 1
            let duration = Date().timeIntervalSince(executionLog.startedAt)
            let errorMessage = result != "success" ? summary : nil
            executionLog.complete(
                exitCode: exitCode,
                durationSeconds: duration,
                logFilePath: nil,  // Coordinatorが後で登録
                errorMessage: errorMessage
            )
            try executionLogRepository.save(executionLog)
            Self.log("[MCP] ExecutionLog auto-completed: \(executionLog.id.value), status=\(executionLog.status.rawValue)")
        }

        Self.log("[MCP] reportCompleted: Task \(task.id.value) status changed to \(newStatus.rawValue)")

        return [
            "success": true,
            "instruction": "タスクが完了しました。セッションを終了しました。"
        ]
    }

    // MARK: Phase 4: State-Driven Workflow Control

    /// get_next_action - 状態駆動ワークフロー制御
    /// 参照: docs/plan/STATE_DRIVEN_WORKFLOW.md
    /// Agent の hierarchy_type と Context のワークフローフェーズに基づいて次のアクションを判断
    /// モデル検証が未完了の場合は report_model アクションを返す
    private func getNextAction(session: AgentSession) throws -> [String: Any] {
        let agentId = session.agentId
        let projectId = session.projectId
        Self.log("[MCP] getNextAction called for agent: '\(agentId.value)', project: '\(projectId.value)'")

        // 1. エージェント情報を取得（hierarchy_type 判断用）
        guard let agent = try agentRepository.findById(agentId) else {
            Self.log("[MCP] getNextAction: Agent not found: \(agentId.value)")
            return [
                "action": "error",
                "instruction": "エージェントが見つかりません。",
                "error": "agent_not_found"
            ]
        }

        // 1.5. モデル検証チェック - 未検証の場合は report_model を要求
        if session.modelVerified == nil {
            Self.log("[MCP] getNextAction: Model not verified yet, requesting report_model")
            return [
                "action": "report_model",
                "instruction": """
                    モデル情報を申告してください。
                    report_model ツールを呼び出し、現在使用中の provider と model_id を申告してください。
                    申告後、get_next_action を再度呼び出してください。
                    """,
                "state": "needs_model_verification"
            ]
        }

        // 2. メインタスク（in_progress 状態、parentTaskId = nil）を取得
        let allTasks = try taskRepository.findByAssignee(agentId)
        let inProgressTasks = allTasks.filter { $0.status == .inProgress && $0.projectId == projectId }
        let mainTask = inProgressTasks.first { $0.parentTaskId == nil }

        guard let main = mainTask else {
            // メインタスクがない = get_my_task をまだ呼んでいない
            // Coordinator は in_progress タスクがある場合のみ起動するので、
            // ここに来るのは get_my_task 呼び出し前のみ
            return [
                "action": "get_task",
                "instruction": """
                    get_my_task を呼び出してタスク詳細を取得してください。
                    取得後、get_next_action を呼び出して次の指示を受けてください。
                    タスクの description を直接実行しないでください。
                    """,
                "state": "needs_task"
            ]
        }

        // 3. Context から最新のワークフローフェーズを取得
        let latestContext = try contextRepository.findLatest(taskId: main.id)
        let phase = latestContext?.progress ?? ""

        Self.log("[MCP] getNextAction: hierarchy=\(agent.hierarchyType.rawValue), phase=\(phase)")

        // 4. 階層タイプに応じた処理を分岐
        switch agent.hierarchyType {
        case .worker:
            return try getWorkerNextAction(mainTask: main, phase: phase, allTasks: allTasks)
        case .manager:
            return try getManagerNextAction(mainTask: main, phase: phase, allTasks: allTasks)
        }
    }

    /// Worker のワークフロー制御
    /// 参照: docs/plan/STATE_DRIVEN_WORKFLOW.md - Worker のワークフロー
    /// Worker はサブタスクを作成し、自分で順番に実行する
    private func getWorkerNextAction(mainTask: Task, phase: String, allTasks: [Task]) throws -> [String: Any] {
        Self.log("[MCP] getWorkerNextAction: task=\(mainTask.id.value), phase=\(phase)")

        // サブタスク（parentTaskId = mainTask.id）を取得
        let subTasks = allTasks.filter { $0.parentTaskId == mainTask.id }
        let pendingSubTasks = subTasks.filter { $0.status == .todo || $0.status == .backlog }
        let inProgressSubTasks = subTasks.filter { $0.status == .inProgress }
        let completedSubTasks = subTasks.filter { $0.status == .done }

        Self.log("[MCP] getWorkerNextAction: subTasks=\(subTasks.count), pending=\(pendingSubTasks.count), inProgress=\(inProgressSubTasks.count), completed=\(completedSubTasks.count)")

        // 1. サブタスク未作成 → サブタスク作成フェーズへ
        if phase == "workflow:task_fetched" && subTasks.isEmpty {
            // サブタスク作成フェーズを記録
            // Note: Context.sessionId は sessions テーブルを参照するため、
            // 先に Session を作成してからその ID を使用する
            let workflowSession = Session(
                id: SessionID.generate(),
                projectId: mainTask.projectId,
                agentId: mainTask.assigneeId!,
                startedAt: Date(),
                status: .active
            )
            try sessionRepository.save(workflowSession)

            let context = Context(
                id: ContextID.generate(),
                taskId: mainTask.id,
                sessionId: workflowSession.id,
                agentId: mainTask.assigneeId!,
                progress: "workflow:creating_subtasks"
            )
            try contextRepository.save(context)

            return [
                "action": "create_subtasks",
                "instruction": """
                    タスクを2〜5個のサブタスクに分解してください。
                    create_task ツールを使用して、具体的で実行可能なサブタスクを作成してください。
                    各サブタスクには parent_task_id として '\(mainTask.id.value)' を指定してください。
                    タスク間に順序関係がある場合（例: タスクBがタスクAの出力を使用する）、
                    後続タスクの dependencies に先行タスクのIDを指定してください。
                    サブタスク作成後、get_next_action を呼び出してください。
                    """,
                "state": "needs_subtask_creation",
                "task": [
                    "id": mainTask.id.value,
                    "title": mainTask.title,
                    "description": mainTask.description
                ]
            ]
        }

        // 2. サブタスクが存在する場合 → 順番に実行
        if !subTasks.isEmpty {
            // 全サブタスク完了 → メインタスク完了報告
            if completedSubTasks.count == subTasks.count {
                return [
                    "action": "report_completion",
                    "instruction": """
                        全てのサブタスクが完了しました。
                        report_completed を呼び出してメインタスクを完了してください。
                        result には 'success' を指定し、作業内容を summary に記載してください。
                        """,
                    "state": "needs_completion",
                    "task": [
                        "id": mainTask.id.value,
                        "title": mainTask.title
                    ],
                    "completed_subtasks": completedSubTasks.count
                ]
            }

            // 実行中のサブタスクがある → 続けて実行
            if let currentSubTask = inProgressSubTasks.first {
                return [
                    "action": "execute_subtask",
                    "instruction": """
                        現在のサブタスクを実行してください。
                        完了したら update_task_status で status を 'done' に変更し、
                        get_next_action を呼び出してください。
                        """,
                    "state": "executing_subtask",
                    "current_subtask": [
                        "id": currentSubTask.id.value,
                        "title": currentSubTask.title,
                        "description": currentSubTask.description
                    ],
                    "progress": [
                        "completed": completedSubTasks.count,
                        "total": subTasks.count
                    ]
                ]
            }

            // 次のサブタスクを開始
            if let nextSubTask = pendingSubTasks.first {
                return [
                    "action": "start_subtask",
                    "instruction": """
                        次のサブタスクを開始してください。
                        update_task_status で '\(nextSubTask.id.value)' のステータスを 'in_progress' に変更し、
                        作業を実行してください。
                        """,
                    "state": "start_next_subtask",
                    "next_subtask": [
                        "id": nextSubTask.id.value,
                        "title": nextSubTask.title,
                        "description": nextSubTask.description
                    ],
                    "progress": [
                        "completed": completedSubTasks.count,
                        "total": subTasks.count
                    ]
                ]
            }
        }

        // 3. サブタスク作成中フェーズ → 作成完了後の処理
        if phase == "workflow:creating_subtasks" && !subTasks.isEmpty {
            // サブタスク作成完了を記録
            // Note: Context.sessionId は sessions テーブルを参照するため、
            // 先に Session を作成してからその ID を使用する
            let workflowSession = Session(
                id: SessionID.generate(),
                projectId: mainTask.projectId,
                agentId: mainTask.assigneeId!,
                startedAt: Date(),
                status: .active
            )
            try sessionRepository.save(workflowSession)

            let context = Context(
                id: ContextID.generate(),
                taskId: mainTask.id,
                sessionId: workflowSession.id,
                agentId: mainTask.assigneeId!,
                progress: "workflow:subtasks_created"
            )
            try contextRepository.save(context)

            // 最初のサブタスクを開始
            if let firstSubTask = pendingSubTasks.first {
                return [
                    "action": "start_subtask",
                    "instruction": """
                        サブタスクの実行を開始してください。
                        update_task_status で '\(firstSubTask.id.value)' のステータスを 'in_progress' に変更し、
                        作業を実行してください。
                        """,
                    "state": "start_next_subtask",
                    "next_subtask": [
                        "id": firstSubTask.id.value,
                        "title": firstSubTask.title,
                        "description": firstSubTask.description
                    ]
                ]
            }
        }

        // フォールバック
        return [
            "action": "get_task",
            "instruction": "get_my_task を呼び出してタスク詳細を取得してください。",
            "state": "needs_task"
        ]
    }

    /// Manager のワークフロー制御
    /// 参照: docs/plan/STATE_DRIVEN_WORKFLOW.md - Manager のワークフロー
    /// Manager はサブタスクを作成して Worker に割り当て（自分では実行しない）
    private func getManagerNextAction(mainTask: Task, phase: String, allTasks: [Task]) throws -> [String: Any] {
        Self.log("[MCP] getManagerNextAction: task=\(mainTask.id.value), phase=\(phase)")

        // サブタスク（parentTaskId = mainTask.id）を取得
        let subTasks = allTasks.filter { $0.parentTaskId == mainTask.id }
        let pendingSubTasks = subTasks.filter { $0.status == .todo || $0.status == .backlog }
        let inProgressSubTasks = subTasks.filter { $0.status == .inProgress }
        let completedSubTasks = subTasks.filter { $0.status == .done }

        Self.log("[MCP] getManagerNextAction: subTasks=\(subTasks.count), pending=\(pendingSubTasks.count), inProgress=\(inProgressSubTasks.count), completed=\(completedSubTasks.count)")

        // サブタスクがまだ作成されていない
        if phase == "workflow:task_fetched" && subTasks.isEmpty {
            // サブタスク作成フェーズを記録
            // Note: Context.sessionId は sessions テーブルを参照するため、
            // 先に Session を作成してからその ID を使用する
            let workflowSession = Session(
                id: SessionID.generate(),
                projectId: mainTask.projectId,
                agentId: mainTask.assigneeId!,
                startedAt: Date(),
                status: .active
            )
            try sessionRepository.save(workflowSession)

            let context = Context(
                id: ContextID.generate(),
                taskId: mainTask.id,
                sessionId: workflowSession.id,
                agentId: mainTask.assigneeId!,
                progress: "workflow:creating_subtasks"
            )
            try contextRepository.save(context)

            return [
                "action": "create_subtasks",
                "instruction": """
                    タスクを2〜5個のサブタスクに分解してください。
                    create_task ツールを使用して、具体的で実行可能なサブタスクを作成してください。
                    各サブタスクには parent_task_id として '\(mainTask.id.value)' を指定してください。
                    タスク間に順序関係がある場合（例: タスクBがタスクAの出力を使用する）、
                    後続タスクの dependencies に先行タスクのIDを指定してください。
                    サブタスク作成後、get_next_action を呼び出してください。
                    """,
                "state": "needs_subtask_creation",
                "task": [
                    "id": mainTask.id.value,
                    "title": mainTask.title,
                    "description": mainTask.description
                ]
            ]
        }

        // サブタスクが存在する場合の処理
        if !subTasks.isEmpty {
            // 全サブタスクが完了
            if completedSubTasks.count == subTasks.count {
                return [
                    "action": "report_completion",
                    "instruction": """
                        全てのサブタスクが完了しました。
                        report_completed を呼び出してメインタスクを完了してください。
                        result には 'success' を指定し、作業内容を summary に記載してください。
                        """,
                    "state": "needs_completion",
                    "task": [
                        "id": mainTask.id.value,
                        "title": mainTask.title
                    ],
                    "completed_subtasks": completedSubTasks.count
                ]
            }

            // 実行中のサブタスクがある → Worker の完了を待つ
            // Context に waiting_for_workers を記録し、exit アクションを返す
            // Coordinator が should_start で待機状態を判断し、Worker 完了後に再起動する
            if !inProgressSubTasks.isEmpty {
                // 待機状態を Context に記録
                let workflowSession = Session(
                    id: SessionID.generate(),
                    projectId: mainTask.projectId,
                    agentId: mainTask.assigneeId!,
                    startedAt: Date(),
                    status: .active
                )
                try sessionRepository.save(workflowSession)

                let context = Context(
                    id: ContextID.generate(),
                    taskId: mainTask.id,
                    sessionId: workflowSession.id,
                    agentId: mainTask.assigneeId!,
                    progress: "workflow:waiting_for_workers"
                )
                try contextRepository.save(context)
                Self.log("[MCP] Manager waiting for workers, saved context: waiting_for_workers")

                return [
                    "action": "exit",
                    "instruction": """
                        サブタスクを Worker に委譲しました。
                        Worker の完了を待つため、ここでプロセスを終了してください。
                        Coordinator が Worker 完了後に自動的に再起動します。
                        """,
                    "state": "waiting_for_workers",
                    "reason": "subtasks_delegated_to_workers",
                    "in_progress_subtasks": inProgressSubTasks.map { [
                        "id": $0.id.value,
                        "title": $0.title,
                        "assignee_id": $0.assigneeId?.value ?? "unassigned"
                    ] as [String: Any] },
                    "progress": [
                        "completed": completedSubTasks.count,
                        "in_progress": inProgressSubTasks.count,
                        "total": subTasks.count
                    ]
                ]
            }

            // 未割り当てのサブタスクがある → Worker に委譲
            if let nextSubTask = pendingSubTasks.first {
                // 下位エージェント（Worker）を取得
                let subordinates = try agentRepository.findByParent(mainTask.assigneeId!)
                    .filter { $0.hierarchyType == .worker && $0.status == .active }

                return [
                    "action": "delegate",
                    "instruction": """
                        次のサブタスクを Worker に割り当ててください。
                        assign_task ツールを使用して、task_id と assignee_id を指定してください。
                        割り当て後、update_task_status でサブタスクのステータスを in_progress に変更してください。
                        その後、get_next_action を呼び出してください。
                        """,
                    "state": "needs_delegation",
                    "next_subtask": [
                        "id": nextSubTask.id.value,
                        "title": nextSubTask.title,
                        "description": nextSubTask.description
                    ],
                    "available_workers": subordinates.map { [
                        "id": $0.id.value,
                        "name": $0.name,
                        "role": $0.role,
                        "status": $0.status.rawValue
                    ] as [String: Any] },
                    "progress": [
                        "completed": completedSubTasks.count,
                        "total": subTasks.count
                    ]
                ]
            }
        }

        // サブタスク作成中フェーズ
        if phase == "workflow:creating_subtasks" {
            // サブタスク作成完了を記録
            // Note: Context.sessionId は sessions テーブルを参照するため、
            // 先に Session を作成してからその ID を使用する
            let workflowSession = Session(
                id: SessionID.generate(),
                projectId: mainTask.projectId,
                agentId: mainTask.assigneeId!,
                startedAt: Date(),
                status: .active
            )
            try sessionRepository.save(workflowSession)

            let context = Context(
                id: ContextID.generate(),
                taskId: mainTask.id,
                sessionId: workflowSession.id,
                agentId: mainTask.assigneeId!,
                progress: "workflow:subtasks_created"
            )
            try contextRepository.save(context)

            return [
                "action": "delegate",
                "instruction": """
                    サブタスクを Worker に割り当ててください。
                    割り当て後、get_next_action を呼び出してください。
                    """,
                "state": "needs_delegation",
                "subtasks": subTasks.map { [
                    "id": $0.id.value,
                    "title": $0.title
                ] as [String: Any] }
            ]
        }

        // フォールバック
        return [
            "action": "get_task",
            "instruction": "get_my_task を呼び出してタスク詳細を取得してください。",
            "state": "needs_task"
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
    /// ⚠️ Phase 5で非推奨: list_subordinates を使用
    private func listAgents() throws -> [[String: Any]] {
        let agents = try agentRepository.findAll()
        return agents.map { agentToDict($0) }
    }

    // MARK: - Phase 5: Manager-Only Tools

    /// list_subordinates - マネージャーの下位エージェント一覧を取得
    /// 参照: Sources/MCPServer/Authorization/ToolAuthorization.swift
    private func listSubordinates(managerId: String) throws -> [[String: Any]] {
        Self.log("[MCP] listSubordinates called for manager: '\(managerId)'")

        // マネージャーの下位エージェント（parentAgentId == managerId）を取得
        let allAgents = try agentRepository.findAll()
        let subordinates = allAgents.filter { $0.parentAgentId?.value == managerId }

        Self.log("[MCP] Found \(subordinates.count) subordinates for manager '\(managerId)'")

        return subordinates.map { agent in
            [
                "id": agent.id.value,
                "name": agent.name,
                "role": agent.role,
                "type": agent.type.rawValue,
                "hierarchy_type": agent.hierarchyType.rawValue,
                "status": agent.status.rawValue
            ]
        }
    }

    /// get_subordinate_profile - 下位エージェントの詳細情報を取得
    /// 参照: Sources/MCPServer/Authorization/ToolAuthorization.swift
    private func getSubordinateProfile(managerId: String, targetAgentId: String) throws -> [String: Any] {
        Self.log("[MCP] getSubordinateProfile called by manager: '\(managerId)' for target: '\(targetAgentId)'")

        let targetId = AgentID(value: targetAgentId)
        guard let agent = try agentRepository.findById(targetId) else {
            throw MCPError.agentNotFound(targetAgentId)
        }

        // 下位エージェントかどうかを検証
        guard agent.parentAgentId?.value == managerId else {
            throw MCPError.notSubordinate(managerId: managerId, targetId: targetAgentId)
        }

        Self.log("[MCP] Found subordinate: \(agent.name)")

        // 詳細情報（システムプロンプト含む）を返す
        return [
            "id": agent.id.value,
            "name": agent.name,
            "role": agent.role,
            "type": agent.type.rawValue,
            "hierarchy_type": agent.hierarchyType.rawValue,
            "status": agent.status.rawValue,
            "system_prompt": agent.systemPrompt ?? "",
            "parent_agent_id": agent.parentAgentId?.value ?? NSNull(),
            "ai_type": agent.aiType?.rawValue ?? NSNull(),
            "kick_method": agent.kickMethod.rawValue,
            "kick_command": agent.kickCommand ?? NSNull(),
            "max_parallel_tasks": agent.maxParallelTasks
        ]
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

    /// create_task - 新規タスク作成（サブタスク作成用）
    /// Agent Instanceがメインタスクをサブタスクに分解する際に使用
    private func createTask(
        agentId: AgentID,
        projectId: ProjectID,
        title: String,
        description: String,
        priority: String?,
        parentTaskId: String?,
        dependencies: [String]?
    ) throws -> [String: Any] {
        // 優先度のパース
        let taskPriority: TaskPriority
        if let priorityStr = priority, let parsed = TaskPriority(rawValue: priorityStr) {
            taskPriority = parsed
        } else {
            taskPriority = .medium
        }

        // 親タスクIDの検証
        var parentId: TaskID?
        if let parentTaskIdStr = parentTaskId {
            parentId = TaskID(value: parentTaskIdStr)
            guard try taskRepository.findById(parentId!) != nil else {
                throw MCPError.taskNotFound(parentTaskIdStr)
            }
        }

        // 依存タスクIDの検証
        var taskDependencies: [TaskID] = []
        if let deps = dependencies {
            for depId in deps {
                let depTaskId = TaskID(value: depId)
                guard try taskRepository.findById(depTaskId) != nil else {
                    throw MCPError.taskNotFound(depId)
                }
                taskDependencies.append(depTaskId)
            }
        }

        // 新しいタスクを作成
        let newTask = Task(
            id: TaskID.generate(),
            projectId: projectId,
            title: title,
            description: description,
            status: .todo,
            priority: taskPriority,
            assigneeId: agentId,
            dependencies: taskDependencies,
            parentTaskId: parentId
        )

        try taskRepository.save(newTask)

        let depsStr = taskDependencies.map { $0.value }.joined(separator: ", ")
        Self.log("[MCP] Task created: \(newTask.id.value) (parent: \(parentTaskId ?? "none"), dependencies: [\(depsStr)])")

        return [
            "success": true,
            "task": [
                "id": newTask.id.value,
                "title": newTask.title,
                "description": newTask.description,
                "status": newTask.status.rawValue,
                "priority": newTask.priority.rawValue,
                "assignee_id": agentId.value,
                "parent_task_id": parentTaskId as Any,
                "dependencies": taskDependencies.map { $0.value }
            ],
            "instruction": "サブタスクが作成されました。assign_taskで適切なワーカーに割り当ててください。"
        ]
    }

    /// assign_task - タスクを指定のエージェントに割り当て
    /// バリデーション:
    /// 1. 呼び出し元がマネージャーであること
    /// 2. 割り当て先が呼び出し元の下位エージェントであること（または割り当て解除）
    private func assignTask(taskId: String, assigneeId: String?, callingAgentId: String) throws -> [String: Any] {
        Self.log("[MCP] assignTask: taskId=\(taskId), assigneeId=\(assigneeId ?? "nil"), callingAgentId=\(callingAgentId)")

        // 呼び出し元エージェントを取得
        guard let callingAgent = try agentRepository.findById(AgentID(value: callingAgentId)) else {
            throw MCPError.agentNotFound(callingAgentId)
        }

        // バリデーション1: 呼び出し元がマネージャーであること
        guard callingAgent.hierarchyType == .manager else {
            throw MCPError.permissionDenied("assign_task can only be called by manager agents")
        }

        // タスクを取得
        guard var task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        let previousAssigneeId = task.assigneeId?.value

        // 割り当て解除の場合
        if assigneeId == nil {
            task.assigneeId = nil
            task.updatedAt = Date()
            try taskRepository.save(task)

            Self.log("[MCP] assignTask: unassigned task \(taskId)")
            return [
                "success": true,
                "message": "タスクの割り当てを解除しました",
                "task_id": taskId,
                "previous_assignee_id": previousAssigneeId as Any
            ]
        }

        // 割り当て先エージェントを取得
        guard let assignee = try agentRepository.findById(AgentID(value: assigneeId!)) else {
            throw MCPError.agentNotFound(assigneeId!)
        }

        // バリデーション2: 割り当て先が呼び出し元の下位エージェントであること
        guard assignee.parentAgentId == callingAgent.id else {
            throw MCPError.permissionDenied("Can only assign tasks to subordinate agents (agents with parentAgentId = \(callingAgentId))")
        }

        // タスクを更新
        task.assigneeId = AgentID(value: assigneeId!)
        task.updatedAt = Date()
        try taskRepository.save(task)

        Self.log("[MCP] assignTask: assigned task \(taskId) to \(assigneeId!)")
        return [
            "success": true,
            "message": "タスクを \(assignee.name) に割り当てました",
            "task_id": taskId,
            "assignee_id": assigneeId!,
            "assignee_name": assignee.name,
            "previous_assignee_id": previousAssigneeId as Any
        ]
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

    // MARK: - Phase 4: Coordinator API（認証不要）

    /// register_execution_log_file - 実行ログにログファイルパスを登録
    /// Coordinatorがプロセス完了後にログファイルパスを登録する際に使用
    /// 認証不要: Coordinatorは認証せずに直接呼び出す
    private func registerExecutionLogFile(agentId: String, taskId: String, logFilePath: String) throws -> [String: Any] {
        Self.log("[MCP] registerExecutionLogFile called: agentId='\(agentId)', taskId='\(taskId)', logFilePath='\(logFilePath)'")

        let agId = AgentID(value: agentId)
        let tId = TaskID(value: taskId)

        // 最新の実行ログを取得
        guard var log = try executionLogRepository.findLatestByAgentAndTask(agentId: agId, taskId: tId) else {
            Self.log("[MCP] No execution log found for agent '\(agentId)' and task '\(taskId)'")
            return [
                "success": false,
                "error": "execution_log_not_found"
            ]
        }

        // ログファイルパスを設定して保存
        log.setLogFilePath(logFilePath)
        try executionLogRepository.save(log)

        Self.log("[MCP] ExecutionLog updated with log file path: \(log.id.value)")

        return [
            "success": true,
            "execution_log_id": log.id.value,
            "task_id": log.taskId.value,
            "agent_id": log.agentId.value,
            "log_file_path": logFilePath
        ]
    }

    /// セッションを無効化（Coordinator用）
    /// エージェントプロセス終了時に呼び出され、shouldStartが再度trueを返せるようにする
    private func invalidateSession(agentId: String, projectId: String) throws -> [String: Any] {
        Self.log("[MCP] invalidateSession called: agentId='\(agentId)', projectId='\(projectId)'")

        let agId = AgentID(value: agentId)
        let projId = ProjectID(value: projectId)

        // 該当する全セッションを取得して削除
        let sessions = try agentSessionRepository.findByAgentIdAndProjectId(agId, projectId: projId)
        var deletedCount = 0

        for session in sessions {
            try agentSessionRepository.delete(session.id)
            deletedCount += 1
            Self.log("[MCP] Deleted session: \(session.id.value)")
        }

        Self.log("[MCP] invalidateSession completed: deleted \(deletedCount) session(s)")

        return [
            "success": true,
            "agent_id": agentId,
            "project_id": projectId,
            "deleted_count": deletedCount
        ]
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
    case taskAccessDenied(String)  // Phase 4: タスクアクセス権限なし
    case permissionDenied(String)  // Phase 4: 権限エラー（マネージャー専用ツール等）
    case invalidCoordinatorToken  // Phase 5: Coordinatorトークン無効
    case notSubordinate(managerId: String, targetId: String)  // Phase 5: 下位エージェントではない

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
        case .taskAccessDenied(let taskId):
            return "Access denied: You don't have permission to modify task '\(taskId)'. Only the assignee or parent task assignee can modify this task."
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        case .invalidCoordinatorToken:
            return "Invalid coordinator token. Set MCP_COORDINATOR_TOKEN environment variable."
        case .notSubordinate(let managerId, let targetId):
            return "Agent '\(targetId)' is not a subordinate of manager '\(managerId)'"
        }
    }
}
