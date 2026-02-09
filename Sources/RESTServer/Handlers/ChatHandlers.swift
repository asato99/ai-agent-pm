import Foundation
import Hummingbird
import GRDB
import Infrastructure
import UseCase
import Domain

extension RESTServer {

    // MARK: - Chat Handlers

    // 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 1-2

    /// GET /projects/:projectId/agents/:agentId/chat/messages
    /// Query params: limit (default 50, max 200), after, before (cursor-based pagination)
    func getChatMessages(request: Request, context: AuthenticatedContext) async throws -> Response {
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

            // 自動既読更新: チャット画面を開いたとき、相手からのメッセージを既読にマーク
            // Reference: docs/plan/UNREAD_MESSAGE_REFACTOR_TDD.md - Phase 4
            try chatRepository.markAsRead(
                projectId: projectId,
                currentAgentId: currentAgentId,
                senderAgentId: targetAgentId
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
    func sendChatMessage(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func getUnreadCounts(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func markChatAsRead(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func startChatSession(request: Request, context: AuthenticatedContext) async throws -> Response {
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
            // Create a system message to trigger WorkDetectionService.hasChatWork
            // Reference: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 2.2
            let systemMessage = ChatMessage(
                id: ChatMessageID.generate(),
                senderId: AgentID(value: "system"),
                receiverId: nil,
                content: "セッション開始",
                createdAt: Date()
            )
            try chatRepository.saveMessage(systemMessage, projectId: projectId, agentId: targetAgentId)

            debugLog("startChatSession: Created system message, Coordinator will spawn agent=\(agentIdStr), project=\(projectIdStr)")
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
    func endChatSession(request: Request, context: AuthenticatedContext) async throws -> Response {
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
    func jsonResponse<T: Encodable>(_ value: T, status: HTTPResponse.Status) -> Response {
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

}
