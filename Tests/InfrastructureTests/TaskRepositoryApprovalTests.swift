// Tests/InfrastructureTests/TaskRepositoryApprovalTests.swift
// 参照: docs/design/TASK_REQUEST_APPROVAL.md - Task承認機能のInfrastructure層テスト

import XCTest
import GRDB
@testable import Domain
@testable import Infrastructure

/// TaskRepository承認関連機能のテスト
final class TaskRepositoryApprovalTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var taskRepository: TaskRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // 一時ファイルのDBを作成
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_task_approval_\(UUID().uuidString).db").path
        dbQueue = try DatabaseSetup.createDatabase(at: dbPath)
        taskRepository = TaskRepository(database: dbQueue)

        // テスト用プロジェクトを作成
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO projects (id, name, status, description, created_at, updated_at)
                VALUES ('prj_test', 'Test Project', 'active', 'Test', datetime('now'), datetime('now'))
            """)
        }
    }

    override func tearDownWithError() throws {
        taskRepository = nil
        dbQueue = nil
        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    private func makeTask(
        id: String = "task_001",
        title: String = "Test Task",
        approvalStatus: ApprovalStatus = .approved,
        requesterId: String? = nil,
        approvedBy: String? = nil,
        rejectedReason: String? = nil
    ) -> Task {
        Task(
            id: TaskID(value: id),
            projectId: ProjectID(value: "prj_test"),
            title: title,
            requesterId: requesterId.map { AgentID(value: $0) },
            approvalStatus: approvalStatus,
            rejectedReason: rejectedReason,
            approvedBy: approvedBy.map { AgentID(value: $0) }
        )
    }

    // MARK: - 承認ステータス永続化テスト

    /// approvalStatus が正しく永続化される
    func test_save_approvalStatus_persisted() throws {
        // Given
        let task = makeTask(
            id: "task_pending",
            approvalStatus: .pendingApproval
        )

        // When
        try taskRepository.save(task)
        let found = try taskRepository.findById(task.id)

        // Then
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.approvalStatus, .pendingApproval)
    }

    /// requesterId が正しく永続化される
    func test_save_requesterId_persisted() throws {
        // Given
        let task = makeTask(
            id: "task_requested",
            requesterId: "requester-agent"
        )

        // When
        try taskRepository.save(task)
        let found = try taskRepository.findById(task.id)

        // Then
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.requesterId?.value, "requester-agent")
    }

    /// approvedBy と approvedAt が正しく永続化される
    func test_save_approvalInfo_persisted() throws {
        // Given
        var task = makeTask(
            id: "task_approved",
            approvalStatus: .pendingApproval
        )
        task.approve(by: AgentID(value: "approver-agent"))

        // When
        try taskRepository.save(task)
        let found = try taskRepository.findById(task.id)

        // Then
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.approvalStatus, .approved)
        XCTAssertEqual(found?.approvedBy?.value, "approver-agent")
        XCTAssertNotNil(found?.approvedAt)
    }

    /// rejectedReason が正しく永続化される
    func test_save_rejectedReason_persisted() throws {
        // Given
        var task = makeTask(
            id: "task_rejected",
            approvalStatus: .pendingApproval
        )
        task.reject(reason: "優先度が低いため却下")

        // When
        try taskRepository.save(task)
        let found = try taskRepository.findById(task.id)

        // Then
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.approvalStatus, .rejected)
        XCTAssertEqual(found?.rejectedReason, "優先度が低いため却下")
    }

    // MARK: - 承認待ちタスク検索テスト

    /// findPendingApproval() で承認待ちタスクのみ取得できる
    func test_findPendingApproval_returnsOnlyPendingTasks() throws {
        // Given
        let pendingTask1 = makeTask(id: "pending-1", approvalStatus: .pendingApproval)
        let pendingTask2 = makeTask(id: "pending-2", approvalStatus: .pendingApproval)
        let approvedTask = makeTask(id: "approved-1", approvalStatus: .approved)
        let rejectedTask = makeTask(id: "rejected-1", approvalStatus: .rejected)

        try taskRepository.save(pendingTask1)
        try taskRepository.save(pendingTask2)
        try taskRepository.save(approvedTask)
        try taskRepository.save(rejectedTask)

        // When
        let pendingTasks = try taskRepository.findPendingApproval(projectId: ProjectID(value: "prj_test"))

        // Then
        XCTAssertEqual(pendingTasks.count, 2)
        XCTAssertTrue(pendingTasks.allSatisfy { $0.approvalStatus == .pendingApproval })
    }

    /// findPendingApproval() はプロジェクト単位でフィルタリングする
    func test_findPendingApproval_filtersByProject() throws {
        // Given - 別プロジェクトを作成
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO projects (id, name, status, description, created_at, updated_at)
                VALUES ('prj_other', 'Other Project', 'active', 'Other', datetime('now'), datetime('now'))
            """)
        }

        let task1 = makeTask(id: "pending-prj-test", approvalStatus: .pendingApproval)
        let task2 = Task(
            id: TaskID(value: "pending-prj-other"),
            projectId: ProjectID(value: "prj_other"),
            title: "Other Project Task",
            approvalStatus: .pendingApproval
        )

        try taskRepository.save(task1)
        try taskRepository.save(task2)

        // When
        let pendingTasks = try taskRepository.findPendingApproval(projectId: ProjectID(value: "prj_test"))

        // Then
        XCTAssertEqual(pendingTasks.count, 1)
        XCTAssertEqual(pendingTasks.first?.id.value, "pending-prj-test")
    }
}
