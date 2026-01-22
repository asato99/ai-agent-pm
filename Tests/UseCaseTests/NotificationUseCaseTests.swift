// Tests/UseCaseTests/NotificationUseCaseTests.swift
// 通知システム - UseCase層テスト
// 参照: docs/design/NOTIFICATION_SYSTEM.md

import XCTest
@testable import Domain
@testable import UseCase

final class NotificationUseCaseTests: XCTestCase {

    private var mockNotificationRepository: MockNotificationRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        mockNotificationRepository = MockNotificationRepository()
    }

    override func tearDownWithError() throws {
        mockNotificationRepository = nil
        try super.tearDownWithError()
    }

    // MARK: - CreateNotificationUseCase Tests

    func testCreateStatusChangeNotification() throws {
        let useCase = CreateNotificationUseCase(
            notificationRepository: mockNotificationRepository
        )

        let notification = try useCase.createStatusChange(
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            taskId: TaskID(value: "tsk_001"),
            newStatus: "blocked"
        )

        XCTAssertTrue(notification.id.value.hasPrefix("ntf_"))
        XCTAssertEqual(notification.type, .statusChange)
        XCTAssertEqual(notification.action, "blocked")
        XCTAssertEqual(notification.targetAgentId.value, "agt_001")

        // リポジトリに保存されたことを確認
        XCTAssertEqual(mockNotificationRepository.savedNotifications.count, 1)
    }

    func testCreateInterruptNotification() throws {
        let useCase = CreateNotificationUseCase(
            notificationRepository: mockNotificationRepository
        )

        let notification = try useCase.createInterrupt(
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            action: "cancel",
            taskId: TaskID(value: "tsk_001"),
            instruction: "即座に停止してください"
        )

        XCTAssertEqual(notification.type, .interrupt)
        XCTAssertEqual(notification.action, "cancel")
        XCTAssertEqual(notification.instruction, "即座に停止してください")
    }

    func testCreateMessageNotification() throws {
        let useCase = CreateNotificationUseCase(
            notificationRepository: mockNotificationRepository
        )

        let notification = try useCase.createMessage(
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001")
        )

        XCTAssertEqual(notification.type, .message)
        XCTAssertEqual(notification.action, "user_message")
        XCTAssertNil(notification.taskId)
    }

    // MARK: - CheckNotificationsUseCase Tests

    func testCheckNotificationsWhenUnreadExist() throws {
        // 未読通知を追加
        let notification = AgentNotification(
            id: NotificationID.generate(),
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            type: .statusChange,
            action: "blocked",
            taskId: nil,
            message: "Test",
            instruction: "Test",
            createdAt: Date(),
            isRead: false
        )
        mockNotificationRepository.notifications.append(notification)

        let useCase = CheckNotificationsUseCase(
            notificationRepository: mockNotificationRepository
        )

        let hasUnread = try useCase.execute(
            agentId: AgentID(value: "agt_001"),
            projectId: ProjectID(value: "prj_001")
        )

        XCTAssertTrue(hasUnread)
    }

    func testCheckNotificationsWhenNoUnread() throws {
        let useCase = CheckNotificationsUseCase(
            notificationRepository: mockNotificationRepository
        )

        let hasUnread = try useCase.execute(
            agentId: AgentID(value: "agt_001"),
            projectId: ProjectID(value: "prj_001")
        )

        XCTAssertFalse(hasUnread)
    }

    // MARK: - GetNotificationsUseCase Tests

    func testGetNotificationsAndMarkAsRead() throws {
        // 未読通知を追加
        let notification = AgentNotification(
            id: NotificationID(value: "ntf_test001"),
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            type: .statusChange,
            action: "blocked",
            taskId: TaskID(value: "tsk_001"),
            message: "Test message",
            instruction: "Test instruction",
            createdAt: Date(),
            isRead: false
        )
        mockNotificationRepository.notifications.append(notification)

        let useCase = GetNotificationsUseCase(
            notificationRepository: mockNotificationRepository
        )

        let result = try useCase.execute(
            agentId: AgentID(value: "agt_001"),
            projectId: ProjectID(value: "prj_001"),
            markAsRead: true
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id.value, "ntf_test001")

        // markAllAsReadが呼ばれたことを確認
        XCTAssertTrue(mockNotificationRepository.markAllAsReadCalled)
    }

    func testGetNotificationsWithoutMarkingAsRead() throws {
        // 未読通知を追加
        let notification = AgentNotification(
            id: NotificationID(value: "ntf_test001"),
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            type: .statusChange,
            action: "blocked",
            taskId: nil,
            message: "Test",
            instruction: "Test",
            createdAt: Date(),
            isRead: false
        )
        mockNotificationRepository.notifications.append(notification)

        let useCase = GetNotificationsUseCase(
            notificationRepository: mockNotificationRepository
        )

        let result = try useCase.execute(
            agentId: AgentID(value: "agt_001"),
            projectId: ProjectID(value: "prj_001"),
            markAsRead: false
        )

        XCTAssertEqual(result.count, 1)
        // markAllAsReadは呼ばれていない
        XCTAssertFalse(mockNotificationRepository.markAllAsReadCalled)
    }

    // MARK: - CleanupOldNotificationsUseCase Tests

    func testCleanupOldNotifications() throws {
        let useCase = CleanupOldNotificationsUseCase(
            notificationRepository: mockNotificationRepository
        )

        mockNotificationRepository.deleteOlderThanResult = 5

        let deleted = try useCase.execute(olderThanDays: 7)

        XCTAssertEqual(deleted, 5)
        XCTAssertEqual(mockNotificationRepository.deleteOlderThanDays, 7)
    }
}

// MARK: - Mock Repository

private final class MockNotificationRepository: NotificationRepositoryProtocol, @unchecked Sendable {
    var notifications: [AgentNotification] = []
    var savedNotifications: [AgentNotification] = []
    var markAllAsReadCalled = false
    var deleteOlderThanDays: Int?
    var deleteOlderThanResult: Int = 0

    func findById(_ id: NotificationID) throws -> AgentNotification? {
        notifications.first { $0.id == id }
    }

    func findUnreadByAgentAndProject(agentId: AgentID, projectId: ProjectID) throws -> [AgentNotification] {
        notifications.filter {
            $0.targetAgentId == agentId &&
            $0.targetProjectId == projectId &&
            !$0.isRead
        }
    }

    func hasUnreadNotifications(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        notifications.contains {
            $0.targetAgentId == agentId &&
            $0.targetProjectId == projectId &&
            !$0.isRead
        }
    }

    func save(_ notification: AgentNotification) throws {
        savedNotifications.append(notification)
        notifications.append(notification)
    }

    func markAsRead(_ id: NotificationID) throws {
        if let index = notifications.firstIndex(where: { $0.id == id }) {
            var notification = notifications[index]
            notification.markAsRead()
            notifications[index] = notification
        }
    }

    func markAllAsRead(agentId: AgentID, projectId: ProjectID) throws {
        markAllAsReadCalled = true
        for i in notifications.indices {
            if notifications[i].targetAgentId == agentId &&
               notifications[i].targetProjectId == projectId {
                notifications[i].markAsRead()
            }
        }
    }

    func deleteOlderThan(days: Int) throws -> Int {
        deleteOlderThanDays = days
        return deleteOlderThanResult
    }

    func countAll() throws -> Int {
        notifications.count
    }
}

