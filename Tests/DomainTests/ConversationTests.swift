// Tests/DomainTests/ConversationTests.swift
// Conversation entity tests for AI-to-AI conversation feature
// Reference: docs/design/AI_TO_AI_CONVERSATION.md

import XCTest
@testable import Domain

final class ConversationTests: XCTestCase {

    // MARK: - Entity Initialization

    func testConversationInitialization() {
        let conv = Conversation(
            projectId: ProjectID(value: "prj-001"),
            initiatorAgentId: AgentID(value: "agent-a"),
            participantAgentId: AgentID(value: "agent-b"),
            purpose: "しりとり"
        )

        XCTAssertNotNil(conv.id)
        XCTAssertEqual(conv.projectId.value, "prj-001")
        XCTAssertEqual(conv.initiatorAgentId.value, "agent-a")
        XCTAssertEqual(conv.participantAgentId.value, "agent-b")
        XCTAssertEqual(conv.state, .pending)
        XCTAssertEqual(conv.purpose, "しりとり")
        XCTAssertNil(conv.endedAt)
    }

    func testConversationInitializationWithCustomState() {
        let conv = Conversation(
            projectId: ProjectID(value: "prj-001"),
            initiatorAgentId: AgentID(value: "agent-a"),
            participantAgentId: AgentID(value: "agent-b"),
            state: .active
        )

        XCTAssertEqual(conv.state, .active)
    }

    func testConversationPurposeIsOptional() {
        let conv = Conversation(
            projectId: ProjectID(value: "prj-001"),
            initiatorAgentId: AgentID(value: "agent-a"),
            participantAgentId: AgentID(value: "agent-b")
        )

        XCTAssertNil(conv.purpose)
    }

    // MARK: - State Values

    func testConversationStateValues() {
        XCTAssertEqual(ConversationState.pending.rawValue, "pending")
        XCTAssertEqual(ConversationState.active.rawValue, "active")
        XCTAssertEqual(ConversationState.terminating.rawValue, "terminating")
        XCTAssertEqual(ConversationState.ended.rawValue, "ended")
        XCTAssertEqual(ConversationState.expired.rawValue, "expired")
    }

    // MARK: - Codable

    func testConversationEncodable() throws {
        let conv = Conversation(
            id: ConversationID(value: "conv-001"),
            projectId: ProjectID(value: "prj-001"),
            initiatorAgentId: AgentID(value: "agent-a"),
            participantAgentId: AgentID(value: "agent-b"),
            state: .active,
            purpose: "テスト会話",
            createdAt: Date(timeIntervalSince1970: 1705827600)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(conv)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"state\":\"active\""))
        XCTAssertTrue(jsonString.contains("\"purpose\":\"テスト会話\""))
    }

    func testConversationDecodable() throws {
        let json = """
        {
            "id": {"value": "conv-001"},
            "projectId": {"value": "prj-001"},
            "initiatorAgentId": {"value": "agent-a"},
            "participantAgentId": {"value": "agent-b"},
            "state": "active",
            "purpose": "テスト",
            "createdAt": "2026-01-23T10:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let conv = try decoder.decode(Conversation.self, from: data)

        XCTAssertEqual(conv.id.value, "conv-001")
        XCTAssertEqual(conv.state, .active)
        XCTAssertEqual(conv.purpose, "テスト")
    }

    func testConversationDecodableWithEndedAt() throws {
        let json = """
        {
            "id": {"value": "conv-001"},
            "projectId": {"value": "prj-001"},
            "initiatorAgentId": {"value": "agent-a"},
            "participantAgentId": {"value": "agent-b"},
            "state": "ended",
            "createdAt": "2026-01-23T10:00:00Z",
            "endedAt": "2026-01-23T10:30:00Z"
        }
        """
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let conv = try decoder.decode(Conversation.self, from: data)

        XCTAssertEqual(conv.state, .ended)
        XCTAssertNotNil(conv.endedAt)
    }

    // MARK: - Participant Check

    func testIsParticipantReturnsTrueForInitiator() {
        let conv = Conversation(
            projectId: ProjectID(value: "prj-001"),
            initiatorAgentId: AgentID(value: "agent-a"),
            participantAgentId: AgentID(value: "agent-b")
        )

        XCTAssertTrue(conv.isParticipant(AgentID(value: "agent-a")))
    }

    func testIsParticipantReturnsTrueForParticipant() {
        let conv = Conversation(
            projectId: ProjectID(value: "prj-001"),
            initiatorAgentId: AgentID(value: "agent-a"),
            participantAgentId: AgentID(value: "agent-b")
        )

        XCTAssertTrue(conv.isParticipant(AgentID(value: "agent-b")))
    }

    func testIsParticipantReturnsFalseForNonParticipant() {
        let conv = Conversation(
            projectId: ProjectID(value: "prj-001"),
            initiatorAgentId: AgentID(value: "agent-a"),
            participantAgentId: AgentID(value: "agent-b")
        )

        XCTAssertFalse(conv.isParticipant(AgentID(value: "agent-c")))
    }

    // MARK: - Partner Identification

    func testGetPartnerIdForInitiator() {
        let conv = Conversation(
            projectId: ProjectID(value: "prj-001"),
            initiatorAgentId: AgentID(value: "agent-a"),
            participantAgentId: AgentID(value: "agent-b")
        )

        XCTAssertEqual(conv.getPartnerId(for: AgentID(value: "agent-a"))?.value, "agent-b")
    }

    func testGetPartnerIdForParticipant() {
        let conv = Conversation(
            projectId: ProjectID(value: "prj-001"),
            initiatorAgentId: AgentID(value: "agent-a"),
            participantAgentId: AgentID(value: "agent-b")
        )

        XCTAssertEqual(conv.getPartnerId(for: AgentID(value: "agent-b"))?.value, "agent-a")
    }

    func testGetPartnerIdForNonParticipant() {
        let conv = Conversation(
            projectId: ProjectID(value: "prj-001"),
            initiatorAgentId: AgentID(value: "agent-a"),
            participantAgentId: AgentID(value: "agent-b")
        )

        XCTAssertNil(conv.getPartnerId(for: AgentID(value: "agent-c")))
    }
}
