// Tests/DomainTests/AgentNotificationTests.swift
// 通知システム - Domain層テスト
// 参照: docs/design/NOTIFICATION_SYSTEM.md

import XCTest
@testable import Domain

final class AgentNotificationTests: XCTestCase {

    // MARK: - NotificationID Tests

    func testNotificationIDGeneration() {
        let id = NotificationID.generate()
        XCTAssertTrue(id.value.hasPrefix("ntf_"), "Notification ID must start with 'ntf_'")
        XCTAssertGreaterThan(id.value.count, 4, "Notification ID must have characters after prefix")
    }

    func testNotificationIDEquality() {
        let id1 = NotificationID(value: "ntf_test123")
        let id2 = NotificationID(value: "ntf_test123")
        let id3 = NotificationID(value: "ntf_other456")

        XCTAssertEqual(id1, id2)
        XCTAssertNotEqual(id1, id3)
    }

    // MARK: - AgentNotificationType Tests

    func testAgentNotificationTypeRawValues() {
        XCTAssertEqual(AgentNotificationType.statusChange.rawValue, "status_change")
        XCTAssertEqual(AgentNotificationType.interrupt.rawValue, "interrupt")
        XCTAssertEqual(AgentNotificationType.message.rawValue, "message")
    }

    func testAgentNotificationTypeCodable() throws {
        let type = AgentNotificationType.statusChange
        let encoded = try JSONEncoder().encode(type)
        let decoded = try JSONDecoder().decode(AgentNotificationType.self, from: encoded)
        XCTAssertEqual(decoded, type)
    }

    // MARK: - AgentNotification Entity Tests

    func testAgentNotificationCreation() {
        let now = Date()
        let notification = AgentNotification(
            id: NotificationID(value: "ntf_001"),
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            type: .statusChange,
            action: "blocked",
            taskId: TaskID(value: "tsk_001"),
            message: "タスクのステータスがblockedに変更されました",
            instruction: "作業を中断し、report_completedをresult='blocked'で呼び出してください",
            createdAt: now
        )

        XCTAssertEqual(notification.id.value, "ntf_001")
        XCTAssertEqual(notification.targetAgentId.value, "agt_001")
        XCTAssertEqual(notification.targetProjectId.value, "prj_001")
        XCTAssertEqual(notification.type, .statusChange)
        XCTAssertEqual(notification.action, "blocked")
        XCTAssertEqual(notification.taskId?.value, "tsk_001")
        XCTAssertTrue(notification.message.contains("blocked"))
        XCTAssertTrue(notification.instruction.contains("report_completed"))
        XCTAssertEqual(notification.createdAt, now)
        XCTAssertFalse(notification.isRead)
        XCTAssertNil(notification.readAt)
    }

    func testAgentNotificationCreationWithoutTaskId() {
        let notification = AgentNotification(
            id: NotificationID.generate(),
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            type: .message,
            action: "user_message",
            taskId: nil,
            message: "ユーザーからのメッセージがあります",
            instruction: "get_pending_messagesを呼び出して確認してください",
            createdAt: Date()
        )

        XCTAssertNil(notification.taskId)
        XCTAssertEqual(notification.type, .message)
    }

    func testAgentNotificationMarkAsRead() {
        var notification = AgentNotification(
            id: NotificationID.generate(),
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            type: .statusChange,
            action: "blocked",
            taskId: TaskID(value: "tsk_001"),
            message: "Test message",
            instruction: "Test instruction",
            createdAt: Date()
        )

        XCTAssertFalse(notification.isRead)
        XCTAssertNil(notification.readAt)

        notification.markAsRead()

        XCTAssertTrue(notification.isRead)
        XCTAssertNotNil(notification.readAt)
    }

    func testAgentNotificationMarkAsReadIdempotent() {
        var notification = AgentNotification(
            id: NotificationID.generate(),
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            type: .statusChange,
            action: "blocked",
            taskId: nil,
            message: "Test",
            instruction: "Test",
            createdAt: Date()
        )

        notification.markAsRead()
        let firstReadAt = notification.readAt

        // 少し待ってから再度呼び出し
        Thread.sleep(forTimeInterval: 0.01)
        notification.markAsRead()

        // 既読時刻は更新されない（冪等性）
        XCTAssertEqual(notification.readAt, firstReadAt)
    }

    // MARK: - AgentNotification Codable Tests

    func testAgentNotificationCodable() throws {
        let notification = AgentNotification(
            id: NotificationID(value: "ntf_codable"),
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            type: .interrupt,
            action: "cancel",
            taskId: TaskID(value: "tsk_001"),
            message: "キャンセルされました",
            instruction: "即座に停止してください",
            createdAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(notification)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AgentNotification.self, from: data)

        XCTAssertEqual(decoded.id, notification.id)
        XCTAssertEqual(decoded.type, notification.type)
        XCTAssertEqual(decoded.action, notification.action)
        XCTAssertEqual(decoded.isRead, notification.isRead)
    }

    // MARK: - AgentNotification Equatable Tests

    func testAgentNotificationEquality() {
        let id = NotificationID(value: "ntf_eq")
        let now = Date()

        let notif1 = AgentNotification(
            id: id,
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            type: .statusChange,
            action: "blocked",
            taskId: nil,
            message: "Test",
            instruction: "Test",
            createdAt: now
        )

        let notif2 = AgentNotification(
            id: id,
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            type: .statusChange,
            action: "blocked",
            taskId: nil,
            message: "Test",
            instruction: "Test",
            createdAt: now
        )

        XCTAssertEqual(notif1, notif2)
    }

    // MARK: - Factory Method Tests

    func testCreateStatusChangeNotification() {
        let notification = AgentNotification.createStatusChangeNotification(
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            taskId: TaskID(value: "tsk_001"),
            newStatus: "blocked"
        )

        XCTAssertTrue(notification.id.value.hasPrefix("ntf_"))
        XCTAssertEqual(notification.type, .statusChange)
        XCTAssertEqual(notification.action, "blocked")
        XCTAssertEqual(notification.taskId?.value, "tsk_001")
        XCTAssertTrue(notification.message.contains("blocked"))
        XCTAssertTrue(notification.instruction.contains("report_completed"))
        XCTAssertFalse(notification.isRead)
    }

    func testCreateInterruptNotification() {
        let notification = AgentNotification.createInterruptNotification(
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            action: "cancel",
            taskId: TaskID(value: "tsk_001"),
            instruction: "即座に停止してください"
        )

        XCTAssertTrue(notification.id.value.hasPrefix("ntf_"))
        XCTAssertEqual(notification.type, .interrupt)
        XCTAssertEqual(notification.action, "cancel")
        XCTAssertTrue(notification.message.contains("cancel"))
        XCTAssertEqual(notification.instruction, "即座に停止してください")
    }

    func testCreateMessageNotification() {
        let notification = AgentNotification.createMessageNotification(
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001")
        )

        XCTAssertTrue(notification.id.value.hasPrefix("ntf_"))
        XCTAssertEqual(notification.type, .message)
        XCTAssertEqual(notification.action, "user_message")
        XCTAssertNil(notification.taskId)
        XCTAssertTrue(notification.instruction.contains("get_pending_messages"))
    }

    // MARK: - Chat Session Notification Tests (Phase 1-1)

    func testChatSessionNotificationType() {
        // chatSessionNotification タイプが存在することを確認
        XCTAssertEqual(AgentNotificationType.chatSessionNotification.rawValue, "chat_session_notification")
    }

    func testChatSessionNotificationTypeInAllCases() {
        // CaseIterable に含まれることを確認
        XCTAssertTrue(AgentNotificationType.allCases.contains(.chatSessionNotification))
    }

    func testAgentNotificationWithConversationId() {
        let conversationId = ConversationID(value: "conv_001")
        let notification = AgentNotification(
            id: NotificationID(value: "ntf_chat_001"),
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            type: .chatSessionNotification,
            action: "check_chat",
            taskId: TaskID(value: "tsk_001"),
            conversationId: conversationId,
            message: "チャットを確認してください",
            instruction: "get_conversation_messages で確認してください",
            createdAt: Date()
        )

        XCTAssertEqual(notification.conversationId?.value, "conv_001")
        XCTAssertEqual(notification.type, .chatSessionNotification)
    }

    func testAgentNotificationConversationIdOptional() {
        // conversationId なしでも作成可能（既存互換性）
        let notification = AgentNotification(
            id: NotificationID(value: "ntf_no_conv"),
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            type: .statusChange,
            action: "blocked",
            taskId: nil,
            conversationId: nil,
            message: "Test",
            instruction: "Test",
            createdAt: Date()
        )

        XCTAssertNil(notification.conversationId)
    }

    func testCreateChatSessionNotification() {
        let notification = AgentNotification.createChatSessionNotification(
            targetAgentId: AgentID(value: "worker-01"),
            targetProjectId: ProjectID(value: "prj_001"),
            conversationId: ConversationID(value: "conv_abc"),
            message: "Manager から緊急の指示があります",
            relatedTaskId: TaskID(value: "tsk_001")
        )

        XCTAssertTrue(notification.id.value.hasPrefix("ntf_"))
        XCTAssertEqual(notification.type, .chatSessionNotification)
        XCTAssertEqual(notification.action, "check_chat")
        XCTAssertEqual(notification.conversationId?.value, "conv_abc")
        XCTAssertEqual(notification.taskId?.value, "tsk_001")
        XCTAssertTrue(notification.message.contains("Manager から緊急の指示"))
        XCTAssertTrue(notification.instruction.contains("get_conversation_messages"))
        XCTAssertTrue(notification.instruction.contains("conv_abc"))
    }

    func testCreateChatSessionNotificationWithoutTaskId() {
        let notification = AgentNotification.createChatSessionNotification(
            targetAgentId: AgentID(value: "worker-01"),
            targetProjectId: ProjectID(value: "prj_001"),
            conversationId: ConversationID(value: "conv_xyz"),
            message: nil,
            relatedTaskId: nil
        )

        XCTAssertEqual(notification.type, .chatSessionNotification)
        XCTAssertEqual(notification.conversationId?.value, "conv_xyz")
        XCTAssertNil(notification.taskId)
        XCTAssertTrue(notification.instruction.contains("conv_xyz"))
    }

    func testChatSessionNotificationCodable() throws {
        let notification = AgentNotification.createChatSessionNotification(
            targetAgentId: AgentID(value: "worker-01"),
            targetProjectId: ProjectID(value: "prj_001"),
            conversationId: ConversationID(value: "conv_codable"),
            message: "テストメッセージ",
            relatedTaskId: TaskID(value: "tsk_001")
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(notification)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AgentNotification.self, from: data)

        XCTAssertEqual(decoded.type, .chatSessionNotification)
        XCTAssertEqual(decoded.conversationId?.value, "conv_codable")
        XCTAssertEqual(decoded.taskId?.value, "tsk_001")
    }
}
