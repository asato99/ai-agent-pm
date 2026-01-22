// Tests/InfrastructureTests/NotificationRepositoryTests.swift
// 通知リポジトリ - Infrastructure層テスト
// 参照: docs/design/NOTIFICATION_SYSTEM.md

import XCTest
import GRDB
@testable import Domain
@testable import Infrastructure

final class NotificationRepositoryTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var repository: NotificationRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // 一時ファイルのDBを作成
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_notification_\(UUID().uuidString).db").path
        dbQueue = try DatabaseSetup.createDatabase(at: dbPath)
        repository = NotificationRepository(database: dbQueue)
    }

    override func tearDownWithError() throws {
        repository = nil
        dbQueue = nil
        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    private func createTestNotification(
        id: String = "ntf_test001",
        targetAgentId: String = "agt_001",
        targetProjectId: String = "prj_001",
        type: AgentNotificationType = .statusChange,
        action: String = "blocked",
        taskId: String? = "tsk_001",
        isRead: Bool = false
    ) -> AgentNotification {
        AgentNotification(
            id: NotificationID(value: id),
            targetAgentId: AgentID(value: targetAgentId),
            targetProjectId: ProjectID(value: targetProjectId),
            type: type,
            action: action,
            taskId: taskId.map { TaskID(value: $0) },
            message: "Test message",
            instruction: "Test instruction",
            createdAt: Date(),
            isRead: isRead,
            readAt: isRead ? Date() : nil
        )
    }

    // MARK: - Save & Find Tests

    func testSaveAndFindById() throws {
        let notification = createTestNotification()

        try repository.save(notification)

        let found = try repository.findById(notification.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, notification.id)
        XCTAssertEqual(found?.targetAgentId.value, "agt_001")
        XCTAssertEqual(found?.type, .statusChange)
        XCTAssertEqual(found?.action, "blocked")
        XCTAssertFalse(found!.isRead)
    }

    func testFindByIdNotFound() throws {
        let found = try repository.findById(NotificationID(value: "ntf_nonexistent"))
        XCTAssertNil(found)
    }

    // MARK: - Unread Notifications Tests

    func testFindUnreadByAgentAndProject() throws {
        // 未読通知を2件作成
        let notif1 = createTestNotification(id: "ntf_001", isRead: false)
        let notif2 = createTestNotification(id: "ntf_002", isRead: false)
        // 既読通知を1件作成
        let notif3 = createTestNotification(id: "ntf_003", isRead: true)
        // 別エージェントの通知
        let notif4 = createTestNotification(id: "ntf_004", targetAgentId: "agt_other", isRead: false)

        try repository.save(notif1)
        try repository.save(notif2)
        try repository.save(notif3)
        try repository.save(notif4)

        let unread = try repository.findUnreadByAgentAndProject(
            agentId: AgentID(value: "agt_001"),
            projectId: ProjectID(value: "prj_001")
        )

        XCTAssertEqual(unread.count, 2)
        XCTAssertTrue(unread.allSatisfy { !$0.isRead })
        XCTAssertTrue(unread.allSatisfy { $0.targetAgentId.value == "agt_001" })
    }

    func testHasUnreadNotifications() throws {
        let agentId = AgentID(value: "agt_001")
        let projectId = ProjectID(value: "prj_001")

        // 通知がない場合
        XCTAssertFalse(try repository.hasUnreadNotifications(agentId: agentId, projectId: projectId))

        // 未読通知を追加
        let notif = createTestNotification(isRead: false)
        try repository.save(notif)

        XCTAssertTrue(try repository.hasUnreadNotifications(agentId: agentId, projectId: projectId))
    }

    func testHasUnreadNotificationsWithOnlyRead() throws {
        let agentId = AgentID(value: "agt_001")
        let projectId = ProjectID(value: "prj_001")

        // 既読通知のみ追加
        let notif = createTestNotification(isRead: true)
        try repository.save(notif)

        XCTAssertFalse(try repository.hasUnreadNotifications(agentId: agentId, projectId: projectId))
    }

    // MARK: - Mark As Read Tests

    func testMarkAsRead() throws {
        let notification = createTestNotification(isRead: false)
        try repository.save(notification)

        XCTAssertFalse(try repository.findById(notification.id)!.isRead)

        try repository.markAsRead(notification.id)

        let updated = try repository.findById(notification.id)
        XCTAssertNotNil(updated)
        XCTAssertTrue(updated!.isRead)
        XCTAssertNotNil(updated!.readAt)
    }

    func testMarkAllAsRead() throws {
        let agentId = AgentID(value: "agt_001")
        let projectId = ProjectID(value: "prj_001")

        // 未読通知を3件作成
        try repository.save(createTestNotification(id: "ntf_001", isRead: false))
        try repository.save(createTestNotification(id: "ntf_002", isRead: false))
        try repository.save(createTestNotification(id: "ntf_003", isRead: false))
        // 別プロジェクトの未読通知
        try repository.save(createTestNotification(id: "ntf_004", targetProjectId: "prj_other", isRead: false))

        try repository.markAllAsRead(agentId: agentId, projectId: projectId)

        // 対象の通知はすべて既読
        let unread = try repository.findUnreadByAgentAndProject(agentId: agentId, projectId: projectId)
        XCTAssertTrue(unread.isEmpty)

        // 別プロジェクトの通知は未読のまま
        let otherUnread = try repository.findUnreadByAgentAndProject(
            agentId: agentId,
            projectId: ProjectID(value: "prj_other")
        )
        XCTAssertEqual(otherUnread.count, 1)
    }

    // MARK: - Cleanup Tests

    func testDeleteOlderThan() throws {
        // 10日前の通知を作成
        var oldNotification = AgentNotification(
            id: NotificationID(value: "ntf_old"),
            targetAgentId: AgentID(value: "agt_001"),
            targetProjectId: ProjectID(value: "prj_001"),
            type: .statusChange,
            action: "blocked",
            taskId: nil,
            message: "Old message",
            instruction: "Old instruction",
            createdAt: Date().addingTimeInterval(-10 * 24 * 60 * 60), // 10日前
            isRead: true
        )

        // 今日の通知を作成
        let newNotification = createTestNotification(id: "ntf_new")

        try repository.save(oldNotification)
        try repository.save(newNotification)

        XCTAssertEqual(try repository.countAll(), 2)

        // 7日より古い通知を削除
        let deleted = try repository.deleteOlderThan(days: 7)

        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(try repository.countAll(), 1)
        XCTAssertNil(try repository.findById(oldNotification.id))
        XCTAssertNotNil(try repository.findById(newNotification.id))
    }

    // MARK: - Count Tests

    func testCountAll() throws {
        XCTAssertEqual(try repository.countAll(), 0)

        try repository.save(createTestNotification(id: "ntf_001"))
        XCTAssertEqual(try repository.countAll(), 1)

        try repository.save(createTestNotification(id: "ntf_002"))
        XCTAssertEqual(try repository.countAll(), 2)
    }

    // MARK: - Notification Type Tests

    func testSaveAndFindDifferentTypes() throws {
        let statusNotif = createTestNotification(id: "ntf_status", type: .statusChange)
        let interruptNotif = createTestNotification(id: "ntf_interrupt", type: .interrupt)
        let messageNotif = createTestNotification(id: "ntf_message", type: .message)

        try repository.save(statusNotif)
        try repository.save(interruptNotif)
        try repository.save(messageNotif)

        let found1 = try repository.findById(statusNotif.id)
        XCTAssertEqual(found1?.type, .statusChange)

        let found2 = try repository.findById(interruptNotif.id)
        XCTAssertEqual(found2?.type, .interrupt)

        let found3 = try repository.findById(messageNotif.id)
        XCTAssertEqual(found3?.type, .message)
    }
}
