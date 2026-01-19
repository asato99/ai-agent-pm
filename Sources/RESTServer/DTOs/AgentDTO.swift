// Sources/RESTServer/DTOs/AgentDTO.swift
// AI Agent PM - REST API Server

import Foundation
import Domain

/// Agent data transfer object for REST API
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
