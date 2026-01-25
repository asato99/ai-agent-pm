// Sources/RESTServer/DTOs/ContextDTO.swift
// AI Agent PM - REST API Server
//
// 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md

import Foundation
import Domain

/// Task context data transfer object for REST API
/// Note: Uses Swift's default camelCase JSON encoding
public struct ContextDTO: Codable {
    let id: String
    let agentId: String
    let agentName: String
    let sessionId: String
    let progress: String?
    let findings: String?
    let blockers: String?
    let nextSteps: String?
    let createdAt: String
    let updatedAt: String

    /// Create DTO from domain model
    /// - Parameters:
    ///   - context: The domain context
    ///   - agentName: The name of the agent (resolved separately)
    init(from context: Context, agentName: String) {
        self.id = context.id.value
        self.agentId = context.agentId.value
        self.agentName = agentName
        self.sessionId = context.sessionId.value
        self.progress = context.progress
        self.findings = context.findings
        self.blockers = context.blockers
        self.nextSteps = context.nextSteps
        self.createdAt = ISO8601DateFormatter().string(from: context.createdAt)
        self.updatedAt = ISO8601DateFormatter().string(from: context.updatedAt)
    }
}

/// Response wrapper for contexts list
public struct ContextsResponseDTO: Codable {
    let contexts: [ContextDTO]
}
