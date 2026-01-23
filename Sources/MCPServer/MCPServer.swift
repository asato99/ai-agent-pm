// Sources/MCPServer/MCPServer.swift
// 参照: docs/architecture/MCP_SERVER.md - MCPサーバー設計
// 参照: docs/prd/MCP_DESIGN.md - MCP Tool/Resource/Prompt設計

import Foundation
import Domain
import Infrastructure
import GRDB  // Explicit import for DatabaseQueue type
import UseCase

/// MCPサーバーのメイン実装（ステートレス設計）
/// 参照: docs/architecture/MCP_SERVER.md - ステートレス設計
///
/// IDはサーバー起動時ではなく、各ツール呼び出し時に引数として受け取る。
/// キック時にプロンプトでID情報を提供し、LLM（Claude Code）が橋渡しする。
public final class MCPServer {
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

    // Chat機能: チャットリポジトリと起動理由リポジトリ
    private let chatRepository: ChatFileRepository
    private let pendingAgentPurposeRepository: PendingAgentPurposeRepository

    // AI-to-AI会話リポジトリ（UC016）
    private let conversationRepository: ConversationRepository

    // アプリ設定リポジトリ（TTL設定など）
    private let appSettingsRepository: AppSettingsRepository

    // Phase 2.3: マルチデバイス対応 - ワーキングディレクトリリポジトリ
    // 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.3
    private let agentWorkingDirectoryRepository: AgentWorkingDirectoryRepository

    // 通知リポジトリ
    // 参照: docs/design/NOTIFICATION_SYSTEM.md
    private let notificationRepository: NotificationRepository

    private let debugMode: Bool

    /// ステートレス設計: DBパスのみで初期化（stdio用）
    convenience init(database: DatabaseQueue) {
        self.init(database: database, transport: StdioTransport())
    }

    /// HTTP Transport用ファクトリメソッド
    /// REST API経由でMCPを呼び出す際に使用
    /// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ1.2
    ///
    /// - Parameter databasePath: データベースファイルへのパス
    /// - Returns: HTTP用に構成されたMCPServerインスタンス
    /// - Throws: データベース作成に失敗した場合
    public static func createForHTTPTransport(databasePath: String) throws -> MCPServer {
        let database = try DatabaseSetup.createDatabase(at: databasePath)
        return MCPServer(database: database, transport: NullTransport())
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
        // Chat機能: チャットリポジトリと起動理由リポジトリ
        let directoryManager = ProjectDirectoryManager()
        self.chatRepository = ChatFileRepository(
            directoryManager: directoryManager,
            projectRepository: self.projectRepository
        )
        self.pendingAgentPurposeRepository = PendingAgentPurposeRepository(database: database)
        // AI-to-AI会話リポジトリ
        self.conversationRepository = ConversationRepository(database: database)
        // アプリ設定リポジトリ
        self.appSettingsRepository = AppSettingsRepository(database: database)
        // Phase 2.3: ワーキングディレクトリリポジトリ
        self.agentWorkingDirectoryRepository = AgentWorkingDirectoryRepository(database: database)
        // 通知リポジトリ
        self.notificationRepository = NotificationRepository(database: database)
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

    // MARK: - HTTP Transport

    /// HTTP経由でJSON-RPCリクエストを処理
    /// REST API の /mcp エンドポイントから呼び出される
    /// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ1.2
    ///
    /// - Parameter request: JSON-RPCリクエスト
    /// - Returns: JSON-RPCレスポンス（通知の場合もレスポンスを返す）
    public func processHTTPRequest(_ request: JSONRPCRequest) -> JSONRPCResponse {
        logDebug("[HTTP] Processing request: \(request.method)")

        // handleRequestを呼び出し、nilの場合は空のレスポンスを返す
        if let response = handleRequest(request) {
            return response
        }

        // 通知（id == nil）の場合は成功レスポンスを返す
        return JSONRPCResponse(id: request.id, result: ["acknowledged": true])
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

            // 通知ミドルウェア: 認証済みエージェントに未読通知の有無を通知
            // 参照: docs/design/NOTIFICATION_SYSTEM.md
            var responseContent: [String: Any] = [
                "content": [
                    ["type": "text", "text": formatResult(result)]
                ]
            ]
            if let (agentId, projectId) = extractAgentAndProject(from: caller) {
                // 未読通知を取得して種類を確認
                let unreadNotifications = (try? notificationRepository.findUnreadByAgentAndProject(
                    agentId: agentId,
                    projectId: projectId
                )) ?? []

                // 中断通知がある場合は、ツールの戻り値を完全に通知メッセージに差し替える
                // これによりエージェントは通知に対応せざるを得なくなる
                if let interruptNotification = unreadNotifications.first(where: { $0.type == .interrupt }) {
                    let interruptMessage = """
                        通知があります。

                        1. get_notifications() を呼び出して詳細を確認してください
                        2. 通知の指示に従ってください
                        """
                    // 戻り値を完全に差し替え
                    responseContent = [
                        "content": [
                            ["type": "text", "text": interruptMessage]
                        ]
                    ]
                } else if !unreadNotifications.isEmpty {
                    responseContent["notification"] = "【重要】通知があります。get_notifications を呼び出して確認してください。"
                } else {
                    responseContent["notification"] = "通知はありません"
                }
            }

            return JSONRPCResponse(id: request.id, result: responseContent)
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
            // DBを優先、環境変数をフォールバック
            var expectedToken: String?
            if let settings = try? appSettingsRepository.get() {
                expectedToken = settings.coordinatorToken
            }
            if expectedToken == nil || expectedToken?.isEmpty == true {
                expectedToken = ProcessInfo.processInfo.environment["MCP_COORDINATOR_TOKEN"]
            }

            if let expected = expectedToken, !expected.isEmpty, coordinatorToken == expected {
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

    /// 認証済みの呼び出し元からエージェントIDとプロジェクトIDを抽出
    /// 通知ミドルウェア用ヘルパー
    private func extractAgentAndProject(from caller: CallerType) -> (AgentID, ProjectID)? {
        guard let agentId = caller.agentId,
              let session = caller.session else {
            return nil
        }
        return (agentId, session.projectId)
    }

    /// Toolを実行
    /// ステートレス設計: 必要なIDは全て引数として受け取る
    /// Phase 5: caller で認可済みの呼び出し元情報を受け取る
    /// Note: internal for @testable access in tests
    func executeTool(name: String, arguments: [String: Any], caller: CallerType) throws -> Any {
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

        case "help":
            let toolName = arguments["tool_name"] as? String
            return executeHelp(caller: caller, toolName: toolName)

        // ========================================
        // Coordinator専用
        // ========================================
        case "health_check":
            return try healthCheck()

        case "list_managed_agents":
            return try listManagedAgents()

        case "list_active_projects_with_agents":
            // Phase 2.3: オプションのagent_idパラメータをサポート
            // Multi-device: root_agent_id も agent_id として受け付ける
            let agentId = arguments["agent_id"] as? String ?? arguments["root_agent_id"] as? String
            return try listActiveProjectsWithAgents(agentId: agentId)

        case "get_agent_action":
            guard let agentId = arguments["agent_id"] as? String,
                  let projectId = arguments["project_id"] as? String else {
                throw MCPError.missingArguments(["agent_id", "project_id"])
            }
            return try getAgentAction(agentId: agentId, projectId: projectId)

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

        case "report_agent_error":
            guard let agentId = arguments["agent_id"] as? String,
                  let projectId = arguments["project_id"] as? String,
                  let errorMessage = arguments["error_message"] as? String else {
                throw MCPError.missingArguments(["agent_id", "project_id", "error_message"])
            }
            return try reportAgentError(agentId: agentId, projectId: projectId, errorMessage: errorMessage)

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

        case "create_tasks_batch":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let parentTaskId = arguments["parent_task_id"] as? String,
                  let tasks = arguments["tasks"] as? [[String: Any]] else {
                throw MCPError.missingArguments(["parent_task_id", "tasks"])
            }
            return try createTasksBatch(
                agentId: session.agentId,
                projectId: session.projectId,
                parentTaskId: parentTaskId,
                tasks: tasks
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
            return try getMyTask(session: session)

        case "get_notifications":
            // 通知取得ツール: エージェントの未読通知を取得
            // 参照: docs/design/NOTIFICATION_SYSTEM.md
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            let markAsRead = (arguments["mark_as_read"] as? Bool) ?? true
            return try getNotifications(
                agentId: session.agentId,
                projectId: session.projectId,
                markAsRead: markAsRead
            )

        case "get_next_action":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            return try getNextAction(session: session)

        case "logout":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            return try logout(session: session)

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
        // チャット機能（認証済み）
        // 参照: docs/design/CHAT_FEATURE.md
        // ========================================
        case "get_pending_messages":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            return try getPendingMessages(session: session)

        case "respond_chat":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let content = arguments["content"] as? String else {
                throw MCPError.missingArguments(["content"])
            }
            let targetAgentId = arguments["target_agent_id"] as? String
            return try respondChat(session: session, content: content, targetAgentId: targetAgentId)

        case "send_message":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let targetAgentId = arguments["target_agent_id"] as? String else {
                throw MCPError.missingArguments(["target_agent_id"])
            }
            guard let content = arguments["content"] as? String else {
                throw MCPError.missingArguments(["content"])
            }
            let relatedTaskId = arguments["related_task_id"] as? String
            let conversationId = arguments["conversation_id"] as? String
            return try sendMessage(
                session: session,
                targetAgentId: targetAgentId,
                content: content,
                relatedTaskId: relatedTaskId,
                conversationId: conversationId
            )

        // ========================================
        // AI-to-AI会話機能
        // 参照: docs/design/AI_TO_AI_CONVERSATION.md
        // ========================================
        case "start_conversation":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let participantAgentId = arguments["participant_agent_id"] as? String else {
                throw MCPError.missingArguments(["participant_agent_id"])
            }
            guard let initialMessage = arguments["initial_message"] as? String else {
                throw MCPError.missingArguments(["initial_message"])
            }
            guard let maxTurns = arguments["max_turns"] as? Int else {
                throw MCPError.missingArguments(["max_turns"])
            }
            let purpose = arguments["purpose"] as? String
            return try startConversation(
                session: session,
                participantAgentId: participantAgentId,
                purpose: purpose,
                initialMessage: initialMessage,
                maxTurns: maxTurns
            )

        case "end_conversation":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let conversationId = arguments["conversation_id"] as? String else {
                throw MCPError.missingArguments(["conversation_id"])
            }
            let finalMessage = arguments["final_message"] as? String
            return try endConversation(
                session: session,
                conversationId: conversationId,
                finalMessage: finalMessage
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

    /// get_agent_action - エージェントが取るべきアクションを返す
    /// Runnerはタスクの詳細を知らない。action と reason を返す。
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// 参照: docs/plan/MULTI_AGENT_USE_CASES.md - AIタイプ
    /// Phase 4: (agent_id, project_id)単位で判断
    /// action: "start" - エージェントを起動すべき
    ///         "hold" - 起動不要（現状維持）
    ///         "stop" - 停止すべき（将来用）
    ///         "restart" - 再起動すべき（将来用）
    private func getAgentAction(agentId: String, projectId: String) throws -> [String: Any] {
        Self.log("[MCP] getAgentAction called for agent: '\(agentId)', project: '\(projectId)'")

        let id = AgentID(value: agentId)
        let projId = ProjectID(value: projectId)

        // エージェントの存在確認
        guard let agent = try agentRepository.findById(id) else {
            Self.log("[MCP] shouldStart: Agent '\(agentId)' not found")
            throw MCPError.agentNotFound(agentId)
        }

        // プロジェクトの存在確認
        guard let project = try projectRepository.findById(projId) else {
            Self.log("[MCP] shouldStart: Project '\(projectId)' not found")
            throw MCPError.projectNotFound(projectId)
        }

        // Feature 14: プロジェクト一時停止チェック
        // pausedプロジェクトではタスク処理を停止（チャット・管理操作は継続）
        if project.status == .paused {
            Self.log("[MCP] getAgentAction for '\(agentId)/\(projectId)': hold (project is paused)")
            return [
                "action": "hold",
                "reason": "project_paused"
            ]
        }

        // エージェントがプロジェクトに割り当てられているか確認
        let isAssigned = try projectAgentAssignmentRepository.isAgentAssignedToProject(
            agentId: id,
            projectId: projId
        )
        if !isAssigned {
            Self.log("[MCP] getAgentAction: Agent '\(agentId)' is not assigned to project '\(projectId)'")
            return [
                "action": "hold",
                "reason": "agent_not_assigned"
            ]
        }

        // UC008: ブロックされたタスクをチェック
        // 該当プロジェクトで該当エージェントにアサインされたblockedタスクがあれば停止
        // ただし、自己ブロック（または下位ワーカーによるブロック）の場合は continue 可能
        // ユーザー（UI）によるブロックは解除不可として stop
        // 参照: docs/plan/BLOCKED_TASK_RECOVERY.md
        let tasks = try taskRepository.findByAssignee(id)

        // in_progressタスクがある場合はblockedタスクの起動チェックをスキップ
        // 複数タスクが割り当てられている場合、実行中タスクを優先
        let hasAnyInProgressTask = tasks.contains { $0.status == .inProgress && $0.projectId == projId }

        // blockedタスクをチェック（in_progressタスクがない場合のみ）
        // blockedタスクがあるだけでは起動しない（holdを返す）
        // in_progressタスクがある場合のみ、そのタスクのために起動する
        let blockedTask = tasks.first { task in
            task.status == .blocked && task.projectId == projId
        }
        if let blocked = blockedTask, !hasAnyInProgressTask {
            // blockedタスクがあるがin_progressタスクがない場合は起動しない
            // マネージャーが下位ワーカーのblocked状態を検知して対処する
            Self.log("[MCP] getAgentAction for '\(agentId)/\(projectId)': hold (blocked task '\(blocked.id.value)' exists but no in_progress task)")
            return [
                "action": "hold",
                "reason": "blocked_without_in_progress",
                "task_id": blocked.id.value,
                "provider": agent.provider ?? "claude",
                "model": agent.modelId ?? "claude-sonnet-4-5-20250929"
            ]
        }

        // Phase 4: (agent_id, project_id)単位でアクティブセッションをチェック
        let allSessions = try agentSessionRepository.findByAgentIdAndProjectId(id, projectId: projId)
        let activeSessions = allSessions.filter { $0.expiresAt > Date() }
        if !activeSessions.isEmpty {
            Self.log("[MCP] getAgentAction for '\(agentId)/\(projectId)': hold (already running - active session exists)")
            return [
                "action": "hold",
                "reason": "already_running"
            ]
        }

        // Debug: log all tasks found for this agent with full details
        Self.log("[MCP] getAgentAction: Agent '\(agentId)' checking for in_progress tasks in project '\(projectId)'")
        Self.log("[MCP] getAgentAction: Found \(tasks.count) total assigned task(s)")
        for task in tasks {
            let matchesProject = task.projectId == projId
            let isInProgress = task.status == .inProgress
            Self.log("[MCP] getAgentAction:   - Task '\(task.id.value)': status=\(task.status.rawValue), projectId=\(task.projectId.value), matchesProject=\(matchesProject), isInProgress=\(isInProgress)")
        }

        let inProgressTask = tasks.first { task in
            task.status == .inProgress && task.projectId == projId
        }
        let hasInProgressTask = inProgressTask != nil

        Self.log("[MCP] getAgentAction for '\(agentId)/\(projectId)': hasInProgressTask=\(hasInProgressTask) (in_progress task: \(inProgressTask?.id.value ?? "none"))")

        // Manager の待機状態チェック
        // Context.progress に基づいて起動/待機を判断
        if agent.hierarchyType == .manager, let task = inProgressTask {
            let latestContext = try contextRepository.findLatest(taskId: task.id)
            let progress = latestContext?.progress

            // worker_blocked: ワーカーがブロックされた → 即座に起動して対処
            if progress == "workflow:worker_blocked" {
                Self.log("[MCP] getAgentAction: Manager has worker_blocked state, starting immediately to handle")
                return [
                    "action": "start",
                    "reason": "worker_blocked",
                    "task_id": task.id.value,
                    "provider": agent.provider ?? "claude",
                    "model": agent.modelId ?? "claude-sonnet-4-5-20250929"
                ]
            }

            // handled_blocked: ブロック対処済み、進行中ワーカーなし → 再起動しない
            if progress == "workflow:handled_blocked" {
                Self.log("[MCP] getAgentAction: Manager has handled_blocked state, holding (no restart)")
                return [
                    "action": "hold",
                    "reason": "handled_blocked"
                ]
            }

            // waiting_for_workers: ワーカー完了待ち
            if progress == "workflow:waiting_for_workers" {
                Self.log("[MCP] getAgentAction: Manager is in waiting_for_workers state, checking subtasks")

                // サブタスクの状態を動的に確認
                let allTasks = try taskRepository.findByProject(projId, status: nil)
                let subTasks = allTasks.filter { $0.parentTaskId == task.id }
                let inProgressSubTasks = subTasks.filter { $0.status == .inProgress }
                let completedSubTasks = subTasks.filter { $0.status == .done }

                Self.log("[MCP] getAgentAction: subtasks=\(subTasks.count), inProgress=\(inProgressSubTasks.count), completed=\(completedSubTasks.count)")

                // まだ Worker が実行中 → 起動しない
                if !inProgressSubTasks.isEmpty {
                    Self.log("[MCP] getAgentAction: Manager should hold (waiting for \(inProgressSubTasks.count) workers)")
                    return [
                        "action": "hold",
                        "reason": "waiting_for_workers",
                        "progress": [
                            "completed": completedSubTasks.count,
                            "in_progress": inProgressSubTasks.count,
                            "total": subTasks.count
                        ]
                    ]
                }

                // 全サブタスク完了 → 起動して report_completion
                Self.log("[MCP] getAgentAction: All subtasks completed, Manager should start for report_completion")
            }
        }

        // Chat機能: pending_agent_purposesをチェック
        // チャットメッセージが送信された場合、purpose=chatでエージェントを起動する
        Self.log("[MCP] getAgentAction: Checking pending_agent_purposes for '\(agentId)/\(projectId)'")

        // DEBUG: Dump all pending purposes in database to diagnose visibility issues
        do {
            let rows = try pendingAgentPurposeRepository.dumpAllForDebug()
            Self.log("[MCP] DEBUG: All pending_agent_purposes rows: \(rows)")
        } catch {
            Self.log("[MCP] DEBUG: Failed to dump pending_agent_purposes: \(error)")
        }

        let pendingPurpose = try pendingAgentPurposeRepository.find(agentId: id, projectId: projId)
        var hasPendingPurpose = false
        var pendingPurposeExpired = false

        // AppSettingsから設定可能なTTLを取得（デフォルト: 300秒 = 5分）
        let configuredTTL: TimeInterval
        do {
            let settings = try appSettingsRepository.get()
            configuredTTL = TimeInterval(settings.pendingPurposeTTLSeconds)
            Self.log("[MCP] getAgentAction: Using configured TTL: \(Int(configuredTTL))s")
        } catch {
            configuredTTL = TimeInterval(AppSettings.defaultPendingPurposeTTLSeconds)
            Self.log("[MCP] getAgentAction: Failed to load TTL setting, using default: \(Int(configuredTTL))s")
        }

        if let pending = pendingPurpose {
            let now = Date()

            // 起動済みチェック（started_atがあれば既に起動済み）
            // 起動済みの場合はTTLチェックをスキップ（起動後のタイムアウトは別途検討）
            if pending.startedAt != nil {
                Self.log("[MCP] getAgentAction for '\(agentId)/\(projectId)': pending purpose already STARTED at \(pending.startedAt!), returning hold")
                hasPendingPurpose = false  // 起動済みなのでstartは返さない
            }
            // 未起動の場合: TTLチェック（設定された時間経過でタイムアウト）
            else if pending.isExpired(now: now, ttlSeconds: configuredTTL) {
                Self.log("[MCP] getAgentAction for '\(agentId)/\(projectId)': pending purpose EXPIRED (created: \(pending.createdAt), TTL: \(Int(configuredTTL))s)")
                // 期限切れのpending purposeを削除
                try pendingAgentPurposeRepository.delete(agentId: id, projectId: projId)
                pendingPurposeExpired = true
            }
            // 未起動でTTL内 → startを返し、started_atを更新
            else {
                Self.log("[MCP] getAgentAction for '\(agentId)/\(projectId)': pending purpose exists, marking as started")
                hasPendingPurpose = true
                // started_atを更新（次回以降はholdを返す）
                try pendingAgentPurposeRepository.markAsStarted(agentId: id, projectId: projId, startedAt: now)
            }
        }

        Self.log("[MCP] getAgentAction for '\(agentId)/\(projectId)': hasPendingPurpose=\(hasPendingPurpose), expired=\(pendingPurposeExpired)")

        // TTL超過時はチャットにエラーメッセージを書き込み、holdを返す
        if pendingPurposeExpired {
            let ttlMinutes = Int(configuredTTL) / 60
            // チャットにシステムエラーメッセージを書き込む
            // System messages use a special "system" senderId, no dual write needed
            let errorMessage = ChatMessage(
                id: ChatMessageID(value: "sys_\(UUID().uuidString)"),
                senderId: AgentID(value: "system"),
                receiverId: nil,  // System messages don't have a specific receiver
                content: "エージェントの起動がタイムアウトしました（\(ttlMinutes)分経過）。再度メッセージを送信してください。",
                createdAt: Date()
            )
            do {
                // System messages are saved only to the agent's storage (no dual write)
                try chatRepository.saveMessage(errorMessage, projectId: projId, agentId: id)
                Self.log("[MCP] getAgentAction: Wrote timeout error message to chat")
            } catch {
                Self.log("[MCP] getAgentAction: Failed to write timeout error to chat: \(error)")
            }

            return [
                "action": "hold",
                "reason": "no_pending_work"
            ]
        }

        // action と reason を設定（pending purposeがあれば起動）
        let shouldStart = hasInProgressTask || hasPendingPurpose
        let action = shouldStart ? "start" : "hold"
        let reason: String
        if hasInProgressTask {
            reason = "has_in_progress_task"
        } else if hasPendingPurpose {
            reason = "has_pending_purpose"
        } else {
            reason = "no_in_progress_task"
        }

        var result: [String: Any] = [
            "action": action,
            "reason": reason
        ]

        // task_id を返す（Coordinatorがログファイルパスを登録するため）
        if let task = inProgressTask {
            result["task_id"] = task.id.value
        }

        // provider/model を返す（RunnerがCLIコマンドを選択するため）
        // v29: 直接保存された値を使用（Enumパースに依存しない）
        Self.log("[MCP] getAgentAction: agent '\(agentId)' - provider='\(agent.provider ?? "nil")', modelId='\(agent.modelId ?? "nil")', aiType='\(agent.aiType?.rawValue ?? "nil")'")
        if let provider = agent.provider {
            result["provider"] = provider              // "claude", "gemini", "openai"
        } else {
            result["provider"] = "claude"              // デフォルト
        }
        if let modelId = agent.modelId {
            result["model"] = modelId                  // "gemini-2.5-pro", "claude-opus-4-20250514", etc.
        } else {
            result["model"] = "claude-sonnet-4-5-20250929"  // デフォルト（正しいモデルID）
        }
        Self.log("[MCP] getAgentAction: returning provider='\(result["provider"] ?? "nil")', model='\(result["model"] ?? "nil")'")

        return result
    }

    // MARK: Phase 4: Agent API

    /// get_my_task - 認証済みエージェントの現在のタスクを取得
    /// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    /// Phase 4: projectId でフィルタリング（同一エージェントが複数プロジェクトで同時稼働可能）
    private func getMyTask(session: AgentSession) throws -> [String: Any] {
        let agentId = session.agentId.value
        let projectId = session.projectId.value
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

            // Note: working_directoryはコーディネーターが管理するため、
            // get_my_taskでは返さない（エージェントの混乱を防ぐ）

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

            if let ctx = latestContext {
                taskDict["context"] = contextToDict(ctx)
            }

            if let handoff = latestHandoff {
                taskDict["handoff"] = handoffToDict(handoff)
            }

            // Phase 4: 実行ログを自動作成（report_execution_startの代替）
            var executionLog = ExecutionLog(
                taskId: task.id,
                agentId: id,
                startedAt: Date()
            )

            // セッションに既に model info がある場合は ExecutionLog にコピー
            // （report_model が get_my_task より先に呼ばれた場合）
            if session.modelVerified != nil {
                executionLog.setModelInfo(
                    provider: session.reportedProvider ?? "",
                    model: session.reportedModel ?? "",
                    verified: session.modelVerified ?? false
                )
                Self.log("[MCP] ExecutionLog: Copying model info from session")
            }

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

    /// get_notifications - エージェントの未読通知を取得
    /// 参照: docs/design/NOTIFICATION_SYSTEM.md
    private func getNotifications(
        agentId: AgentID,
        projectId: ProjectID,
        markAsRead: Bool
    ) throws -> [String: Any] {
        Self.log("[MCP] getNotifications called for agent: '\(agentId.value)', project: '\(projectId.value)', markAsRead: \(markAsRead)")

        let useCase = GetNotificationsUseCase(notificationRepository: notificationRepository)
        let notifications = try useCase.execute(
            agentId: agentId,
            projectId: projectId,
            markAsRead: markAsRead
        )

        let notificationDicts: [[String: Any]] = notifications.map { notification in
            var dict: [String: Any] = [
                "id": notification.id.value,
                "type": notification.type.rawValue,
                "action": notification.action,
                "message": notification.message,
                "instruction": notification.instruction,
                "created_at": ISO8601DateFormatter().string(from: notification.createdAt)
            ]
            if let taskId = notification.taskId {
                dict["task_id"] = taskId.value
            }
            return dict
        }

        return [
            "success": true,
            "count": notifications.count,
            "notifications": notificationDicts
        ]
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
        Self.log("[MCP] reportCompleted: Fetching assigned tasks...")

        let id = AgentID(value: agentId)
        let projId = ProjectID(value: projectId)

        // Phase 4: in_progress 状態のタスクを該当プロジェクトでフィルタリング
        let allAssignedTasks = try taskRepository.findByAssignee(id)
        Self.log("[MCP] reportCompleted: Found \(allAssignedTasks.count) assigned tasks for agent '\(agentId)'")
        for t in allAssignedTasks {
            Self.log("[MCP] reportCompleted:   - \(t.id.value) status=\(t.status.rawValue) project=\(t.projectId.value) parent=\(t.parentTaskId?.value ?? "nil")")
        }
        let inProgressTasks = allAssignedTasks.filter { $0.status == .inProgress && $0.projectId == projId }
        Self.log("[MCP] reportCompleted: Found \(inProgressTasks.count) in_progress tasks in project '\(projectId)'")

        // UC010: result='blocked' で呼び出され、タスクが既に blocked なら成功
        // これは、ユーザーがUIでステータスを変更し、エージェントが通知を受けて完了報告する場合
        // 参照: docs/design/NOTIFICATION_SYSTEM.md
        if result == "blocked" {
            let blockedTasks = allAssignedTasks.filter { $0.status == .blocked && $0.projectId == projId }
            if let blockedTask = blockedTasks.first {
                Self.log("[MCP] reportCompleted: Task already blocked (UC010 interrupt flow). Task: \(blockedTask.id.value)")

                // 重要: 早期リターンの前に実行ログを完了させる
                // これをスキップすると、Coordinatorが実行中のログを検出してタスクが終了しない
                let runningLogs = try executionLogRepository.findRunning(agentId: id)
                Self.log("[MCP] reportCompleted (blocked early exit): Completing \(runningLogs.count) running execution logs")
                for var executionLog in runningLogs {
                    let duration = Date().timeIntervalSince(executionLog.startedAt)
                    executionLog.complete(
                        exitCode: 1,  // blocked = error exit
                        durationSeconds: duration,
                        logFilePath: nil,
                        errorMessage: "Task was blocked by user"
                    )
                    try executionLogRepository.save(executionLog)
                    Self.log("[MCP] ExecutionLog completed (blocked): \(executionLog.id.value)")
                }

                return [
                    "success": true,
                    "task_id": blockedTask.id.value,
                    "status": "blocked",
                    "message": "タスクは既に中断されています。作業を終了してください。",
                    "instruction": "logout を呼び出してセッションを終了してください。"
                ]
            }
        }

        guard var task = inProgressTasks.first else {
            Self.log("[MCP] reportCompleted: No in_progress task for agent '\(agentId)' in project '\(projectId)'")
            return [
                "success": false,
                "error": "No in_progress task found for this agent"
            ]
        }

        // Worker（parentTaskId != nil）の場合、すべてのin_progressタスクを完了させる
        // これはManagerが複数のサブタスクを同じWorkerに割り当てた場合に対応
        let additionalInProgressTasks = inProgressTasks.dropFirst()

        // Workerに割り当てられた未着手（todo）タスクも収集（後で完了させる）
        let pendingTodoTasks = allAssignedTasks.filter { $0.status == .todo && $0.projectId == projId && $0.parentTaskId != nil }

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
        // Bug fix: statusChangedByAgentIdとstatusChangedAtを設定
        // これにより、誰がステータスを変更したかを追跡可能にする
        task.statusChangedByAgentId = id
        task.statusChangedAt = Date()
        if newStatus == .done {
            task.completedAt = Date()
        }

        try taskRepository.save(task)

        // ワーカーがブロック報告した場合、親タスク（マネージャー）のコンテキストを更新
        // マネージャーが waiting_for_workers 状態の場合のみ更新
        if newStatus == .blocked, let parentTaskId = task.parentTaskId {
            if let parentTask = try taskRepository.findById(parentTaskId),
               let parentAssigneeId = parentTask.assigneeId {
                // 親タスクの最新コンテキストを確認
                let parentLatestContext = try contextRepository.findLatest(taskId: parentTaskId)
                if parentLatestContext?.progress == "workflow:waiting_for_workers" {
                    // 親タスク（マネージャー）のアクティブセッションを検索
                    if let parentSession = try sessionRepository.findActiveByAgentAndProject(
                        agentId: parentAssigneeId,
                        projectId: projId
                    ).first {
                        // 親タスクのコンテキストを worker_blocked に更新
                        let parentContext = Context(
                            id: ContextID.generate(),
                            taskId: parentTaskId,
                            sessionId: parentSession.id,
                            agentId: parentAssigneeId,
                            progress: "workflow:worker_blocked",
                            findings: nil,
                            blockers: "Subtask \(task.id.value) blocked: \(summary ?? "no reason")",
                            nextSteps: nil
                        )
                        try contextRepository.save(parentContext)
                        Self.log("[MCP] reportCompleted: Updated parent task context to worker_blocked for manager '\(parentAssigneeId.value)'")
                    } else {
                        Self.log("[MCP] reportCompleted: No active session for parent task manager, skipping context update")
                    }
                } else {
                    Self.log("[MCP] reportCompleted: Parent task not in waiting_for_workers state, skipping context update")
                }
            }
        }

        // コンテキストを保存（サマリーや次のステップがあれば）
        // Bug fix: 有効なワークフローセッションを検索してそのIDを使用
        // SessionID.generate()は外部キー制約違反を引き起こすため使用しない
        if summary != nil || nextSteps != nil {
            if let activeSession = try sessionRepository.findActiveByAgentAndProject(
                agentId: id,
                projectId: projId
            ).first {
                let context = Context(
                    id: ContextID.generate(),
                    taskId: task.id,
                    sessionId: activeSession.id,
                    agentId: id,
                    progress: summary,
                    findings: nil,
                    blockers: result == "blocked" ? summary : nil,
                    nextSteps: nextSteps
                )
                try contextRepository.save(context)
            } else {
                Self.log("[MCP] reportCompleted: Skipped context creation - no active workflow session")
            }
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
        // AgentSession（認証トークン）を削除
        try agentSessionRepository.deleteByToken(sessionToken)
        Self.log("[MCP] reportCompleted: AgentSession invalidated for agent '\(agentId)'")

        // ワークフローSession（作業セッション）も終了
        let sessionStatus: SessionStatus = (result == "success") ? .completed : .abandoned
        let endSessionsUseCase = EndActiveSessionsUseCase(sessionRepository: sessionRepository)
        let endedSessionCount = try endSessionsUseCase.execute(
            agentId: id,
            projectId: projId,
            status: sessionStatus
        )
        Self.log("[MCP] reportCompleted: \(endedSessionCount) workflow session(s) ended for agent '\(agentId)'")

        // Phase 4: 実行ログを完了（report_execution_completeの代替）
        // エージェントの running 状態の実行ログを取得して完了状態に更新
        // Note: findLatestByAgentAndTask(taskId: task.id) は使えない
        //       task.id はワーカーが作成したサブサブタスクの可能性があり、
        //       そのタスクには実行ログがない（実行ログは start_task で作成されるため）
        // Bug fix: 全ての running 状態の実行ログを完了させる
        // 同じエージェントが複数回 start_task を呼び出すと、複数の running ログが存在する可能性がある
        let runningLogs = try executionLogRepository.findRunning(agentId: id)
        Self.log("[MCP] reportCompleted: Found \(runningLogs.count) running execution logs for agent '\(agentId)'")
        for var executionLog in runningLogs {
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

        // 追加のin_progressタスクも完了させる（Managerが複数タスクを割り当てた場合）
        Self.log("[MCP] reportCompleted: Processing \(additionalInProgressTasks.count) additional in_progress tasks")
        for var additionalTask in additionalInProgressTasks {
            Self.log("[MCP] reportCompleted: Checking additional task \(additionalTask.id.value) parentTaskId=\(additionalTask.parentTaskId?.value ?? "nil")")
            if additionalTask.parentTaskId != nil {  // Workerタスクのみ
                additionalTask.status = newStatus
                additionalTask.updatedAt = Date()
                additionalTask.statusChangedByAgentId = id
                additionalTask.statusChangedAt = Date()
                if newStatus == .done {
                    additionalTask.completedAt = Date()
                }
                try taskRepository.save(additionalTask)
                Self.log("[MCP] reportCompleted: Additional in_progress task \(additionalTask.id.value) also marked as \(newStatus.rawValue)")
            }
        }

        // 未着手（todo）タスクもすべて完了させる（Workerがセッション終了後に新タスクを受け取らないように）
        for var todoTask in pendingTodoTasks {
            todoTask.status = newStatus
            todoTask.updatedAt = Date()
            todoTask.statusChangedByAgentId = id
            todoTask.statusChangedAt = Date()
            if newStatus == .done {
                todoTask.completedAt = Date()
            }
            try taskRepository.save(todoTask)
            Self.log("[MCP] reportCompleted: Pending todo task \(todoTask.id.value) also marked as \(newStatus.rawValue)")
        }

        return [
            "success": true,
            "action": "exit",
            "instruction": "タスクが完了しました。プロセスを終了してください。"
        ]
    }

    // MARK: - Logout

    /// logout - セッション終了
    /// 認証済みエージェントがセッションを明示的に終了する
    /// チャット完了後など、get_next_actionから指示される
    private func logout(session: AgentSession) throws -> [String: Any] {
        let agentId = session.agentId
        let projectId = session.projectId
        Self.log("[MCP] logout called for agent: '\(agentId.value)', project: '\(projectId.value)'")

        // AgentSession を削除
        try agentSessionRepository.delete(session.id)
        Self.log("[MCP] logout: AgentSession deleted for agent: '\(agentId.value)', project: '\(projectId.value)'")

        // ワークフローSession（作業セッション）も終了（completed扱い）
        let endSessionsUseCase = EndActiveSessionsUseCase(sessionRepository: sessionRepository)
        let endedWorkflowSessionCount = try endSessionsUseCase.execute(
            agentId: agentId,
            projectId: projectId,
            status: .completed
        )
        Self.log("[MCP] logout: \(endedWorkflowSessionCount) workflow session(s) ended")

        return [
            "success": true,
            "message": "セッションを終了しました。",
            "instruction": "セッションが正常に終了しました。エージェントプロセスを終了してください。"
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

                    - provider: "claude", "gemini", "openai" などのプロバイダー名
                    - model_id: バージョンを含む完全なモデルID（例: "claude-sonnet-4-5-20250929", "gemini-2.5-pro", "gpt-4o"）

                    ※ model_id は省略形ではなく、使用中の正確なモデル名を申告してください。
                    申告後、get_next_action を再度呼び出してください。
                    """,
                "state": "needs_model_verification"
            ]
        }

        // 1.6. UC015: セッション終了チェック - terminating 状態なら exit を返す
        // 参照: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 6
        if session.state == .terminating {
            Self.log("[MCP] getNextAction: Session is terminating, returning exit action")
            return [
                "action": "exit",
                "instruction": """
                    ユーザーがチャットを閉じました。
                    logout を呼び出してセッションを終了してください。
                    """,
                "state": "session_terminating",
                "reason": "user_closed_chat"
            ]
        }

        // 1.7. Chat機能: purpose=chat の場合はチャット応答フローへ
        if session.purpose == .chat {
            // セッションタイムアウトチェック（10分）
            // lastActivityAt からの経過時間を使用（アイドル時間ベース）
            let idleTime = Date().timeIntervalSince(session.lastActivityAt)
            let softTimeoutSeconds = 10.0 * 60.0  // 10分

            if idleTime > softTimeoutSeconds {
                Self.log("[MCP] getNextAction: Chat session soft timeout reached (\(Int(idleTime))s idle)")
                return [
                    "action": "logout",
                    "instruction": """
                        セッションがタイムアウトしました（10分経過）。
                        logout を呼び出してセッションを終了してください。
                        """,
                    "state": "chat_timeout",
                    "reason": "session_timeout"
                ]
            }

            // 1.7.1. AI-to-AI会話チェック（UC016）
            // 参照: docs/design/AI_TO_AI_CONVERSATION.md - getNextAction拡張
            // pending会話の検出（相手からの会話要求）
            let pendingConversations = try conversationRepository.findPendingForParticipant(
                session.agentId,
                projectId: session.projectId
            )
            if let pendingConv = pendingConversations.first {
                // 会話をactiveに遷移
                try conversationRepository.updateState(pendingConv.id, state: .active)
                Self.log("[MCP] getNextAction: Accepted conversation request: \(pendingConv.id.value)")

                return [
                    "action": "conversation_request",
                    "instruction": """
                        AI-to-AI会話の要求を受信しました。
                        相手エージェントからの会話を受け入れ、get_pending_messages でメッセージを取得してください。
                        会話を終了する場合は end_conversation を呼び出してください。
                        """,
                    "state": "conversation_active",
                    "conversation_id": pendingConv.id.value,
                    "initiator_agent_id": pendingConv.initiatorAgentId.value,
                    "purpose": pendingConv.purpose ?? ""
                ]
            }

            // terminatingの会話をチェック（相手が終了を要求）
            let activeConversations = try conversationRepository.findActiveByAgentId(
                session.agentId,
                projectId: session.projectId
            )
            for conv in activeConversations {
                // 自分がparticipantで、会話がterminatingの場合
                if let terminatingConv = try conversationRepository.findById(conv.id),
                   terminatingConv.state == .terminating {
                    // 会話をendedに遷移
                    try conversationRepository.updateState(terminatingConv.id, state: .ended, endedAt: Date())
                    Self.log("[MCP] getNextAction: Conversation ended by partner: \(terminatingConv.id.value)")

                    return [
                        "action": "conversation_ended",
                        "instruction": """
                            AI-to-AI会話が終了しました。
                            相手エージェントが会話を終了しました。
                            未読メッセージがあれば処理し、get_next_action で次のアクションを確認してください。
                            """,
                        "state": "conversation_ended",
                        "conversation_id": terminatingConv.id.value,
                        "ended_by": terminatingConv.getPartnerId(for: session.agentId)?.value ?? ""
                    ]
                }
            }

            // 未読メッセージがあるか確認してからアクションを決定
            let pendingMessages = try chatRepository.findUnreadMessages(
                projectId: session.projectId,
                agentId: session.agentId
            )

            if pendingMessages.isEmpty {
                // 未読メッセージなし = 待機モードへ（セッション維持）
                // Note: 2秒間隔でポーリングして、5秒以内の応答を実現する
                let remainingMinutes = Int((softTimeoutSeconds - idleTime) / 60)
                Self.log("[MCP] getNextAction: Chat session with no pending messages, waiting for messages (remaining: \(remainingMinutes)min)")
                return [
                    "action": "wait_for_messages",
                    "instruction": """
                        現在処理待ちのメッセージがありません。
                        2秒後に再度 get_next_action を呼び出して新しいメッセージを確認してください。
                        他のAIエージェントと会話する場合は start_conversation で開始し、end_conversation で終了します。
                        その他の可能な操作は help ツールで確認できます。
                        """,
                    "state": "chat_waiting",
                    "wait_seconds": 2,
                    "remaining_timeout_minutes": remainingMinutes
                ]
            } else {
                Self.log("[MCP] getNextAction: Chat session detected with \(pendingMessages.count) pending message(s), directing to get_pending_messages")
                return [
                    "action": "get_pending_messages",
                    "instruction": """
                        チャットセッションです。
                        get_pending_messages を呼び出してユーザーからの未読メッセージを取得してください。
                        メッセージに対する応答は respond_chat で送信してください。
                        他のAIエージェントと会話する場合は start_conversation で開始し、end_conversation で終了します。
                        その他の可能な操作は help ツールで確認できます。
                        """,
                    "state": "chat_session"
                ]
            }
        }

        // 2. メインタスク（in_progress 状態）を取得
        // 階層タイプによって検索方法が異なる:
        // - Manager: トップレベルタスク（parentTaskId == nil）を所有
        // - Worker: 直接割り当てタスクまたは委任されたサブタスク（parentTaskId != nil の場合もある）
        let allTasks = try taskRepository.findByAssignee(agentId)
        let inProgressTasks = allTasks.filter { $0.status == .inProgress && $0.projectId == projectId }

        let mainTask: Task?
        switch agent.hierarchyType {
        case .manager:
            // Manager はトップレベルタスクを所有
            mainTask = inProgressTasks.first { $0.parentTaskId == nil }
        case .worker:
            // Worker は直接割り当てタスクまたは Manager から委任されたサブタスクを持つ
            // parentTaskId の有無は関係ない
            mainTask = inProgressTasks.first
        }

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
        let blockedSubTasks = subTasks.filter { $0.status == .blocked }

        Self.log("[MCP] getWorkerNextAction: subTasks=\(subTasks.count), pending=\(pendingSubTasks.count), inProgress=\(inProgressSubTasks.count), completed=\(completedSubTasks.count), blocked=\(blockedSubTasks.count)")

        // 委譲タスク判定: createdByAgentId != assigneeId → 他のエージェントから委譲されたタスク
        // 委譲タスクはサブタスクに分解できるが、自己作成タスクはさらに分解しない（無限ネスト防止）
        let isDelegatedTask: Bool
        if let createdBy = mainTask.createdByAgentId, let assignee = mainTask.assigneeId {
            isDelegatedTask = createdBy != assignee
        } else {
            // createdByAgentId が nil の場合は、既存データ（マイグレーション前）
            // 後方互換性のため parentTaskId == nil で判定
            isDelegatedTask = mainTask.parentTaskId == nil
        }
        Self.log("[MCP] getWorkerNextAction: isDelegatedTask=\(isDelegatedTask), createdBy=\(mainTask.createdByAgentId?.value ?? "nil"), assignee=\(mainTask.assigneeId?.value ?? "nil")")

        // 1. サブタスク未作成 → サブタスク作成フェーズへ
        // 委譲タスク（他のエージェントから割り当てられた）場合はサブタスク作成可能
        // 自己作成タスク（自分で作成した）場合は実際の作業を行うべき（無限ネスト防止）
        if phase == "workflow:task_fetched" && subTasks.isEmpty && isDelegatedTask {
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
                    create_tasks_batch ツールを使用して、一度に全てのサブタスクを作成してください。
                    parent_task_id には '\(mainTask.id.value)' を指定してください。
                    各タスクには local_id（例: "task_1", "generator"）を付けてください。
                    タスク間に順序関係がある場合（例: タスクBがタスクAの出力を使用する）、
                    後続タスクの dependencies に先行タスクの local_id を指定してください。
                    システムが local_id を実際のタスクIDに自動変換します。
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

        // 1.5. 自己作成タスク（自分で作成した）で子タスクがない場合
        // → 実際の作業を行う（さらなる分解は不要、無限ネスト防止）
        if !isDelegatedTask && subTasks.isEmpty {
            return [
                "action": "work",
                "instruction": """
                    このタスクを直接実行してください。
                    タスクの内容に従って作業を行い、完了したら
                    update_task_status で status を 'done' に変更してください。
                    その後 get_next_action を呼び出してください。
                    """,
                "state": "execute_task",
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

            // 完了ゲート: blocked サブタスクがある場合の処理
            // 参照: docs/plan/BLOCKED_TASK_RECOVERY.md - Phase 1-5
            // 全サブタスクが完了済みまたはブロック状態で、未着手・進行中がない場合
            if !blockedSubTasks.isEmpty && pendingSubTasks.isEmpty && inProgressSubTasks.isEmpty {
                // ブロック種別ごとに分類
                var userBlockedTasks: [[String: Any]] = []
                var selfBlockedTasks: [[String: Any]] = []
                var otherBlockedTasks: [[String: Any]] = []

                for task in blockedSubTasks {
                    let taskInfo: [String: Any] = [
                        "id": task.id.value,
                        "title": task.title,
                        "blocked_reason": task.blockedReason ?? "理由未記載",
                        "blocked_by": task.statusChangedByAgentId?.value ?? "unknown"
                    ]

                    if let changedBy = task.statusChangedByAgentId {
                        if changedBy.isUserAction {
                            userBlockedTasks.append(taskInfo)
                        } else if changedBy == mainTask.assigneeId {
                            selfBlockedTasks.append(taskInfo)
                        } else {
                            otherBlockedTasks.append(taskInfo)
                        }
                    } else {
                        // nilは自己ブロック扱い（後方互換性）
                        selfBlockedTasks.append(taskInfo)
                    }
                }

                // Workerも全てのブロック状況を把握して対処を検討できる
                // 自己ブロック → 解除可能、ユーザー/他者ブロック → 解除不可だが上位への報告は必要
                return [
                    "action": "review_and_resolve_blocks",
                    "instruction": """
                        以下のサブタスクがブロック状態です。対処を検討してください。

                        【ブロック種別と対応】
                        ■ 自己ブロック（解除可能）:
                          - ブロック理由を確認してください
                          - 理由が解決済みなら update_task_status で 'in_progress' に変更して作業再開

                        ■ ユーザー/他者によるブロック（解除不可）:
                          - 解除する権限がありません
                          - メインタスクを blocked として報告し、上位（マネージャー）に委ねてください

                        【最終判断】
                        - 対処できない場合:
                          → メインタスク自体を blocked にして report_completed で報告
                          → result は 'blocked'、summary にブロック理由を記載
                        - 無理に続行せず、上位（マネージャー）に委ねてください
                        """,
                    "state": "needs_review",
                    "self_blocked_subtasks": selfBlockedTasks,
                    "user_blocked_subtasks": userBlockedTasks,
                    "other_blocked_subtasks": otherBlockedTasks,
                    "completed_subtasks": completedSubTasks.count,
                    "total_subtasks": subTasks.count,
                    "can_unblock_self": !selfBlockedTasks.isEmpty,
                    "has_unresolvable_blocks": !userBlockedTasks.isEmpty || !otherBlockedTasks.isEmpty
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

            // 次のサブタスクを開始（依存関係を考慮）
            // 依存タスクが全て完了しているサブタスクのみを実行可能とする
            let completedTaskIds = Set(completedSubTasks.map { $0.id })
            let executableSubTasks = pendingSubTasks.filter { task in
                // 依存関係がないか、全ての依存タスクが完了している
                task.dependencies.isEmpty || task.dependencies.allSatisfy { completedTaskIds.contains($0) }
            }

            Self.log("[MCP] getWorkerNextAction: executableSubTasks=\(executableSubTasks.count) (filtered from \(pendingSubTasks.count) pending)")

            if let nextSubTask = executableSubTasks.first {
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

            // 待機中のサブタスクはあるが、依存関係が満たされていない
            // → 循環依存または不正な依存関係の可能性
            if !pendingSubTasks.isEmpty {
                let waitingTasks = pendingSubTasks.map { task -> [String: Any] in
                    let unmetDeps = task.dependencies.filter { !completedTaskIds.contains($0) }
                    return [
                        "id": task.id.value,
                        "title": task.title,
                        "waiting_for": unmetDeps.map { $0.value }
                    ]
                }
                Self.log("[MCP] getWorkerNextAction: All pending subtasks have unmet dependencies")
                return [
                    "action": "dependency_deadlock",
                    "instruction": """
                        全ての待機中サブタスクに未完了の依存関係があります。
                        循環依存または不正な依存関係の可能性があります。

                        対処方法:
                        1. 依存関係を確認し、不要な依存を削除する
                        2. または、このタスク全体を blocked として報告し、
                           report_completed で result='blocked' を指定してください。
                        """,
                    "state": "dependency_deadlock",
                    "waiting_subtasks": waitingTasks,
                    "completed_subtasks": completedSubTasks.count,
                    "total_subtasks": subTasks.count
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
        // Note: allTasksはマネージャーに割り当てられたタスクのみ（findByAssignee）なので、
        // ワーカーに割り当てられたサブタスクは含まれない。
        // プロジェクト全体からサブタスクを検索する必要がある。
        let projectTasks = try taskRepository.findByProject(mainTask.projectId, status: nil)
        let subTasks = projectTasks.filter { $0.parentTaskId == mainTask.id }
        let pendingSubTasks = subTasks.filter { $0.status == .todo || $0.status == .backlog }
        let inProgressSubTasks = subTasks.filter { $0.status == .inProgress }
        let completedSubTasks = subTasks.filter { $0.status == .done }
        let blockedSubTasks = subTasks.filter { $0.status == .blocked }

        // 未割り当てサブタスク: assigneeが未設定(nil)、またはマネージャーに割り当てられたままの pending タスク
        // これらはまずワーカーへの割り当て（assignee変更）が必要
        let unassignedSubTasks = pendingSubTasks.filter { $0.assigneeId == nil || $0.assigneeId == mainTask.assigneeId }

        // ワーカー割り当て済みサブタスク: ワーカーに割り当て済みの pending タスク
        // 注意: assigneeIdがnilの場合は「ワーカー割り当て済み」ではない
        let workerAssignedSubTasks = pendingSubTasks.filter { $0.assigneeId != nil && $0.assigneeId != mainTask.assigneeId }

        // 実行可能サブタスク: ワーカー割り当て済み かつ 依存関係がクリアされたタスク
        // これらは in_progress に変更可能
        let executableSubTasks = workerAssignedSubTasks.filter { task in
            // 依存タスクがない場合は実行可能
            if task.dependencies.isEmpty {
                return true
            }
            // 全ての依存タスクがdoneの場合のみ実行可能
            return task.dependencies.allSatisfy { depId in
                subTasks.first { $0.id == depId }?.status == .done
            }
        }

        Self.log("[MCP] getManagerNextAction: subTasks=\(subTasks.count), pending=\(pendingSubTasks.count), unassigned=\(unassignedSubTasks.count), workerAssigned=\(workerAssignedSubTasks.count), executable=\(executableSubTasks.count), inProgress=\(inProgressSubTasks.count), completed=\(completedSubTasks.count), blocked=\(blockedSubTasks.count)")

        // DEBUG: 各サブタスクの詳細をログ出力（バグ調査用）
        for task in subTasks {
            let depsStr = task.dependencies.map { $0.value }.joined(separator: ", ")
            let depsStatus = task.dependencies.map { depId -> String in
                if let depTask = subTasks.first(where: { $0.id == depId }) {
                    return "\(depId.value)=\(depTask.status.rawValue)"
                } else {
                    return "\(depId.value)=NOT_IN_SUBTASKS"
                }
            }.joined(separator: ", ")
            Self.log("[MCP] DEBUG subtask: id=\(task.id.value), status=\(task.status.rawValue), assignee=\(task.assigneeId?.value ?? "nil"), deps=[\(depsStr)], depsStatus=[\(depsStatus)]")
        }

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
                    create_tasks_batch ツールを使用して、一度に全てのサブタスクを作成してください。
                    parent_task_id には '\(mainTask.id.value)' を指定してください。
                    各タスクには local_id（例: "task_1", "generator"）を付けてください。
                    タスク間に順序関係がある場合（例: タスクBがタスクAの出力を使用する）、
                    後続タスクの dependencies に先行タスクの local_id を指定してください。
                    システムが local_id を実際のタスクIDに自動変換します。
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

            // 完了ゲート: blocked サブタスクがある場合の処理
            // 参照: docs/plan/BLOCKED_TASK_RECOVERY.md - Phase 1-5
            // 全サブタスクが完了済みまたはブロック状態で、未着手・進行中がない場合
            if !blockedSubTasks.isEmpty && pendingSubTasks.isEmpty && inProgressSubTasks.isEmpty {
                // ブロック種別ごとに分類
                var userBlockedTasks: [[String: Any]] = []
                var selfBlockedTasks: [[String: Any]] = []
                var otherBlockedTasks: [[String: Any]] = []

                for task in blockedSubTasks {
                    let taskInfo: [String: Any] = [
                        "id": task.id.value,
                        "title": task.title,
                        "blocked_reason": task.blockedReason ?? "理由未記載",
                        "blocked_by": task.statusChangedByAgentId?.value ?? "unknown"
                    ]

                    if let changedBy = task.statusChangedByAgentId {
                        if changedBy.isUserAction {
                            userBlockedTasks.append(taskInfo)
                        } else if changedBy == mainTask.assigneeId {
                            selfBlockedTasks.append(taskInfo)
                        } else {
                            // 下位ワーカーによるブロックも自己ブロック扱い
                            let subordinates = try agentRepository.findByParent(mainTask.assigneeId!)
                            if subordinates.contains(where: { $0.id == changedBy }) {
                                selfBlockedTasks.append(taskInfo)
                            } else {
                                otherBlockedTasks.append(taskInfo)
                            }
                        }
                    } else {
                        // nilは自己ブロック扱い（後方互換性）
                        selfBlockedTasks.append(taskInfo)
                    }
                }

                // 状態遷移: worker_blocked → handled_blocked
                // ブロック対処を返す際にコンテキストを更新して無限ループを防止
                let latestContext = try contextRepository.findLatest(taskId: mainTask.id)
                if latestContext?.progress == "workflow:worker_blocked" {
                    // worker_blocked から handled_blocked に遷移
                    // マネージャーが対処を試みた後、再起動されないようにする
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
                        progress: "workflow:handled_blocked",
                        blockers: "Handling blocked subtasks: \(blockedSubTasks.map { $0.id.value }.joined(separator: ", "))"
                    )
                    try contextRepository.save(context)
                    Self.log("[MCP] getManagerNextAction: Transitioned from worker_blocked to handled_blocked")
                }

                // Managerは全てのブロック状況を把握して対処を検討できる
                // 自己/下位ブロック → 解除可能、ユーザー/他者ブロック → 解除不可だが自主判断で対処
                return [
                    "action": "review_and_resolve_blocks",
                    "instruction": """
                        以下のサブタスクがブロック状態です。マネージャーとして自主的に対処を検討してください。

                        【ブロック種別と対応】
                        ■ 自己/下位ワーカーによるブロック（解除可能）:
                          - ブロック理由を確認してください
                          - 理由が解決済みなら update_task_status で 'todo' に変更
                          - assign_task でワーカーに再割り当て

                        ■ ユーザーによるブロック:
                          - ユーザーが意図的にブロックしたタスクです
                          - 直接解除する権限はありませんが、以下の対処を自主的に検討してください:
                            1. 別のワーカーへの再アサイン（assign_task）
                            2. タスクの分割・再設計（新しいサブタスクを作成）
                            3. 代替アプローチの検討
                            4. ブロック理由に基づく問題解決
                          - 対処不可能と判断した場合のみ、メインタスクをブロックとして報告

                        【最終判断】
                        - 自主的な対処を試みた上で、それでも完了できない場合:
                          → メインタスク自体を blocked にして report_completed で報告
                          → result は 'blocked'、summary に試みた対処と残る問題を記載
                        - すぐに諦めず、まず対処を試みてください
                        """,
                    "state": "needs_review",
                    "self_blocked_subtasks": selfBlockedTasks,
                    "user_blocked_subtasks": userBlockedTasks,
                    "other_blocked_subtasks": otherBlockedTasks,
                    "completed_subtasks": completedSubTasks.count,
                    "total_subtasks": subTasks.count,
                    "can_unblock_self": !selfBlockedTasks.isEmpty,
                    "has_unresolvable_blocks": !userBlockedTasks.isEmpty || !otherBlockedTasks.isEmpty
                ]
            }

            // Phase 1: 未割り当てタスクをワーカーに割り当て（assignee変更のみ）
            // 全てのサブタスクがワーカーに割り当てられるまで繰り返す
            if !unassignedSubTasks.isEmpty {
                // 下位エージェント（Worker）を取得
                let subordinates = try agentRepository.findByParent(mainTask.assigneeId!)
                    .filter { $0.hierarchyType == .worker && $0.status == .active }

                // 利用可能な Worker がいない場合、タスクを blocked 状態にする
                if subordinates.isEmpty {
                    Self.log("[MCP] No available workers, blocking subtask")
                    let firstSubTask = unassignedSubTasks[0]
                    return [
                        "action": "block_subtask",
                        "instruction": """
                            利用可能な Worker がいません。
                            update_task_status を使用して、サブタスク '\(firstSubTask.id.value)' のステータスを
                            'blocked' に変更し、blocked_reason に '利用可能なWorkerがいません' と設定してください。
                            その後、logout を呼び出してセッションを終了してください。
                            """,
                        "state": "no_available_workers",
                        "subtask_to_block": [
                            "id": firstSubTask.id.value,
                            "title": firstSubTask.title
                        ],
                        "reason": "no_available_workers",
                        "progress": [
                            "completed": completedSubTasks.count,
                            "total": subTasks.count
                        ]
                    ]
                }

                // 次の1件を割り当て（assigneeの変更のみ、in_progressにはしない）
                let nextSubTask = unassignedSubTasks[0]
                Self.log("[MCP] Assigning task '\(nextSubTask.id.value)' to worker (unassigned: \(unassignedSubTasks.count), executable: \(executableSubTasks.count))")

                return [
                    "action": "assign",
                    "instruction": """
                        次のサブタスクを Worker に割り当ててください。
                        assign_task ツールを使用して、task_id と assignee_id を指定してください。
                        【重要】この段階では in_progress に変更しないでください。割り当てのみ行います。
                        割り当て後、get_next_action を呼び出してください。
                        """,
                    "state": "needs_assignment",
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
                        "unassigned": unassignedSubTasks.count,
                        "worker_assigned": workerAssignedSubTasks.count,
                        "executable": executableSubTasks.count,
                        "in_progress": inProgressSubTasks.count,
                        "total": subTasks.count
                    ]
                ]
            }

            // Phase 2: 実行可能タスクを in_progress に変更
            // 全て割り当て済みで、依存関係がクリアされたタスクがある場合
            if !executableSubTasks.isEmpty {
                let nextSubTask = executableSubTasks[0]
                Self.log("[MCP] Starting task '\(nextSubTask.id.value)' (executable: \(executableSubTasks.count), inProgress: \(inProgressSubTasks.count))")

                return [
                    "action": "start_task",
                    "instruction": """
                        次のサブタスクを実行開始してください。
                        update_task_status でサブタスクのステータスを in_progress に変更してください。
                        その後、get_next_action を呼び出してください。
                        """,
                    "state": "needs_start",
                    "next_subtask": [
                        "id": nextSubTask.id.value,
                        "title": nextSubTask.title,
                        "assignee_id": nextSubTask.assigneeId?.value ?? "unknown"
                    ],
                    "progress": [
                        "completed": completedSubTasks.count,
                        "executable": executableSubTasks.count,
                        "in_progress": inProgressSubTasks.count,
                        "total": subTasks.count
                    ]
                ]
            }

            // 実行状態に変更可能なタスクがない → exit
            // 待機状態を Context に記録
            let workflowSession = Session(
                id: SessionID.generate(),
                projectId: mainTask.projectId,
                agentId: mainTask.assigneeId!,
                startedAt: Date(),
                status: .active
            )
            try sessionRepository.save(workflowSession)

            let waitingState = !inProgressSubTasks.isEmpty ? "workflow:waiting_for_workers" : "workflow:waiting_for_dependencies"
            let context = Context(
                id: ContextID.generate(),
                taskId: mainTask.id,
                sessionId: workflowSession.id,
                agentId: mainTask.assigneeId!,
                progress: waitingState
            )
            try contextRepository.save(context)

            if !inProgressSubTasks.isEmpty {
                Self.log("[MCP] No more assignable tasks, waiting for workers (inProgress: \(inProgressSubTasks.count), pending: \(pendingSubTasks.count))")
                return [
                    "action": "exit",
                    "instruction": """
                        現在実行状態に変更可能なサブタスクがありません。
                        Worker の完了を待つため、ここでプロセスを終了してください。
                        Coordinator が Worker 完了後に自動的に再起動します。
                        """,
                    "state": "waiting_for_workers",
                    "reason": "no_assignable_tasks",
                    "in_progress_subtasks": inProgressSubTasks.map { [
                        "id": $0.id.value,
                        "title": $0.title,
                        "assignee_id": $0.assigneeId?.value ?? "unassigned"
                    ] as [String: Any] },
                    "progress": [
                        "completed": completedSubTasks.count,
                        "in_progress": inProgressSubTasks.count,
                        "worker_assigned_waiting": workerAssignedSubTasks.count,
                        "total": subTasks.count
                    ]
                ]
            } else {
                Self.log("[MCP] No executable tasks due to unmet dependencies (workerAssigned: \(workerAssignedSubTasks.count))")
                let pendingWithDeps = pendingSubTasks.map { task -> [String: Any] in
                    let unmetDeps = task.dependencies.filter { depId in
                        subTasks.first { $0.id == depId }?.status != .done
                    }
                    return [
                        "id": task.id.value,
                        "title": task.title,
                        "unmet_dependencies": unmetDeps.map { $0.value }
                    ]
                }
                return [
                    "action": "exit",
                    "instruction": """
                        現在実行状態に変更可能なサブタスクがありません。
                        保留中のタスクは依存関係の完了を待っています。
                        Worker の完了後に自動的に再起動します。
                        """,
                    "state": "waiting_for_dependencies",
                    "reason": "dependencies_not_met",
                    "pending_tasks_with_dependencies": pendingWithDeps,
                    "progress": [
                        "completed": completedSubTasks.count,
                        "in_progress": 0,
                        "worker_assigned_waiting": workerAssignedSubTasks.count,
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

            // 下位エージェント（Worker）を取得
            let subordinates = try agentRepository.findByParent(mainTask.assigneeId!)
                .filter { $0.hierarchyType == .worker && $0.status == .active }

            // 利用可能な Worker がいない場合、タスクを blocked 状態にする
            if subordinates.isEmpty {
                Self.log("[MCP] No available workers after subtask creation, blocking subtasks")
                if let firstSubTask = unassignedSubTasks.first {
                    return [
                        "action": "block_subtask",
                        "instruction": """
                            利用可能な Worker がいません。
                            update_task_status を使用して、サブタスク '\(firstSubTask.id.value)' のステータスを
                            'blocked' に変更し、blocked_reason に '利用可能なWorkerがいません' と設定してください。
                            その後、logout を呼び出してセッションを終了してください。
                            """,
                        "state": "no_available_workers",
                        "subtask_to_block": [
                            "id": firstSubTask.id.value,
                            "title": firstSubTask.title
                        ],
                        "reason": "no_available_workers",
                        "subtasks": subTasks.map { [
                            "id": $0.id.value,
                            "title": $0.title
                        ] as [String: Any] }
                    ]
                }
            }

            // Phase 1: 未割り当てタスクをワーカーに割り当て（assignee変更のみ）
            if let nextSubTask = unassignedSubTasks.first {
                Self.log("[MCP] Assigning first task after subtask creation (unassigned: \(unassignedSubTasks.count))")
                return [
                    "action": "assign",
                    "instruction": """
                        サブタスクを Worker に割り当ててください。
                        assign_task ツールを使用して、task_id と assignee_id を指定してください。
                        【重要】この段階では in_progress に変更しないでください。割り当てのみ行います。
                        割り当て後、get_next_action を呼び出してください。
                        """,
                    "state": "needs_assignment",
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
                        "unassigned": unassignedSubTasks.count,
                        "total": subTasks.count
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
                "error": "Project not found",
                "action": "exit"  // 案A: 認証失敗時は即終了
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
                "error": "Agent not assigned to project",
                "action": "exit"  // 案A: 認証失敗時は即終了
            ]
        }

        // Phase 4: 二重起動防止 - (agent_id, project_id)単位でアクティブセッションがあればエラー
        let allSessions = try agentSessionRepository.findByAgentIdAndProjectId(id, projectId: projId)
        let activeSessions = allSessions.filter { $0.expiresAt > Date() }
        if !activeSessions.isEmpty {
            Self.log("[MCP] authenticate failed for agent: '\(agentId)' on project '\(projectId)' - Agent already running")
            return [
                "success": false,
                "error": "Agent already running on this project",
                "action": "exit"  // 案A: 認証失敗時は即終了
            ]
        }

        // AuthenticateUseCaseを使用して認証（Chat機能: pendingAgentPurposeRepository を渡す）
        let useCase = AuthenticateUseCase(
            credentialRepository: agentCredentialRepository,
            sessionRepository: agentSessionRepository,
            agentRepository: agentRepository,
            pendingPurposeRepository: pendingAgentPurposeRepository
        )

        let result = try useCase.execute(agentId: agentId, passkey: passkey, projectId: projectId)

        if result.success {
            Self.log("[MCP] Authentication successful for agent: \(result.agentName ?? agentId)")
            var response: [String: Any] = [
                "success": true,
                "session_token": result.sessionToken ?? "",
                "expires_in": result.expiresIn ?? 0,
                "agent_name": result.agentName ?? "",
                // Phase 4: 次のアクション指示（get_next_actionがchat/taskを判別）
                "instruction": "get_next_action を呼び出して次の指示を確認してください"
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
                "error": result.error ?? "Authentication failed",
                "action": "exit"  // 案A: 認証失敗時は即終了
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
    /// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.3
    /// Runnerがポーリング対象を決定するために使用
    /// - Parameter agentId: オプション。指定された場合、そのエージェントのAgentWorkingDirectoryを参照して
    ///                     プロジェクトごとのworking_directoryを解決（マルチデバイス対応）
    private func listActiveProjectsWithAgents(agentId: String? = nil) throws -> [String: Any] {
        // アクティブなプロジェクトのみ取得
        let allProjects = try projectRepository.findAll()
        let activeProjects = allProjects.filter { $0.status == .active }

        var projectsWithAgents: [[String: Any]] = []

        for project in activeProjects {
            // 各プロジェクトに割り当てられたエージェントを取得
            let agents = try projectAgentAssignmentRepository.findAgentsByProject(project.id)
            let agentIdsList = agents.map { $0.id.value }

            // Phase 2.3: working_directoryの解決
            // 優先順位: AgentWorkingDirectory > Project.workingDirectory
            var workingDirectory = project.workingDirectory ?? ""
            if let humanAgentIdStr = agentId {
                let humanAgentId = AgentID(value: humanAgentIdStr)
                if let agentWorkingDir = try agentWorkingDirectoryRepository.findByAgentAndProject(
                    agentId: humanAgentId,
                    projectId: project.id
                ) {
                    workingDirectory = agentWorkingDir.workingDirectory
                }
            }

            let projectEntry: [String: Any] = [
                "project_id": project.id.value,
                "project_name": project.name,
                "working_directory": workingDirectory,
                "agents": agentIdsList
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
    /// Note: working_directoryはコーディネーターが管理するため返さない
    private func getPendingTasks(agentId: String) throws -> [String: Any] {
        let useCase = GetPendingTasksUseCase(taskRepository: taskRepository)
        let tasks = try useCase.execute(agentId: AgentID(value: agentId))

        return [
            "success": true,
            "tasks": tasks.map { taskToDict($0) }
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

        // 作成者のエージェントを取得してhierarchyTypeを確認
        let creatorAgent = try agentRepository.findById(agentId)

        // assigneeId の決定:
        // - Manager: nil（assign_task で明示的に割り当てる必要がある）
        // - Worker: 自分自身（自己作成タスクは自分で実行する）
        // これにより、Workerが作成したサブタスクは自動的に自分にアサインされる
        let assigneeId: AgentID?
        if let agent = creatorAgent, agent.hierarchyType == .worker {
            assigneeId = agentId
            Self.log("[MCP] Worker creating task - auto-assigning to self")
        } else {
            assigneeId = nil
        }

        // 新しいタスクを作成
        // createdByAgentId: タスク作成者を記録（委譲タスク判別用）
        let newTask = Task(
            id: TaskID.generate(),
            projectId: projectId,
            title: title,
            description: description,
            status: .todo,
            priority: taskPriority,
            assigneeId: assigneeId,
            createdByAgentId: agentId,
            dependencies: taskDependencies,
            parentTaskId: parentId
        )

        try taskRepository.save(newTask)

        let depsStr = taskDependencies.map { $0.value }.joined(separator: ", ")
        Self.log("[MCP] Task created: \(newTask.id.value) (parent: \(parentTaskId ?? "none"), dependencies: [\(depsStr)], assignee: \(assigneeId?.value ?? "nil"))")

        // 作成者に応じた instruction を決定
        let instruction: String
        if assigneeId != nil {
            // Worker の場合: タスクは既に自分にアサインされている
            instruction = "サブタスクが作成され、あなたに自動的に割り当てられました。全てのサブタスク作成後、get_next_action を呼び出してください。"
        } else {
            // Manager の場合: assign_task で Worker に割り当てが必要
            instruction = "サブタスクが作成されました。assign_task で適切なワーカーに割り当て、update_task_status で in_progress に変更してください。未割り当てのままのタスクは実行されません。"
        }

        return [
            "success": true,
            "task": [
                "id": newTask.id.value,
                "title": newTask.title,
                "description": newTask.description,
                "status": newTask.status.rawValue,
                "priority": newTask.priority.rawValue,
                "assignee_id": assigneeId?.value as Any,
                "parent_task_id": parentTaskId as Any,
                "dependencies": taskDependencies.map { $0.value }
            ],
            "instruction": instruction
        ]
    }

    /// create_tasks_batch - 複数タスクを依存関係付きで一括作成
    /// ローカル参照ID（local_id）を使ってバッチ内でタスク間の依存関係を指定可能
    /// システムがlocal_idを実際のタスクIDに解決する
    private func createTasksBatch(
        agentId: AgentID,
        projectId: ProjectID,
        parentTaskId: String,
        tasks: [[String: Any]]
    ) throws -> [String: Any] {
        Self.log("[MCP] createTasksBatch: agentId=\(agentId.value), projectId=\(projectId.value), parentTaskId=\(parentTaskId), taskCount=\(tasks.count)")

        // 親タスクの検証
        let parentId = TaskID(value: parentTaskId)
        guard try taskRepository.findById(parentId) != nil else {
            throw MCPError.taskNotFound(parentTaskId)
        }

        // 作成者のエージェントを取得してhierarchyTypeを確認
        let creatorAgent = try agentRepository.findById(agentId)
        let isWorker = creatorAgent?.hierarchyType == .worker

        // assigneeIdの決定（Worker の場合は自分自身）
        let assigneeId: AgentID? = isWorker ? agentId : nil

        // Phase 1: 全タスクを作成し、local_id → real_id のマッピングを構築
        var localIdToRealId: [String: TaskID] = [:]
        var createdTasks: [(Task, [String])] = []  // (task, local_dependencies)

        for taskDef in tasks {
            guard let localId = taskDef["local_id"] as? String,
                  let title = taskDef["title"] as? String,
                  let description = taskDef["description"] as? String else {
                throw MCPError.validationError("Each task must have local_id, title, and description")
            }

            // 優先度のパース
            let taskPriority: TaskPriority
            if let priorityStr = taskDef["priority"] as? String,
               let parsed = TaskPriority(rawValue: priorityStr) {
                taskPriority = parsed
            } else {
                taskPriority = .medium
            }

            // ローカル依存関係を保存（後で解決する）
            let localDependencies = taskDef["dependencies"] as? [String] ?? []

            // タスクを作成（依存関係は後で設定）
            let newTask = Task(
                id: TaskID.generate(),
                projectId: projectId,
                title: title,
                description: description,
                status: .todo,
                priority: taskPriority,
                assigneeId: assigneeId,
                createdByAgentId: agentId,
                dependencies: [],  // 後で設定
                parentTaskId: parentId
            )

            localIdToRealId[localId] = newTask.id
            createdTasks.append((newTask, localDependencies))

            Self.log("[MCP] createTasksBatch: Created task local_id=\(localId) → real_id=\(newTask.id.value)")
        }

        // Phase 2: ローカル依存関係を実際のTaskIDに解決して保存
        var savedTasks: [[String: Any]] = []

        for (var task, localDependencies) in createdTasks {
            var resolvedDependencies: [TaskID] = []

            for localDep in localDependencies {
                guard let realId = localIdToRealId[localDep] else {
                    throw MCPError.validationError("Unknown dependency local_id: \(localDep)")
                }
                resolvedDependencies.append(realId)
            }

            // 依存関係を設定
            task.dependencies = resolvedDependencies

            // タスクを保存
            try taskRepository.save(task)

            let depsStr = resolvedDependencies.map { $0.value }.joined(separator: ", ")
            Self.log("[MCP] createTasksBatch: Saved task \(task.id.value) with dependencies: [\(depsStr)]")

            savedTasks.append([
                "id": task.id.value,
                "title": task.title,
                "description": task.description,
                "status": task.status.rawValue,
                "priority": task.priority.rawValue,
                "assignee_id": assigneeId?.value as Any,
                "dependencies": resolvedDependencies.map { $0.value }
            ])
        }

        // 作成者に応じた instruction を決定
        let instruction: String
        if isWorker {
            instruction = "\(tasks.count)個のサブタスクが作成され、あなたに自動的に割り当てられました。get_next_action を呼び出してください。"
        } else {
            instruction = "\(tasks.count)個のサブタスクが作成されました。assign_task で適切なワーカーに割り当ててください。"
        }

        return [
            "success": true,
            "tasks": savedTasks,
            "task_count": savedTasks.count,
            "local_id_to_real_id": localIdToRealId.mapValues { $0.value },
            "instruction": instruction
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

        // バリデーション3: 割り当て先がタスクのプロジェクトに属していること
        let isAssigneeInProject = try projectAgentAssignmentRepository.isAgentAssignedToProject(
            agentId: assignee.id,
            projectId: task.projectId
        )
        guard isAssigneeInProject else {
            throw MCPError.permissionDenied("Agent '\(assignee.name)' is not assigned to this project. Only project members can be assigned to tasks.")
        }

        // バリデーション4: 割り当て先がアクティブであること
        guard assignee.status == .active else {
            throw MCPError.permissionDenied("Agent '\(assignee.name)' is not active (status: \(assignee.status.rawValue)). Only active agents can be assigned to tasks.")
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
    /// UpdateTaskStatusUseCaseに委譲（カスケードブロック等のロジックを統一）
    /// 参照: docs/design/EXECUTION_LOG_DESIGN.md - タスク完了時の実行ログ更新
    private func updateTaskStatus(taskId: String, status: String, reason: String?) throws -> [String: Any] {
        guard let newStatus = TaskStatus(rawValue: status) else {
            throw MCPError.invalidStatus(status)
        }

        // UseCaseを使用してステータス更新（カスケードブロック含む）
        let useCase = UpdateTaskStatusUseCase(
            taskRepository: taskRepository,
            agentRepository: agentRepository,
            eventRepository: eventRepository
        )

        do {
            let result = try useCase.executeWithResult(
                taskId: TaskID(value: taskId),
                newStatus: newStatus,
                agentId: nil,
                sessionId: nil,
                reason: reason
            )

            logDebug("Task \(taskId) status changed: \(result.previousStatus.rawValue) -> \(result.task.status.rawValue)")

            // タスクが done に遷移した場合、対応する実行ログも完了させる
            // これにより、report_completed を呼ばずに update_task_status で完了した場合も
            // 実行ログが正しく完了状態になる
            if newStatus == .done, let assigneeId = result.task.assigneeId {
                if var executionLog = try executionLogRepository.findLatestByAgentAndTask(
                    agentId: assigneeId,
                    taskId: TaskID(value: taskId)
                ), executionLog.status == .running {
                    let duration = Date().timeIntervalSince(executionLog.startedAt)
                    executionLog.complete(
                        exitCode: 0,
                        durationSeconds: duration,
                        logFilePath: nil,
                        errorMessage: nil
                    )
                    try executionLogRepository.save(executionLog)
                    Self.log("[MCP] ExecutionLog auto-completed via update_task_status: \(executionLog.id.value)")
                }
            }

            return [
                "success": true,
                "task": [
                    "id": result.task.id.value,
                    "title": result.task.title,
                    "previous_status": result.previousStatus.rawValue,
                    "new_status": result.task.status.rawValue
                ]
            ]
        } catch UseCaseError.taskNotFound {
            throw MCPError.taskNotFound(taskId)
        } catch UseCaseError.invalidStatusTransition(let from, let to) {
            throw MCPError.invalidStatusTransition(from: from.rawValue, to: to.rawValue)
        } catch UseCaseError.validationFailed(let message) {
            throw MCPError.validationError(message)
        }
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

        Self.log("[MCP] invalidateSession completed: deleted \(deletedCount) AgentSession(s)")

        // ワークフローSession（作業セッション）も終了（abandoned扱い）
        let endSessionsUseCase = EndActiveSessionsUseCase(sessionRepository: sessionRepository)
        let endedWorkflowSessionCount = try endSessionsUseCase.execute(
            agentId: agId,
            projectId: projId,
            status: .abandoned
        )
        Self.log("[MCP] invalidateSession: \(endedWorkflowSessionCount) workflow session(s) ended")

        // AI-to-AI会話のクリーンアップ
        // どちらかのエージェントがセッションを抜けた時点で会話は成立しないため、自動終了する
        // 参照: docs/design/AI_TO_AI_CONVERSATION.md
        let endedConversationCount = try cleanupAgentConversations(agentId: agId, projectId: projId)

        return [
            "success": true,
            "agent_id": agentId,
            "project_id": projectId,
            "deleted_agent_sessions": deletedCount,
            "ended_workflow_sessions": endedWorkflowSessionCount,
            "ended_conversations": endedConversationCount
        ]
    }

    /// AI-to-AI会話のクリーンアップ
    /// エージェントがセッションを終了する際、参加中の会話を自動終了する
    /// - Returns: 終了した会話の数
    private func cleanupAgentConversations(agentId: AgentID, projectId: ProjectID) throws -> Int {
        // このエージェントが参加しているactive/terminating会話を取得
        let activeConversations = try conversationRepository.findActiveByAgentId(agentId, projectId: projectId)

        var endedCount = 0
        for conversation in activeConversations {
            // initiatorまたはparticipantとして参加している会話を終了
            try conversationRepository.updateState(
                conversation.id,
                state: .ended,
                endedAt: Date()
            )
            let role = conversation.initiatorAgentId == agentId ? "initiator" : "participant"
            Self.log("[MCP] Auto-ended conversation on session invalidation: \(conversation.id.value) (agent was \(role))")
            endedCount += 1
        }

        if endedCount > 0 {
            Self.log("[MCP] invalidateSession: \(endedCount) conversation(s) auto-ended")
        }

        return endedCount
    }

    /// エージェントエラーを報告（Coordinator用）
    /// エージェントプロセスがエラー終了した場合、チャットにエラーメッセージを表示する
    private func reportAgentError(agentId: String, projectId: String, errorMessage: String) throws -> [String: Any] {
        Self.log("[MCP] reportAgentError called: agentId='\(agentId)', projectId='\(projectId)', error='\(errorMessage)'")

        let agId = AgentID(value: agentId)
        let projId = ProjectID(value: projectId)

        // エラーメッセージをチャットに保存
        // System error messages use a special "system" senderId, no dual write needed
        let message = ChatMessage(
            id: ChatMessageID(value: "err_\(UUID().uuidString)"),
            senderId: AgentID(value: "system"),
            receiverId: nil,  // System messages don't have a specific receiver
            content: "⚠️ エージェントエラー:\n\(errorMessage)",
            createdAt: Date()
        )

        // System messages are saved only to the agent's storage (no dual write)
        try chatRepository.saveMessage(message, projectId: projId, agentId: agId)
        Self.log("[MCP] Error message saved to chat: \(message.id.value)")

        return [
            "success": true,
            "agent_id": agentId,
            "project_id": projectId,
            "message_id": message.id.value
        ]
    }

    // MARK: - Chat Tools
    // 参照: docs/design/CHAT_FEATURE.md

    /// get_pending_messages - 未読チャットメッセージを取得
    /// チャット目的で起動されたエージェントが呼び出す
    /// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 3
    ///
    /// 返り値:
    /// - context_messages: 文脈理解用の直近メッセージ（最大20件）
    /// - pending_messages: 応答対象の未読メッセージ（最大10件）
    /// - total_history_count: 全履歴の件数
    /// - context_truncated: コンテキストが切り詰められたかどうか
    private func getPendingMessages(session: AgentSession) throws -> [String: Any] {
        Self.log("[MCP] getPendingMessages called: agentId='\(session.agentId.value)', projectId='\(session.projectId.value)'")

        // 全メッセージを取得
        let allMessages = try chatRepository.findMessages(
            projectId: session.projectId,
            agentId: session.agentId
        )

        Self.log("[MCP] Found \(allMessages.count) total message(s)")

        // PendingMessageIdentifier を使用してコンテキストと未読を分離
        let result = PendingMessageIdentifier.separateContextAndPending(
            allMessages,
            agentId: session.agentId,
            contextLimit: PendingMessageIdentifier.defaultContextLimit,  // 20
            pendingLimit: PendingMessageIdentifier.defaultPendingLimit   // 10
        )

        Self.log("[MCP] Context: \(result.contextMessages.count), Pending: \(result.pendingMessages.count), Truncated: \(result.contextTruncated)")

        // ISO8601フォーマッタを共有
        let formatter = ISO8601DateFormatter()

        // コンテキストメッセージを辞書に変換
        let contextDicts = result.contextMessages.map { message -> [String: Any] in
            var dict: [String: Any] = [
                "id": message.id.value,
                "sender_id": message.senderId.value,
                "content": message.content,
                "created_at": formatter.string(from: message.createdAt)
            ]
            if let receiverId = message.receiverId {
                dict["receiver_id"] = receiverId.value
            }
            return dict
        }

        // 未読メッセージを辞書に変換
        let pendingDicts = result.pendingMessages.map { message -> [String: Any] in
            var dict: [String: Any] = [
                "id": message.id.value,
                "sender_id": message.senderId.value,
                "content": message.content,
                "created_at": formatter.string(from: message.createdAt)
            ]
            if let receiverId = message.receiverId {
                dict["receiver_id"] = receiverId.value
            }
            return dict
        }

        // 指示文を生成
        let instruction: String
        if result.pendingMessages.isEmpty {
            instruction = "未読メッセージはありません。get_next_action を呼び出して次のアクションを確認してください。"
        } else {
            instruction = """
            上記の pending_messages に応答してください。
            context_messages は会話の文脈理解用です（応答対象ではありません）。
            respond_chat ツールを使用して応答を保存してください。
            """
        }

        return [
            "success": true,
            "context_messages": contextDicts,
            "pending_messages": pendingDicts,
            "total_history_count": result.totalHistoryCount,
            "context_truncated": result.contextTruncated,
            "instruction": instruction
        ]
    }

    /// respond_chat - チャット応答を保存
    /// エージェントがユーザーメッセージに対する応答を保存する
    /// Dual write: saves to both agent's and receiver's storage
    /// - Parameters:
    ///   - targetAgentId: 送信先エージェントID（省略時は最新未読メッセージの送信者に返信）
    ///                    UC013のようなリレーシナリオでは、明示的に人間を指定する
    private func respondChat(session: AgentSession, content: String, targetAgentId: String? = nil) throws -> [String: Any] {
        Self.log("[MCP] respondChat called: agentId='\(session.agentId.value)', content length=\(content.count), targetAgentId='\(targetAgentId ?? "auto")'")

        // Determine receiver
        let receiverId: AgentID?
        if let explicitTarget = targetAgentId {
            // 明示的な送信先が指定された場合（リレーシナリオなど）
            // 送信先エージェントの存在確認
            guard let _ = try agentRepository.findById(AgentID(value: explicitTarget)) else {
                throw MCPError.agentNotFound(explicitTarget)
            }
            // 同一プロジェクト内のエージェントか確認
            let isTargetInProject = try projectAgentAssignmentRepository.isAgentAssignedToProject(
                agentId: AgentID(value: explicitTarget),
                projectId: session.projectId
            )
            guard isTargetInProject else {
                throw MCPError.targetAgentNotInProject(targetAgentId: explicitTarget, projectId: session.projectId.value)
            }
            receiverId = AgentID(value: explicitTarget)
            Self.log("[MCP] respondChat: Using explicit target agent: \(explicitTarget)")
        } else {
            // 送信先が未指定の場合は最新未読メッセージの送信者に返信
            let unreadMessages = try chatRepository.findUnreadMessages(
                projectId: session.projectId,
                agentId: session.agentId
            )
            receiverId = unreadMessages.last?.senderId
            Self.log("[MCP] respondChat: Auto-detected receiver from unread messages: \(receiverId?.value ?? "none")")
        }

        // conversationIdの解決
        // receiverIdがAIエージェントの場合、アクティブな会話があれば自動設定
        // 参照: docs/design/AI_TO_AI_CONVERSATION.md
        var resolvedConversationId: ConversationID? = nil
        if let receiverAgentId = receiverId {
            // 受信者がAIエージェントか確認
            if let receiverAgent = try agentRepository.findById(receiverAgentId),
               receiverAgent.type == .ai {
                // 送信者と受信者間のアクティブな会話を検索
                let activeConversations = try conversationRepository.findActiveByAgentId(
                    session.agentId,
                    projectId: session.projectId
                )
                // 両者が参加している会話を探す
                if let activeConv = activeConversations.first(where: {
                    $0.getPartnerId(for: session.agentId)?.value == receiverAgentId.value
                }) {
                    resolvedConversationId = activeConv.id
                    Self.log("[MCP] respondChat: Auto-resolved conversation_id from active: \(activeConv.id.value)")
                }
            }
        }

        // エージェント応答メッセージを作成
        let message = ChatMessage(
            id: ChatMessageID.generate(),
            senderId: session.agentId,
            receiverId: receiverId,
            content: content,
            createdAt: Date(),
            conversationId: resolvedConversationId
        )

        // メッセージを保存 (dual write if receiver is known)
        if let receiverAgentId = receiverId {
            try chatRepository.saveMessageDualWrite(
                message,
                projectId: session.projectId,
                senderAgentId: session.agentId,
                receiverAgentId: receiverAgentId
            )
            Self.log("[MCP] Chat response saved with dual write: \(message.id.value) → \(receiverAgentId.value)")
        } else {
            // No receiver known, save only to agent's own storage
            try chatRepository.saveMessage(message, projectId: session.projectId, agentId: session.agentId)
            Self.log("[MCP] Chat response saved (no receiver): \(message.id.value)")
        }

        // セッションの lastActivityAt を更新（チャットタイムアウトのリセット）
        try agentSessionRepository.updateLastActivity(token: session.token)
        Self.log("[MCP] respondChat: Updated lastActivityAt for session: \(session.token.prefix(8))...")

        var result: [String: Any] = [
            "success": true,
            "message_id": message.id.value,
            "receiver_id": receiverId?.value as Any,
            "instruction": "応答を保存しました。get_next_action を呼び出して次の指示を確認してください。"
        ]

        // 会話内メッセージ数をカウント
        // 参照: docs/design/AI_TO_AI_CONVERSATION.md
        if let convId = resolvedConversationId {
            result["conversation_id"] = convId.value
            let allMessages = try chatRepository.findMessages(projectId: session.projectId, agentId: session.agentId)
            let conversationMessageCount = allMessages.filter { $0.conversationId == convId }.count

            // 会話を取得してmax_turnsをチェック
            if let conversation = try conversationRepository.findById(convId) {
                result["current_turns"] = conversationMessageCount
                result["max_turns"] = conversation.maxTurns

                // ターン数上限に達した場合、会話を自動終了
                if conversationMessageCount >= conversation.maxTurns {
                    try conversationRepository.updateState(convId, state: .ended, endedAt: Date())
                    result["conversation_ended"] = true
                    result["warning"] = "【会話終了】最大ターン数（\(conversation.maxTurns)）に達したため会話を自動終了しました。必要であれば新しい会話を開始してください。"
                    Self.log("[MCP] respondChat: Conversation auto-ended due to max_turns limit: \(conversationMessageCount)/\(conversation.maxTurns)")
                } else if conversationMessageCount > 0 && conversationMessageCount % 5 == 0 {
                    // 5件ごとにリマインド
                    result["reminder"] = "【確認】会話の目的は達成されましたか？達成された場合は end_conversation で会話を終了してください。（\(conversationMessageCount)/\(conversation.maxTurns)ターン）"
                    Self.log("[MCP] respondChat: Conversation reminder added at message count: \(conversationMessageCount)/\(conversation.maxTurns)")
                }
            }
        }

        return result
    }

    /// send_message - プロジェクト内の他のエージェントにメッセージを送信
    /// タスクセッション・チャットセッションの両方で使用可能（.authenticated権限）
    /// 参照: docs/design/SEND_MESSAGE_FROM_TASK_SESSION.md
    /// 参照: docs/design/AI_TO_AI_CONVERSATION.md - conversationId自動設定
    private func sendMessage(
        session: AgentSession,
        targetAgentId: String,
        content: String,
        relatedTaskId: String?,
        conversationId: String? = nil
    ) throws -> [String: Any] {
        Self.log("[MCP] sendMessage called: from='\(session.agentId.value)' to='\(targetAgentId)' content_length=\(content.count)")

        // 1. コンテンツ長チェック（最大4,000文字）
        guard content.count <= 4000 else {
            throw MCPError.contentTooLong(maxLength: 4000, actual: content.count)
        }

        // 2. 自分自身への送信は禁止
        guard targetAgentId != session.agentId.value else {
            throw MCPError.cannotMessageSelf
        }

        // 3. 送信先エージェントの存在確認
        guard let targetAgent = try agentRepository.findById(AgentID(value: targetAgentId)) else {
            throw MCPError.agentNotFound(targetAgentId)
        }

        // 4. 同一プロジェクト内のエージェントか確認
        let isTargetInProject = try projectAgentAssignmentRepository.isAgentAssignedToProject(
            agentId: AgentID(value: targetAgentId),
            projectId: session.projectId
        )
        guard isTargetInProject else {
            throw MCPError.targetAgentNotInProject(targetAgentId: targetAgentId, projectId: session.projectId.value)
        }

        // 5. conversationIdの解決
        // 明示的に指定されていない場合、アクティブまたはpending会話から自動設定
        // 参照: docs/design/AI_TO_AI_CONVERSATION.md - pending状態でもイニシエーターからのメッセージは許可
        var resolvedConversationId: ConversationID? = nil
        if let convIdStr = conversationId {
            resolvedConversationId = ConversationID(value: convIdStr)
        } else {
            // 送信者と受信者間のアクティブな会話を検索
            let activeConversations = try conversationRepository.findActiveByAgentId(
                session.agentId,
                projectId: session.projectId
            )
            // 両者が参加している会話を探す
            if let activeConv = activeConversations.first(where: {
                $0.getPartnerId(for: session.agentId)?.value == targetAgentId
            }) {
                resolvedConversationId = activeConv.id
                Self.log("[MCP] Auto-resolved conversation_id from active: \(activeConv.id.value)")
            } else {
                // active会話がない場合、イニシエーターとしてpending会話を検索
                let pendingConversations = try conversationRepository.findPendingForInitiator(
                    session.agentId,
                    projectId: session.projectId
                )
                if let pendingConv = pendingConversations.first(where: {
                    $0.participantAgentId.value == targetAgentId
                }) {
                    resolvedConversationId = pendingConv.id
                    Self.log("[MCP] Auto-resolved conversation_id from pending (initiator): \(pendingConv.id.value)")
                }
            }
        }

        // 6. AI間メッセージ制約チェック
        // 参照: docs/design/AI_TO_AI_CONVERSATION.md - send_message 制約
        // 両者がAIエージェントの場合、アクティブな会話が必須
        let senderAgent = try agentRepository.findById(session.agentId)
        if senderAgent?.type == .ai && targetAgent.type == .ai {
            guard resolvedConversationId != nil else {
                Self.log("[MCP] AI-to-AI message rejected: no active conversation between \(session.agentId.value) and \(targetAgentId)")
                throw MCPError.conversationRequiredForAIToAI(
                    fromAgentId: session.agentId.value,
                    toAgentId: targetAgentId
                )
            }
        }

        // 7. メッセージ作成
        let message = ChatMessage(
            id: ChatMessageID.generate(),
            senderId: session.agentId,
            receiverId: AgentID(value: targetAgentId),
            content: content,
            createdAt: Date(),
            relatedTaskId: relatedTaskId.map { TaskID(value: $0) },
            conversationId: resolvedConversationId
        )

        // 8. 双方向保存
        try chatRepository.saveMessageDualWrite(
            message,
            projectId: session.projectId,
            senderAgentId: session.agentId,
            receiverAgentId: AgentID(value: targetAgentId)
        )

        // 9. ターゲットエージェントのPendingAgentPurposeを作成
        // これにより、get_agent_actionがターゲットエージェントに対してstart(reason=has_pending_messages)を返す
        // 会話IDがある場合は紐付け
        let pendingPurpose = PendingAgentPurpose(
            agentId: AgentID(value: targetAgentId),
            projectId: session.projectId,
            purpose: .chat,
            createdAt: Date(),
            startedAt: nil,
            conversationId: resolvedConversationId
        )
        try pendingAgentPurposeRepository.save(pendingPurpose)
        Self.log("[MCP] Created pending purpose for target agent: agent=\(targetAgentId), project=\(session.projectId.value), purpose=chat, conversation=\(resolvedConversationId?.value ?? "none")")

        Self.log("[MCP] Message sent successfully: \(message.id.value) from \(session.agentId.value) to \(targetAgentId)")

        var result: [String: Any] = [
            "success": true,
            "message_id": message.id.value,
            "target_agent_id": targetAgentId
        ]
        if let convId = resolvedConversationId {
            result["conversation_id"] = convId.value

            // 会話内メッセージ数をカウント
            // 参照: docs/design/AI_TO_AI_CONVERSATION.md
            let allMessages = try chatRepository.findMessages(projectId: session.projectId, agentId: session.agentId)
            let conversationMessageCount = allMessages.filter { $0.conversationId == convId }.count

            // 会話を取得してmax_turnsをチェック
            if let conversation = try conversationRepository.findById(convId) {
                result["current_turns"] = conversationMessageCount
                result["max_turns"] = conversation.maxTurns

                // ターン数上限に達した場合、会話を自動終了
                if conversationMessageCount >= conversation.maxTurns {
                    try conversationRepository.updateState(convId, state: .ended, endedAt: Date())
                    result["conversation_ended"] = true
                    result["warning"] = "【会話終了】最大ターン数（\(conversation.maxTurns)）に達したため会話を自動終了しました。必要であれば新しい会話を開始してください。"
                    Self.log("[MCP] sendMessage: Conversation auto-ended due to max_turns limit: \(conversationMessageCount)/\(conversation.maxTurns)")
                } else if conversationMessageCount > 0 && conversationMessageCount % 5 == 0 {
                    // 5件ごとにリマインド
                    result["reminder"] = "【確認】会話の目的は達成されましたか？達成された場合は end_conversation で会話を終了してください。（\(conversationMessageCount)/\(conversation.maxTurns)ターン）"
                    Self.log("[MCP] sendMessage: Conversation reminder added at message count: \(conversationMessageCount)/\(conversation.maxTurns)")
                }
            }
        }
        return result
    }

    // MARK: - AI-to-AI Conversation Tools
    // 参照: docs/design/AI_TO_AI_CONVERSATION.md

    /// start_conversation - 他のAIエージェントとの会話を開始
    private func startConversation(
        session: AgentSession,
        participantAgentId: String,
        purpose: String?,
        initialMessage: String,
        maxTurns: Int
    ) throws -> [String: Any] {
        Self.log("[MCP] startConversation called: initiator='\(session.agentId.value)' participant='\(participantAgentId)' maxTurns=\(maxTurns)")

        // 1. コンテンツ長チェック
        guard initialMessage.count <= 4000 else {
            throw MCPError.contentTooLong(maxLength: 4000, actual: initialMessage.count)
        }

        // 2. 自分自身との会話は禁止
        guard participantAgentId != session.agentId.value else {
            throw MCPError.cannotMessageSelf
        }

        // 3. 参加者エージェントの存在確認
        guard let _ = try agentRepository.findById(AgentID(value: participantAgentId)) else {
            throw MCPError.agentNotFound(participantAgentId)
        }

        // 4. 同一プロジェクト内のエージェントか確認
        let isParticipantInProject = try projectAgentAssignmentRepository.isAgentAssignedToProject(
            agentId: AgentID(value: participantAgentId),
            projectId: session.projectId
        )
        guard isParticipantInProject else {
            throw MCPError.targetAgentNotInProject(targetAgentId: participantAgentId, projectId: session.projectId.value)
        }

        // 5. 既存のアクティブ/保留中会話がないか確認（重複防止）
        let hasExisting = try conversationRepository.hasActiveOrPendingConversation(
            initiatorAgentId: session.agentId,
            participantAgentId: AgentID(value: participantAgentId),
            projectId: session.projectId
        )
        if hasExisting {
            throw MCPError.conversationAlreadyExists(
                initiator: session.agentId.value,
                participant: participantAgentId
            )
        }

        // 6. 会話エンティティ作成
        // maxTurnsはシステム上限（40）以下に制限
        let validatedMaxTurns = min(max(maxTurns, 2), Conversation.systemMaxTurns)
        let conversation = Conversation(
            id: ConversationID.generate(),
            projectId: session.projectId,
            initiatorAgentId: session.agentId,
            participantAgentId: AgentID(value: participantAgentId),
            state: .pending,
            purpose: purpose,
            maxTurns: validatedMaxTurns,
            createdAt: Date()
        )
        try conversationRepository.save(conversation)
        Self.log("[MCP] Created conversation: \(conversation.id.value) state=pending maxTurns=\(validatedMaxTurns)")

        // 7. 初期メッセージを送信（会話IDを紐付け）
        let message = ChatMessage(
            id: ChatMessageID.generate(),
            senderId: session.agentId,
            receiverId: AgentID(value: participantAgentId),
            content: initialMessage,
            createdAt: Date(),
            conversationId: conversation.id
        )
        try chatRepository.saveMessageDualWrite(
            message,
            projectId: session.projectId,
            senderAgentId: session.agentId,
            receiverAgentId: AgentID(value: participantAgentId)
        )

        // 8. 参加者エージェントのPendingAgentPurposeを作成（会話ID付き）
        let pendingPurpose = PendingAgentPurpose(
            agentId: AgentID(value: participantAgentId),
            projectId: session.projectId,
            purpose: .chat,
            createdAt: Date(),
            startedAt: nil,
            conversationId: conversation.id
        )
        try pendingAgentPurposeRepository.save(pendingPurpose)
        Self.log("[MCP] Created pending purpose for participant: agent=\(participantAgentId), conversation=\(conversation.id.value)")

        return [
            "success": true,
            "conversation_id": conversation.id.value,
            "state": conversation.state.rawValue,
            "participant_agent_id": participantAgentId,
            "message_id": message.id.value,
            "instruction": "会話を開始しました。相手エージェントが認証後、会話がアクティブになります。send_messageでメッセージを送信し、get_next_actionで相手の応答を待機してください。"
        ]
    }

    /// end_conversation - AI-to-AI会話を終了
    private func endConversation(
        session: AgentSession,
        conversationId: String,
        finalMessage: String?
    ) throws -> [String: Any] {
        Self.log("[MCP] endConversation called: conversation='\(conversationId)' by='\(session.agentId.value)'")

        // 1. 会話の存在確認
        let convId = ConversationID(value: conversationId)
        guard let conversation = try conversationRepository.findById(convId) else {
            throw MCPError.conversationNotFound(conversationId)
        }

        // 2. 参加者確認
        guard conversation.isParticipant(session.agentId) else {
            throw MCPError.notConversationParticipant(
                conversationId: conversationId,
                agentId: session.agentId.value
            )
        }

        // 3. 会話状態の確認
        guard conversation.state == .active || conversation.state == .pending else {
            throw MCPError.conversationNotActive(
                conversationId: conversationId,
                currentState: conversation.state.rawValue
            )
        }

        // 4. 最終メッセージがあれば送信
        if let finalMsg = finalMessage, !finalMsg.isEmpty {
            guard finalMsg.count <= 4000 else {
                throw MCPError.contentTooLong(maxLength: 4000, actual: finalMsg.count)
            }

            let partnerId = conversation.getPartnerId(for: session.agentId)!
            let message = ChatMessage(
                id: ChatMessageID.generate(),
                senderId: session.agentId,
                receiverId: partnerId,
                content: finalMsg,
                createdAt: Date(),
                conversationId: convId
            )
            try chatRepository.saveMessageDualWrite(
                message,
                projectId: session.projectId,
                senderAgentId: session.agentId,
                receiverAgentId: partnerId
            )
            Self.log("[MCP] Sent final message: \(message.id.value)")
        }

        // 5. 会話状態を terminating に更新
        try conversationRepository.updateState(convId, state: .terminating)
        Self.log("[MCP] Conversation state updated to terminating: \(conversationId)")

        // 6. 相手エージェントに終了通知用のPendingAgentPurposeを作成
        let partnerId = conversation.getPartnerId(for: session.agentId)!
        let pendingPurpose = PendingAgentPurpose(
            agentId: partnerId,
            projectId: session.projectId,
            purpose: .chat,
            createdAt: Date(),
            startedAt: nil,
            conversationId: convId
        )
        try pendingAgentPurposeRepository.save(pendingPurpose)

        return [
            "success": true,
            "conversation_id": conversationId,
            "state": ConversationState.terminating.rawValue,
            "instruction": "会話終了を要求しました。相手エージェントが終了を確認後、会話は完全に終了します。"
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
        // Note: working_directoryはコーディネーターが管理するため返さない
        return [
            "id": project.id.value,
            "name": project.name,
            "description": project.description,
            "status": project.status.rawValue,
            "created_at": ISO8601DateFormatter().string(from: project.createdAt),
            "updated_at": ISO8601DateFormatter().string(from: project.updatedAt)
        ]
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

    // MARK: - Help Tool
    // 参照: docs/design/TOOL_AUTHORIZATION_ENHANCEMENT.md

    /// helpツール実行: コンテキストに応じた利用可能ツール一覧/詳細を返す
    private func executeHelp(caller: CallerType, toolName: String?) -> [String: Any] {
        // コンテキスト情報を構築
        var context: [String: Any] = [
            "caller_type": callerTypeDescription(caller)
        ]

        if let session = caller.session {
            context["session_purpose"] = session.purpose.rawValue
            context["agent_id"] = session.agentId.value
            context["project_id"] = session.projectId.value
        }

        // 利用可能なツールをフィルタリング
        let availableTools = filterAvailableTools(for: caller)

        if let toolName = toolName {
            // 特定ツールの詳細を返す
            return buildToolDetail(toolName: toolName, caller: caller, context: context)
        } else {
            // ツール一覧を返す
            return buildToolList(availableTools: availableTools, caller: caller, context: context)
        }
    }

    /// CallerTypeの説明文字列を返す
    private func callerTypeDescription(_ caller: CallerType) -> String {
        switch caller {
        case .coordinator:
            return "coordinator"
        case .manager:
            return "manager"
        case .worker:
            return "worker"
        case .unauthenticated:
            return "unauthenticated"
        }
    }

    /// 呼び出し元が利用可能なツール名一覧を取得
    private func filterAvailableTools(for caller: CallerType) -> [String] {
        ToolAuthorization.permissions.compactMap { (toolName, permission) -> String? in
            if canAccess(permission: permission, caller: caller) {
                return toolName
            }
            return nil
        }.sorted()
    }

    /// 権限チェック（簡易版: 実際の認可エラーをthrowせずにbool返却）
    private func canAccess(permission: ToolPermission, caller: CallerType) -> Bool {
        switch (permission, caller) {
        case (.unauthenticated, _):
            return true

        case (.coordinatorOnly, .coordinator):
            return true
        case (.coordinatorOnly, _):
            return false

        case (.managerOnly, .manager):
            return true
        case (.managerOnly, _):
            return false

        case (.workerOnly, .worker):
            return true
        case (.workerOnly, _):
            return false

        case (.authenticated, .manager), (.authenticated, .worker):
            return true
        case (.authenticated, _):
            return false

        case (.chatOnly, .manager(_, let session)), (.chatOnly, .worker(_, let session)):
            return session.purpose == .chat
        case (.chatOnly, _):
            return false

        case (.taskOnly, .manager(_, let session)), (.taskOnly, .worker(_, let session)):
            return session.purpose == .task
        case (.taskOnly, _):
            return false
        }
    }

    /// ツール一覧を構築
    private func buildToolList(availableTools: [String], caller: CallerType, context: [String: Any]) -> [String: Any] {
        let allToolDefs = ToolDefinitions.all()
        let toolDefsByName = Dictionary(uniqueKeysWithValues: allToolDefs.compactMap { def -> (String, [String: Any])? in
            guard let name = def["name"] as? String else { return nil }
            return (name, def)
        })

        var toolList: [[String: Any]] = []
        for toolName in availableTools {
            if let def = toolDefsByName[toolName] {
                let permission = ToolAuthorization.permissions[toolName] ?? .authenticated
                toolList.append([
                    "name": toolName,
                    "description": def["description"] as? String ?? "",
                    "category": permission.rawValue
                ])
            }
        }

        // 利用不可ツールの情報を追加
        var unavailableInfo: [String: String] = [:]

        // chatOnly ツールがtaskセッションで利用不可の場合
        if case .manager(_, let session) = caller, session.purpose == .task {
            unavailableInfo["chat_tools"] = "チャットツール（get_pending_messages, respond_chat）はpurpose=chatのセッションでのみ利用可能です"
        } else if case .worker(_, let session) = caller, session.purpose == .task {
            unavailableInfo["chat_tools"] = "チャットツール（get_pending_messages, respond_chat）はpurpose=chatのセッションでのみ利用可能です"
        }

        // 未認証の場合
        if case .unauthenticated = caller {
            unavailableInfo["authenticated_tools"] = "認証が必要です。authenticateツールを使用してください"
        }

        // Coordinator でない場合
        if case .coordinator = caller {
            // Coordinatorは全て利用可能
        } else if case .unauthenticated = caller {
            unavailableInfo["coordinator_tools"] = "Coordinator専用ツールは利用できません"
        } else {
            unavailableInfo["coordinator_tools"] = "Coordinator専用ツール（health_check等）は利用できません"
        }

        var result: [String: Any] = [
            "context": context,
            "available_tools": toolList,
            "total_available": toolList.count
        ]

        if !unavailableInfo.isEmpty {
            result["unavailable_info"] = unavailableInfo
        }

        return result
    }

    /// 特定ツールの詳細を構築
    private func buildToolDetail(toolName: String, caller: CallerType, context: [String: Any]) -> [String: Any] {
        let allToolDefs = ToolDefinitions.all()
        guard let def = allToolDefs.first(where: { ($0["name"] as? String) == toolName }) else {
            return [
                "context": context,
                "error": "Tool '\(toolName)' not found"
            ]
        }

        let permission = ToolAuthorization.permissions[toolName] ?? .authenticated
        let isAvailable = canAccess(permission: permission, caller: caller)

        var result: [String: Any] = [
            "context": context,
            "name": toolName,
            "description": def["description"] as? String ?? "",
            "category": permission.rawValue,
            "available": isAvailable
        ]

        // パラメータ情報を抽出
        if let inputSchema = def["inputSchema"] as? [String: Any] {
            if let properties = inputSchema["properties"] as? [String: Any] {
                var parameters: [[String: Any]] = []
                let requiredParams = inputSchema["required"] as? [String] ?? []

                for (paramName, paramDef) in properties {
                    guard let paramDict = paramDef as? [String: Any] else { continue }
                    var paramInfo: [String: Any] = [
                        "name": paramName,
                        "type": paramDict["type"] as? String ?? "string",
                        "required": requiredParams.contains(paramName),
                        "description": paramDict["description"] as? String ?? ""
                    ]
                    if let enumValues = paramDict["enum"] as? [String] {
                        paramInfo["enum"] = enumValues
                    }
                    parameters.append(paramInfo)
                }
                result["parameters"] = parameters.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
            }
        }

        // 利用不可の理由を追加
        if !isAvailable {
            result["reason"] = unavailabilityReason(permission: permission, caller: caller)
        }

        return result
    }

    /// 利用不可の理由を返す
    private func unavailabilityReason(permission: ToolPermission, caller: CallerType) -> String {
        switch permission {
        case .coordinatorOnly:
            return "このツールはCoordinator専用です"
        case .managerOnly:
            return "このツールはManager専用です"
        case .workerOnly:
            return "このツールはWorker専用です"
        case .authenticated:
            return "このツールは認証が必要です。authenticateツールを使用してください"
        case .chatOnly:
            if let session = caller.session {
                return "このツールはpurpose=chatのセッションでのみ利用可能です。現在のセッションはpurpose=\(session.purpose.rawValue)です"
            }
            return "このツールはチャットセッションでのみ利用可能です"
        case .taskOnly:
            if let session = caller.session {
                return "このツールはpurpose=taskのセッションでのみ利用可能です。現在のセッションはpurpose=\(session.purpose.rawValue)です"
            }
            return "このツールはタスクセッションでのみ利用可能です"
        case .unauthenticated:
            return "" // 未認証ツールは常に利用可能
        }
    }
}

// MARK: - BlockType

/// ブロックの種別を表すenum
private enum BlockType {
    /// 自分がブロックした
    case selfBlocked
    /// 下位ワーカーがブロックした
    case subordinateBlocked
    /// ユーザー（UI）がブロックした
    case userBlocked
    /// 他のエージェントがブロックした
    case otherBlocked
}

// MARK: - MCPError

enum MCPError: Error, CustomStringConvertible, LocalizedError {
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
    case validationError(String)  // バリデーションエラー
    case invalidCoordinatorToken  // Phase 5: Coordinatorトークン無効
    case notSubordinate(managerId: String, targetId: String)  // Phase 5: 下位エージェントではない

    // send_message用エラー（UC012, UC013）
    case cannotMessageSelf  // 自分自身へのメッセージ送信禁止
    case targetAgentNotInProject(targetAgentId: String, projectId: String)  // 送信先がプロジェクト外
    case contentTooLong(maxLength: Int, actual: Int)  // コンテンツ長超過

    // AI-to-AI会話用エラー（UC016）
    case conversationNotFound(String)  // 会話が見つからない
    case conversationAlreadyExists(initiator: String, participant: String)  // 既にアクティブな会話が存在
    case notConversationParticipant(conversationId: String, agentId: String)  // 会話の参加者ではない
    case conversationNotActive(conversationId: String, currentState: String)  // 会話がアクティブではない
    case conversationRequiredForAIToAI(fromAgentId: String, toAgentId: String)  // AI間メッセージにはアクティブ会話必須

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
        case .validationError(let message):
            return "Validation error: \(message)"
        case .invalidCoordinatorToken:
            return "Invalid coordinator token. Set MCP_COORDINATOR_TOKEN environment variable."
        case .notSubordinate(let managerId, let targetId):
            return "Agent '\(targetId)' is not a subordinate of manager '\(managerId)'"
        case .cannotMessageSelf:
            return "Cannot send message to yourself"
        case .targetAgentNotInProject(let targetAgentId, let projectId):
            return "Target agent '\(targetAgentId)' is not assigned to project '\(projectId)'"
        case .contentTooLong(let maxLength, let actual):
            return "Content too long: \(actual) characters (max \(maxLength))"
        case .conversationNotFound(let id):
            return "Conversation not found: \(id)"
        case .conversationAlreadyExists(let initiator, let participant):
            return "An active or pending conversation already exists between '\(initiator)' and '\(participant)'"
        case .notConversationParticipant(let conversationId, let agentId):
            return "Agent '\(agentId)' is not a participant of conversation '\(conversationId)'"
        case .conversationNotActive(let conversationId, let currentState):
            return "Conversation '\(conversationId)' is not active (current state: \(currentState))"
        case .conversationRequiredForAIToAI(let fromAgentId, let toAgentId):
            return "AIエージェント間のメッセージ送信にはアクティブな会話が必要です。先にstart_conversation(participant_agent_id: \"\(toAgentId)\", initial_message: \"...\")を呼び出してください。(from: \(fromAgentId), to: \(toAgentId))"
        }
    }

    /// LocalizedError conformance - errorDescription returns the same as description
    var errorDescription: String? {
        return description
    }
}
