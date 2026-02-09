import Foundation
import Hummingbird
import GRDB
import Infrastructure
import UseCase
import Domain

extension RESTServer {

    // MARK: - Handoff Handlers


    /// GET /api/handoffs - 自分宛ての未処理ハンドオフ一覧
    func listHandoffs(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        let handoffs = try handoffRepository.findPending(agentId: agentId)
        let dtos = handoffs.map { HandoffDTO(from: $0) }
        return jsonResponse(dtos)
    }

    /// POST /api/handoffs - ハンドオフ作成
    func createHandoff(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func acceptHandoff(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func listTaskHandoffs(request: Request, context: AuthenticatedContext) async throws -> Response {
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

}
