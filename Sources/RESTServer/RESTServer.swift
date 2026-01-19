// Sources/RESTServer/RESTServer.swift
// AI Agent PM - REST API Server

import Foundation
import Hummingbird
import GRDB
import Infrastructure
import UseCase
import Domain

// Debug logging helper
private func debugLog(_ message: String) {
    let line = "[RESTServer] \(message)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
}

/// REST API Server for web-ui
public final class RESTServer {
    private let database: DatabaseQueue
    private let port: Int
    private let webUIPath: String?

    // Repositories
    private let projectRepository: ProjectRepository
    private let agentRepository: AgentRepository
    private let taskRepository: TaskRepository
    private let sessionRepository: AgentSessionRepository
    private let credentialRepository: AgentCredentialRepository

    /// Initialize the REST server
    /// - Parameters:
    ///   - database: Database connection
    ///   - port: HTTP port (default: 8080)
    ///   - webUIPath: Path to web-ui static files directory (optional, enables static file serving)
    public init(database: DatabaseQueue, port: Int = 8080, webUIPath: String? = nil) {
        self.database = database
        self.port = port
        self.webUIPath = webUIPath

        // Initialize repositories
        self.projectRepository = ProjectRepository(database: database)
        self.agentRepository = AgentRepository(database: database)
        self.taskRepository = TaskRepository(database: database)
        self.sessionRepository = AgentSessionRepository(database: database)
        self.credentialRepository = AgentCredentialRepository(database: database)
    }

    public func run() async throws {
        debugLog("run() starting")

        // Create router with custom context
        let router = Router(context: AuthenticatedContext.self)
        debugLog("Router created")

        // Add CORS middleware
        router.add(middleware: CORSMiddleware())
        debugLog("CORS middleware added")

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

            // Catch-all for files and SPA (must be after specific routes)
            router.get("/**") { request, context in
                let pathComponents = context.parameters.getCatchAll()
                let path = pathComponents.joined(separator: "/")
                debugLog("Catch-all handler for: \(path)")

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
            debugLog("Catch-all route registered")
        } else {
            debugLog("No webUIPath provided, static files disabled")
        }

        debugLog("Creating Application...")
        // Create and run application
        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )

        debugLog("Server about to start on http://127.0.0.1:\(port)")
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

        // Tasks under projects
        let projectTaskRouter = projectRouter.group(":projectId").group("tasks")
        projectTaskRouter.get { [self] request, context in
            try await listTasks(request: request, context: context)
        }
        projectTaskRouter.post { [self] request, context in
            try await createTask(request: request, context: context)
        }

        // Direct task access
        let taskRouter = protectedRouter.group("tasks")
        taskRouter.get(":taskId") { [self] request, context in
            try await getTask(request: request, context: context)
        }
        taskRouter.patch(":taskId") { [self] request, context in
            try await updateTask(request: request, context: context)
        }
        taskRouter.delete(":taskId") { [self] request, context in
            try await deleteTask(request: request, context: context)
        }

        // Agents
        let agentRouter = protectedRouter.group("agents")
        agentRouter.get("assignable") { [self] request, context in
            try await listAssignableAgents(request: request, context: context)
        }
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

        let projects = try projectRepository.findAll()
        var summaries: [ProjectSummaryDTO] = []

        for project in projects {
            let tasks = try taskRepository.findByProject(project.id, status: nil)
            let counts = calculateTaskCounts(tasks: tasks, agentId: agentId)
            summaries.append(ProjectSummaryDTO(from: project, taskCounts: counts.counts, myTaskCount: counts.myTasks))
        }

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
        let summary = ProjectSummaryDTO(from: project, taskCounts: counts.counts, myTaskCount: counts.myTasks)

        return jsonResponse(summary)
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
        guard context.agentId != nil else {
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
            id: TaskID(value: UUID().uuidString),
            projectId: projectId,
            title: createRequest.title,
            description: createRequest.description ?? "",
            status: .backlog,
            priority: createRequest.priority.flatMap { TaskPriority(rawValue: $0) } ?? .medium,
            assigneeId: createRequest.assigneeId.map { AgentID(value: $0) },
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

    // MARK: - Agent Handlers

    private func listAssignableAgents(request: Request, context: AuthenticatedContext) async throws -> Response {
        let agents = try agentRepository.findAll()
        let assignable = agents.filter { $0.status == .active }
        let dtos = assignable.map { AgentDTO(from: $0) }
        return jsonResponse(dtos)
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
