// Sources/RESTServer/RESTServer.swift
// AI Agent PM - REST API Server

import Foundation
import Hummingbird
import GRDB
import Infrastructure
import UseCase
import Domain
// MCPServer types are compiled directly in this target (not imported as module)
// (os.log import removed - using file-based logging instead)

// Debug logging helper - uses file-based logging for reliable debugging
// Reference: docs/guide/LOGGING.md - ファイルベースログの推奨
func debugLog(_ message: String) {
    let logFile = "/tmp/restserver_debug.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"

    if let handle = FileHandle(forWritingAtPath: logFile) {
        handle.seekToEndOfFile()
        if let data = logMessage.data(using: .utf8) {
            handle.write(data)
        }
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logFile, contents: logMessage.data(using: .utf8), attributes: nil)
    }
}

/// REST API Server for web-ui
final class RESTServer {
    let database: DatabaseQueue
    let port: Int
    let webUIPath: String?

    // Repositories
    let projectRepository: ProjectRepository
    let agentRepository: AgentRepository
    let taskRepository: TaskRepository
    let sessionRepository: AgentSessionRepository
    let credentialRepository: AgentCredentialRepository
    let handoffRepository: HandoffRepository
    let eventRepository: EventRepository
    let appSettingsRepository: AppSettingsRepository
    /// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.2
    let workingDirectoryRepository: AgentWorkingDirectoryRepository
    /// 参照: docs/requirements/PROJECTS.md - エージェント割り当て
    let projectAgentAssignmentRepository: ProjectAgentAssignmentRepository
    /// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 1-2
    let chatRepository: ChatFileRepository
    let directoryManager: ProjectDirectoryManager
    /// 参照: docs/design/NOTIFICATION_SYSTEM.md - UC010通知
    let notificationRepository: NotificationRepository
    /// 参照: docs/design/LOG_TRANSFER_DESIGN.md - ログアップロード
    let executionLogRepository: ExecutionLogRepository
    /// 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md - 実行ログ表示
    let contextRepository: ContextRepository
    // スキル関連リポジトリ
    // 参照: docs/design/AGENT_SKILLS.md
    let skillDefinitionRepository: SkillDefinitionRepository
    let agentSkillAssignmentRepository: AgentSkillAssignmentRepository

    // MCP Server for HTTP transport
    // 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ1.2
    // MCPServerのソースファイルが直接コンパイルされるため、internal initにアクセス可能
    lazy var mcpServer: MCPServer = {
        return MCPServer(database: database, transport: NullTransport())
    }()

    /// Initialize the REST server
    /// - Parameters:
    ///   - database: Database connection
    ///   - port: HTTP port (default: 8080)
    ///   - webUIPath: Path to web-ui static files directory (optional, enables static file serving)
    init(database: DatabaseQueue, port: Int = 8080, webUIPath: String? = nil) {
        self.database = database
        self.port = port
        self.webUIPath = webUIPath

        // Initialize repositories
        self.projectRepository = ProjectRepository(database: database)
        self.agentRepository = AgentRepository(database: database)
        self.taskRepository = TaskRepository(database: database)
        self.sessionRepository = AgentSessionRepository(database: database)
        self.credentialRepository = AgentCredentialRepository(database: database)
        self.handoffRepository = HandoffRepository(database: database)
        self.eventRepository = EventRepository(database: database)
        self.appSettingsRepository = AppSettingsRepository(database: database)
        self.workingDirectoryRepository = AgentWorkingDirectoryRepository(database: database)
        self.projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: database)
        // 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 1-2
        self.directoryManager = ProjectDirectoryManager()
        self.chatRepository = ChatFileRepository(
            directoryManager: directoryManager,
            projectRepository: projectRepository
        )
        // 参照: docs/design/NOTIFICATION_SYSTEM.md - UC010通知
        self.notificationRepository = NotificationRepository(database: database)
        // 参照: docs/design/LOG_TRANSFER_DESIGN.md - ログアップロード
        self.executionLogRepository = ExecutionLogRepository(database: database)
        // 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md - 実行ログ表示
        self.contextRepository = ContextRepository(database: database)
        // 参照: docs/design/AGENT_SKILLS.md - スキル機能
        self.skillDefinitionRepository = SkillDefinitionRepository(database: database)
        self.agentSkillAssignmentRepository = AgentSkillAssignmentRepository(database: database)
    }

    func run() async throws {
        debugLog("run() starting")

        // Load settings for remote access configuration
        let settings = try appSettingsRepository.get()
        let allowRemoteAccess = settings.allowRemoteAccess

        // Create router with custom context
        let router = Router(context: AuthenticatedContext.self)
        debugLog("Router created")

        // Add CORS middleware with remote access configuration
        router.add(middleware: CORSMiddleware(allowRemoteAccess: allowRemoteAccess))
        debugLog("CORS middleware added (allowRemoteAccess: \(allowRemoteAccess))")

        // Health check
        router.get("health") { _, _ in
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: "{\"status\":\"ok\"}"))
            )
        }
        debugLog("Health route registered")

        // API routes
        let apiRouter = router.group("api")
        debugLog("API group created")

        // Auth routes (no auth required for login)
        registerAuthRoutes(router: apiRouter)
        debugLog("Auth routes registered")

        // Protected routes need auth middleware
        registerProtectedRoutes(router: apiRouter)
        debugLog("Protected routes registered")

        // MCP HTTP Transport endpoint (coordinator_token auth)
        // 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ1.2
        registerMCPRoutes(router: router)
        debugLog("MCP routes registered")

        // API catch-all for unmatched routes (must be registered LAST on apiRouter)
        // This ensures API routes return proper JSON 404 instead of falling through to static file handler
        apiRouter.get("**") { _, context in
            let pathComponents = context.parameters.getCatchAll()
            let path = pathComponents.joined(separator: "/")
            debugLog("API catch-all: /api/\(path) not found")
            return Response(
                status: .notFound,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: "{\"message\":\"Not Found\",\"path\":\"/api/\(path)\"}"))
            )
        }
        debugLog("API catch-all registered")

        // Static file serving for web-ui (if enabled)
        if let webUIPath = webUIPath {
            debugLog("Static files will be enabled from: \(webUIPath)")

            // Serve index.html at root
            router.get("/") { _, _ in
                debugLog("Root GET handler called")
                return self.serveFile(at: "\(webUIPath)/index.html")
            }
            debugLog("Root route registered")

            // Serve assets with catch-all pattern
            router.get("/assets/**") { request, context in
                let pathComponents = context.parameters.getCatchAll()
                let path = pathComponents.joined(separator: "/")
                debugLog("Assets handler called for: \(path)")
                return self.serveFile(at: "\(webUIPath)/assets/\(path)")
            }
            debugLog("Assets route registered")

            // Catch-all for static files and SPA (must be after specific routes)
            // Note: API routes are handled by apiRouter, so we don't need to exclude /api here
            router.get("/**") { request, context in
                let pathComponents = context.parameters.getCatchAll()
                let path = pathComponents.joined(separator: "/")
                debugLog("Static catch-all handler for: \(path)")

                // Skip if this looks like an API path (should not happen due to apiRouter priority)
                if path.hasPrefix("api/") || path == "api" {
                    debugLog("Warning: API path reached static catch-all: /\(path)")
                    return self.serveFile(at: "\(webUIPath)/index.html")
                }

                // Check if file exists
                let filePath = "\(webUIPath)/\(path)"
                if FileManager.default.fileExists(atPath: filePath) {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory),
                       !isDirectory.boolValue {
                        debugLog("Serving file: \(filePath)")
                        return self.serveFile(at: filePath)
                    }
                }

                // SPA fallback
                debugLog("SPA fallback: index.html")
                return self.serveFile(at: "\(webUIPath)/index.html")
            }
            debugLog("Static catch-all route registered")
        } else {
            debugLog("No webUIPath provided, static files disabled")
        }

        debugLog("Creating Application...")

        // Determine bind address based on allowRemoteAccess setting (already loaded above)
        let bindAddress = allowRemoteAccess ? "0.0.0.0" : "127.0.0.1"

        // Create and run application
        let app = Application(
            router: router,
            configuration: .init(address: .hostname(bindAddress, port: port))
        )

        debugLog("Server about to start on http://\(bindAddress):\(port)")
        if allowRemoteAccess {
            debugLog("⚠️ Remote access enabled - server is accessible from LAN")
        }
        try await app.runService()
        debugLog("Server stopped")
    }

    // MARK: - Static File Serving

    func serveFile(at path: String) -> Response {
        guard let data = FileManager.default.contents(atPath: path) else {
            return Response(status: .notFound)
        }

        let contentType = mimeType(for: path)
        return Response(
            status: .ok,
            headers: [.contentType: contentType],
            body: .init(byteBuffer: .init(data: data))
        )
    }

    func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "eot": return "application/vnd.ms-fontobject"
        default: return "application/octet-stream"
        }
    }
    // MARK: - Auth Routes (public)

    func registerAuthRoutes(router: RouterGroup<AuthenticatedContext>) {
        let authRouter = router.group("auth")

        // POST /api/auth/login
        authRouter.post("login") { [self] request, context in
            try await handleLogin(request: request, context: context)
        }
    }

    // MARK: - Protected Routes

    func registerProtectedRoutes(router: RouterGroup<AuthenticatedContext>) {
        // Add auth middleware for protected routes
        let protectedRouter = router.group()
        protectedRouter.add(middleware: AuthMiddleware(sessionRepository: sessionRepository))

        // Auth endpoints
        let authRouter = protectedRouter.group("auth")
        authRouter.post("logout") { [self] request, context in
            try await handleLogout(request: request, context: context)
        }
        authRouter.get("me") { [self] request, context in
            try await handleMe(request: request, context: context)
        }

        // Projects
        protectedRouter.get("projects") { [self] request, context in
            try await listProjects(request: request, context: context)
        }

        let projectRouter = protectedRouter.group("projects")
        projectRouter.get(":projectId") { [self] request, context in
            try await getProject(request: request, context: context)
        }

        // Phase 2.2: Working Directory management endpoints
        // 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.2
        projectRouter.put(":projectId/my-working-directory") { [self] request, context in
            try await setMyWorkingDirectory(request: request, context: context)
        }
        projectRouter.delete(":projectId/my-working-directory") { [self] request, context in
            try await deleteMyWorkingDirectory(request: request, context: context)
        }

        // Tasks under projects
        let projectTaskRouter = projectRouter.group(":projectId").group("tasks")
        projectTaskRouter.get { [self] request, context in
            try await listTasks(request: request, context: context)
        }
        projectTaskRouter.post { [self] request, context in
            try await createTask(request: request, context: context)
        }

        // Assignable agents for project (agents assigned to the project)
        // According to requirements (PROJECTS.md): Task assignees must be agents assigned to the project
        projectRouter.get(":projectId/assignable-agents") { [self] request, context in
            try await listProjectAssignableAgents(request: request, context: context)
        }

        // Agent session counts for project (active sessions per assigned agent)
        // 参照: docs/design/CHAT_FEATURE.md - セッション状態表示
        projectRouter.get(":projectId/agent-sessions") { [self] request, context in
            try await listProjectAgentSessions(request: request, context: context)
        }

        // Direct task access
        let taskRouter = protectedRouter.group("tasks")
        debugLog("Task router created with group 'tasks'")
        taskRouter.get(":taskId") { [self] request, context in
            debugLog("GET /api/tasks/:taskId called")
            return try await getTask(request: request, context: context)
        }
        taskRouter.patch(":taskId") { [self] request, context in
            debugLog("PATCH /api/tasks/:taskId called")
            return try await updateTask(request: request, context: context)
        }
        taskRouter.delete(":taskId") { [self] request, context in
            debugLog("DELETE /api/tasks/:taskId called")
            return try await deleteTask(request: request, context: context)
        }
        taskRouter.get(":taskId/permissions") { [self] request, context in
            debugLog("GET /api/tasks/:taskId/permissions called")
            return try await getTaskPermissions(request: request, context: context)
        }
        // Task Request/Approval endpoints
        // 参照: docs/design/TASK_REQUEST_APPROVAL.md - REST API
        taskRouter.post("request") { [self] request, context in
            debugLog("POST /api/tasks/request called")
            return try await requestTask(request: request, context: context)
        }
        taskRouter.get("pending") { [self] request, context in
            debugLog("GET /api/tasks/pending called")
            return try await getPendingTasks(request: request, context: context)
        }
        taskRouter.post(":taskId/approve") { [self] request, context in
            debugLog("POST /api/tasks/:taskId/approve called")
            return try await approveTask(request: request, context: context)
        }
        taskRouter.post(":taskId/reject") { [self] request, context in
            debugLog("POST /api/tasks/:taskId/reject called")
            return try await rejectTask(request: request, context: context)
        }
        debugLog("Task routes registered: GET/:taskId, PATCH/:taskId, DELETE/:taskId, GET/:taskId/permissions, POST/request, GET/pending, POST/:taskId/approve, POST/:taskId/reject")

        // Agents
        let agentRouter = protectedRouter.group("agents")
        agentRouter.get("assignable") { [self] request, context in
            try await listAssignableAgents(request: request, context: context)
        }
        agentRouter.get("subordinates") { [self] request, context in
            try await listSubordinates(request: request, context: context)
        }
        agentRouter.get(":agentId") { [self] request, context in
            try await getAgent(request: request, context: context)
        }
        agentRouter.patch(":agentId") { [self] request, context in
            try await updateAgent(request: request, context: context)
        }
        // Agent skills
        // 参照: docs/design/AGENT_SKILLS.md
        agentRouter.get(":agentId/skills") { [self] request, context in
            debugLog("GET /api/agents/:agentId/skills called")
            return try await getAgentSkills(request: request, context: context)
        }
        agentRouter.put(":agentId/skills") { [self] request, context in
            debugLog("PUT /api/agents/:agentId/skills called")
            return try await assignAgentSkills(request: request, context: context)
        }
        debugLog("Agent routes registered: GET/assignable, GET/subordinates, GET/:agentId, PATCH/:agentId, GET/:agentId/skills, PUT/:agentId/skills")

        // Skills (list all available skills)
        let skillRouter = protectedRouter.group("skills")
        skillRouter.get { [self] request, context in
            debugLog("GET /api/skills called")
            return try await listSkills(request: request, context: context)
        }
        debugLog("Skill routes registered: GET/skills")

        // Handoffs
        let handoffRouter = protectedRouter.group("handoffs")
        debugLog("Handoff router created with group 'handoffs'")
        handoffRouter.get { [self] request, context in
            debugLog("GET /api/handoffs called")
            return try await listHandoffs(request: request, context: context)
        }
        handoffRouter.post { [self] request, context in
            debugLog("POST /api/handoffs called")
            return try await createHandoff(request: request, context: context)
        }
        handoffRouter.post(":handoffId/accept") { [self] request, context in
            debugLog("POST /api/handoffs/:handoffId/accept called")
            return try await acceptHandoff(request: request, context: context)
        }
        debugLog("Handoff routes registered")

        // Handoffs for a specific task
        taskRouter.get(":taskId/handoffs") { [self] request, context in
            debugLog("GET /api/tasks/:taskId/handoffs called")
            return try await listTaskHandoffs(request: request, context: context)
        }
        debugLog("Task handoffs route registered: GET/:taskId/handoffs")

        // Execution logs and contexts for a task
        // 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md
        taskRouter.get(":taskId/execution-logs") { [self] request, context in
            debugLog("GET /api/tasks/:taskId/execution-logs called")
            return try await listTaskExecutionLogs(request: request, context: context)
        }
        taskRouter.get(":taskId/contexts") { [self] request, context in
            debugLog("GET /api/tasks/:taskId/contexts called")
            return try await listTaskContexts(request: request, context: context)
        }
        debugLog("Task execution logs/contexts routes registered")

        // Execution log content (top-level endpoint for log file access)
        // 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md
        let executionLogRouter = protectedRouter.group("execution-logs")
        executionLogRouter.get(":logId/content") { [self] request, context in
            debugLog("GET /api/execution-logs/:logId/content called")
            return try await getExecutionLogContent(request: request, context: context)
        }
        debugLog("Execution log content route registered")

        // Chat messages
        // 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 1-2
        let chatRouter = projectRouter.group(":projectId/agents/:agentId/chat")
        chatRouter.get("messages") { [self] request, context in
            debugLog("GET /api/projects/:projectId/agents/:agentId/chat/messages called")
            return try await getChatMessages(request: request, context: context)
        }
        chatRouter.post("messages") { [self] request, context in
            debugLog("POST /api/projects/:projectId/agents/:agentId/chat/messages called")
            return try await sendChatMessage(request: request, context: context)
        }
        chatRouter.post("mark-read") { [self] request, context in
            debugLog("POST /api/projects/:projectId/agents/:agentId/chat/mark-read called")
            return try await markChatAsRead(request: request, context: context)
        }
        // Chat session start endpoint
        // Reference: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Phase 3
        chatRouter.post("start") { [self] request, context in
            debugLog("POST /api/projects/:projectId/agents/:agentId/chat/start called")
            return try await startChatSession(request: request, context: context)
        }
        // Chat session end endpoint (UC015)
        // Reference: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 6
        chatRouter.post("end") { [self] request, context in
            debugLog("POST /api/projects/:projectId/agents/:agentId/chat/end called")
            return try await endChatSession(request: request, context: context)
        }
        debugLog("Chat routes registered: GET/messages, POST/messages, POST/mark-read, POST/start, POST/end")

        // Unread counts (project-level aggregation)
        // Reference: docs/design/CHAT_FEATURE.md - Unread count feature
        projectRouter.get(":projectId/unread-counts") { [self] request, context in
            debugLog("GET /api/projects/:projectId/unread-counts called")
            return try await getUnreadCounts(request: request, context: context)
        }
        debugLog("Unread counts route registered: GET/:projectId/unread-counts")
    }

    // MARK: - Helpers

    func calculateTaskCounts(tasks: [Domain.Task], agentId: AgentID) -> (counts: TaskCounts, myTasks: Int) {
        var done = 0
        var inProgress = 0
        var blocked = 0
        var myTasks = 0

        for task in tasks {
            switch task.status {
            case .done:
                done += 1
            case .inProgress:
                inProgress += 1
            case .blocked:
                blocked += 1
            default:
                break
            }

            if task.assigneeId == agentId {
                myTasks += 1
            }
        }

        let counts = TaskCounts(
            total: tasks.count,
            done: done,
            inProgress: inProgress,
            blocked: blocked
        )

        return (counts, myTasks)
    }

    func jsonResponse<T: Encodable>(_ value: T) -> Response {
        do {
            let data = try JSONEncoder().encode(value)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(data: data))
            )
        } catch {
            return errorResponse(status: .internalServerError, message: "JSON encoding failed")
        }
    }

    func errorResponse(status: HTTPResponse.Status, message: String) -> Response {
        let json = "{\"message\":\"\(message)\"}"
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(string: json))
        )
    }

    // MARK: - MCP HTTP Transport

    /// MCP HTTP Transport エンドポイントを登録
    /// リモートCoordinatorからMCPサーバーにアクセス可能にする
    /// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ1.2
    func registerMCPRoutes(router: Router<AuthenticatedContext>) {
        // POST /mcp - JSON-RPC over HTTP
        router.post("mcp") { [self] request, context in
            try await handleMCPRequest(request: request, context: context)
        }

        // POST /api/v1/execution-logs/upload - ログアップロード
        // 参照: docs/design/LOG_TRANSFER_DESIGN.md
        router.post("api/v1/execution-logs/upload") { [self] request, context in
            try await handleLogUpload(request: request, context: context)
        }
    }
}
