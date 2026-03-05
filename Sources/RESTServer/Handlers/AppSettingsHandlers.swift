// Sources/RESTServer/Handlers/AppSettingsHandlers.swift
// Settings REST API endpoints

import Foundation
import Hummingbird
import Domain
import Infrastructure
import UseCase

// MARK: - Settings DTO

struct AppSettingsDTO: Encodable {
    let coordinatorTokenSet: Bool
    let coordinatorTokenMasked: String?
    let pendingPurposeTTLSeconds: Int
    let allowRemoteAccess: Bool
    let agentBasePrompt: String?
    let updatedAt: String
}

struct PatchSettingsRequest: Decodable {
    let allowRemoteAccess: Bool?
    let agentBasePrompt: String?
    let pendingPurposeTTLSeconds: Int?
}

// MARK: - Settings Handlers (Session Auth)

extension RESTServer {

    /// GET /api/settings - Get current settings (token is masked)
    func getSettings(request: Request, context: AuthenticatedContext) async throws -> Response {
        let settings = try appSettingsRepository.get()
        let dto = makeSettingsDTO(settings)
        return jsonResponse(dto)
    }

    /// PATCH /api/settings - Partially update settings
    func patchSettings(request: Request, context: AuthenticatedContext) async throws -> Response {
        let body = try await request.body.collect(upTo: 64 * 1024)
        guard let data = body.getData(at: 0, length: body.readableBytes) else {
            return errorResponse(status: .badRequest, message: "Empty request body")
        }

        let patch: PatchSettingsRequest
        do {
            patch = try JSONDecoder().decode(PatchSettingsRequest.self, from: data)
        } catch {
            return errorResponse(status: .badRequest, message: "Invalid JSON: \(error.localizedDescription)")
        }

        var settings = try appSettingsRepository.get()

        if let allowRemoteAccess = patch.allowRemoteAccess {
            settings = settings.withAllowRemoteAccess(allowRemoteAccess)
        }
        if let agentBasePrompt = patch.agentBasePrompt {
            settings = settings.withAgentBasePrompt(agentBasePrompt.isEmpty ? nil : agentBasePrompt)
        }
        if let ttl = patch.pendingPurposeTTLSeconds {
            guard ttl > 0 else {
                return errorResponse(status: .badRequest, message: "pendingPurposeTTLSeconds must be positive")
            }
            settings = settings.withPendingPurposeTTL(ttl)
        }

        try appSettingsRepository.save(settings)
        let dto = makeSettingsDTO(settings)
        return jsonResponse(dto)
    }

    /// POST /api/settings/regenerate-token - Regenerate coordinator token
    func regenerateToken(request: Request, context: AuthenticatedContext) async throws -> Response {
        var settings = try appSettingsRepository.get()
        settings = settings.regenerateCoordinatorToken()
        try appSettingsRepository.save(settings)
        let dto = makeSettingsDTO(settings)
        return jsonResponse(dto)
    }

    /// DELETE /api/settings/coordinator-token - Clear coordinator token
    func clearCoordinatorToken(request: Request, context: AuthenticatedContext) async throws -> Response {
        var settings = try appSettingsRepository.get()
        settings = settings.clearCoordinatorToken()
        try appSettingsRepository.save(settings)
        let dto = makeSettingsDTO(settings)
        return jsonResponse(dto)
    }

    // MARK: - Helpers

    private func makeSettingsDTO(_ settings: AppSettings) -> AppSettingsDTO {
        let tokenSet = settings.coordinatorToken != nil && !settings.coordinatorToken!.isEmpty
        let masked: String?
        if let token = settings.coordinatorToken, !token.isEmpty {
            let suffix = String(token.suffix(4))
            masked = "****\(suffix)"
        } else {
            masked = nil
        }

        let formatter = ISO8601DateFormatter()
        return AppSettingsDTO(
            coordinatorTokenSet: tokenSet,
            coordinatorTokenMasked: masked,
            pendingPurposeTTLSeconds: settings.pendingPurposeTTLSeconds,
            allowRemoteAccess: settings.allowRemoteAccess,
            agentBasePrompt: settings.agentBasePrompt,
            updatedAt: formatter.string(from: settings.updatedAt)
        )
    }
}

// MARK: - Coordinator Config API (coordinator_token Auth)

struct CoordinatorConfigDTO: Encodable {
    let server_url: String
    let coordinator_token: String
    let root_agent_id: String?
    let polling_interval: Int
    let max_concurrent: Int
    let agents: [String: AgentConfigDTO]
    let ai_providers: [String: AIProviderConfigDTO]
    let agent_base_prompt: String?
}

struct AgentConfigDTO: Encodable {
    let passkey: String?
}

struct AIProviderConfigDTO: Encodable {
    let cli_command: String
    let cli_args: [String]
}

extension RESTServer {

    /// GET /api/coordinator/config - Get coordinator configuration (coordinator_token auth)
    func getCoordinatorConfig(request: Request, context: AuthenticatedContext) async throws -> Response {
        // 1. coordinator_token authentication (same pattern as MCPTransport.swift)
        guard let authHeader = request.headers[.authorization],
              authHeader.hasPrefix("Bearer ") else {
            return errorResponse(status: .unauthorized, message: "Authorization header required")
        }

        let coordinatorToken = String(authHeader.dropFirst("Bearer ".count))

        var expectedToken: String?
        if let settings = try? appSettingsRepository.get() {
            expectedToken = settings.coordinatorToken
        }
        if expectedToken == nil || expectedToken?.isEmpty == true {
            expectedToken = ProcessInfo.processInfo.environment["COORDINATOR_TOKEN"]
        }

        guard let expected = expectedToken, !expected.isEmpty, coordinatorToken == expected else {
            return errorResponse(status: .unauthorized, message: "Invalid coordinator token")
        }

        // 2. Load settings
        let settings = try appSettingsRepository.get()

        // 3. Determine root_agent_id and target agents
        let rootAgentIdParam = request.uri.queryParameters.get("root_agent_id")
        let rootAgentId: AgentID? = rootAgentIdParam.map { AgentID(value: $0) }

        let targetAgents: [Agent]
        if let rootId = rootAgentId {
            let useCase = GetManagedAgentsUseCase(agentRepository: agentRepository)
            do {
                targetAgents = try useCase.execute(rootAgentId: rootId)
            } catch {
                return errorResponse(status: .badRequest, message: "Failed to get managed agents: \(error.localizedDescription)")
            }
        } else {
            targetAgents = (try? agentRepository.findAll()) ?? []
        }

        // 4. Build agents dict with passkeys
        var agentsDict: [String: AgentConfigDTO] = [:]
        for agent in targetAgents {
            let credential = try? credentialRepository.findByAgentId(agent.id)
            agentsDict[agent.id.value] = AgentConfigDTO(passkey: credential?.rawPasskey)
        }

        // 5. Derive server_url from request Host/authority
        let host = request.head.authority ?? "localhost:\(port)"
        let scheme = "http" // coordinator connections are typically HTTP within LAN
        let serverUrl = "\(scheme)://\(host)"

        // 6. Build response
        let config = CoordinatorConfigDTO(
            server_url: serverUrl,
            coordinator_token: coordinatorToken,
            root_agent_id: rootAgentIdParam,
            polling_interval: 10,
            max_concurrent: 3,
            agents: agentsDict,
            ai_providers: [
                "claude": AIProviderConfigDTO(
                    cli_command: "claude",
                    cli_args: ["--dangerously-skip-permissions", "--max-turns", "50", "--verbose"]
                ),
                "gemini": AIProviderConfigDTO(
                    cli_command: "gemini",
                    cli_args: ["-y", "-d"]
                )
            ],
            agent_base_prompt: settings.agentBasePrompt
        )

        return jsonResponse(config)
    }
}
