// Sources/RestServer/DTOs/SkillDTO.swift
// AI Agent PM - REST API Server
// スキル関連のDTO
// 参照: docs/design/AGENT_SKILLS.md

import Foundation
import Domain

/// Skill data transfer object for REST API
public struct SkillDTO: Codable {
    let id: String
    let name: String
    let description: String
    let directoryName: String
    let createdAt: String
    let updatedAt: String

    init(from skill: SkillDefinition) {
        self.id = skill.id.value
        self.name = skill.name
        self.description = skill.description
        self.directoryName = skill.directoryName
        self.createdAt = ISO8601DateFormatter().string(from: skill.createdAt)
        self.updatedAt = ISO8601DateFormatter().string(from: skill.updatedAt)
    }
}

/// Request body for registering a new skill
public struct RegisterSkillRequest: Decodable {
    let skillMdContent: String?
    let name: String?
    let directoryName: String?
    let description: String?
}

/// Response for skill registration
public struct RegisterSkillResponse: Encodable {
    let status: String
    let skill: SkillDTO
}

/// Request body for assigning skills to an agent
public struct AssignSkillsRequest: Decodable {
    let skillIds: [String]
}

/// Response for agent skills
public struct AgentSkillsResponse: Encodable {
    let agentId: String
    let skills: [SkillDTO]
}
