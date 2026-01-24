// Tests/DomainTests/TaskApprovalTests.swift
// 参照: docs/design/TASK_REQUEST_APPROVAL.md - Task承認機能

import XCTest
@testable import Domain

/// Task承認関連プロパティのテスト
/// 要件: approval_status, requester_id, approved_by, rejected_reason 等
final class TaskApprovalTests: XCTestCase {

    // MARK: - テストデータ

    private func makeTaskID() -> TaskID {
        TaskID(value: UUID().uuidString)
    }

    private func makeProjectID() -> ProjectID {
        ProjectID(value: UUID().uuidString)
    }

    private func makeAgentID(_ value: String = UUID().uuidString) -> AgentID {
        AgentID(value: value)
    }

    // MARK: - ApprovalStatus デフォルト値

    /// デフォルトの承認ステータスはapproved
    func test_task_defaultApprovalStatus_isApproved() {
        // Given
        let task = Task(
            id: makeTaskID(),
            projectId: makeProjectID(),
            title: "Test Task"
        )

        // Then
        XCTAssertEqual(task.approvalStatus, .approved, "デフォルトはapproved")
    }

    // MARK: - 依頼者情報

    /// 依頼者IDを設定できる
    func test_task_requesterId_canBeSet() {
        // Given
        let requesterId = makeAgentID("requester-1")

        // When
        let task = Task(
            id: makeTaskID(),
            projectId: makeProjectID(),
            title: "Requested Task",
            requesterId: requesterId
        )

        // Then
        XCTAssertEqual(task.requesterId, requesterId, "依頼者IDが設定される")
    }

    // MARK: - 承認待ちステータス

    /// pending_approval ステータスで作成できる
    func test_task_pendingApprovalStatus() {
        // Given/When
        let task = Task(
            id: makeTaskID(),
            projectId: makeProjectID(),
            title: "Pending Task",
            approvalStatus: .pendingApproval
        )

        // Then
        XCTAssertEqual(task.approvalStatus, .pendingApproval, "pending_approvalで作成できる")
    }

    // MARK: - 承認処理

    /// タスクを承認するとステータスと承認情報が設定される
    func test_task_approve_setsApprovalInfo() {
        // Given
        var task = Task(
            id: makeTaskID(),
            projectId: makeProjectID(),
            title: "Task to Approve",
            approvalStatus: .pendingApproval
        )
        let approverId = makeAgentID("approver-1")
        let approvedAt = Date()

        // When
        task.approve(by: approverId, at: approvedAt)

        // Then
        XCTAssertEqual(task.approvalStatus, .approved, "承認後はapproved")
        XCTAssertEqual(task.approvedBy, approverId, "承認者が設定される")
        XCTAssertEqual(task.approvedAt, approvedAt, "承認日時が設定される")
    }

    // MARK: - 却下処理

    /// タスクを却下するとステータスと理由が設定される
    func test_task_reject_setsReasonAndStatus() {
        // Given
        var task = Task(
            id: makeTaskID(),
            projectId: makeProjectID(),
            title: "Task to Reject",
            approvalStatus: .pendingApproval
        )
        let reason = "現在の優先度では対応できません"

        // When
        task.reject(reason: reason)

        // Then
        XCTAssertEqual(task.approvalStatus, .rejected, "却下後はrejected")
        XCTAssertEqual(task.rejectedReason, reason, "却下理由が設定される")
    }

    // MARK: - 承認待ち判定

    /// isPendingApproval プロパティ
    func test_task_isPendingApproval() {
        // Given
        let pendingTask = Task(
            id: makeTaskID(),
            projectId: makeProjectID(),
            title: "Pending",
            approvalStatus: .pendingApproval
        )
        let approvedTask = Task(
            id: makeTaskID(),
            projectId: makeProjectID(),
            title: "Approved",
            approvalStatus: .approved
        )

        // Then
        XCTAssertTrue(pendingTask.isPendingApproval, "pending_approvalはtrue")
        XCTAssertFalse(approvedTask.isPendingApproval, "approvedはfalse")
    }

    // MARK: - ApprovalStatus enum

    /// ApprovalStatus の displayName
    func test_approvalStatus_displayName() {
        XCTAssertEqual(ApprovalStatus.approved.displayName, "Approved")
        XCTAssertEqual(ApprovalStatus.pendingApproval.displayName, "Pending Approval")
        XCTAssertEqual(ApprovalStatus.rejected.displayName, "Rejected")
    }

    /// ApprovalStatus の rawValue
    func test_approvalStatus_rawValue() {
        XCTAssertEqual(ApprovalStatus.approved.rawValue, "approved")
        XCTAssertEqual(ApprovalStatus.pendingApproval.rawValue, "pending_approval")
        XCTAssertEqual(ApprovalStatus.rejected.rawValue, "rejected")
    }
}
