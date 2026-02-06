// Tests/InfrastructureTests/ChatFileRepositoryTests.swift
// チャットファイルリポジトリ - Infrastructure層テスト
// 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 1-2

import XCTest
import GRDB
@testable import Domain
@testable import Infrastructure

final class ChatFileRepositoryTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var projectRepository: ProjectRepository!
    private var directoryManager: ProjectDirectoryManager!
    private var repository: ChatFileRepository!
    private var testWorkingDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // 一時ファイルのDBを作成
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_chat_\(UUID().uuidString).db").path
        dbQueue = try DatabaseSetup.createDatabase(at: dbPath)
        projectRepository = ProjectRepository(database: dbQueue)
        directoryManager = ProjectDirectoryManager()

        // テスト用の作業ディレクトリを作成
        testWorkingDir = tempDir.appendingPathComponent("test_project_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testWorkingDir, withIntermediateDirectories: true)

        // テスト用のプロジェクトを作成
        let project = Project(
            id: ProjectID(value: "prj_chat_test"),
            name: "Chat Test Project",
            description: "Test",
            status: .active,
            workingDirectory: testWorkingDir.path,
            createdAt: Date(),
            updatedAt: Date()
        )
        try projectRepository.save(project)

        repository = ChatFileRepository(
            directoryManager: directoryManager,
            projectRepository: projectRepository
        )
    }

    override func tearDownWithError() throws {
        // テスト用ディレクトリを削除
        if let testWorkingDir = testWorkingDir {
            try? FileManager.default.removeItem(at: testWorkingDir)
        }
        repository = nil
        directoryManager = nil
        projectRepository = nil
        dbQueue = nil
        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    private func createTestMessage(
        id: String,
        senderId: String,
        receiverId: String? = nil,
        content: String,
        conversationId: String? = nil
    ) -> ChatMessage {
        ChatMessage(
            id: ChatMessageID(value: id),
            senderId: AgentID(value: senderId),
            receiverId: receiverId.map { AgentID(value: $0) },
            content: content,
            createdAt: Date(),
            relatedTaskId: nil,
            relatedHandoffId: nil,
            conversationId: conversationId.map { ConversationID(value: $0) }
        )
    }

    // MARK: - findByConversationId Tests (Phase 1-2)

    func testFindByConversationIdReturnsMatchingMessages() throws {
        // Given: 複数のメッセージ（異なるconversationIdを持つ）を保存
        let projectId = ProjectID(value: "prj_chat_test")
        let agentId = AgentID(value: "worker-01")
        let targetConversationId = ConversationID(value: "conv_target")

        let msg1 = createTestMessage(
            id: "msg_001",
            senderId: "manager-01",
            content: "Message 1 in target conversation",
            conversationId: "conv_target"
        )
        let msg2 = createTestMessage(
            id: "msg_002",
            senderId: "worker-01",
            content: "Message 2 in target conversation",
            conversationId: "conv_target"
        )
        let msg3 = createTestMessage(
            id: "msg_003",
            senderId: "manager-01",
            content: "Message in different conversation",
            conversationId: "conv_other"
        )
        let msg4 = createTestMessage(
            id: "msg_004",
            senderId: "manager-01",
            content: "Message without conversation",
            conversationId: nil
        )

        try repository.saveMessage(msg1, projectId: projectId, agentId: agentId)
        try repository.saveMessage(msg2, projectId: projectId, agentId: agentId)
        try repository.saveMessage(msg3, projectId: projectId, agentId: agentId)
        try repository.saveMessage(msg4, projectId: projectId, agentId: agentId)

        // When: findByConversationIdを呼び出す
        let result = try repository.findByConversationId(
            projectId: projectId,
            agentId: agentId,
            conversationId: targetConversationId
        )

        // Then: 対象のconversationIdを持つメッセージのみ返される
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.conversationId == targetConversationId })
        XCTAssertEqual(result[0].id.value, "msg_001")
        XCTAssertEqual(result[1].id.value, "msg_002")
    }

    func testFindByConversationIdReturnsEmptyWhenNoMatch() throws {
        // Given: 異なるconversationIdのメッセージのみ存在
        let projectId = ProjectID(value: "prj_chat_test")
        let agentId = AgentID(value: "worker-01")
        let nonExistentConversationId = ConversationID(value: "conv_nonexistent")

        let msg = createTestMessage(
            id: "msg_001",
            senderId: "manager-01",
            content: "Message with different conversation",
            conversationId: "conv_other"
        )
        try repository.saveMessage(msg, projectId: projectId, agentId: agentId)

        // When: 存在しないconversationIdで検索
        let result = try repository.findByConversationId(
            projectId: projectId,
            agentId: agentId,
            conversationId: nonExistentConversationId
        )

        // Then: 空の配列が返される
        XCTAssertTrue(result.isEmpty)
    }

    func testFindByConversationIdReturnsMessagesInChronologicalOrder() throws {
        // Given: 複数のメッセージを保存（順序を確認）
        let projectId = ProjectID(value: "prj_chat_test")
        let agentId = AgentID(value: "worker-01")
        let conversationId = ConversationID(value: "conv_order_test")

        // メッセージを順番に保存
        for i in 1...5 {
            let msg = ChatMessage(
                id: ChatMessageID(value: "msg_\(String(format: "%03d", i))"),
                senderId: AgentID(value: i % 2 == 0 ? "worker-01" : "manager-01"),
                content: "Message \(i)",
                createdAt: Date().addingTimeInterval(Double(i)),
                conversationId: conversationId
            )
            try repository.saveMessage(msg, projectId: projectId, agentId: agentId)
        }

        // When: findByConversationIdを呼び出す
        let result = try repository.findByConversationId(
            projectId: projectId,
            agentId: agentId,
            conversationId: conversationId
        )

        // Then: 保存順（時系列順）で返される
        XCTAssertEqual(result.count, 5)
        for i in 0..<5 {
            XCTAssertEqual(result[i].id.value, "msg_\(String(format: "%03d", i + 1))")
        }
    }

    func testFindByConversationIdWithEmptyFile() throws {
        // Given: チャットファイルが存在しない
        let projectId = ProjectID(value: "prj_chat_test")
        let agentId = AgentID(value: "new-agent")
        let conversationId = ConversationID(value: "conv_empty")

        // When: findByConversationIdを呼び出す
        let result = try repository.findByConversationId(
            projectId: projectId,
            agentId: agentId,
            conversationId: conversationId
        )

        // Then: 空の配列が返される
        XCTAssertTrue(result.isEmpty)
    }
}
