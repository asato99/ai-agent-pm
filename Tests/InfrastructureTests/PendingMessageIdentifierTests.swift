// Tests/InfrastructureTests/PendingMessageIdentifierTests.swift
// Phase 0: 未読メッセージ判定ロジックのユニットテスト

import XCTest
@testable import Domain
@testable import Infrastructure

final class PendingMessageIdentifierTests: XCTestCase {

    // MARK: - 基本ケース

    func testIdentifyPending_LastMessageIsUser_IsPending() {
        // Given: [user, agent, user]
        let messages = [
            createMessage(id: "1", sender: .user, offset: 0),
            createMessage(id: "2", sender: .agent, offset: 1),
            createMessage(id: "3", sender: .user, offset: 2),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages)

        // Then: 最後のuserメッセージが未読
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].id.value, "3")
    }

    func testIdentifyPending_LastMessageIsAgent_NoPending() {
        // Given: [user, agent]
        let messages = [
            createMessage(id: "1", sender: .user, offset: 0),
            createMessage(id: "2", sender: .agent, offset: 1),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages)

        // Then: 未読なし
        XCTAssertTrue(pending.isEmpty)
    }

    func testIdentifyPending_ConsecutiveUserMessages_AllPending() {
        // Given: [user, agent, user, user, user]
        let messages = [
            createMessage(id: "1", sender: .user, offset: 0),
            createMessage(id: "2", sender: .agent, offset: 1),
            createMessage(id: "3", sender: .user, offset: 2),
            createMessage(id: "4", sender: .user, offset: 3),
            createMessage(id: "5", sender: .user, offset: 4),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages)

        // Then: 連続するuserメッセージが全て未読
        XCTAssertEqual(pending.count, 3)
        XCTAssertEqual(pending.map { $0.id.value }, ["3", "4", "5"])
    }

    func testIdentifyPending_EmptyMessages_NoPending() {
        // Given: 空の配列
        let messages: [ChatMessage] = []

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages)

        // Then: 未読なし
        XCTAssertTrue(pending.isEmpty)
    }

    func testIdentifyPending_OnlyUserMessages_AllPending() {
        // Given: [user, user, user]（agentの応答なし）
        let messages = [
            createMessage(id: "1", sender: .user, offset: 0),
            createMessage(id: "2", sender: .user, offset: 1),
            createMessage(id: "3", sender: .user, offset: 2),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages)

        // Then: 全て未読
        XCTAssertEqual(pending.count, 3)
    }

    func testIdentifyPending_OnlyAgentMessages_NoPending() {
        // Given: [agent, agent]
        let messages = [
            createMessage(id: "1", sender: .agent, offset: 0),
            createMessage(id: "2", sender: .agent, offset: 1),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages)

        // Then: 未読なし
        XCTAssertTrue(pending.isEmpty)
    }

    // MARK: - システムメッセージの扱い

    func testIdentifyPending_SystemMessageAfterAgent_NotPending() {
        // Given: [user, agent, system]
        let messages = [
            createMessage(id: "1", sender: .user, offset: 0),
            createMessage(id: "2", sender: .agent, offset: 1),
            createMessage(id: "3", sender: .system, offset: 2),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages)

        // Then: システムメッセージは未読扱いしない
        XCTAssertTrue(pending.isEmpty)
    }

    func testIdentifyPending_UserAfterSystem_IsPending() {
        // Given: [user, agent, system, user]
        let messages = [
            createMessage(id: "1", sender: .user, offset: 0),
            createMessage(id: "2", sender: .agent, offset: 1),
            createMessage(id: "3", sender: .system, offset: 2),
            createMessage(id: "4", sender: .user, offset: 3),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages)

        // Then: userメッセージは未読
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].id.value, "4")
    }

    // MARK: - limit パラメータ

    func testIdentifyPending_WithLimit_ReturnsLatestOnly() {
        // Given: 10件の未読メッセージ
        var messages = [createMessage(id: "0", sender: .agent, offset: 0)]
        for i in 1...10 {
            messages.append(createMessage(id: "\(i)", sender: .user, offset: i))
        }

        // When: limit=5で判定
        let pending = PendingMessageIdentifier.identify(messages, limit: 5)

        // Then: 最新5件のみ
        XCTAssertEqual(pending.count, 5)
        XCTAssertEqual(pending.map { $0.id.value }, ["6", "7", "8", "9", "10"])
    }

    func testIdentifyPending_WithLimitExceedingCount_ReturnsAll() {
        // Given: 3件の未読メッセージ
        let messages = [
            createMessage(id: "0", sender: .agent, offset: 0),
            createMessage(id: "1", sender: .user, offset: 1),
            createMessage(id: "2", sender: .user, offset: 2),
            createMessage(id: "3", sender: .user, offset: 3),
        ]

        // When: limit=10で判定
        let pending = PendingMessageIdentifier.identify(messages, limit: 10)

        // Then: 全て返る
        XCTAssertEqual(pending.count, 3)
    }

    // MARK: - separateContextAndPending

    func testSeparateContextAndPending_ReturnsContextAndPending() {
        // Given: 25件の会話（交互）、最後3件がuser
        var messages: [ChatMessage] = []
        for i in 0..<22 {
            let sender: SenderType = i % 2 == 0 ? .user : .agent
            messages.append(createMessage(id: "\(i)", sender: sender, offset: i))
        }
        // 最後の3件はuser
        messages.append(createMessage(id: "22", sender: .user, offset: 22))
        messages.append(createMessage(id: "23", sender: .user, offset: 23))
        messages.append(createMessage(id: "24", sender: .user, offset: 24))

        // When: コンテキストと未読を分離
        let result = PendingMessageIdentifier.separateContextAndPending(
            messages,
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
        // Given: 最後のメッセージがagent（全て既読）
        let messages = [
            createMessage(id: "1", sender: .user, offset: 0),
            createMessage(id: "2", sender: .agent, offset: 1),
        ]

        // When: コンテキストと未読を分離
        let result = PendingMessageIdentifier.separateContextAndPending(messages)

        // Then: pending は空
        XCTAssertTrue(result.pendingMessages.isEmpty)
        XCTAssertEqual(result.contextMessages.count, 2)
        XCTAssertFalse(result.contextTruncated)
    }

    func testSeparateContextAndPending_ManyPending_LimitsTo10() {
        // Given: 15件の未読メッセージ
        var messages = [createMessage(id: "0", sender: .agent, offset: 0)]
        for i in 1...15 {
            messages.append(createMessage(id: "\(i)", sender: .user, offset: i))
        }

        // When: pendingLimit=10 で分離
        let result = PendingMessageIdentifier.separateContextAndPending(
            messages,
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
        let result = PendingMessageIdentifier.separateContextAndPending(messages)

        // Then: 全て空
        XCTAssertTrue(result.contextMessages.isEmpty)
        XCTAssertTrue(result.pendingMessages.isEmpty)
        XCTAssertEqual(result.totalHistoryCount, 0)
        XCTAssertFalse(result.contextTruncated)
    }

    func testSeparateContextAndPending_FewMessages_NoTruncation() {
        // Given: 5件の会話履歴
        let messages = [
            createMessage(id: "1", sender: .user, offset: 0),
            createMessage(id: "2", sender: .agent, offset: 1),
            createMessage(id: "3", sender: .user, offset: 2),
            createMessage(id: "4", sender: .agent, offset: 3),
            createMessage(id: "5", sender: .user, offset: 4),
        ]

        // When: コンテキストと未読を分離
        let result = PendingMessageIdentifier.separateContextAndPending(messages)

        // Then: context_truncated = false
        XCTAssertFalse(result.contextTruncated)
        XCTAssertEqual(result.totalHistoryCount, 5)
    }

    // MARK: - Helper

    private func createMessage(id: String, sender: SenderType, offset: Int) -> ChatMessage {
        ChatMessage(
            id: ChatMessageID(value: id),
            sender: sender,
            content: "Message \(id)",
            createdAt: Date().addingTimeInterval(TimeInterval(offset))
        )
    }
}
