import Foundation
import Hummingbird
import GRDB
import Infrastructure
import UseCase
import Domain

extension RESTServer {

    // MARK: - Agent Handlers


    /// GET /api/agents/assignable (deprecated - use /projects/:projectId/assignable-agents)
    func listAssignableAgents(request: Request, context: AuthenticatedContext) async throws -> Response {
        // Legacy endpoint: returns all active agents
        // Note: This endpoint doesn't filter by project. Use /projects/:projectId/assignable-agents instead.
        let agents = try agentRepository.findAll()
        let assignable = agents.filter { $0.status == .active }
        let dtos = assignable.map { AgentDTO(from: $0) }
        return jsonResponse(dtos)
    }

    /// GET /api/projects/:projectId/assignable-agents - プロジェクトに割り当て可能なエージェント一覧
    /// According to requirements (PROJECTS.md): Task assignees must be agents assigned to the project
    func listProjectAssignableAgents(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func listProjectAgentSessions(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func listSubordinates(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }

        // 直下だけでなく、全ての下位エージェントを再帰的に取得
        let subordinates = try agentRepository.findAllDescendants(agentId)
        let dtos = subordinates.map { AgentDTO(from: $0) }
        return jsonResponse(dtos)
    }

    /// GET /api/agents/:agentId - エージェント詳細取得（自分または部下のみ）
    func getAgent(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func updateAgent(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func canAccessAgent(currentAgentId: AgentID, targetAgentId: AgentID) throws -> Bool {
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
    func canChatWithAgent(currentAgentId: AgentID, targetAgentId: AgentID, projectId: ProjectID) throws -> Bool {
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

}
