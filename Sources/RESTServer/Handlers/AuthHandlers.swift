import Foundation
import Hummingbird
import GRDB
import Infrastructure
import UseCase
import Domain

extension RESTServer {

    // MARK: - Auth Handlers

    func handleLogin(request: Request, context: AuthenticatedContext) async throws -> Response {
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

    func handleLogout(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let token = context.sessionToken else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }
        try sessionRepository.deleteByToken(token)
        return jsonResponse(["success": true])
    }

    func handleMe(request: Request, context: AuthenticatedContext) async throws -> Response {
        guard let agentId = context.agentId else {
            return errorResponse(status: .unauthorized, message: "Not authenticated")
        }
        guard let agent = try agentRepository.findById(agentId) else {
            return errorResponse(status: .notFound, message: "Agent not found")
        }
        return jsonResponse(AgentDTO(from: agent))
    }

}
