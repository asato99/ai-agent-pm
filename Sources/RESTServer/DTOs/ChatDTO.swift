// Sources/RESTServer/DTOs/ChatDTO.swift
// AI Agent PM - REST API Server
// Reference: docs/design/CHAT_FEATURE.md - Section 11.4

import Foundation
import Domain

/// Chat message data transfer object for REST API
/// Uses senderId/receiverId instead of sender type
public struct ChatMessageDTO: Codable {
    public let id: String
    public let senderId: String
    public let receiverId: String?
    public let content: String
    public let createdAt: String
    public let relatedTaskId: String?

    public init(from message: ChatMessage) {
        self.id = message.id.value
        self.senderId = message.senderId.value
        self.receiverId = message.receiverId?.value
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
/// Note: The receiverId comes from the URL path (agentId parameter)
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

/// Response for GET /projects/:projectId/unread-counts
/// Reference: docs/design/CHAT_FEATURE.md - Unread count feature
public struct UnreadCountsResponse: Codable {
    /// Agent ID -> unread message count mapping
    public let counts: [String: Int]

    public init(counts: [String: Int]) {
        self.counts = counts
    }
}
