// Tests/DomainTests/ChatMessageTests.swift
// ChatMessage entity tests for dual storage model
// Reference: docs/plan/CHAT_DUAL_STORAGE_IMPLEMENTATION.md - Phase 1

import XCTest
@testable import Domain

final class ChatMessageTests: XCTestCase {

    // MARK: - Basic Properties

    func testChatMessageHasSenderId() {
        let message = ChatMessage(
            id: ChatMessageID(value: "msg-1"),
            senderId: AgentID(value: "owner-1"),
            receiverId: AgentID(value: "worker-1"),
            content: "Hello"
        )

        XCTAssertEqual(message.senderId.value, "owner-1")
    }

    func testChatMessageHasReceiverId() {
        let message = ChatMessage(
            id: ChatMessageID(value: "msg-1"),
            senderId: AgentID(value: "owner-1"),
            receiverId: AgentID(value: "worker-1"),
            content: "Hello"
        )

        XCTAssertEqual(message.receiverId?.value, "worker-1")
    }

    func testChatMessageReceiverIdIsOptional() {
        // Receiver storage does not have receiverId
        let message = ChatMessage(
            id: ChatMessageID(value: "msg-1"),
            senderId: AgentID(value: "owner-1"),
            receiverId: nil,
            content: "Hello"
        )

        XCTAssertNil(message.receiverId)
    }

    // MARK: - Sender/Receiver Identification

    func testIsSentBy_WhenSenderIdMatches_ReturnsTrue() {
        let myAgentId = AgentID(value: "owner-1")
        let message = ChatMessage(
            id: ChatMessageID(value: "msg-1"),
            senderId: AgentID(value: "owner-1"),
            receiverId: AgentID(value: "worker-1"),
            content: "Hello"
        )

        XCTAssertTrue(message.isSentBy(myAgentId))
    }

    func testIsSentBy_WhenSenderIdDoesNotMatch_ReturnsFalse() {
        let myAgentId = AgentID(value: "worker-1")
        let message = ChatMessage(
            id: ChatMessageID(value: "msg-1"),
            senderId: AgentID(value: "owner-1"),
            receiverId: AgentID(value: "worker-1"),
            content: "Hello"
        )

        XCTAssertFalse(message.isSentBy(myAgentId))
    }

    func testIsReceivedBy_WhenSenderIdDoesNotMatch_ReturnsTrue() {
        let myAgentId = AgentID(value: "worker-1")
        let message = ChatMessage(
            id: ChatMessageID(value: "msg-1"),
            senderId: AgentID(value: "owner-1"),
            receiverId: nil,  // Receiver's storage doesn't have receiverId
            content: "Hello"
        )

        XCTAssertTrue(message.isReceivedBy(myAgentId))
    }

    func testIsReceivedBy_WhenSenderIdMatches_ReturnsFalse() {
        let myAgentId = AgentID(value: "owner-1")
        let message = ChatMessage(
            id: ChatMessageID(value: "msg-1"),
            senderId: AgentID(value: "owner-1"),
            receiverId: AgentID(value: "worker-1"),
            content: "Hello"
        )

        XCTAssertFalse(message.isReceivedBy(myAgentId))
    }

    // MARK: - Codable

    func testChatMessageEncodesWithSenderId() throws {
        let message = ChatMessage(
            id: ChatMessageID(value: "msg-1"),
            senderId: AgentID(value: "owner-1"),
            receiverId: AgentID(value: "worker-1"),
            content: "Hello",
            createdAt: Date(timeIntervalSince1970: 1705827600) // Fixed date for testing
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)
        let jsonString = String(data: data, encoding: .utf8)!

        // ID types encode as objects with "value" property
        XCTAssertTrue(jsonString.contains("\"senderId\":{\"value\":\"owner-1\"}"))
        XCTAssertTrue(jsonString.contains("\"receiverId\":{\"value\":\"worker-1\"}"))
        XCTAssertFalse(jsonString.contains("\"sender\":"))
    }

    func testChatMessageDecodesWithSenderId() throws {
        // ID types encode as objects with "value" property
        let json = """
        {
            "id": {"value": "msg-1"},
            "senderId": {"value": "owner-1"},
            "receiverId": {"value": "worker-1"},
            "content": "Hello",
            "createdAt": "2026-01-21T10:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(ChatMessage.self, from: data)

        XCTAssertEqual(message.senderId.value, "owner-1")
        XCTAssertEqual(message.receiverId?.value, "worker-1")
    }

    func testChatMessageDecodesWithoutReceiverId() throws {
        // ID types encode as objects with "value" property
        let json = """
        {
            "id": {"value": "msg-1"},
            "senderId": {"value": "owner-1"},
            "content": "Hello",
            "createdAt": "2026-01-21T10:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(ChatMessage.self, from: data)

        XCTAssertEqual(message.senderId.value, "owner-1")
        XCTAssertNil(message.receiverId)
    }

    // MARK: - Related IDs

    func testChatMessageWithRelatedTaskId() {
        let message = ChatMessage(
            id: ChatMessageID(value: "msg-1"),
            senderId: AgentID(value: "owner-1"),
            receiverId: AgentID(value: "worker-1"),
            content: "Check this task",
            relatedTaskId: TaskID(value: "task-123")
        )

        XCTAssertEqual(message.relatedTaskId?.value, "task-123")
    }

    func testChatMessageWithRelatedHandoffId() {
        let message = ChatMessage(
            id: ChatMessageID(value: "msg-1"),
            senderId: AgentID(value: "owner-1"),
            receiverId: AgentID(value: "worker-1"),
            content: "Handoff received",
            relatedHandoffId: HandoffID(value: "handoff-456")
        )

        XCTAssertEqual(message.relatedHandoffId?.value, "handoff-456")
    }

    // MARK: - Conversation ID (UC016: AI-to-AI Conversation)

    func testChatMessageWithConversationId() {
        let convId = ConversationID(value: "conv-001")
        let message = ChatMessage(
            id: ChatMessageID(value: "msg-1"),
            senderId: AgentID(value: "agent-a"),
            receiverId: AgentID(value: "agent-b"),
            content: "りんご",
            conversationId: convId
        )

        XCTAssertEqual(message.conversationId?.value, "conv-001")
    }

    func testChatMessageConversationIdIsOptional() {
        let message = ChatMessage(
            id: ChatMessageID(value: "msg-1"),
            senderId: AgentID(value: "agent-a"),
            receiverId: AgentID(value: "agent-b"),
            content: "テスト"
        )

        XCTAssertNil(message.conversationId)
    }

    func testChatMessageWithoutReceiverIdPreservesConversationId() {
        let convId = ConversationID(value: "conv-001")
        let message = ChatMessage(
            id: ChatMessageID(value: "msg-1"),
            senderId: AgentID(value: "agent-a"),
            receiverId: AgentID(value: "agent-b"),
            content: "テスト",
            conversationId: convId
        )

        let withoutReceiver = message.withoutReceiverId()

        XCTAssertNil(withoutReceiver.receiverId)
        XCTAssertEqual(withoutReceiver.conversationId?.value, "conv-001")
    }

    func testChatMessageEncodesConversationId() throws {
        let message = ChatMessage(
            id: ChatMessageID(value: "msg-1"),
            senderId: AgentID(value: "agent-a"),
            receiverId: AgentID(value: "agent-b"),
            content: "テスト",
            createdAt: Date(timeIntervalSince1970: 1705827600),
            conversationId: ConversationID(value: "conv-001")
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"conversationId\":{\"value\":\"conv-001\"}"))
    }

    func testChatMessageDecodesConversationId() throws {
        let json = """
        {
            "id": {"value": "msg-1"},
            "senderId": {"value": "agent-a"},
            "receiverId": {"value": "agent-b"},
            "content": "テスト",
            "createdAt": "2026-01-23T10:00:00Z",
            "conversationId": {"value": "conv-001"}
        }
        """
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(ChatMessage.self, from: data)

        XCTAssertEqual(message.conversationId?.value, "conv-001")
    }
}
