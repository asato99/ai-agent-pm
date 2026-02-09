import Foundation
import Hummingbird
import GRDB
import Infrastructure
import UseCase
import Domain

extension RESTServer {

    // MARK: - Task Request/Approval Handlers

    // 参照: docs/design/TASK_REQUEST_APPROVAL.md

    /// POST /api/tasks/request - タスク依頼作成
    func requestTask(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func getPendingTasks(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func approveTask(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func rejectTask(request: Request, context: AuthenticatedContext) async throws -> Response {
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

}
