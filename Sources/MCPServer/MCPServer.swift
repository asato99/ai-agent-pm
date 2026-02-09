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
    let transport: MCPTransport

    // Repositories
    let agentRepository: AgentRepository
    let taskRepository: TaskRepository
    let projectRepository: ProjectRepository
    let sessionRepository: SessionRepository
    let contextRepository: ContextRepository
    let handoffRepository: HandoffRepository
    let eventRepository: EventRepository

    // Phase 3-1: Authentication Repositories
    let agentCredentialRepository: AgentCredentialRepository
    let agentSessionRepository: AgentSessionRepository

    // Phase 3-3: Execution Log Repository
    let executionLogRepository: ExecutionLogRepository

    // Phase 4: Project-Agent Assignment Repository
    let projectAgentAssignmentRepository: ProjectAgentAssignmentRepository

    // Chat機能: チャットリポジトリ
    let chatRepository: ChatFileRepository

    // AI-to-AI会話リポジトリ（UC016）
    let conversationRepository: ConversationRepository

    // チャットセッション委譲リポジトリ
    // 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
    let chatDelegationRepository: ChatDelegationRepository

    // アプリ設定リポジトリ（TTL設定など）
    let appSettingsRepository: AppSettingsRepository

    // Phase 2.3: マルチデバイス対応 - ワーキングディレクトリリポジトリ
    // 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.3
    let agentWorkingDirectoryRepository: AgentWorkingDirectoryRepository

    // 通知リポジトリ
    // 参照: docs/design/NOTIFICATION_SYSTEM.md
    let notificationRepository: NotificationRepository

    // スキルリポジトリ
    // 参照: docs/design/AGENT_SKILLS.md
    let skillDefinitionRepository: SkillDefinitionRepository
    let agentSkillAssignmentRepository: AgentSkillAssignmentRepository

    // WorkDetectionService: 共通の仕事判定ロジック
    // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
    let workDetectionService: WorkDetectionService

    let debugMode: Bool

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
        // Chat機能: チャットリポジトリ
        let directoryManager = ProjectDirectoryManager()
        self.chatRepository = ChatFileRepository(
            directoryManager: directoryManager,
            projectRepository: self.projectRepository
        )
        // AI-to-AI会話リポジトリ
        self.conversationRepository = ConversationRepository(database: database)
        // チャットセッション委譲リポジトリ
        self.chatDelegationRepository = ChatDelegationRepository(database: database)
        // アプリ設定リポジトリ
        self.appSettingsRepository = AppSettingsRepository(database: database)
        // Phase 2.3: ワーキングディレクトリリポジトリ
        self.agentWorkingDirectoryRepository = AgentWorkingDirectoryRepository(database: database)
        // 通知リポジトリ
        self.notificationRepository = NotificationRepository(database: database)
        // スキルリポジトリ
        self.skillDefinitionRepository = SkillDefinitionRepository(database: database)
        self.agentSkillAssignmentRepository = AgentSkillAssignmentRepository(database: database)
        // WorkDetectionService: 共通の仕事判定ロジック
        // chatDelegationRepositoryを渡してpending委譲の検出を有効化
        self.workDetectionService = WorkDetectionService(
            chatRepository: self.chatRepository,
            sessionRepository: self.agentSessionRepository,
            taskRepository: self.taskRepository,
            chatDelegationRepository: self.chatDelegationRepository
        )
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

    /// 共有ロガーインスタンス
    static let logger: MCPLogger = {
        let logger = MCPLogger.shared
        let logDirectory = AppConfig.appSupportDirectory.path

        // 既存ログファイルの移行（日付なしファイル → 日付付きファイル）
        let migrator = LogMigrator(directory: logDirectory)
        migrator.migrateIfNeeded(prefix: "mcp-server")

        // ファイル出力を設定（日付別ローテーション、JSON形式）
        let fileOutput = RotatingFileLogOutput(directory: logDirectory, prefix: "mcp-server", format: .json)
        logger.addOutput(fileOutput)
        // stderr出力を設定
        logger.addOutput(StderrLogOutput())
        return logger
    }()

    /// ログ出力（MCPLoggerに委譲）
    static func log(_ message: String, category: LogCategory = .system) {
        logger.info(message, category: category)
    }

    /// デバッグモード時のみログ出力
    func logDebug(_ message: String) {
        if debugMode {
            Self.logger.debug(message, category: .system)
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

    /// HTTP経由のリクエストを処理（非同期版 - Long Polling対応）
    /// 参照: docs/design/LONG_POLLING_DESIGN.md
    public func processHTTPRequestAsync(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        logDebug("[HTTP Async] Processing request: \(request.method)")

        // handleRequestAsyncを呼び出し、nilの場合は空のレスポンスを返す
        if let response = await handleRequestAsync(request) {
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

    /// リクエストをハンドリング（非同期版 - Long Polling対応）
    /// 通知（id == nil）の場合は nil を返す
    /// 参照: docs/design/LONG_POLLING_DESIGN.md
    private func handleRequestAsync(_ request: JSONRPCRequest) async -> JSONRPCResponse? {
        logDebug("Received (async): \(request.method)")

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
            // 非同期版を使用（Long Polling対応）
            return await handleToolsCallAsync(request)
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

            // ツール呼び出しログ
            let agentAndProject = extractAgentAndProject(from: caller)
            let agentIdStr = agentAndProject?.0.description
            let projectIdStr = agentAndProject?.1.description
            Self.logger.info(
                "Tool called: \(name)",
                category: .mcp,
                operation: name,
                agentId: agentIdStr,
                projectId: projectIdStr,
                details: LogUtils.formatArguments(arguments)
            )

            let startTime = Date()
            let result = try executeTool(name: name, arguments: arguments, caller: caller)
            let duration = Date().timeIntervalSince(startTime)

            // ツール完了ログ
            var resultDetails = LogUtils.formatResult(result)
            resultDetails["duration_ms"] = Int(duration * 1000)
            Self.logger.info(
                "Tool completed: \(name)",
                category: .mcp,
                operation: name,
                agentId: agentIdStr,
                projectId: projectIdStr,
                details: resultDetails
            )

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
            // 認可エラーログ
            Self.logger.warn(
                "Tool authorization failed: \(name)",
                category: .mcp,
                operation: name,
                details: ["error": error.errorDescription ?? error.localizedDescription]
            )
            // 認可エラーは専用のエラーメッセージで返す
            return JSONRPCResponse(id: request.id, result: [
                "content": [
                    ["type": "text", "text": "Authorization Error: \(error.errorDescription ?? error.localizedDescription)"]
                ],
                "isError": true
            ])
        } catch {
            // ツールエラーログ
            Self.logger.error(
                "Tool failed: \(name)",
                category: .mcp,
                operation: name,
                details: ["error": String(describing: error)]
            )
            return JSONRPCResponse(id: request.id, result: [
                "content": [
                    ["type": "text", "text": "Error: \(error)"]
                ],
                "isError": true
            ])
        }
    }

    /// ツール呼び出しを処理（非同期版 - Long Polling対応）
    /// get_next_action ツールで timeout_seconds が指定されている場合、
    /// サーバー側でLong Polling待機を行う
    /// 参照: docs/design/LONG_POLLING_DESIGN.md
    private func handleToolsCallAsync(_ request: JSONRPCRequest) async -> JSONRPCResponse {
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

            // ツール呼び出しログ
            let agentAndProject = extractAgentAndProject(from: caller)
            let agentIdStr = agentAndProject?.0.description
            let projectIdStr = agentAndProject?.1.description
            Self.logger.info(
                "Tool called: \(name)",
                category: .mcp,
                operation: name,
                agentId: agentIdStr,
                projectId: projectIdStr,
                details: LogUtils.formatArguments(arguments)
            )

            let startTime = Date()
            // 非同期版のツール実行（Long Polling対応）
            let result = try await executeToolAsync(name: name, arguments: arguments, caller: caller)
            let duration = Date().timeIntervalSince(startTime)

            // ツール完了ログ
            var resultDetails = LogUtils.formatResult(result)
            resultDetails["duration_ms"] = Int(duration * 1000)
            Self.logger.info(
                "Tool completed: \(name)",
                category: .mcp,
                operation: name,
                agentId: agentIdStr,
                projectId: projectIdStr,
                details: resultDetails
            )

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
            // 認可エラーログ
            Self.logger.warn(
                "Tool authorization failed: \(name)",
                category: .mcp,
                operation: name,
                details: ["error": error.errorDescription ?? error.localizedDescription]
            )
            // 認可エラーは専用のエラーメッセージで返す
            return JSONRPCResponse(id: request.id, result: [
                "content": [
                    ["type": "text", "text": "Authorization Error: \(error.errorDescription ?? error.localizedDescription)"]
                ],
                "isError": true
            ])
        } catch {
            // ツールエラーログ
            Self.logger.error(
                "Tool failed: \(name)",
                category: .mcp,
                operation: name,
                details: ["error": String(describing: error)]
            )
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
        // MCP Tool Call Logging: 呼び出し開始
        let startTime = Date()
        let formattedArgs = LogUtils.formatArguments(arguments)
        let callerDesc = callerTypeDescription(caller)
        Self.logger.debug(
            "MCP tool call: \(name)",
            category: .mcp,
            operation: name,
            details: ["caller": callerDesc, "arguments": formattedArgs]
        )
        Self.logger.trace(
            "MCP tool arguments detail",
            category: .mcp,
            operation: name,
            details: ["arguments": formattedArgs]
        )

        do {
            let result = try executeToolImpl(name: name, arguments: arguments, caller: caller)

            // MCP Tool Call Logging: 呼び出し成功
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let resultInfo = LogUtils.formatResult(result)
            Self.logger.debug(
                "MCP tool completed: \(name)",
                category: .mcp,
                operation: name,
                details: ["duration_ms": durationMs, "result_size_bytes": resultInfo["result_size_bytes"] ?? 0]
            )
            Self.logger.trace(
                "MCP tool result detail",
                category: .mcp,
                operation: name,
                details: resultInfo
            )

            return result
        } catch {
            // MCP Tool Call Logging: 呼び出しエラー
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            Self.logger.error(
                "MCP tool failed: \(name) - \(error.localizedDescription)",
                category: .mcp,
                operation: name,
                details: ["duration_ms": durationMs, "error": String(describing: error)]
            )
            throw error
        }
    }

    /// 実際のツール実行（ログなし）
    func executeToolImpl(name: String, arguments: [String: Any], caller: CallerType) throws -> Any {
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

        case "get_app_settings":
            return try getAppSettings()

        // ========================================
        // Manager専用
        // ========================================
        case "list_subordinates":
            guard case .manager(let agentId, _) = caller else {
                throw ToolAuthorizationError.managerRequired("list_subordinates")
            }
            return try listSubordinates(managerId: agentId.value)

        case "get_subordinate_profile":
            guard let targetAgentId = arguments["agent_id"] as? String else {
                throw MCPError.missingArguments(["agent_id"])
            }
            // Coordinator または Manager から呼び出し可能
            // 参照: docs/design/AGENT_CONTEXT_DIRECTORY.md
            switch caller {
            case .coordinator:
                // Coordinator経由: 任意のエージェントのプロファイルを取得可能
                return try getAgentProfileForCoordinator(agentId: targetAgentId)
            case .manager(let managerId, _):
                // Manager経由: 下位エージェントのみ取得可能
                return try getSubordinateProfile(managerId: managerId.value, targetAgentId: targetAgentId)
            default:
                throw ToolAuthorizationError.managerRequired("get_subordinate_profile")
            }

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

        case "select_action":
            guard case .manager(_, let session) = caller else {
                throw ToolAuthorizationError.managerRequired("select_action")
            }
            guard let action = arguments["action"] as? String else {
                throw MCPError.missingArguments(["action"])
            }
            let reason = arguments["reason"] as? String
            return try selectAction(session: session, action: action, reason: reason)

        // ========================================
        // Worker専用
        // ========================================
        case "report_completed":
            // Manager も自身のメインタスクを完了報告できる
            let session: AgentSession
            switch caller {
            case .worker(_, let s):
                session = s
            case .manager(_, let s):
                session = s
            default:
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

        case "get_my_task_progress":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            return try getMyTaskProgress(session: session)

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
            return try updateTaskStatus(taskId: taskId, status: status, reason: reason, session: session)

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
        // チャットセッション委譲機能
        // 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
        // ========================================
        case "delegate_to_chat_session":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let targetAgentId = arguments["target_agent_id"] as? String else {
                throw MCPError.missingArguments(["target_agent_id"])
            }
            guard let purpose = arguments["purpose"] as? String else {
                throw MCPError.missingArguments(["purpose"])
            }
            let context = arguments["context"] as? String
            return try delegateToChatSession(
                session: session,
                targetAgentId: targetAgentId,
                purpose: purpose,
                context: context
            )

        case "get_task_conversations":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            return try getTaskConversations(session: session)

        case "report_delegation_completed":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let delegationId = arguments["delegation_id"] as? String else {
                throw MCPError.missingArguments(["delegation_id"])
            }
            let result = arguments["result"] as? String
            return try reportDelegationCompleted(
                session: session,
                delegationId: delegationId,
                result: result
            )

        // ========================================
        // タスク依頼・承認機能
        // 参照: docs/design/TASK_REQUEST_APPROVAL.md
        // ========================================
        case "request_task":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let title = arguments["title"] as? String else {
                throw MCPError.missingArguments(["title"])
            }
            // チャットセッションからの呼び出しは、ユーザーのチャットメッセージに @@タスク作成: マーカーが必要
            // 参照: docs/design/CHAT_COMMAND_MARKER.md
            if session.purpose == .chat {
                Self.log("[MCP] request_task validation: session.agentId=\(session.agentId.value), projectId=\(session.projectId.value)")
                let messages = try chatRepository.findMessages(projectId: session.projectId, agentId: session.agentId)
                Self.log("[MCP] request_task validation: messages.count=\(messages.count)")
                let incomingMessages = messages.filter { $0.senderId != session.agentId }
                Self.log("[MCP] request_task validation: incomingMessages.count=\(incomingMessages.count)")
                if let lastMsg = incomingMessages.last {
                    Self.log("[MCP] request_task validation: lastMessage.senderId=\(lastMsg.senderId.value), content prefix=\(String(lastMsg.content.prefix(100)))")
                    Self.log("[MCP] request_task validation: containsMarker=\(ChatCommandMarker.containsTaskCreateMarker(lastMsg.content))")
                }
                guard let lastMessage = incomingMessages.last,
                      ChatCommandMarker.containsTaskCreateMarker(lastMessage.content) else {
                    Self.log("[MCP] request_task validation: FAILED - marker not found")
                    throw MCPError.taskRequestMarkerRequired
                }
                Self.log("[MCP] request_task validation: PASSED")
            }
            // タイトルにマーカーが含まれていた場合は除去（安全策）
            let cleanTitle: String
            if let extracted = ChatCommandMarker.extractTaskTitle(from: title) {
                cleanTitle = extracted
            } else {
                cleanTitle = title
            }
            // assignee_id は常に自分自身（チャットから他者への割り当ては不可）
            let assigneeId = session.agentId.value
            let description = arguments["description"] as? String
            let priority = arguments["priority"] as? String
            let parentTaskId = arguments["parent_task_id"] as? String
            return try requestTask(
                session: session,
                title: cleanTitle,
                description: description,
                assigneeId: assigneeId,
                priority: priority,
                parentTaskId: parentTaskId
            )

        case "approve_task_request":
            guard case .manager(_, let session) = caller else {
                throw ToolAuthorizationError.managerRequired("approve_task_request")
            }
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            return try approveTaskRequest(
                session: session,
                taskId: taskId
            )

        case "reject_task_request":
            guard case .manager(_, let session) = caller else {
                throw ToolAuthorizationError.managerRequired("reject_task_request")
            }
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            let reason = arguments["reason"] as? String
            return try rejectTaskRequest(
                session: session,
                taskId: taskId,
                reason: reason
            )

        // ========================================
        // 自己状況確認機能（認証済み：タスク・チャット両方）
        // 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 2
        // ========================================
        case "get_my_execution_history":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            let taskId = arguments["task_id"] as? String
            let limit = arguments["limit"] as? Int
            return try getMyExecutionHistory(session: session, taskId: taskId, limit: limit)

        case "get_execution_log":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let executionId = arguments["execution_id"] as? String else {
                throw MCPError.missingArguments(["execution_id"])
            }
            return try getExecutionLog(session: session, executionId: executionId)

        // ========================================
        // チャット→タスク操作ツール
        // 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 3
        // ========================================
        case "start_task_from_chat":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            guard let requesterId = arguments["requester_id"] as? String else {
                throw MCPError.missingArguments(["requester_id"])
            }
            // チャットセッションからの呼び出しは、ユーザーのチャットメッセージに @@タスク開始: マーカーが必要
            // 参照: docs/design/CHAT_COMMAND_MARKER.md
            if session.purpose == .chat {
                let messages = try chatRepository.findMessages(projectId: session.projectId, agentId: session.agentId)
                let incomingMessages = messages.filter { $0.senderId != session.agentId }
                guard let lastMessage = incomingMessages.last,
                      ChatCommandMarker.containsTaskStartMarker(lastMessage.content) else {
                    throw MCPError.taskStartMarkerRequired
                }
            }
            return try startTaskFromChat(session: session, taskId: taskId, requesterId: requesterId)

        case "update_task_from_chat":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let taskId = arguments["task_id"] as? String else {
                throw MCPError.missingArguments(["task_id"])
            }
            guard let requesterId = arguments["requester_id"] as? String else {
                throw MCPError.missingArguments(["requester_id"])
            }
            // チャットセッションからの呼び出しは、ユーザーのチャットメッセージに @@タスク調整: マーカーが必要
            // 参照: docs/design/CHAT_COMMAND_MARKER.md
            if session.purpose == .chat {
                let messages = try chatRepository.findMessages(projectId: session.projectId, agentId: session.agentId)
                let incomingMessages = messages.filter { $0.senderId != session.agentId }
                guard let lastMessage = incomingMessages.last,
                      ChatCommandMarker.containsTaskAdjustMarker(lastMessage.content) else {
                    throw MCPError.taskAdjustMarkerRequired
                }
            }
            let description = arguments["description"] as? String
            let status = arguments["status"] as? String
            return try updateTaskFromChat(session: session, taskId: taskId, requesterId: requesterId, description: description, status: status)

        // ========================================
        // セッション間通知ツール
        // 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 4
        // ========================================
        case "notify_task_session":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let message = arguments["message"] as? String else {
                throw MCPError.missingArguments(["message"])
            }
            // チャットセッションからの呼び出しは、ユーザーのチャットメッセージに @@タスク通知: マーカーが必要
            // 参照: docs/design/CHAT_COMMAND_MARKER.md
            if session.purpose == .chat {
                let messages = try chatRepository.findMessages(projectId: session.projectId, agentId: session.agentId)
                let incomingMessages = messages.filter { $0.senderId != session.agentId }
                guard let lastMessage = incomingMessages.last,
                      ChatCommandMarker.containsTaskNotifyMarker(lastMessage.content) else {
                    throw MCPError.taskNotifyMarkerRequired
                }
            }
            // メッセージにマーカーが含まれていた場合は除去（安全策）
            let cleanMessage: String
            if let extracted = ChatCommandMarker.extractNotifyMessage(from: message) {
                cleanMessage = extracted
            } else {
                cleanMessage = message
            }
            let conversationId = arguments["conversation_id"] as? String
            let relatedTaskId = arguments["related_task_id"] as? String
            let priority = arguments["priority"] as? String
            return try notifyTaskSession(
                session: session,
                message: cleanMessage,
                conversationId: conversationId,
                relatedTaskId: relatedTaskId,
                priority: priority
            )

        case "get_conversation_messages":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            guard let conversationId = arguments["conversation_id"] as? String else {
                throw MCPError.missingArguments(["conversation_id"])
            }
            let limit = arguments["limit"] as? Int
            return try getConversationMessages(
                session: session,
                conversationId: conversationId,
                limit: limit
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

    /// 非同期版ツール実行（Long Polling対応）
    /// get_next_actionのようなLong Polling対応ツールで使用
    /// Note: internal for @testable access in tests
    func executeToolAsync(name: String, arguments: [String: Any], caller: CallerType) async throws -> Any {
        switch name {
        case "get_next_action":
            guard let session = caller.session else {
                throw MCPError.sessionTokenRequired
            }
            let timeoutSeconds = (arguments["timeout_seconds"] as? Int) ?? 45
            // Long Polling開始をログ出力（これが表示されればLong Pollingが有効）
            let agentIdStr = String(describing: session.agentId)
            logDebug("[Long Polling] getNextActionAsync called with timeout=\(timeoutSeconds)s for agent: '\(agentIdStr.prefix(15))'...")
            return try await getNextActionAsync(session: session, timeoutSeconds: timeoutSeconds)

        default:
            // その他のツールは同期版にフォールバック
            return try executeTool(name: name, arguments: arguments, caller: caller)
        }
    }

    /// 結果をJSON文字列にフォーマット
    func formatResult(_ result: Any) -> String {
        if let data = try? JSONSerialization.data(
            withJSONObject: result,
            options: [.prettyPrinted, .sortedKeys]
        ),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: result)
    }

}


// MARK: - BlockType

/// ブロックの種別を表すenum
enum BlockType {
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
    case executionLogNotFound(String)  // Phase 2: 実行ログが見つからない
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

    // チャットセッション委譲用エラー
    // 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
    case delegationNotFound(String)  // 委譲が見つからない
    case notDelegationOwner(delegationId: String, agentId: String)  // 委譲の所有者ではない
    case delegationAlreadyProcessed(delegationId: String, currentStatus: String)  // 委譲が既に処理済み
    case toolNotAvailable(tool: String, reason: String)  // ツールが利用不可
    case invalidOperation(String)  // 無効な操作

    // チャットコマンドマーカー用エラー
    // 参照: docs/design/CHAT_COMMAND_MARKER.md
    case taskRequestMarkerRequired  // チャットセッションからのタスク作成にはマーカーが必要
    case taskNotifyMarkerRequired   // チャットセッションからのタスク通知にはマーカーが必要
    case taskAdjustMarkerRequired   // チャットセッションからのタスク調整にはマーカーが必要
    case taskStartMarkerRequired    // チャットセッションからのタスク開始にはマーカーが必要

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
        case .executionLogNotFound(let id):
            return "Execution log not found: \(id)"
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
            return "AIエージェント間の場合は、メッセージ送信にアクティブな会話が必要です。アクティブな会話がありません。業務上の必要性がある場合のみ、start_conversationで新しい会話を開始してください。(from: \(fromAgentId), to: \(toAgentId))"
        case .delegationNotFound(let id):
            return "Chat delegation not found: \(id)"
        case .notDelegationOwner(let delegationId, let agentId):
            return "Agent '\(agentId)' is not the owner of delegation '\(delegationId)'"
        case .delegationAlreadyProcessed(let delegationId, let currentStatus):
            return "Delegation '\(delegationId)' has already been processed (current status: \(currentStatus))"
        case .toolNotAvailable(let tool, let reason):
            return "Tool '\(tool)' is not available: \(reason)"
        case .invalidOperation(let message):
            return "Invalid operation: \(message)"
        case .taskRequestMarkerRequired:
            return "チャットセッションからの新規タスク作成には、ユーザーメッセージに @@タスク作成: マーカーが必要です。ユーザーに「@@タスク作成: タスク名」の形式で送信するよう案内してください。"
        case .taskNotifyMarkerRequired:
            return "チャットセッションからのタスク通知には、ユーザーメッセージに @@タスク通知: マーカーが必要です。ユーザーに「@@タスク通知: 通知内容」の形式で送信するよう案内してください。"
        case .taskAdjustMarkerRequired:
            return "チャットセッションからのタスク調整には、ユーザーメッセージに @@タスク調整: マーカーが必要です。ユーザーに「@@タスク調整: 調整内容」の形式で送信するよう案内してください。"
        case .taskStartMarkerRequired:
            return "チャットセッションからのタスク開始には、ユーザーメッセージに @@タスク開始: マーカーが必要です。ユーザーに「@@タスク開始: タスクID」の形式で送信するよう案内してください。"
        }
    }

    /// LocalizedError conformance - errorDescription returns the same as description
    var errorDescription: String? {
        return description
    }
}
