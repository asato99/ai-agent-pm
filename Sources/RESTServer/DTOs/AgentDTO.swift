// Sources/RESTServer/DTOs/AgentDTO.swift
// AI Agent PM - REST API Server

import Foundation
import Domain

/// Agent data transfer object for REST API (list view)
public struct AgentDTO: Codable {
    let id: String
    let name: String
    let role: String
    let agentType: String
    let status: String
    let hierarchyType: String
    let parentAgentId: String?

    init(from agent: Agent) {
        self.id = agent.id.value
        self.name = agent.name
        self.role = agent.role
        self.agentType = agent.type.rawValue
        self.status = agent.status.rawValue
        self.hierarchyType = agent.hierarchyType.rawValue
        self.parentAgentId = agent.parentAgentId?.value
    }
}

/// Agent detail data transfer object for REST API (detail view)
/// Note: passkey and authLevel are intentionally excluded for security
public struct AgentDetailDTO: Codable {
    let id: String
    let name: String
    let role: String
    let agentType: String
    let status: String
    let hierarchyType: String
    let parentAgentId: String?
    let roleType: String
    let maxParallelTasks: Int
    let capabilities: [String]
    let systemPrompt: String?
    let kickMethod: String
    let provider: String?
    let modelId: String?
    let isLocked: Bool
    let createdAt: String
    let updatedAt: String

    init(from agent: Agent) {
        self.id = agent.id.value
        self.name = agent.name
        self.role = agent.role
        self.agentType = agent.type.rawValue
        self.status = agent.status.rawValue
        self.hierarchyType = agent.hierarchyType.rawValue
        self.parentAgentId = agent.parentAgentId?.value
        self.roleType = agent.roleType.rawValue
        self.maxParallelTasks = agent.maxParallelTasks
        self.capabilities = agent.capabilities
        self.systemPrompt = agent.systemPrompt
        self.kickMethod = agent.kickMethod.rawValue
        self.provider = agent.provider
        self.modelId = agent.modelId
        self.isLocked = agent.isLocked
        self.createdAt = ISO8601DateFormatter().string(from: agent.createdAt)
        self.updatedAt = ISO8601DateFormatter().string(from: agent.updatedAt)
    }
}

/// Request body for updating an agent
public struct UpdateAgentRequest: Decodable {
    let name: String?
    let role: String?
    let maxParallelTasks: Int?
    let capabilities: [String]?
    let systemPrompt: String?
    let status: String?
}
