import Foundation
import Hummingbird
import GRDB
import Infrastructure
import UseCase
import Domain

extension RESTServer {

    // MARK: - Task Handlers


    func listTasks(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func calculateDependentTasks(tasks: [Domain.Task]) -> [String: [String]] {
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

    func createTask(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func getTask(request: Request, context: AuthenticatedContext) async throws -> Response {
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

    func updateTask(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func deleteTask(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func getTaskPermissions(request: Request, context: AuthenticatedContext) async throws -> Response {
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

}
