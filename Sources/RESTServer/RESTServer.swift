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
private func debugLog(_ message: String) {
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
    private let database: DatabaseQueue
    private let port: Int
    private let webUIPath: String?

    // Repositories
    private let projectRepository: ProjectRepository
    private let agentRepository: AgentRepository
    private let taskRepository: TaskRepository
    private let sessionRepository: AgentSessionRepository
    private let credentialRepository: AgentCredentialRepository
    private let handoffRepository: HandoffRepository
    private let eventRepository: EventRepository
    private let appSettingsRepository: AppSettingsRepository
    /// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.2
    private let workingDirectoryRepository: AgentWorkingDirectoryRepository
    /// 参照: docs/requirements/PROJECTS.md - エージェント割り当て
    private let projectAgentAssignmentRepository: ProjectAgentAssignmentRepository
    /// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 1-2
    private let chatRepository: ChatFileRepository
    private let directoryManager: ProjectDirectoryManager
    /// 参照: docs/design/NOTIFICATION_SYSTEM.md - UC010通知
    private let notificationRepository: NotificationRepository
    /// 参照: docs/design/LOG_TRANSFER_DESIGN.md - ログアップロード
    private let executionLogRepository: ExecutionLogRepository
    /// 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md - 実行ログ表示
    private let contextRepository: ContextRepository

    // MCP Server for HTTP transport
    // 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ1.2
    // MCPServerのソースファイルが直接コンパイルされるため、internal initにアクセス可能
    private lazy var mcpServer: MCPServer = {
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

    private func serveFile(at path: String) -> Response {
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

    private func mimeType(for path: String) -> String {
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

    private func registerAuthRoutes(router: RouterGroup<AuthenticatedContext>) {
        let authRouter = router.group("auth")

        // POST /api/auth/login
        authRouter.post("login") { [self] request, context in
            try await handleLogin(request: request, context: context)
        }
    }

    private func handleLogin(request: Request, context: AuthenticatedContext) async throws -> Response {
        // Parse request body
        let body = try await request.body.collect(upTo: 1024 * 1024)
        guard let data = body.getData(at: 0, length: body.readableBytes),
              let loginRequest = try? JSONDecoder().decode(LoginRequest.self, from: data) else {
            return errorResponse(status: .badRequest, message: "Invalid request body")
        }

        // Find agent
        let agentId = AgentID(value: loginRequest.agentId)
        guard let agent = try agentRepository.findById(agentId) else {
            return errorResponse(status: .unauthorized, message: "Invalid agent ID or passkey")
        }

        // Only human agents can login to Web UI
        guard agent.type == .human else {
            return errorResponse(status: .forbidden, message: "Only human agents can login to Web UI")
        }

        // Validate passkey
        guard let credential = try credentialRepository.findByAgentId(agentId),
              credential.verify(passkey: loginRequest.passkey) else {
            return errorResponse(status: .unauthorized, message: "Invalid agent ID or passkey")
        }

        // Get default project for session (required in Phase 4)
        let defaultProjectId = ProjectID(value: AppConfig.DefaultProject.id)

        // Create session using the standard init (generates token internally)
        let expiresAt = Date().addingTimeInterval(24 * 60 * 60) // 24 hours
        let session = AgentSession(
            agentId: agentId,
            projectId: defaultProjectId,
            purpose: .task,
            expiresAt: expiresAt
        )
        try sessionRepository.save(session)

        // Build response
        let loginResponse = LoginResponse(
            sessionToken: session.token,
            agent: AgentDTO(from: agent),
            expiresAt: ISO8601DateFormatter().string(from: expiresAt)
        )

        return jsonResponse(loginResponse)
    }

    // MARK: - Protected Routes

    private func registerProtectedRoutes(router: RouterGroup<AuthenticatedContext>) {
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
        debugLog("Agent routes registered: GET/assignable, GET/subordinates, GET/:agentId, PATCH/:agentId")

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

    // MARK: - Auth Handlers

    private func handleLogout(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let token = context.sessionToken else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }
        try sessionRepository.deleteByToken(token)
        return jsonResponse(["success": true])
    }

    private func handleMe(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }
        guard let agent = try agentRepository.findById(agentId) else {
            return errorResponse(status: .notFound, message: "Agent not found")
        }
        return jsonResponse(AgentDTO(from: agent))
    }

    // MARK: - Project Handlers

    private func listProjects(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        // Return only projects that the logged-in agent is assigned to
        // Reference: docs/requirements/PROJECTS.md - Agent Assignment
        let projects = try projectAgentAssignmentRepository.findProjectsByAgent(agentId)
        debugLog("listProjects: agentId=\(agentId.value), assigned projects count=\(projects.count)")
        for p in projects {
            debugLog("  - assigned project: \(p.id.value) (\(p.name))")
        }
        var summaries: [ProjectSummaryDTO] = []

        for project in projects {
            let tasks = try taskRepository.findByProject(project.id, status: nil)
            let counts = calculateTaskCounts(tasks: tasks, agentId: agentId)
            summaries.append(ProjectSummaryDTO(from: project, taskCounts: counts.counts, myTaskCount: counts.myTasks))
        }

        debugLog("listProjects: returning \(summaries.count) projects")
        return jsonResponse(summaries)
    }

    private func getProject(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let projectIdStr = context.parameters.get("projectId") else {
            return errorResponse(status: .badRequest, message: "Missing project ID")
        }

        let projectId = ProjectID(value: projectIdStr)
        guard let project = try projectRepository.findById(projectId) else {
            return errorResponse(status: .notFound, message: "Project not found")
        }

        let tasks = try taskRepository.findByProject(projectId, status: nil)
        let counts = calculateTaskCounts(tasks: tasks, agentId: agentId)

        // Phase 2.2: ログイン中エージェントのワーキングディレクトリを取得
        let workingDirectory = try workingDirectoryRepository.findByAgentAndProject(agentId: agentId, projectId: projectId)
        let summary = ProjectSummaryDTO(
            from: project,
            taskCounts: counts.counts,
            myTaskCount: counts.myTasks,
            myWorkingDirectory: workingDirectory?.workingDirectory
        )

        return jsonResponse(summary)
    }

    /// PUT /api/projects/:projectId/my-working-directory - ワーキングディレクトリを設定
    /// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.2
    private func setMyWorkingDirectory(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let projectIdStr = context.parameters.get("projectId") else {
            return errorResponse(status: .badRequest, message: "Missing project ID")
        }

        let projectId = ProjectID(value: projectIdStr)
        guard try projectRepository.findById(projectId) != nil else {
            return errorResponse(status: .notFound, message: "Project not found")
        }

        // Parse request body
        let body = try await request.body.collect(upTo: 1024 * 1024)
        guard let data = body.getData(at: 0, length: body.readableBytes),
              let setRequest = try? JSONDecoder().decode(SetWorkingDirectoryRequest.self, from: data) else {
            return errorResponse(status: .badRequest, message: "Invalid request body")
        }

        // Validate working directory is not empty
        let workingDir = setRequest.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workingDir.isEmpty else {
            return errorResponse(status: .badRequest, message: "Working directory cannot be empty")
        }

        // Check if already exists and update, or create new
        if var existing = try workingDirectoryRepository.findByAgentAndProject(agentId: agentId, projectId: projectId) {
            existing.updateWorkingDirectory(workingDir)
            try workingDirectoryRepository.save(existing)
            return jsonResponse(WorkingDirectoryDTO(workingDirectory: existing.workingDirectory))
        } else {
            let newEntry = AgentWorkingDirectory.create(
                agentId: agentId,
                projectId: projectId,
                workingDirectory: workingDir
            )
            try workingDirectoryRepository.save(newEntry)
            var response = jsonResponse(WorkingDirectoryDTO(workingDirectory: newEntry.workingDirectory))
            response.status = .created
            return response
        }
    }

    /// DELETE /api/projects/:projectId/my-working-directory - ワーキングディレクトリ設定を削除
    /// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.2
    private func deleteMyWorkingDirectory(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let projectIdStr = context.parameters.get("projectId") else {
            return errorResponse(status: .badRequest, message: "Missing project ID")
        }

        let projectId = ProjectID(value: projectIdStr)
        guard try projectRepository.findById(projectId) != nil else {
            return errorResponse(status: .notFound, message: "Project not found")
        }

        try workingDirectoryRepository.deleteByAgentAndProject(agentId: agentId, projectId: projectId)
        return Response(status: .noContent)
    }

    // MARK: - Task Handlers

    private func listTasks(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let projectIdStr = context.parameters.get("projectId") else {
            return errorResponse(status: .badRequest, message: "Missing project ID")
        }

        let projectId = ProjectID(value: projectIdStr)
        guard try projectRepository.findById(projectId) != nil else {
            return errorResponse(status: .notFound, message: "Project not found")
        }

        let tasks = try taskRepository.findByProject(projectId, status: nil)

        // Phase 4: 逆依存関係を計算
        let dependentTasksMap = calculateDependentTasks(tasks: tasks)

        let dtos = tasks.map { task in
            TaskDTO(from: task, dependentTasks: dependentTasksMap[task.id.value])
        }

        return jsonResponse(dtos)
    }

    /// Phase 4: 逆依存関係マップを生成
    /// key: taskId, value: このタスクに依存しているタスクIDの配列
    private func calculateDependentTasks(tasks: [Domain.Task]) -> [String: [String]] {
        var result: [String: [String]] = [:]

        for task in tasks {
            for depId in task.dependencies {
                if result[depId.value] == nil {
                    result[depId.value] = []
                }
                result[depId.value]?.append(task.id.value)
            }
        }

        return result
    }

    private func createTask(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let projectIdStr = context.parameters.get("projectId") else {
            return errorResponse(status: .badRequest, message: "Missing project ID")
        }

        let projectId = ProjectID(value: projectIdStr)
        guard try projectRepository.findById(projectId) != nil else {
            return errorResponse(status: .notFound, message: "Project not found")
        }

        // Parse request body
        let body = try await request.body.collect(upTo: 1024 * 1024)
        guard let data = body.getData(at: 0, length: body.readableBytes),
              let createRequest = try? JSONDecoder().decode(CreateTaskRequest.self, from: data) else {
            return errorResponse(status: .badRequest, message: "Invalid request body")
        }

        let task = Domain.Task(
            id: TaskID.generate(),
            projectId: projectId,
            title: createRequest.title,
            description: createRequest.description ?? "",
            status: .backlog,
            priority: createRequest.priority.flatMap { TaskPriority(rawValue: $0) } ?? .medium,
            assigneeId: createRequest.assigneeId.map { AgentID(value: $0) },
            createdByAgentId: agentId,
            dependencies: createRequest.dependencies?.map { TaskID(value: $0) } ?? []
        )

        try taskRepository.save(task)

        var response = jsonResponse(TaskDTO(from: task))
        response.status = .created
        return response
    }

    /// GET /api/tasks/:taskId - タスク詳細取得
    private func getTask(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let taskIdStr = context.parameters.get("taskId") else {
            return errorResponse(status: .badRequest, message: "Missing task ID")
        }

        let taskId = TaskID(value: taskIdStr)
        guard let task = try taskRepository.findById(taskId) else {
            return errorResponse(status: .notFound, message: "Task not found")
        }

        // Phase 4: 逆依存関係を取得
        let allTasks = try taskRepository.findByProject(task.projectId, status: nil)
        let dependentTasks = allTasks
            .filter { $0.dependencies.contains(taskId) }
            .map { $0.id.value }

        return jsonResponse(TaskDTO(from: task, dependentTasks: dependentTasks))
    }

    private func updateTask(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let taskIdStr = context.parameters.get("taskId") else {
            return errorResponse(status: .badRequest, message: "Missing task ID")
        }

        let taskId = TaskID(value: taskIdStr)
        guard var task = try taskRepository.findById(taskId) else {
            return errorResponse(status: .notFound, message: "Task not found")
        }

        // Parse request body
        let body = try await request.body.collect(upTo: 1024 * 1024)
        guard let data = body.getData(at: 0, length: body.readableBytes),
              let updateRequest = try? JSONDecoder().decode(UpdateTaskRequest.self, from: data) else {
            return errorResponse(status: .badRequest, message: "Invalid request body")
        }

        let loggedInAgentId = context.agentId

        // Apply updates by direct property assignment (Task has var properties)
        if let title = updateRequest.title {
            task.title = title
        }
        if let description = updateRequest.description {
            task.description = description
        }

        // ステータス変更の処理
        if let statusStr = updateRequest.status,
           let newStatus = TaskStatus(rawValue: statusStr) {
            // 1. ステータス遷移検証
            guard UpdateTaskStatusUseCase.canTransition(from: task.status, to: newStatus) else {
                return errorResponse(
                    status: .badRequest,
                    message: "Invalid status transition: \(task.status.rawValue) -> \(newStatus.rawValue)"
                )
            }

            // 2. 権限検証（自分または下位エージェントが最後に変更したタスクのみ変更可能）
            if let lastChangedBy = task.statusChangedByAgentId {
                let subordinates = try agentRepository.findByParent(loggedInAgentId)
                let canChange = lastChangedBy == loggedInAgentId ||
                               subordinates.contains { $0.id == lastChangedBy }
                guard canChange else {
                    return errorResponse(
                        status: .forbidden,
                        message: "Cannot change status. Last changed by \(lastChangedBy.value). Only self or subordinate workers can modify."
                    )
                }
            }

            task.status = newStatus
            task.statusChangedByAgentId = loggedInAgentId
            task.statusChangedAt = Date()

            // Phase 3: blockedに変更時、blockedReasonも一緒に設定
            if newStatus == .blocked {
                task.blockedReason = updateRequest.blockedReason

                // UC010: blockedに変更時、担当エージェントにinterrupt通知を送信
                // 参照: docs/design/NOTIFICATION_SYSTEM.md
                if let assigneeId = task.assigneeId {
                    let notification = AgentNotification.createInterruptNotification(
                        targetAgentId: assigneeId,
                        targetProjectId: task.projectId,
                        action: "blocked",
                        taskId: taskId,
                        instruction: "タスクがblockedに変更されました。現在の作業を中断し、report_completed(result='blocked')を呼び出してください。"
                    )
                    try notificationRepository.save(notification)
                    debugLog("UC010: Created interrupt notification for agent \(assigneeId.value)")
                }
            } else {
                task.blockedReason = nil
            }

        }

        if let priorityStr = updateRequest.priority,
           let priority = TaskPriority(rawValue: priorityStr) {
            task.priority = priority
        }

        // 担当者変更の処理
        if let assigneeIdStr = updateRequest.assigneeId {
            let newAssigneeId = assigneeIdStr.isEmpty ? nil : AgentID(value: assigneeIdStr)
            // 担当者変更時の制限チェック（in_progress/blocked タスクは変更不可）
            if newAssigneeId != task.assigneeId {
                guard task.status != .inProgress && task.status != .blocked else {
                    return errorResponse(
                        status: .badRequest,
                        message: "Cannot reassign task in \(task.status.rawValue) status. Work context must be preserved."
                    )
                }
            }
            task.assigneeId = newAssigneeId
        }

        if let deps = updateRequest.dependencies {
            // Phase 4: 循環依存チェック
            let newDeps = deps.map { TaskID(value: $0) }
            if newDeps.contains(taskId) {
                return errorResponse(status: .badRequest, message: "Self-reference not allowed in dependencies")
            }
            task.dependencies = newDeps
        }
        // Phase 2: 時間追跡フィールド
        if let estimatedMinutes = updateRequest.estimatedMinutes {
            task.estimatedMinutes = estimatedMinutes > 0 ? estimatedMinutes : nil
        }
        if let actualMinutes = updateRequest.actualMinutes {
            task.actualMinutes = actualMinutes > 0 ? actualMinutes : nil
        }
        // Phase 3: blockedReasonは単独でも更新可能（ステータス変更なしの場合）
        if task.status == .blocked, let reason = updateRequest.blockedReason {
            task.blockedReason = reason
        }
        task.updatedAt = Date()

        try taskRepository.save(task)

        return jsonResponse(TaskDTO(from: task))
    }

    /// DELETE /api/tasks/:taskId - タスク削除（cancelled状態に変更）
    private func deleteTask(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let taskIdStr = context.parameters.get("taskId") else {
            return errorResponse(status: .badRequest, message: "Missing task ID")
        }

        let taskId = TaskID(value: taskIdStr)
        guard var task = try taskRepository.findById(taskId) else {
            return errorResponse(status: .notFound, message: "Task not found")
        }

        // タスクをcancelled状態に変更（論理削除）
        task.status = .cancelled
        task.updatedAt = Date()

        try taskRepository.save(task)

        return Response(status: .noContent)
    }

    /// GET /api/tasks/:taskId/permissions - タスク権限取得
    private func getTaskPermissions(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let loggedInAgentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let taskIdStr = context.parameters.get("taskId") else {
            return errorResponse(status: .badRequest, message: "Missing task ID")
        }

        let taskId = TaskID(value: taskIdStr)
        guard let task = try taskRepository.findById(taskId) else {
            return errorResponse(status: .notFound, message: "Task not found")
        }

        // 1. ステータス変更権限をチェック
        var canChangeStatus = true
        var statusChangeReason: String? = nil

        if let lastChangedBy = task.statusChangedByAgentId {
            let subordinates = try agentRepository.findByParent(loggedInAgentId)
            let isSelfOrSubordinate = lastChangedBy == loggedInAgentId ||
                                     subordinates.contains { $0.id == lastChangedBy }
            if !isSelfOrSubordinate {
                canChangeStatus = false
                statusChangeReason = "Last changed by \(lastChangedBy.value). Only self or subordinate workers can modify."
            }
        }

        // 2. 有効なステータス遷移を計算
        let allStatuses: [TaskStatus] = [.backlog, .todo, .inProgress, .blocked, .done, .cancelled]
        let validTransitions = allStatuses.filter { newStatus in
            UpdateTaskStatusUseCase.canTransition(from: task.status, to: newStatus)
        }.map { $0.rawValue }

        // 3. 担当者変更権限をチェック
        let canReassign = task.status != .inProgress && task.status != .blocked
        let reassignReason = canReassign ? nil : "Task is \(task.status.rawValue), reassignment disabled"

        // 4. 編集権限（現時点では常にtrue、将来的に拡張可能）
        let canEdit = true

        let permissions = TaskPermissionsDTO(
            canEdit: canEdit,
            canChangeStatus: canChangeStatus,
            canReassign: canReassign,
            validStatusTransitions: validTransitions,
            reason: statusChangeReason ?? reassignReason
        )

        return jsonResponse(permissions)
    }

    // MARK: - Task Request/Approval Handlers
    // 参照: docs/design/TASK_REQUEST_APPROVAL.md

    /// POST /api/tasks/request - タスク依頼作成
    private func requestTask(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        // Parse request body
        let body = try await request.body.collect(upTo: 1024 * 1024)
        guard let data = body.getData(at: 0, length: body.readableBytes),
              let createRequest = try? JSONDecoder().decode(RequestTaskRequest.self, from: data) else {
            return errorResponse(status: .badRequest, message: "Invalid request body")
        }

        // 担当者エージェントを取得
        let assigneeId = AgentID(value: createRequest.assigneeId)
        guard let assignee = try agentRepository.findById(assigneeId) else {
            return errorResponse(status: .notFound, message: "Assignee not found")
        }

        // 依頼者エージェントを取得
        guard try agentRepository.findById(agentId) != nil else {
            return errorResponse(status: .notFound, message: "Requester not found")
        }

        // プロジェクト割り当て確認（担当者がプロジェクトに割り当てられていることを確認）
        let assigneeProjects = try projectAgentAssignmentRepository.findProjectsByAgent(assigneeId)
        guard let project = assigneeProjects.first else {
            return errorResponse(status: .badRequest, message: "Assignee is not assigned to any project")
        }
        let projectId = project.id

        // 全エージェントを取得して辞書に変換
        let allAgentsList = try agentRepository.findAll()
        let allAgents = Dictionary(uniqueKeysWithValues: allAgentsList.map { ($0.id, $0) })

        // 依頼者が担当者の祖先かどうかを判定
        let isAncestor = AgentHierarchy.isAncestorOf(
            ancestor: agentId,
            descendant: assigneeId,
            agents: allAgents
        )

        // 優先度のパース
        let priority: TaskPriority
        if let priorityStr = createRequest.priority,
           let parsed = TaskPriority(rawValue: priorityStr) {
            priority = parsed
        } else {
            priority = .medium
        }

        // タスク作成
        var task = Task(
            id: TaskID.generate(),
            projectId: projectId,
            title: createRequest.title,
            description: createRequest.description ?? "",
            priority: priority,
            assigneeId: assigneeId
        )
        task.requesterId = agentId

        if isAncestor {
            // 自動承認
            task.approve(by: agentId)
        } else {
            // 承認待ち
            task.approvalStatus = .pendingApproval
        }

        try taskRepository.save(task)

        // レスポンス作成
        if isAncestor {
            let response = TaskRequestResponseDTO(
                taskId: task.id.value,
                approvalStatus: task.approvalStatus.rawValue,
                status: task.status.rawValue,
                approvers: nil
            )
            var httpResponse = jsonResponse(response)
            httpResponse.status = .created
            return httpResponse
        } else {
            // 承認可能なエージェント（担当者の祖先でHuman）を取得
            var approverIds: [String] = []
            var currentParentId = assignee.parentAgentId
            while let parentId = currentParentId {
                if let parent = allAgents[parentId] {
                    if parent.type == .human {
                        approverIds.append(parent.id.value)
                    }
                    currentParentId = parent.parentAgentId
                } else {
                    break
                }
            }

            let response = TaskRequestResponseDTO(
                taskId: task.id.value,
                approvalStatus: task.approvalStatus.rawValue,
                status: nil,
                approvers: approverIds
            )
            var httpResponse = jsonResponse(response)
            httpResponse.status = .created
            return httpResponse
        }
    }

    /// GET /api/tasks/pending - 承認待ちタスク一覧
    private func getPendingTasks(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        // 現在のエージェントを取得
        guard try agentRepository.findById(agentId) != nil else {
            return errorResponse(status: .notFound, message: "Agent not found")
        }

        // 全エージェントを取得して辞書に変換
        let allAgentsList = try agentRepository.findAll()
        let allAgents = Dictionary(uniqueKeysWithValues: allAgentsList.map { ($0.id, $0) })

        // このエージェントが承認可能なタスク（自分が祖先である担当者のタスク）を取得
        // まずはアサインされているプロジェクトの承認待ちタスクを取得
        let assignedProjects = try projectAgentAssignmentRepository.findProjectsByAgent(agentId)

        var pendingTasks: [TaskWithApprovalDTO] = []

        for project in assignedProjects {
            let projectPendingTasks = try taskRepository.findPendingApproval(projectId: project.id)

            for task in projectPendingTasks {
                // このタスクの担当者に対して、現在のエージェントが祖先かどうかを確認
                if let taskAssigneeId = task.assigneeId {
                    if AgentHierarchy.isAncestorOf(ancestor: agentId, descendant: taskAssigneeId, agents: allAgents) {
                        pendingTasks.append(TaskWithApprovalDTO(from: task))
                    }
                }
            }
        }

        return jsonResponse(pendingTasks)
    }

    /// POST /api/tasks/:taskId/approve - タスク依頼を承認
    private func approveTask(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let taskIdStr = context.parameters.get("taskId") else {
            return errorResponse(status: .badRequest, message: "Task ID is required")
        }
        let taskId = TaskID(value: taskIdStr)

        // タスクを取得
        guard var task = try taskRepository.findById(taskId) else {
            return errorResponse(status: .notFound, message: "Task not found")
        }

        // 承認待ち状態の確認
        guard task.approvalStatus == .pendingApproval else {
            return errorResponse(status: .badRequest, message: "Task is not pending approval")
        }

        // 承認者の存在確認
        guard try agentRepository.findById(agentId) != nil else {
            return errorResponse(status: .notFound, message: "Approver not found")
        }

        guard let taskAssigneeId = task.assigneeId else {
            return errorResponse(status: .badRequest, message: "Task has no assignee")
        }

        // 承認者が担当者の祖先であることを確認
        let allAgentsList = try agentRepository.findAll()
        let allAgents = Dictionary(uniqueKeysWithValues: allAgentsList.map { ($0.id, $0) })
        guard AgentHierarchy.isAncestorOf(ancestor: agentId, descendant: taskAssigneeId, agents: allAgents) else {
            return errorResponse(status: .forbidden, message: "You are not authorized to approve this task")
        }

        // 承認処理
        task.approve(by: agentId)
        try taskRepository.save(task)

        let response = TaskApprovalResponseDTO(
            taskId: task.id.value,
            approvalStatus: task.approvalStatus.rawValue,
            status: task.status.rawValue,
            approvedBy: agentId.value,
            approvedAt: ISO8601DateFormatter().string(from: task.approvedAt ?? Date())
        )
        return jsonResponse(response)
    }

    /// POST /api/tasks/:taskId/reject - タスク依頼を却下
    private func rejectTask(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let taskIdStr = context.parameters.get("taskId") else {
            return errorResponse(status: .badRequest, message: "Task ID is required")
        }
        let taskId = TaskID(value: taskIdStr)

        // Parse request body for optional reason
        var reason: String? = nil
        let body = try await request.body.collect(upTo: 1024 * 1024)
        if let data = body.getData(at: 0, length: body.readableBytes),
           let rejectRequest = try? JSONDecoder().decode(RejectTaskRequest.self, from: data) {
            reason = rejectRequest.reason
        }

        // タスクを取得
        guard var task = try taskRepository.findById(taskId) else {
            return errorResponse(status: .notFound, message: "Task not found")
        }

        // 承認待ち状態の確認
        guard task.approvalStatus == .pendingApproval else {
            return errorResponse(status: .badRequest, message: "Task is not pending approval")
        }

        // 却下者の存在確認
        guard try agentRepository.findById(agentId) != nil else {
            return errorResponse(status: .notFound, message: "Rejecter not found")
        }

        guard let taskAssigneeId = task.assigneeId else {
            return errorResponse(status: .badRequest, message: "Task has no assignee")
        }

        // 却下者が担当者の祖先であることを確認
        let allAgentsList = try agentRepository.findAll()
        let allAgents = Dictionary(uniqueKeysWithValues: allAgentsList.map { ($0.id, $0) })
        guard AgentHierarchy.isAncestorOf(ancestor: agentId, descendant: taskAssigneeId, agents: allAgents) else {
            return errorResponse(status: .forbidden, message: "You are not authorized to reject this task")
        }

        // 却下処理
        task.reject(reason: reason)
        try taskRepository.save(task)

        let response = TaskRejectionResponseDTO(
            taskId: task.id.value,
            approvalStatus: task.approvalStatus.rawValue,
            rejectedReason: task.rejectedReason
        )
        return jsonResponse(response)
    }

    // MARK: - Agent Handlers

    /// GET /api/agents/assignable (deprecated - use /projects/:projectId/assignable-agents)
    private func listAssignableAgents(request: Request, context: AuthenticatedContext) async throws -> Response {
        // Legacy endpoint: returns all active agents
        // Note: This endpoint doesn't filter by project. Use /projects/:projectId/assignable-agents instead.
        let agents = try agentRepository.findAll()
        let assignable = agents.filter { $0.status == .active }
        let dtos = assignable.map { AgentDTO(from: $0) }
        return jsonResponse(dtos)
    }

    /// GET /api/projects/:projectId/assignable-agents - プロジェクトに割り当て可能なエージェント一覧
    /// According to requirements (PROJECTS.md): Task assignees must be agents assigned to the project
    private func listProjectAssignableAgents(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let projectIdStr = context.parameters.get("projectId") else {
            return errorResponse(status: .badRequest, message: "Project ID is required")
        }
        let projectId = ProjectID(value: projectIdStr)

        // Get agents assigned to this project
        let projectAgents = try projectAgentAssignmentRepository.findAgentsByProject(projectId)

        // Filter to active agents only
        let assignable = projectAgents.filter { $0.status == .active }
        let dtos = assignable.map { AgentDTO(from: $0) }
        return jsonResponse(dtos)
    }

    /// GET /api/projects/:projectId/agent-sessions - プロジェクトのエージェントセッション情報を取得
    /// 参照: docs/design/CHAT_SESSION_STATUS.md - セッション状態表示
    private func listProjectAgentSessions(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let projectIdStr = context.parameters.get("projectId") else {
            return errorResponse(status: .badRequest, message: "Project ID is required")
        }
        let projectId = ProjectID(value: projectIdStr)

        // Get agents assigned to this project (active only, same as assignable-agents)
        let projectAgents = try projectAgentAssignmentRepository.findAgentsByProject(projectId)
        let activeAgents = projectAgents.filter { $0.status == .active }

        // Get session counts and chat status for each active agent
        var agentSessions: [String: AgentSessionPurposeCountsDTO] = [:]
        for agent in activeAgents {
            let counts = try sessionRepository.countActiveSessionsByPurpose(agentId: agent.id)
            let chatCount = counts[.chat] ?? 0
            let taskCount = counts[.task] ?? 0

            // Determine chat status: connected > connecting > disconnected
            // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
            let chatStatus: String
            if chatCount > 0 {
                // Active chat session exists
                chatStatus = "connected"
            } else if let assignment = try projectAgentAssignmentRepository.findAssignment(
                agentId: agent.id,
                projectId: projectId
            ), let spawnStartedAt = assignment.spawnStartedAt {
                // Check if spawn is still in progress (within 120 seconds)
                let spawnTimeout: TimeInterval = 120
                if Date().timeIntervalSince(spawnStartedAt) < spawnTimeout {
                    chatStatus = "connecting"
                } else {
                    // Spawn timed out
                    chatStatus = "disconnected"
                }
            } else {
                // No session and no spawn in progress
                chatStatus = "disconnected"
            }

            agentSessions[agent.id.value] = AgentSessionPurposeCountsDTO(
                chat: ChatSessionDTO(count: chatCount, status: chatStatus),
                task: TaskSessionDTO(count: taskCount)
            )
        }

        let dto = AgentSessionCountsDTO(agentSessions: agentSessions)
        return jsonResponse(dto)
    }

    /// GET /api/agents/subordinates - 全下位エージェント一覧（再帰的に取得）
    private func listSubordinates(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        // 直下だけでなく、全ての下位エージェントを再帰的に取得
        let subordinates = try agentRepository.findAllDescendants(agentId)
        let dtos = subordinates.map { AgentDTO(from: $0) }
        return jsonResponse(dtos)
    }

    /// GET /api/agents/:agentId - エージェント詳細取得（自分または部下のみ）
    private func getAgent(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let currentAgentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let targetAgentIdStr = context.parameters.get("agentId") else {
            return errorResponse(status: .badRequest, message: "Agent ID is required")
        }
        let targetAgentId = AgentID(value: targetAgentIdStr)

        // Verify permission: self or subordinate
        guard try canAccessAgent(currentAgentId: currentAgentId, targetAgentId: targetAgentId) else {
            return errorResponse(status: .forbidden, message: "You can only view yourself or your subordinates")
        }

        guard let agent = try agentRepository.findById(targetAgentId) else {
            return errorResponse(status: .notFound, message: "Agent not found")
        }

        let dto = AgentDetailDTO(from: agent)
        return jsonResponse(dto)
    }

    /// PATCH /api/agents/:agentId - エージェント更新（自分または部下のみ）
    private func updateAgent(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let currentAgentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let targetAgentIdStr = context.parameters.get("agentId") else {
            return errorResponse(status: .badRequest, message: "Agent ID is required")
        }
        let targetAgentId = AgentID(value: targetAgentIdStr)

        // Verify permission: self or subordinate
        guard try canAccessAgent(currentAgentId: currentAgentId, targetAgentId: targetAgentId) else {
            return errorResponse(status: .forbidden, message: "You can only update yourself or your subordinates")
        }

        guard var agent = try agentRepository.findById(targetAgentId) else {
            return errorResponse(status: .notFound, message: "Agent not found")
        }

        // Check if agent is locked (423 Locked)
        if agent.isLocked {
            return errorResponse(status: HTTPResponse.Status(code: 423), message: "Agent is currently locked")
        }

        // Parse update request
        let updateRequest = try await request.decode(as: UpdateAgentRequest.self, context: context)

        // Apply updates
        if let name = updateRequest.name {
            agent.name = name
        }
        if let role = updateRequest.role {
            agent.role = role
        }
        if let maxParallelTasks = updateRequest.maxParallelTasks {
            agent.maxParallelTasks = maxParallelTasks
        }
        if let capabilities = updateRequest.capabilities {
            agent.capabilities = capabilities
        }
        if let systemPrompt = updateRequest.systemPrompt {
            agent.systemPrompt = systemPrompt
        }
        if let statusStr = updateRequest.status,
           let status = AgentStatus(rawValue: statusStr) {
            agent.status = status
        }

        agent.updatedAt = Date()
        try agentRepository.save(agent)

        let dto = AgentDetailDTO(from: agent)
        return jsonResponse(dto)
    }

    /// Check if current agent can access target agent (self or any descendant)
    /// Used for agent info viewing and updating - hierarchical downward access only
    private func canAccessAgent(currentAgentId: AgentID, targetAgentId: AgentID) throws -> Bool {
        // Self access is always allowed
        if currentAgentId == targetAgentId {
            return true
        }

        // Check if target is a descendant (includes grandchildren, etc.)
        let allDescendants = try agentRepository.findAllDescendants(currentAgentId)
        return allDescendants.contains { $0.id == targetAgentId }
    }

    /// Check if current agent can chat with target agent
    /// Chat is allowed if:
    /// 1. Self access (always allowed)
    /// 2. Both agents are assigned to the same project
    /// 3. Target is a descendant (subordinate)
    /// 4. Target is an ancestor (manager)
    private func canChatWithAgent(currentAgentId: AgentID, targetAgentId: AgentID, projectId: ProjectID) throws -> Bool {
        debugLog("canChatWithAgent: current=\(currentAgentId.value), target=\(targetAgentId.value), project=\(projectId.value)")

        // Self access is always allowed
        if currentAgentId == targetAgentId {
            debugLog("canChatWithAgent: ALLOWED (self)")
            return true
        }

        // Check if both agents are assigned to the same project
        let currentAssigned = try projectAgentAssignmentRepository.isAgentAssignedToProject(agentId: currentAgentId, projectId: projectId)
        let targetAssigned = try projectAgentAssignmentRepository.isAgentAssignedToProject(agentId: targetAgentId, projectId: projectId)
        debugLog("canChatWithAgent: currentAssigned=\(currentAssigned), targetAssigned=\(targetAssigned)")

        if currentAssigned && targetAssigned {
            debugLog("canChatWithAgent: ALLOWED (same project)")
            return true
        }

        // Fallback to hierarchical check: Check if target is a descendant (includes grandchildren, etc.)
        let allDescendants = try agentRepository.findAllDescendants(currentAgentId)
        debugLog("canChatWithAgent: descendants count=\(allDescendants.count), ids=\(allDescendants.map { $0.id.value })")
        if allDescendants.contains(where: { $0.id == targetAgentId }) {
            debugLog("canChatWithAgent: ALLOWED (descendant)")
            return true
        }

        // Fallback to hierarchical check: Check if target is an ancestor (parent, grandparent, etc.)
        // Walk up the hierarchy from current agent to see if we reach target
        var currentId: AgentID? = currentAgentId
        while let id = currentId {
            guard let agent = try agentRepository.findById(id) else { break }
            debugLog("canChatWithAgent: checking ancestor - agent=\(agent.id.value), parentId=\(agent.parentAgentId?.value ?? "nil")")
            if agent.parentAgentId == targetAgentId {
                debugLog("canChatWithAgent: ALLOWED (ancestor)")
                return true
            }
            currentId = agent.parentAgentId
        }

        debugLog("canChatWithAgent: DENIED - no relationship found")
        return false
    }

    // MARK: - Handoff Handlers

    /// GET /api/handoffs - 自分宛ての未処理ハンドオフ一覧
    private func listHandoffs(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        let handoffs = try handoffRepository.findPending(agentId: agentId)
        let dtos = handoffs.map { HandoffDTO(from: $0) }
        return jsonResponse(dtos)
    }

    /// POST /api/handoffs - ハンドオフ作成
    private func createHandoff(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        // Parse request body
        let body = try await request.body.collect(upTo: 1024 * 1024)
        guard let data = body.getData(at: 0, length: body.readableBytes),
              let createRequest = try? JSONDecoder().decode(CreateHandoffRequest.self, from: data) else {
            return errorResponse(status: .badRequest, message: "Invalid request body")
        }

        // Validate summary
        guard !createRequest.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return errorResponse(status: .badRequest, message: "Summary cannot be empty")
        }

        // Validate task exists
        let taskId = TaskID(value: createRequest.taskId)
        guard let task = try taskRepository.findById(taskId) else {
            return errorResponse(status: .notFound, message: "Task not found")
        }

        // Validate toAgentId if provided
        var toAgentId: AgentID? = nil
        if let toAgentIdStr = createRequest.toAgentId {
            toAgentId = AgentID(value: toAgentIdStr)
            guard try agentRepository.findById(toAgentId!) != nil else {
                return errorResponse(status: .badRequest, message: "Target agent not found")
            }
        }

        // Create handoff
        let handoff = Handoff(
            id: HandoffID(value: UUID().uuidString),
            taskId: taskId,
            fromAgentId: agentId,
            toAgentId: toAgentId,
            summary: createRequest.summary,
            context: createRequest.context,
            recommendations: createRequest.recommendations
        )

        try handoffRepository.save(handoff)

        // Record event
        var metadata: [String: String] = [:]
        if let toAgent = toAgentId {
            metadata["to_agent_id"] = toAgent.value
        }

        let event = StateChangeEvent(
            id: EventID(value: UUID().uuidString),
            projectId: task.projectId,
            entityType: .handoff,
            entityId: handoff.id.value,
            eventType: .created,
            agentId: agentId,
            metadata: metadata.isEmpty ? nil : metadata
        )
        try eventRepository.save(event)

        var response = jsonResponse(HandoffDTO(from: handoff))
        response.status = .created
        return response
    }

    /// POST /api/handoffs/:handoffId/accept - ハンドオフ承認
    private func acceptHandoff(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let handoffIdStr = context.parameters.get("handoffId") else {
            return errorResponse(status: .badRequest, message: "Missing handoff ID")
        }

        let handoffId = HandoffID(value: handoffIdStr)
        guard var handoff = try handoffRepository.findById(handoffId) else {
            return errorResponse(status: .notFound, message: "Handoff not found")
        }

        // Check if already accepted
        guard handoff.acceptedAt == nil else {
            return errorResponse(status: .badRequest, message: "Handoff already accepted")
        }

        // Check if target agent matches (if specified)
        if let targetAgentId = handoff.toAgentId {
            guard targetAgentId == agentId else {
                return errorResponse(status: .forbidden, message: "This handoff is not for you")
            }
        }

        // Accept handoff
        handoff.acceptedAt = Date()
        try handoffRepository.save(handoff)

        // Record event
        guard let task = try taskRepository.findById(handoff.taskId) else {
            return errorResponse(status: .internalServerError, message: "Task not found for handoff")
        }

        let event = StateChangeEvent(
            id: EventID(value: UUID().uuidString),
            projectId: task.projectId,
            entityType: .handoff,
            entityId: handoff.id.value,
            eventType: .completed,
            agentId: agentId,
            previousState: "pending",
            newState: "accepted"
        )
        try eventRepository.save(event)

        return jsonResponse(HandoffDTO(from: handoff))
    }

    /// GET /api/tasks/:taskId/handoffs - タスクに関連するハンドオフ一覧
    private func listTaskHandoffs(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let taskIdStr = context.parameters.get("taskId") else {
            return errorResponse(status: .badRequest, message: "Missing task ID")
        }

        let taskId = TaskID(value: taskIdStr)
        guard try taskRepository.findById(taskId) != nil else {
            return errorResponse(status: .notFound, message: "Task not found")
        }

        let handoffs = try handoffRepository.findByTask(taskId)
        let dtos = handoffs.map { HandoffDTO(from: $0) }
        return jsonResponse(dtos)
    }

    // MARK: - Execution Log Handlers
    // 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md

    /// GET /tasks/:taskId/execution-logs
    /// Returns execution logs for a task with agent names
    private func listTaskExecutionLogs(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    private func getExecutionLogContent(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    private func listTaskContexts(request: Request, context: AuthenticatedContext) async throws -> Response {
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

    // MARK: - Chat Handlers
    // 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 1-2

    /// GET /projects/:projectId/agents/:agentId/chat/messages
    /// Query params: limit (default 50, max 200), after, before (cursor-based pagination)
    private func getChatMessages(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let currentAgentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        // Extract path parameters
        guard let projectIdStr = context.parameters.get("projectId"),
              let agentIdStr = context.parameters.get("agentId") else {
            return errorResponse(status: .badRequest, message: "Missing project or agent ID")
        }

        let projectId = ProjectID(value: projectIdStr)
        let targetAgentId = AgentID(value: agentIdStr)

        // Verify agent can access this chat (same project or hierarchical relationship)
        guard try canChatWithAgent(currentAgentId: currentAgentId, targetAgentId: targetAgentId, projectId: projectId) else {
            return errorResponse(status: .forbidden, message: "Cannot access this agent's chat")
        }

        // Parse query parameters
        let limitStr = request.uri.queryParameters.get("limit")
        let afterStr = request.uri.queryParameters.get("after")
        let beforeStr = request.uri.queryParameters.get("before")

        // Parse and validate limit parameter
        let limitInt = limitStr.flatMap { Int($0) }
        let limitResult = ChatMessageValidator.validateLimit(limitInt)
        let limit = limitResult.effectiveValue

        // Get messages with pagination
        let afterId = afterStr.map { ChatMessageID(value: $0) }
        let beforeId = beforeStr.map { ChatMessageID(value: $0) }

        do {
            let page = try chatRepository.findMessagesWithCursor(
                projectId: projectId,
                agentId: targetAgentId,
                limit: limit,
                after: afterId,
                before: beforeId
            )

            // Check if the agent has pending messages to respond to
            // This uses the same logic as get_next_action to determine waiting state
            let pendingMessages = try chatRepository.findUnreadMessages(
                projectId: projectId,
                agentId: targetAgentId
            )
            let awaitingAgentResponse = !pendingMessages.isEmpty

            let response = ChatMessagesResponse(
                messages: page.messages.map { ChatMessageDTO(from: $0) },
                hasMore: page.hasMore,
                totalCount: page.totalCount,
                awaitingAgentResponse: awaitingAgentResponse
            )

            return jsonResponse(response)
        } catch {
            debugLog("Failed to get chat messages: \(error)")
            return errorResponse(status: .internalServerError, message: "Failed to retrieve messages")
        }
    }

    /// POST /projects/:projectId/agents/:agentId/chat/messages
    /// Request body: { content: string, relatedTaskId?: string }
    private func sendChatMessage(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let currentAgentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        // Extract path parameters
        guard let projectIdStr = context.parameters.get("projectId"),
              let agentIdStr = context.parameters.get("agentId") else {
            return errorResponse(status: .badRequest, message: "Missing project or agent ID")
        }

        let projectId = ProjectID(value: projectIdStr)
        let targetAgentId = AgentID(value: agentIdStr)

        // Verify agent can access this chat (same project or hierarchical relationship)
        guard try canChatWithAgent(currentAgentId: currentAgentId, targetAgentId: targetAgentId, projectId: projectId) else {
            return errorResponse(status: .forbidden, message: "Cannot send message to this agent's chat")
        }

        // Parse request body
        let body: SendMessageRequest
        do {
            body = try await request.decode(as: SendMessageRequest.self, context: context)
        } catch {
            return errorResponse(status: .badRequest, message: "Invalid request body")
        }

        // Validate content
        let contentResult = ChatMessageValidator.validate(content: body.content)
        switch contentResult {
        case .valid:
            break  // Continue to save message
        case .invalid(let validationError):
            let details: ChatValidationErrorDetails?
            let errorCode: String
            let errorMessage: String
            switch validationError {
            case .emptyContent:
                errorCode = "EMPTY_CONTENT"
                errorMessage = "Message content cannot be empty"
                details = nil
            case .contentTooLong(let maxLength, let actualLength):
                errorCode = "CONTENT_TOO_LONG"
                errorMessage = "Message content exceeds maximum length of \(maxLength) characters"
                details = ChatValidationErrorDetails(maxLength: maxLength, actualLength: actualLength)
            }
            let errorResponse = ChatValidationError(
                error: errorMessage,
                code: errorCode,
                details: details
            )
            return jsonResponse(errorResponse, status: .badRequest)
        }

        // Create message with sender (current user) and receiver (target agent)
        let message = ChatMessage(
            id: ChatMessageID(value: UUID().uuidString),
            senderId: currentAgentId,
            receiverId: targetAgentId,
            content: body.content,
            createdAt: Date(),
            relatedTaskId: body.relatedTaskId.map { TaskID(value: $0) }
        )

        do {
            // Dual write: save to both sender's and receiver's storage
            // WorkDetectionService will detect this as unread messages
            // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
            try chatRepository.saveMessageDualWrite(
                message,
                projectId: projectId,
                senderAgentId: currentAgentId,
                receiverAgentId: targetAgentId
            )
            debugLog("Saved chat message for agent: \(targetAgentId.value), project=\(projectId.value)")

            return jsonResponse(ChatMessageDTO(from: message), status: .created)
        } catch {
            debugLog("Failed to save chat message: \(error)")
            return errorResponse(status: .internalServerError, message: "Failed to save message")
        }
    }

    /// GET /projects/:projectId/unread-counts
    /// Returns unread message counts per agent for the current user in the project
    /// Reference: docs/design/CHAT_FEATURE.md - Unread count feature
    private func getUnreadCounts(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let currentAgentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        guard let projectIdStr = context.parameters.get("projectId") else {
            return errorResponse(status: .badRequest, message: "Missing project ID")
        }

        let projectId = ProjectID(value: projectIdStr)

        // Verify agent is assigned to this project and get all project agents
        let projectAgents = try projectAgentAssignmentRepository.findAgentsByProject(projectId)
        guard projectAgents.contains(where: { $0.id == currentAgentId }) else {
            return errorResponse(status: .forbidden, message: "Not assigned to this project")
        }

        do {
            // Get all messages in my chat storage for this project
            let allMessages = try chatRepository.findMessages(
                projectId: projectId,
                agentId: currentAgentId
            )

            // Get last read times for each sender
            let lastReadTimes = try chatRepository.getLastReadTimes(
                projectId: projectId,
                agentId: currentAgentId
            )

            // Calculate unread counts per sender using UnreadCountCalculator (with lastReadTimes)
            let counts = UnreadCountCalculator.calculateBySender(
                allMessages,
                agentId: currentAgentId,
                lastReadTimes: lastReadTimes
            )

            debugLog("getUnreadCounts: projectId=\(projectIdStr), agentId=\(currentAgentId.value), counts=\(counts)")
            return jsonResponse(UnreadCountsResponse(counts: counts))
        } catch {
            debugLog("Failed to get unread counts: \(error)")
            return errorResponse(status: .internalServerError, message: "Failed to retrieve unread counts")
        }
    }

    /// POST /projects/:projectId/agents/:agentId/chat/mark-read
    /// Mark messages from a specific agent as read
    private func markChatAsRead(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let currentAgentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        // Extract path parameters
        guard let projectIdStr = context.parameters.get("projectId"),
              let agentIdStr = context.parameters.get("agentId") else {
            return errorResponse(status: .badRequest, message: "Missing project or agent ID")
        }

        let projectId = ProjectID(value: projectIdStr)
        let targetAgentId = AgentID(value: agentIdStr)

        // Verify agent can access this chat
        guard try canChatWithAgent(currentAgentId: currentAgentId, targetAgentId: targetAgentId, projectId: projectId) else {
            return errorResponse(status: .forbidden, message: "Cannot access this agent's chat")
        }

        do {
            // Mark messages from this sender as read
            try chatRepository.markAsRead(
                projectId: projectId,
                currentAgentId: currentAgentId,
                senderAgentId: targetAgentId
            )

            debugLog("markChatAsRead: projectId=\(projectIdStr), currentAgent=\(currentAgentId.value), targetAgent=\(agentIdStr)")
            return jsonResponse(["success": true])
        } catch {
            debugLog("Failed to mark chat as read: \(error)")
            return errorResponse(status: .internalServerError, message: "Failed to mark as read")
        }
    }

    /// POST /projects/:projectId/agents/:agentId/chat/start
    /// Start a chat session with an agent
    /// Reference: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Phase 3
    private func startChatSession(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let currentAgentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        // Extract path parameters
        guard let projectIdStr = context.parameters.get("projectId"),
              let agentIdStr = context.parameters.get("agentId") else {
            return errorResponse(status: .badRequest, message: "Missing project or agent ID")
        }

        let projectId = ProjectID(value: projectIdStr)
        let targetAgentId = AgentID(value: agentIdStr)

        // Verify agent can chat with target
        guard try canChatWithAgent(currentAgentId: currentAgentId, targetAgentId: targetAgentId, projectId: projectId) else {
            return errorResponse(status: .forbidden, message: "Cannot access this agent's chat")
        }

        do {
            // Check if there's already an active session for this agent/project
            let existingSessions = try sessionRepository.findByAgentIdAndProjectId(
                targetAgentId,
                projectId: projectId
            )
            // Filter to active sessions (not expired) with chat purpose
            let hasActiveChatSession = existingSessions.contains { !$0.isExpired && $0.purpose == .chat }

            if hasActiveChatSession {
                debugLog("startChatSession: Active chat session already exists for agent=\(agentIdStr)")
                return jsonResponse(["success": true, "alreadyActive": true])
            }

            // Check if spawn is already in progress (spawn_started_at set and not expired)
            // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
            if let assignment = try projectAgentAssignmentRepository.findAssignment(
                agentId: targetAgentId,
                projectId: projectId
            ), let spawnStartedAt = assignment.spawnStartedAt {
                let spawnTimeout: TimeInterval = 120
                if Date().timeIntervalSince(spawnStartedAt) < spawnTimeout {
                    debugLog("startChatSession: Spawn already in progress for agent=\(agentIdStr)")
                    return jsonResponse(["success": true, "spawnInProgress": true])
                }
            }

            // No active session and no spawn in progress
            // Coordinator will detect unread messages and spawn the agent via WorkDetectionService
            debugLog("startChatSession: No active session, Coordinator will spawn agent=\(agentIdStr), project=\(projectIdStr)")
            return jsonResponse(["success": true])
        } catch {
            debugLog("Failed to start chat session: \(error)")
            return errorResponse(status: .internalServerError, message: "Failed to start chat session")
        }
    }

    // MARK: - UC015: End Chat Session
    /// POST /api/projects/:projectId/agents/:agentId/chat/end
    /// Reference: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 6
    /// Sets the chat session state to 'terminating' so agent receives exit action on next getNextAction call
    private func endChatSession(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let currentAgentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        // Extract path parameters
        guard let projectIdStr = context.parameters.get("projectId"),
              let agentIdStr = context.parameters.get("agentId") else {
            return errorResponse(status: .badRequest, message: "Missing project or agent ID")
        }

        let projectId = ProjectID(value: projectIdStr)
        let targetAgentId = AgentID(value: agentIdStr)

        // Verify agent can chat with target
        guard try canChatWithAgent(currentAgentId: currentAgentId, targetAgentId: targetAgentId, projectId: projectId) else {
            return errorResponse(status: .forbidden, message: "Cannot access this agent's chat")
        }

        do {
            // Find active chat sessions for this agent/project
            let sessions = try sessionRepository.findByAgentIdAndProjectId(
                targetAgentId,
                projectId: projectId
            )

            // Filter to active sessions with chat purpose
            let activeChatSessions = sessions.filter { !$0.isExpired && $0.purpose == .chat && $0.state == .active }

            if activeChatSessions.isEmpty {
                debugLog("endChatSession: No active chat session found for agent=\(agentIdStr)")
                // Clear spawn_started_at to allow fresh spawn next time
                // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
                try projectAgentAssignmentRepository.updateSpawnStartedAt(
                    agentId: targetAgentId,
                    projectId: projectId,
                    startedAt: nil
                )
                debugLog("endChatSession: Cleared spawn_started_at for agent=\(agentIdStr)")
                // Return success even if no session exists (idempotent)
                return jsonResponse(["success": true, "noActiveSession": true])
            }

            // Update each active session's state to terminating
            var terminatedCount = 0
            for session in activeChatSessions {
                try sessionRepository.updateState(token: session.token, state: .terminating)
                terminatedCount += 1
                debugLog("endChatSession: Set session to terminating, token=\(session.token.prefix(8))...")
            }

            debugLog("endChatSession: Terminated \(terminatedCount) session(s) for agent=\(agentIdStr)")

            // Clear spawn_started_at to allow fresh spawn when user reopens chat
            // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
            try projectAgentAssignmentRepository.updateSpawnStartedAt(
                agentId: targetAgentId,
                projectId: projectId,
                startedAt: nil
            )
            debugLog("endChatSession: Cleared spawn_started_at for agent=\(agentIdStr)")

            return jsonResponse(["success": true])
        } catch {
            debugLog("Failed to end chat session: \(error)")
            return errorResponse(status: .internalServerError, message: "Failed to end chat session")
        }
    }

    /// Helper: JSON response with custom status
    private func jsonResponse<T: Encodable>(_ value: T, status: HTTPResponse.Status) -> Response {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(value)
            return Response(
                status: status,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: data))
            )
        } catch {
            return Response(
                status: .internalServerError,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(string: "{\"error\":\"Encoding error\"}"))
            )
        }
    }

    // MARK: - Helpers

    private func calculateTaskCounts(tasks: [Domain.Task], agentId: AgentID) -> (counts: TaskCounts, myTasks: Int) {
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

    private func jsonResponse<T: Encodable>(_ value: T) -> Response {
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

    private func errorResponse(status: HTTPResponse.Status, message: String) -> Response {
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
    private func registerMCPRoutes(router: Router<AuthenticatedContext>) {
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

    /// MCP JSON-RPCリクエストを処理
    /// Authorization: Bearer <coordinator_token> で認証
    private func handleMCPRequest(request: Request, context: AuthenticatedContext) async throws -> Response {
        // 1. coordinator_token認証
        guard let authHeader = request.headers[.authorization],
              authHeader.hasPrefix("Bearer ") else {
            debugLog("[MCP HTTP] Missing or invalid Authorization header")
            return errorResponse(status: .unauthorized, message: "Authorization header required")
        }

        let coordinatorToken = String(authHeader.dropFirst("Bearer ".count))

        // DBの設定を優先、環境変数をフォールバック
        var expectedToken: String?
        if let settings = try? appSettingsRepository.get() {
            expectedToken = settings.coordinatorToken
        }
        if expectedToken == nil || expectedToken?.isEmpty == true {
            expectedToken = ProcessInfo.processInfo.environment["COORDINATOR_TOKEN"]
        }

        guard let expected = expectedToken, !expected.isEmpty, coordinatorToken == expected else {
            debugLog("[MCP HTTP] Invalid coordinator_token")
            return errorResponse(status: .unauthorized, message: "Invalid coordinator token")
        }

        // 2. リクエストボディをパース
        let body = try await request.body.collect(upTo: 1024 * 1024) // 1MB limit
        guard let data = body.getData(at: 0, length: body.readableBytes) else {
            debugLog("[MCP HTTP] Empty request body")
            return jsonRPCErrorResponse(id: nil, error: JSONRPCError.invalidRequest)
        }

        // 3. JSONRPCRequestをデコード
        let jsonRPCRequest: JSONRPCRequest
        do {
            jsonRPCRequest = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
        } catch {
            debugLog("[MCP HTTP] JSON parse error: \(error)")
            return jsonRPCErrorResponse(id: nil, error: JSONRPCError.parseError)
        }

        debugLog("[MCP HTTP] Request: \(jsonRPCRequest.method)")

        // 4. MCPServerで処理（非同期版を使用 - Long Polling対応）
        // 参照: docs/design/LONG_POLLING_DESIGN.md
        let response = await mcpServer.processHTTPRequestAsync(jsonRPCRequest)

        // 5. レスポンスをJSON化して返す
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let responseData = try encoder.encode(response)

        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: responseData))
        )
    }

    /// JSON-RPCエラーレスポンスを生成
    private func jsonRPCErrorResponse(id: RequestID?, error: JSONRPCError) -> Response {
        let response = JSONRPCResponse(id: id, error: error)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(response) else {
            return Response(
                status: .internalServerError,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: "{\"error\":\"Internal Server Error\"}"))
            )
        }

        return Response(
            status: .ok, // JSON-RPC always returns 200, errors are in the body
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }

    // MARK: - Log Upload Handler

    /// POST /api/v1/execution-logs/upload
    /// Coordinatorからのログファイルアップロードを受け付け、プロジェクトWD配下に保存
    /// 参照: docs/design/LOG_TRANSFER_DESIGN.md
    private func handleLogUpload(request: Request, context: AuthenticatedContext) async throws -> Response {
        // 1. coordinator_token認証
        guard let authHeader = request.headers[.authorization],
              authHeader.hasPrefix("Bearer ") else {
            debugLog("[Log Upload] Missing or invalid Authorization header")
            return errorResponse(status: .unauthorized, message: "Authorization header required")
        }

        let coordinatorToken = String(authHeader.dropFirst("Bearer ".count))

        // DBの設定を優先、環境変数をフォールバック
        var expectedToken: String?
        if let settings = try? appSettingsRepository.get() {
            expectedToken = settings.coordinatorToken
        }
        if expectedToken == nil || expectedToken?.isEmpty == true {
            expectedToken = ProcessInfo.processInfo.environment["COORDINATOR_TOKEN"]
        }

        guard let expected = expectedToken, !expected.isEmpty, coordinatorToken == expected else {
            debugLog("[Log Upload] Invalid coordinator_token")
            return errorResponse(status: .unauthorized, message: "Invalid coordinator token")
        }

        // 2. リクエストボディを取得（最大15MB: 10MBログ + メタデータ余裕）
        let maxBodySize = 15 * 1024 * 1024
        let body = try await request.body.collect(upTo: maxBodySize)
        guard let data = body.getData(at: 0, length: body.readableBytes) else {
            debugLog("[Log Upload] Empty request body")
            return errorResponse(status: .badRequest, message: "Empty request body")
        }

        // 3. multipart/form-dataをパース
        guard let contentType = request.headers[.contentType],
              contentType.contains("multipart/form-data") else {
            debugLog("[Log Upload] Content-Type must be multipart/form-data")
            return errorResponse(status: .badRequest, message: "Content-Type must be multipart/form-data")
        }

        // boundaryを抽出
        guard let boundaryRange = contentType.range(of: "boundary="),
              let boundary = contentType[boundaryRange.upperBound...].split(separator: ";").first else {
            debugLog("[Log Upload] Missing boundary in Content-Type")
            return errorResponse(status: .badRequest, message: "Missing boundary in Content-Type")
        }

        let formData = parseMultipartFormData(data: data, boundary: String(boundary))

        // 4. 必須フィールドを取得
        guard let executionLogId = formData.fields["execution_log_id"],
              let agentId = formData.fields["agent_id"],
              let taskId = formData.fields["task_id"],
              let projectId = formData.fields["project_id"],
              let logFileData = formData.files["log_file"] else {
            debugLog("[Log Upload] Missing required fields")
            return errorResponse(status: .badRequest, message: "Missing required fields: execution_log_id, agent_id, task_id, project_id, log_file")
        }

        let originalFilename = formData.fields["original_filename"] ?? formData.filenames["log_file"] ?? "execution.log"

        debugLog("[Log Upload] Received: exec=\(executionLogId), agent=\(agentId), project=\(projectId), file=\(originalFilename)")

        // 5. LogUploadServiceを使用してアップロード処理
        let service = LogUploadService(
            directoryManager: directoryManager,
            projectRepository: projectRepository,
            executionLogRepository: executionLogRepository
        )

        do {
            let result = try service.uploadLog(
                executionLogId: executionLogId,
                agentId: agentId,
                taskId: taskId,
                projectId: projectId,
                logData: logFileData,
                originalFilename: originalFilename
            )

            debugLog("[Log Upload] Success: \(result.logFilePath ?? "unknown")")

            let response = LogUploadResponse(
                success: true,
                executionLogId: executionLogId,
                logFilePath: result.logFilePath ?? "",
                fileSize: result.fileSize
            )
            return jsonResponse(response)
        } catch let error as LogUploadError {
            switch error {
            case .projectNotFound:
                return errorResponse(status: .notFound, message: "Project not found")
            case .workingDirectoryNotConfigured:
                return errorResponse(status: .notFound, message: "Project working directory not configured")
            case .fileTooLarge(let maxMB, let actualMB):
                return errorResponse(status: HTTPResponse.Status(code: 413), message: "Log file exceeds maximum size (\(maxMB)MB). Actual: \(String(format: "%.2f", actualMB))MB")
            case .fileWriteFailed(let underlyingError):
                debugLog("[Log Upload] File write failed: \(underlyingError)")
                return errorResponse(status: .internalServerError, message: "Failed to save log file")
            case .executionLogNotFound:
                return errorResponse(status: .notFound, message: "Execution log not found")
            case .notImplemented:
                return errorResponse(status: .internalServerError, message: "Not implemented")
            }
        } catch {
            debugLog("[Log Upload] Unexpected error: \(error)")
            return errorResponse(status: .internalServerError, message: "Internal server error")
        }
    }

    /// multipart/form-dataをパースする
    private func parseMultipartFormData(data: Data, boundary: String) -> MultipartFormData {
        var result = MultipartFormData()
        let boundaryData = "--\(boundary)".data(using: .utf8)!
        let endBoundaryData = "--\(boundary)--".data(using: .utf8)!

        // パートを分割
        var parts: [Data] = []
        var currentStart = 0

        // 最初のboundaryを見つける
        if let firstBoundaryRange = data.range(of: boundaryData) {
            currentStart = firstBoundaryRange.upperBound
        }

        while currentStart < data.count {
            // 次のboundaryを見つける
            let searchRange = currentStart..<data.count
            if let nextBoundaryRange = data.range(of: boundaryData, in: searchRange) {
                // CRLFをスキップ
                var partStart = currentStart
                if data.count > partStart + 1 && data[partStart] == 0x0D && data[partStart + 1] == 0x0A {
                    partStart += 2
                }
                // 末尾のCRLFを除去
                var partEnd = nextBoundaryRange.lowerBound
                if partEnd >= 2 && data[partEnd - 2] == 0x0D && data[partEnd - 1] == 0x0A {
                    partEnd -= 2
                }
                if partStart < partEnd {
                    parts.append(data.subdata(in: partStart..<partEnd))
                }
                currentStart = nextBoundaryRange.upperBound
            } else if let endRange = data.range(of: endBoundaryData, in: searchRange) {
                // 最後のパート
                var partStart = currentStart
                if data.count > partStart + 1 && data[partStart] == 0x0D && data[partStart + 1] == 0x0A {
                    partStart += 2
                }
                var partEnd = endRange.lowerBound
                if partEnd >= 2 && data[partEnd - 2] == 0x0D && data[partEnd - 1] == 0x0A {
                    partEnd -= 2
                }
                if partStart < partEnd {
                    parts.append(data.subdata(in: partStart..<partEnd))
                }
                break
            } else {
                break
            }
        }

        // 各パートをパース
        for part in parts {
            // ヘッダーとボディを分離（空行で区切り）
            let separatorData = "\r\n\r\n".data(using: .utf8)!
            guard let separatorRange = part.range(of: separatorData) else { continue }

            let headerData = part.subdata(in: 0..<separatorRange.lowerBound)
            let bodyData = part.subdata(in: separatorRange.upperBound..<part.count)

            guard let headerString = String(data: headerData, encoding: .utf8) else { continue }

            // Content-Dispositionからnameとfilenameを抽出
            var fieldName: String?
            var fileName: String?

            let lines = headerString.components(separatedBy: "\r\n")
            for line in lines {
                if line.lowercased().hasPrefix("content-disposition:") {
                    // name="..."を抽出
                    if let nameRange = line.range(of: "name=\"") {
                        let start = nameRange.upperBound
                        if let endQuote = line[start...].firstIndex(of: "\"") {
                            fieldName = String(line[start..<endQuote])
                        }
                    }
                    // filename="..."を抽出
                    if let filenameRange = line.range(of: "filename=\"") {
                        let start = filenameRange.upperBound
                        if let endQuote = line[start...].firstIndex(of: "\"") {
                            fileName = String(line[start..<endQuote])
                        }
                    }
                }
            }

            if let name = fieldName {
                if let fn = fileName {
                    // ファイルフィールド
                    result.files[name] = bodyData
                    result.filenames[name] = fn
                } else {
                    // テキストフィールド
                    if let textValue = String(data: bodyData, encoding: .utf8) {
                        result.fields[name] = textValue
                    }
                }
            }
        }

        return result
    }
}

/// multipart/form-dataのパース結果
private struct MultipartFormData {
    var fields: [String: String] = [:]
    var files: [String: Data] = [:]
    var filenames: [String: String] = [:]
}

// MARK: - Log Upload DTOs

/// ログアップロードレスポンス
/// 参照: docs/design/LOG_TRANSFER_DESIGN.md
struct LogUploadResponse: Encodable {
    let success: Bool
    let executionLogId: String
    let logFilePath: String
    let fileSize: Int

    enum CodingKeys: String, CodingKey {
        case success
        case executionLogId = "execution_log_id"
        case logFilePath = "log_file_path"
        case fileSize = "file_size"
    }
}

// MARK: - Auth DTOs

struct LoginRequest: Decodable {
    let agentId: String
    let passkey: String
}

struct LoginResponse: Encodable {
    let sessionToken: String
    let agent: AgentDTO
    let expiresAt: String
}

// MARK: - Task Permissions DTO

struct TaskPermissionsDTO: Encodable {
    let canEdit: Bool
    let canChangeStatus: Bool
    let canReassign: Bool
    let validStatusTransitions: [String]
    let reason: String?
}

// MARK: - Handoff DTOs

struct HandoffDTO: Encodable {
    let id: String
    let taskId: String
    let fromAgentId: String
    let toAgentId: String?
    let summary: String
    let context: String?
    let recommendations: String?
    let acceptedAt: String?
    let createdAt: String
    let isPending: Bool
    let isTargeted: Bool

    init(from handoff: Handoff) {
        self.id = handoff.id.value
        self.taskId = handoff.taskId.value
        self.fromAgentId = handoff.fromAgentId.value
        self.toAgentId = handoff.toAgentId?.value
        self.summary = handoff.summary
        self.context = handoff.context
        self.recommendations = handoff.recommendations
        self.acceptedAt = handoff.acceptedAt.map { ISO8601DateFormatter().string(from: $0) }
        self.createdAt = ISO8601DateFormatter().string(from: handoff.createdAt)
        self.isPending = handoff.isPending
        self.isTargeted = handoff.isTargeted
    }
}

struct CreateHandoffRequest: Decodable {
    let taskId: String
    let toAgentId: String?
    let summary: String
    let context: String?
    let recommendations: String?
}

// MARK: - Working Directory DTOs
// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.2

struct SetWorkingDirectoryRequest: Decodable {
    let workingDirectory: String
}

struct WorkingDirectoryDTO: Encodable {
    let workingDirectory: String
}
