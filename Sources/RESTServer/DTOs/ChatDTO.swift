// Sources/RESTServer/DTOs/ChatDTO.swift
// AI Agent PM - REST API Server
// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 1-2

import Foundation
import Domain

/// Chat message data transfer object for REST API
public struct ChatMessageDTO: Codable {
    public let id: String
    public let sender: String
    public let content: String
    public let createdAt: String
    public let relatedTaskId: String?

    public init(from message: ChatMessage) {
        self.id = message.id.value
        self.sender = message.sender.rawValue
        self.content = message.content
        self.createdAt = ISO8601DateFormatter().string(from: message.createdAt)
        self.relatedTaskId = message.relatedTaskId?.value
    }
}

/// Response for GET /projects/:projectId/agents/:agentId/chat/messages
public struct ChatMessagesResponse: Codable {
    public let messages: [ChatMessageDTO]
    public let hasMore: Bool
    public let totalCount: Int?

    public init(messages: [ChatMessageDTO], hasMore: Bool, totalCount: Int? = nil) {
        self.messages = messages
        self.hasMore = hasMore
        self.totalCount = totalCount
    }
}

/// Request body for POST /projects/:projectId/agents/:agentId/chat/messages
public struct SendMessageRequest: Decodable {
    public let content: String
    public let relatedTaskId: String?
}

/// Response for validation errors
public struct ChatValidationError: Codable {
    public let error: String
    public let code: String
    public let details: ChatValidationErrorDetails?
}

/// Details for validation errors
public struct ChatValidationErrorDetails: Codable {
    public let maxLength: Int?
    public let actualLength: Int?
}
