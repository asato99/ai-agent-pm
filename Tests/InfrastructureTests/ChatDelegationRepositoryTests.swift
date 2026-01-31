// Tests/InfrastructureTests/ChatDelegationRepositoryTests.swift
// チャットセッション委譲リポジトリ - Infrastructure層テスト
// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md

import XCTest
import GRDB
@testable import Domain
@testable import Infrastructure

final class ChatDelegationRepositoryTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var repository: ChatDelegationRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // 一時ファイルのDBを作成
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_delegation_\(UUID().uuidString).db").path
        dbQueue = try DatabaseSetup.createDatabase(at: dbPath)
        repository = ChatDelegationRepository(database: dbQueue)

        // テスト用のプロジェクトとエージェントを作成
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO projects (id, name, status, description, created_at, updated_at)
                VALUES ('prj_001', 'Test Project', 'active', 'Test', datetime('now'), datetime('now'))
            """)
            try db.execute(sql: """
                INSERT INTO agents (id, name, role, type, status, role_type, created_at, updated_at)
                VALUES ('agt_001', 'Worker A', 'developer', 'worker', 'active', 'developer', datetime('now'), datetime('now'))
            """)
            try db.execute(sql: """
                INSERT INTO agents (id, name, role, type, status, role_type, created_at, updated_at)
                VALUES ('agt_002', 'Worker B', 'developer', 'worker', 'active', 'developer', datetime('now'), datetime('now'))
            """)
            try db.execute(sql: """
                INSERT INTO agents (id, name, role, type, status, role_type, created_at, updated_at)
                VALUES ('worker-a', 'Worker A', 'developer', 'worker', 'active', 'developer', datetime('now'), datetime('now'))
            """)
            try db.execute(sql: """
                INSERT INTO agents (id, name, role, type, status, role_type, created_at, updated_at)
                VALUES ('worker-b', 'Worker B', 'developer', 'worker', 'active', 'developer', datetime('now'), datetime('now'))
            """)
            // testHasPendingReturnsFalseWhenDifferentProject用
            try db.execute(sql: """
                INSERT INTO projects (id, name, status, description, created_at, updated_at)
                VALUES ('prj_other', 'Other Project', 'active', 'Test', datetime('now'), datetime('now'))
            """)
        }
    }

    override func tearDownWithError() throws {
        repository = nil
        dbQueue = nil
        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    private func createTestDelegation(
        id: String = "dlg_test001",
        agentId: String = "agt_001",
        projectId: String = "prj_001",
        targetAgentId: String = "agt_002",
        purpose: String = "テスト委譲",
        context: String? = nil,
        status: ChatDelegationStatus = .pending
    ) -> ChatDelegation {
        ChatDelegation(
            id: ChatDelegationID(value: id),
            agentId: AgentID(value: agentId),
            projectId: ProjectID(value: projectId),
            targetAgentId: AgentID(value: targetAgentId),
            purpose: purpose,
            context: context,
            status: status,
            createdAt: Date()
        )
    }

    // MARK: - Save & Find Tests

    /// テストケース1: 委譲リクエストの保存
    func testSaveDelegation() throws {
        let delegation = createTestDelegation(
            purpose: "6往復しりとりをしてほしい"
        )

        try repository.save(delegation)

        let fetched = try repository.findById(delegation.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, delegation.id)
        XCTAssertEqual(fetched?.agentId.value, "agt_001")
        XCTAssertEqual(fetched?.projectId.value, "prj_001")
        XCTAssertEqual(fetched?.targetAgentId.value, "agt_002")
        XCTAssertEqual(fetched?.purpose, "6往復しりとりをしてほしい")
        XCTAssertEqual(fetched?.status, .pending)
        XCTAssertNil(fetched?.processedAt)
    }

    func testFindByIdNotFound() throws {
        let found = try repository.findById(ChatDelegationID(value: "dlg_nonexistent"))
        XCTAssertNil(found)
    }

    // MARK: - Find Pending Tests

    /// テストケース2: エージェントの保留中委譲を取得
    func testFindPendingDelegationsForAgent() throws {
        // worker-aに2件のpending委譲
        let d1 = createTestDelegation(id: "dlg_001", agentId: "worker-a", status: .pending)
        let d2 = createTestDelegation(id: "dlg_002", agentId: "worker-a", status: .pending)
        // worker-aに1件のcompleted委譲（取得されない）
        let d3 = createTestDelegation(id: "dlg_003", agentId: "worker-a", status: .completed)
        // worker-bに1件のpending委譲（取得されない）
        let d4 = createTestDelegation(id: "dlg_004", agentId: "worker-b", status: .pending)

        try repository.save(d1)
        try repository.save(d2)
        try repository.save(d3)
        try repository.save(d4)

        let delegations = try repository.findPendingByAgentId(
            AgentID(value: "worker-a"),
            projectId: ProjectID(value: "prj_001")
        )

        XCTAssertEqual(delegations.count, 2)
        XCTAssertTrue(delegations.allSatisfy { $0.status == .pending })
        XCTAssertTrue(delegations.allSatisfy { $0.agentId.value == "worker-a" })
    }

    // MARK: - Has Pending Tests

    func testHasPendingReturnsTrueWhenExists() throws {
        let delegation = createTestDelegation(status: .pending)
        try repository.save(delegation)

        let hasPending = try repository.hasPending(
            agentId: AgentID(value: "agt_001"),
            projectId: ProjectID(value: "prj_001")
        )

        XCTAssertTrue(hasPending)
    }

    func testHasPendingReturnsFalseWhenNone() throws {
        // 何も保存しない
        let hasPending = try repository.hasPending(
            agentId: AgentID(value: "agt_001"),
            projectId: ProjectID(value: "prj_001")
        )

        XCTAssertFalse(hasPending)
    }

    func testHasPendingReturnsFalseWhenOnlyCompleted() throws {
        let delegation = createTestDelegation(status: .completed)
        try repository.save(delegation)

        let hasPending = try repository.hasPending(
            agentId: AgentID(value: "agt_001"),
            projectId: ProjectID(value: "prj_001")
        )

        XCTAssertFalse(hasPending)
    }

    func testHasPendingReturnsFalseWhenDifferentProject() throws {
        let delegation = createTestDelegation(
            projectId: "prj_other",
            status: .pending
        )
        try repository.save(delegation)

        let hasPending = try repository.hasPending(
            agentId: AgentID(value: "agt_001"),
            projectId: ProjectID(value: "prj_001")
        )

        XCTAssertFalse(hasPending)
    }

    // MARK: - Update Status Tests

    /// テストケース3: ステータス更新
    func testUpdateDelegationStatus() throws {
        let delegation = createTestDelegation(status: .pending)
        try repository.save(delegation)

        try repository.updateStatus(delegation.id, status: .processing)

        let fetched = try repository.findById(delegation.id)
        XCTAssertEqual(fetched?.status, .processing)
    }

    // MARK: - Mark Completed / Failed Tests

    func testMarkCompleted() throws {
        let delegation = createTestDelegation(status: .processing)
        try repository.save(delegation)

        try repository.markCompleted(delegation.id, result: "会話が完了しました")

        let fetched = try repository.findById(delegation.id)
        XCTAssertEqual(fetched?.status, .completed)
        XCTAssertNotNil(fetched?.processedAt)
        XCTAssertEqual(fetched?.result, "会話が完了しました")
    }

    func testMarkFailed() throws {
        let delegation = createTestDelegation(status: .processing)
        try repository.save(delegation)

        try repository.markFailed(delegation.id, result: "エラー: 相手エージェントが見つかりません")

        let fetched = try repository.findById(delegation.id)
        XCTAssertEqual(fetched?.status, .failed)
        XCTAssertNotNil(fetched?.processedAt)
        XCTAssertEqual(fetched?.result, "エラー: 相手エージェントが見つかりません")
    }

    // MARK: - Context Tests

    func testSaveDelegationWithContext() throws {
        let delegation = createTestDelegation(
            purpose: "相談してほしい",
            context: "前回の会話で未解決だった件について"
        )

        try repository.save(delegation)

        let fetched = try repository.findById(delegation.id)
        XCTAssertEqual(fetched?.context, "前回の会話で未解決だった件について")
    }
}
