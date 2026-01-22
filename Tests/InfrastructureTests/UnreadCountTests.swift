// Tests/InfrastructureTests/UnreadCountTests.swift
// TDD RED: 未読メッセージカウント機能のテスト
// Reference: docs/design/CHAT_FEATURE.md

import XCTest
@testable import Domain
@testable import Infrastructure

final class UnreadCountTests: XCTestCase {

    // Test agent IDs
    private let myAgentId = AgentID(value: "agt_me")
    private let worker1Id = AgentID(value: "agt_worker1")
    private let worker2Id = AgentID(value: "agt_worker2")

    // MARK: - calculateUnreadCountsBySender

    func testCalculateUnreadCountsBySender_ReturnsCountPerSender() {
        // Given: Messages from 2 different senders after my last message
        let messages = [
            createMessage(id: "1", senderId: myAgentId, offset: 0),      // me
            createMessage(id: "2", senderId: worker1Id, offset: 1),      // worker1
            createMessage(id: "3", senderId: worker1Id, offset: 2),      // worker1
            createMessage(id: "4", senderId: worker1Id, offset: 3),      // worker1
            createMessage(id: "5", senderId: worker2Id, offset: 4),      // worker2
        ]

        // When: Calculate unread counts by sender
        let counts = UnreadCountCalculator.calculateBySender(messages, agentId: myAgentId)

        // Then: Returns count per sender
        XCTAssertEqual(counts[worker1Id.value], 3)
        XCTAssertEqual(counts[worker2Id.value], 1)
        XCTAssertNil(counts[myAgentId.value]) // My own messages should not be counted
    }

    func testCalculateUnreadCountsBySender_NoUnread_ReturnsEmptyDictionary() {
        // Given: My last message is the latest
        let messages = [
            createMessage(id: "1", senderId: worker1Id, offset: 0),
            createMessage(id: "2", senderId: myAgentId, offset: 1),
        ]

        // When: Calculate unread counts
        let counts = UnreadCountCalculator.calculateBySender(messages, agentId: myAgentId)

        // Then: Empty dictionary (no unread)
        XCTAssertTrue(counts.isEmpty)
    }

    func testCalculateUnreadCountsBySender_EmptyMessages_ReturnsEmptyDictionary() {
        // Given: No messages
        let messages: [ChatMessage] = []

        // When: Calculate unread counts
        let counts = UnreadCountCalculator.calculateBySender(messages, agentId: myAgentId)

        // Then: Empty dictionary
        XCTAssertTrue(counts.isEmpty)
    }

    func testCalculateUnreadCountsBySender_AllFromOthers_AllUnread() {
        // Given: No messages from me (all unread)
        let messages = [
            createMessage(id: "1", senderId: worker1Id, offset: 0),
            createMessage(id: "2", senderId: worker1Id, offset: 1),
            createMessage(id: "3", senderId: worker2Id, offset: 2),
        ]

        // When: Calculate unread counts
        let counts = UnreadCountCalculator.calculateBySender(messages, agentId: myAgentId)

        // Then: All messages are unread
        XCTAssertEqual(counts[worker1Id.value], 2)
        XCTAssertEqual(counts[worker2Id.value], 1)
    }

    func testCalculateUnreadCountsBySender_MessagesBeforeMyLast_NotCounted() {
        // Given: worker1 messages before and after my last message
        let messages = [
            createMessage(id: "1", senderId: worker1Id, offset: 0),      // worker1 (before)
            createMessage(id: "2", senderId: worker1Id, offset: 1),      // worker1 (before)
            createMessage(id: "3", senderId: myAgentId, offset: 2),      // me
            createMessage(id: "4", senderId: worker1Id, offset: 3),      // worker1 (after - unread)
        ]

        // When: Calculate unread counts
        let counts = UnreadCountCalculator.calculateBySender(messages, agentId: myAgentId)

        // Then: Only the message after my last one is unread
        XCTAssertEqual(counts[worker1Id.value], 1)
    }

    func testCalculateUnreadCountsBySender_MultipleMyMessages_UsesLastOne() {
        // Given: Multiple messages from me, only count after the last one
        let messages = [
            createMessage(id: "1", senderId: worker1Id, offset: 0),
            createMessage(id: "2", senderId: myAgentId, offset: 1),
            createMessage(id: "3", senderId: worker1Id, offset: 2),
            createMessage(id: "4", senderId: myAgentId, offset: 3),      // my last
            createMessage(id: "5", senderId: worker1Id, offset: 4),      // unread
            createMessage(id: "6", senderId: worker1Id, offset: 5),      // unread
        ]

        // When: Calculate unread counts
        let counts = UnreadCountCalculator.calculateBySender(messages, agentId: myAgentId)

        // Then: Only 2 messages after my last one
        XCTAssertEqual(counts[worker1Id.value], 2)
    }

    // MARK: - Total unread count

    func testTotalUnreadCount_SumsAllSenders() {
        // Given: Unread messages from multiple senders
        let messages = [
            createMessage(id: "1", senderId: myAgentId, offset: 0),
            createMessage(id: "2", senderId: worker1Id, offset: 1),      // 3 unread
            createMessage(id: "3", senderId: worker1Id, offset: 2),
            createMessage(id: "4", senderId: worker1Id, offset: 3),
            createMessage(id: "5", senderId: worker2Id, offset: 4),      // 1 unread
        ]

        // When: Calculate total unread
        let total = UnreadCountCalculator.totalUnread(messages, agentId: myAgentId)

        // Then: Sum of all senders
        XCTAssertEqual(total, 4)
    }

    // MARK: - Helper

    private func createMessage(id: String, senderId: AgentID, offset: Int) -> ChatMessage {
        ChatMessage(
            id: ChatMessageID(value: id),
            senderId: senderId,
            content: "Message \(id)",
            createdAt: Date().addingTimeInterval(TimeInterval(offset))
        )
    }
}
