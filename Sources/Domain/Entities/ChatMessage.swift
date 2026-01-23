// Sources/Domain/Entities/ChatMessage.swift
// Reference: docs/design/CHAT_FEATURE.md - Section 2.4

import Foundation

/// Chat message entity with dual storage model
/// Each agent stores messages in their own storage file
/// - Sender's storage: includes receiverId
/// - Receiver's storage: receiverId is nil
public struct ChatMessage: Identifiable, Equatable, Sendable, Codable {
    public let id: ChatMessageID
    /// Sender's agent ID
    public let senderId: AgentID
    /// Receiver's agent ID (only in sender's storage)
    public let receiverId: AgentID?
    public let content: String
    public let createdAt: Date

    /// Related task ID (optional)
    public let relatedTaskId: TaskID?
    /// Related handoff ID (optional)
    public let relatedHandoffId: HandoffID?
    /// Related conversation ID (optional, for AI-to-AI conversations)
    /// Reference: docs/design/AI_TO_AI_CONVERSATION.md
    public let conversationId: ConversationID?

    public init(
        id: ChatMessageID,
        senderId: AgentID,
        receiverId: AgentID? = nil,
        content: String,
        createdAt: Date = Date(),
        relatedTaskId: TaskID? = nil,
        relatedHandoffId: HandoffID? = nil,
        conversationId: ConversationID? = nil
    ) {
        self.id = id
        self.senderId = senderId
        self.receiverId = receiverId
        self.content = content
        self.createdAt = createdAt
        self.relatedTaskId = relatedTaskId
        self.relatedHandoffId = relatedHandoffId
        self.conversationId = conversationId
    }

    /// Check if this message was sent by the given agent
    /// - Parameter agentId: Agent ID to check
    /// - Returns: true if senderId matches
    public func isSentBy(_ agentId: AgentID) -> Bool {
        senderId == agentId
    }

    /// Check if this message was received by the given agent
    /// (i.e., the message is from someone else)
    /// - Parameter agentId: Agent ID to check
    /// - Returns: true if senderId does NOT match
    public func isReceivedBy(_ agentId: AgentID) -> Bool {
        senderId != agentId
    }

    /// Create a copy without receiverId (for receiver's storage)
    public func withoutReceiverId() -> ChatMessage {
        ChatMessage(
            id: id,
            senderId: senderId,
            receiverId: nil,
            content: content,
            createdAt: createdAt,
            relatedTaskId: relatedTaskId,
            relatedHandoffId: relatedHandoffId,
            conversationId: conversationId
        )
    }
}
