// Tests/InfrastructureTests/PendingMessageIdentifierTests.swift
// Phase 0: 未読メッセージ判定ロジックのユニットテスト
// Updated for senderId/receiverId model (dual storage)

import XCTest
@testable import Domain
@testable import Infrastructure

final class PendingMessageIdentifierTests: XCTestCase {

    /// Test agent IDs
    private let myAgentId = AgentID(value: "my-agent")
    private let otherAgentId = AgentID(value: "other-agent")
    private let systemAgentId = AgentID(value: "system")

    // MARK: - 基本ケース

    func testIdentifyPending_LastMessageFromOther_IsPending() {
        // Given: [other, me, other]
        let messages = [
            createMessage(id: "1", senderId: otherAgentId, offset: 0),
            createMessage(id: "2", senderId: myAgentId, offset: 1),
            createMessage(id: "3", senderId: otherAgentId, offset: 2),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages, agentId: myAgentId)

        // Then: 最後の他者からのメッセージが未読
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].id.value, "3")
    }

    func testIdentifyPending_LastMessageFromMe_NoPending() {
        // Given: [other, me]
        let messages = [
            createMessage(id: "1", senderId: otherAgentId, offset: 0),
            createMessage(id: "2", senderId: myAgentId, offset: 1),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages, agentId: myAgentId)

        // Then: 未読なし
        XCTAssertTrue(pending.isEmpty)
    }

    func testIdentifyPending_ConsecutiveOtherMessages_AllPending() {
        // Given: [other, me, other, other, other]
        let messages = [
            createMessage(id: "1", senderId: otherAgentId, offset: 0),
            createMessage(id: "2", senderId: myAgentId, offset: 1),
            createMessage(id: "3", senderId: otherAgentId, offset: 2),
            createMessage(id: "4", senderId: otherAgentId, offset: 3),
            createMessage(id: "5", senderId: otherAgentId, offset: 4),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages, agentId: myAgentId)

        // Then: 連続する他者からのメッセージが全て未読
        XCTAssertEqual(pending.count, 3)
        XCTAssertEqual(pending.map { $0.id.value }, ["3", "4", "5"])
    }

    func testIdentifyPending_EmptyMessages_NoPending() {
        // Given: 空の配列
        let messages: [ChatMessage] = []

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages, agentId: myAgentId)

        // Then: 未読なし
        XCTAssertTrue(pending.isEmpty)
    }

    func testIdentifyPending_OnlyOtherMessages_AllPending() {
        // Given: [other, other, other]（自分の応答なし）
        let messages = [
            createMessage(id: "1", senderId: otherAgentId, offset: 0),
            createMessage(id: "2", senderId: otherAgentId, offset: 1),
            createMessage(id: "3", senderId: otherAgentId, offset: 2),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages, agentId: myAgentId)

        // Then: 全て未読
        XCTAssertEqual(pending.count, 3)
    }

    func testIdentifyPending_OnlyMyMessages_NoPending() {
        // Given: [me, me]
        let messages = [
            createMessage(id: "1", senderId: myAgentId, offset: 0),
            createMessage(id: "2", senderId: myAgentId, offset: 1),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages, agentId: myAgentId)

        // Then: 未読なし
        XCTAssertTrue(pending.isEmpty)
    }

    // MARK: - システムメッセージの扱い

    func testIdentifyPending_SystemMessageAfterMe_NotPending() {
        // Given: [other, me, system]
        // Note: System messages have senderId = "system", which is not myAgentId
        // So they ARE treated as "from others" and thus pending
        // This behavior change is intentional - system messages are now unread
        let messages = [
            createMessage(id: "1", senderId: otherAgentId, offset: 0),
            createMessage(id: "2", senderId: myAgentId, offset: 1),
            createMessage(id: "3", senderId: systemAgentId, offset: 2),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages, agentId: myAgentId)

        // Then: システムメッセージも未読として扱われる（senderId != myAgentId）
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].id.value, "3")
    }

    func testIdentifyPending_OtherAfterSystem_IsPending() {
        // Given: [other, me, system, other]
        let messages = [
            createMessage(id: "1", senderId: otherAgentId, offset: 0),
            createMessage(id: "2", senderId: myAgentId, offset: 1),
            createMessage(id: "3", senderId: systemAgentId, offset: 2),
            createMessage(id: "4", senderId: otherAgentId, offset: 3),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages, agentId: myAgentId)

        // Then: システムメッセージと他者メッセージが未読
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(pending.map { $0.id.value }, ["3", "4"])
    }

    // MARK: - limit パラメータ

    func testIdentifyPending_WithLimit_ReturnsLatestOnly() {
        // Given: 10件の未読メッセージ
        var messages = [createMessage(id: "0", senderId: myAgentId, offset: 0)]
        for i in 1...10 {
            messages.append(createMessage(id: "\(i)", senderId: otherAgentId, offset: i))
        }

        // When: limit=5で判定
        let pending = PendingMessageIdentifier.identify(messages, agentId: myAgentId, limit: 5)

        // Then: 最新5件のみ
        XCTAssertEqual(pending.count, 5)
        XCTAssertEqual(pending.map { $0.id.value }, ["6", "7", "8", "9", "10"])
    }

    func testIdentifyPending_WithLimitExceedingCount_ReturnsAll() {
        // Given: 3件の未読メッセージ
        let messages = [
            createMessage(id: "0", senderId: myAgentId, offset: 0),
            createMessage(id: "1", senderId: otherAgentId, offset: 1),
            createMessage(id: "2", senderId: otherAgentId, offset: 2),
            createMessage(id: "3", senderId: otherAgentId, offset: 3),
        ]

        // When: limit=10で判定
        let pending = PendingMessageIdentifier.identify(messages, agentId: myAgentId, limit: 10)

        // Then: 全て返る
        XCTAssertEqual(pending.count, 3)
    }

    // MARK: - separateContextAndPending

    func testSeparateContextAndPending_ReturnsContextAndPending() {
        // Given: 25件の会話（交互）、最後3件が他者から
        var messages: [ChatMessage] = []
        for i in 0..<22 {
            let senderId = i % 2 == 0 ? otherAgentId : myAgentId
            messages.append(createMessage(id: "\(i)", senderId: senderId, offset: i))
        }
        // 最後の3件は他者から
        messages.append(createMessage(id: "22", senderId: otherAgentId, offset: 22))
        messages.append(createMessage(id: "23", senderId: otherAgentId, offset: 23))
        messages.append(createMessage(id: "24", senderId: otherAgentId, offset: 24))

        // When: コンテキストと未読を分離
        let result = PendingMessageIdentifier.separateContextAndPending(
            messages,
            agentId: myAgentId,
            contextLimit: 20,
            pendingLimit: 10
        )

        // Then: context に20件、pending に3件
        XCTAssertEqual(result.pendingMessages.count, 3)
        XCTAssertEqual(result.contextMessages.count, 20)
        XCTAssertEqual(result.totalHistoryCount, 25)
        XCTAssertTrue(result.contextTruncated)
    }

    func testSeparateContextAndPending_NoPending_ReturnsEmptyPending() {
        // Given: 最後のメッセージが自分（全て既読）
        let messages = [
            createMessage(id: "1", senderId: otherAgentId, offset: 0),
            createMessage(id: "2", senderId: myAgentId, offset: 1),
        ]

        // When: コンテキストと未読を分離
        let result = PendingMessageIdentifier.separateContextAndPending(messages, agentId: myAgentId)

        // Then: pending は空
        XCTAssertTrue(result.pendingMessages.isEmpty)
        XCTAssertEqual(result.contextMessages.count, 2)
        XCTAssertFalse(result.contextTruncated)
    }

    func testSeparateContextAndPending_ManyPending_LimitsTo10() {
        // Given: 15件の未読メッセージ
        var messages = [createMessage(id: "0", senderId: myAgentId, offset: 0)]
        for i in 1...15 {
            messages.append(createMessage(id: "\(i)", senderId: otherAgentId, offset: i))
        }

        // When: pendingLimit=10 で分離
        let result = PendingMessageIdentifier.separateContextAndPending(
            messages,
            agentId: myAgentId,
            contextLimit: 20,
            pendingLimit: 10
        )

        // Then: 最新10件のみ pending に含まれる
        XCTAssertEqual(result.pendingMessages.count, 10)
        XCTAssertEqual(result.pendingMessages.first?.id.value, "6")
        XCTAssertEqual(result.pendingMessages.last?.id.value, "15")
    }

    func testSeparateContextAndPending_EmptyMessages_ReturnsEmpty() {
        // Given: 空の配列
        let messages: [ChatMessage] = []

        // When: コンテキストと未読を分離
        let result = PendingMessageIdentifier.separateContextAndPending(messages, agentId: myAgentId)

        // Then: 全て空
        XCTAssertTrue(result.contextMessages.isEmpty)
        XCTAssertTrue(result.pendingMessages.isEmpty)
        XCTAssertEqual(result.totalHistoryCount, 0)
        XCTAssertFalse(result.contextTruncated)
    }

    func testSeparateContextAndPending_FewMessages_NoTruncation() {
        // Given: 5件の会話履歴
        let messages = [
            createMessage(id: "1", senderId: otherAgentId, offset: 0),
            createMessage(id: "2", senderId: myAgentId, offset: 1),
            createMessage(id: "3", senderId: otherAgentId, offset: 2),
            createMessage(id: "4", senderId: myAgentId, offset: 3),
            createMessage(id: "5", senderId: otherAgentId, offset: 4),
        ]

        // When: コンテキストと未読を分離
        let result = PendingMessageIdentifier.separateContextAndPending(messages, agentId: myAgentId)

        // Then: context_truncated = false
        XCTAssertFalse(result.contextTruncated)
        XCTAssertEqual(result.totalHistoryCount, 5)
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
