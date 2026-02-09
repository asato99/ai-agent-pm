// Tests/MCPServerTests/ChatCommandMarkerValidationTests.swift
// チャットコマンドマーカーのバリデーションテスト（MCPServer統合テスト）
// 参照: docs/design/CHAT_COMMAND_MARKER.md

import XCTest
import GRDB
@testable import Domain
@testable import UseCase
@testable import Infrastructure

/// request_task / notify_task_session のマーカーバリデーションテスト
/// チャット履歴の最新受信メッセージにマーカーが含まれているかを検証する
final class ChatCommandMarkerValidationTests: XCTestCase {

    private var dbQueue: DatabaseQueue!
    private var mcpServer: MCPServer!
    private var agentSessionRepository: AgentSessionRepository!
    private var agentRepository: AgentRepository!
    private var projectRepository: ProjectRepository!
    private var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!
    private var agentCredentialRepository: AgentCredentialRepository!
    private var taskRepository: TaskRepository!

    // テストデータ
    private let ownerId = AgentID(value: "owner-01")
    private let workerId = AgentID(value: "worker-01")
    private let projectId = ProjectID(value: "prj_marker_test")

    override func setUpWithError() throws {
        try super.setUpWithError()

        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_marker_validation_\(UUID().uuidString).db").path
        dbQueue = try DatabaseSetup.createDatabase(at: dbPath)
        mcpServer = MCPServer(database: dbQueue, transport: NullTransport())

        agentSessionRepository = AgentSessionRepository(database: dbQueue)
        agentRepository = AgentRepository(database: dbQueue)
        projectRepository = ProjectRepository(database: dbQueue)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: dbQueue)
        agentCredentialRepository = AgentCredentialRepository(database: dbQueue)
        taskRepository = TaskRepository(database: dbQueue)

        try setupTestData()
    }

    override func tearDownWithError() throws {
        mcpServer = nil
        agentSessionRepository = nil
        agentRepository = nil
        projectRepository = nil
        projectAgentAssignmentRepository = nil
        agentCredentialRepository = nil
        taskRepository = nil
        dbQueue = nil
        try super.tearDownWithError()
    }

    private func setupTestData() throws {
        // プロジェクト作成
        var project = Project(
            id: projectId,
            name: "Marker Test Project",
            description: "Test for chat command marker validation"
        )
        project.workingDirectory = FileManager.default.temporaryDirectory.path
        try projectRepository.save(project)

        // オーナーエージェント作成（ユーザー側・humanタイプ）
        let owner = Agent(
            id: ownerId,
            name: "Owner",
            role: "manager",
            type: .human,
            hierarchyType: .manager,
            systemPrompt: "Test manager"
        )
        try agentRepository.save(owner)

        // ワーカーエージェント作成
        let worker = Agent(
            id: workerId,
            name: "Worker",
            role: "developer",
            hierarchyType: .worker,
            parentAgentId: ownerId,
            systemPrompt: "Test worker"
        )
        try agentRepository.save(worker)

        // プロジェクト割り当て
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: ownerId)
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: workerId)

        // 認証情報作成
        let credentialOwner = AgentCredential(agentId: ownerId, rawPasskey: "passkey_owner")
        try agentCredentialRepository.save(credentialOwner)
        let credentialWorker = AgentCredential(agentId: workerId, rawPasskey: "passkey_worker")
        try agentCredentialRepository.save(credentialWorker)
    }

    // MARK: - Helper

    /// オーナーからワーカーへチャットメッセージを送信
    private func sendMessageFromOwnerToWorker(content: String) throws {
        let ownerChatSession = AgentSession(
            agentId: ownerId,
            projectId: projectId,
            purpose: .chat
        )
        try agentSessionRepository.save(ownerChatSession)
        let ownerCaller = CallerType.worker(agentId: ownerId, session: ownerChatSession)

        _ = try mcpServer.executeTool(
            name: "send_message",
            arguments: [
                "session_token": ownerChatSession.token,
                "target_agent_id": workerId.value,
                "content": content
            ],
            caller: ownerCaller
        )
    }

    /// ワーカーのチャットセッションを作成してCallerTypeを返す
    private func createWorkerChatCaller() throws -> (session: AgentSession, caller: CallerType) {
        let workerChatSession = AgentSession(
            agentId: workerId,
            projectId: projectId,
            purpose: .chat
        )
        try agentSessionRepository.save(workerChatSession)
        let caller = CallerType.worker(agentId: workerId, session: workerChatSession)
        return (workerChatSession, caller)
    }

    /// ワーカーのタスクセッションを作成してCallerTypeを返す
    private func createWorkerTaskCaller() throws -> (session: AgentSession, caller: CallerType) {
        let workerTaskSession = AgentSession(
            agentId: workerId,
            projectId: projectId,
            purpose: .task
        )
        try agentSessionRepository.save(workerTaskSession)
        let caller = CallerType.worker(agentId: workerId, session: workerTaskSession)
        return (workerTaskSession, caller)
    }

    /// テスト用タスクを作成（ワーカーにアサイン済み）
    private func createTestTask() throws -> Domain.Task {
        let task = Domain.Task(
            id: TaskID(value: "task_marker_test_\(UUID().uuidString.prefix(8))"),
            projectId: projectId,
            title: "テスト用タスク",
            assigneeId: workerId,
            createdByAgentId: ownerId
        )
        try taskRepository.save(task)
        return task
    }

    // MARK: - MCPError定義テスト

    /// taskRequestMarkerRequired エラーが定義されていることを確認
    func testTaskRequestMarkerRequiredErrorDefined() {
        let error = MCPError.taskRequestMarkerRequired
        XCTAssertTrue(
            error.description.contains("@@タスク作成:") || error.description.contains("マーカー"),
            "Error message should mention the marker requirement"
        )
    }

    /// taskNotifyMarkerRequired エラーが定義されていることを確認
    func testTaskNotifyMarkerRequiredErrorDefined() {
        let error = MCPError.taskNotifyMarkerRequired
        XCTAssertTrue(
            error.description.contains("@@タスク通知:") || error.description.contains("マーカー"),
            "Error message should mention the marker requirement"
        )
    }

    /// taskAdjustMarkerRequired エラーが定義されていることを確認
    func testTaskAdjustMarkerRequiredErrorDefined() {
        let error = MCPError.taskAdjustMarkerRequired
        XCTAssertTrue(
            error.description.contains("@@タスク調整:") || error.description.contains("マーカー"),
            "Error message should mention the marker requirement"
        )
    }

    // MARK: - request_task バリデーションテスト

    /// チャットセッションで、チャット履歴にマーカー付きメッセージがある場合 → request_task 成功
    func testRequestTaskWithMarkerInChatHistorySucceeds() throws {
        // オーナーからマーカー付きメッセージを送信
        try sendMessageFromOwnerToWorker(content: "@@タスク作成: ログイン機能を実装")

        // ワーカーのチャットセッションから request_task を呼び出す
        let (_, workerCaller) = try createWorkerChatCaller()

        let result = try mcpServer.executeTool(
            name: "request_task",
            arguments: [
                "title": "ログイン機能を実装"
            ],
            caller: workerCaller
        )

        // 成功したことを確認
        guard let resultDict = result as? [String: Any],
              let success = resultDict["success"] as? Bool else {
            XCTFail("Failed to parse result: \(result)")
            return
        }
        XCTAssertTrue(success, "request_task should succeed when marker exists in chat history")
    }

    /// チャットセッションで、チャット履歴にマーカーがない場合 → request_task エラー
    func testRequestTaskWithoutMarkerInChatHistoryFails() throws {
        // オーナーからマーカーなしメッセージを送信
        try sendMessageFromOwnerToWorker(content: "ログイン機能を実装してください")

        // ワーカーのチャットセッションから request_task を呼び出す
        let (_, workerCaller) = try createWorkerChatCaller()

        XCTAssertThrowsError(
            try mcpServer.executeTool(
                name: "request_task",
                arguments: [
                    "title": "ログイン機能を実装"
                ],
                caller: workerCaller
            ),
            "request_task should fail when no marker in chat history"
        ) { error in
            guard let mcpError = error as? MCPError else {
                XCTFail("Expected MCPError but got: \(error)")
                return
            }
            XCTAssertEqual(
                String(describing: mcpError),
                String(describing: MCPError.taskRequestMarkerRequired),
                "Should throw taskRequestMarkerRequired error"
            )
        }
    }

    /// タスクセッションからの呼び出しはマーカーバリデーション対象外 → 成功
    func testRequestTaskFromTaskSessionSkipsValidation() throws {
        // タスクセッションではチャット履歴のマーカーチェックをスキップ
        let (_, workerCaller) = try createWorkerTaskCaller()

        let result = try mcpServer.executeTool(
            name: "request_task",
            arguments: [
                "title": "タスクセッションからのタスク作成"
            ],
            caller: workerCaller
        )

        guard let resultDict = result as? [String: Any],
              let success = resultDict["success"] as? Bool else {
            XCTFail("Failed to parse result: \(result)")
            return
        }
        XCTAssertTrue(success, "request_task from task session should succeed without marker")
    }

    // MARK: - notify_task_session バリデーションテスト

    /// チャットセッションで、チャット履歴にマーカー付きメッセージがある場合 → notify_task_session 成功
    func testNotifyWithMarkerSucceeds() throws {
        // オーナーから通知マーカー付きメッセージを送信
        try sendMessageFromOwnerToWorker(content: "@@タスク通知: デプロイが完了しました")

        // ワーカーのチャットセッションから notify_task_session を呼び出す
        let (_, workerCaller) = try createWorkerChatCaller()

        let result = try mcpServer.executeTool(
            name: "notify_task_session",
            arguments: [
                "message": "デプロイが完了しました"
            ],
            caller: workerCaller
        )

        guard let resultDict = result as? [String: Any],
              let success = resultDict["success"] as? Bool else {
            XCTFail("Failed to parse result: \(result)")
            return
        }
        XCTAssertTrue(success, "notify_task_session should succeed when marker exists in chat history")
    }

    /// チャットセッションで、チャット履歴にマーカーがない場合 → notify_task_session エラー
    func testNotifyWithoutMarkerFails() throws {
        // オーナーからマーカーなしメッセージを送信
        try sendMessageFromOwnerToWorker(content: "デプロイが完了しました")

        // ワーカーのチャットセッションから notify_task_session を呼び出す
        let (_, workerCaller) = try createWorkerChatCaller()

        XCTAssertThrowsError(
            try mcpServer.executeTool(
                name: "notify_task_session",
                arguments: [
                    "message": "デプロイが完了しました"
                ],
                caller: workerCaller
            ),
            "notify_task_session should fail when no marker in chat history"
        ) { error in
            guard let mcpError = error as? MCPError else {
                XCTFail("Expected MCPError but got: \(error)")
                return
            }
            XCTAssertEqual(
                String(describing: mcpError),
                String(describing: MCPError.taskNotifyMarkerRequired),
                "Should throw taskNotifyMarkerRequired error"
            )
        }
    }

    // MARK: - update_task_from_chat バリデーションテスト

    /// チャットセッションで、チャット履歴にマーカー付きメッセージがある場合 → update_task_from_chat 成功
    func testUpdateTaskFromChatWithMarkerSucceeds() throws {
        // テスト用タスクを作成
        let task = try createTestTask()

        // オーナーから調整マーカー付きメッセージを送信
        try sendMessageFromOwnerToWorker(content: "@@タスク調整: 説明を更新してください")

        // ワーカーのチャットセッションから update_task_from_chat を呼び出す
        let (_, workerCaller) = try createWorkerChatCaller()

        let result = try mcpServer.executeTool(
            name: "update_task_from_chat",
            arguments: [
                "task_id": task.id.value,
                "requester_id": ownerId.value,
                "description": "更新された説明文"
            ],
            caller: workerCaller
        )

        guard let resultDict = result as? [String: Any],
              let success = resultDict["success"] as? Bool else {
            XCTFail("Failed to parse result: \(result)")
            return
        }
        XCTAssertTrue(success, "update_task_from_chat should succeed when marker exists in chat history")
    }

    /// チャットセッションで、チャット履歴にマーカーがない場合 → update_task_from_chat エラー
    func testUpdateTaskFromChatWithoutMarkerFails() throws {
        // テスト用タスクを作成
        let task = try createTestTask()

        // オーナーからマーカーなしメッセージを送信
        try sendMessageFromOwnerToWorker(content: "説明を更新してください")

        // ワーカーのチャットセッションから update_task_from_chat を呼び出す
        let (_, workerCaller) = try createWorkerChatCaller()

        XCTAssertThrowsError(
            try mcpServer.executeTool(
                name: "update_task_from_chat",
                arguments: [
                    "task_id": task.id.value,
                    "requester_id": ownerId.value,
                    "description": "更新された説明文"
                ],
                caller: workerCaller
            ),
            "update_task_from_chat should fail when no marker in chat history"
        ) { error in
            guard let mcpError = error as? MCPError else {
                XCTFail("Expected MCPError but got: \(error)")
                return
            }
            XCTAssertEqual(
                String(describing: mcpError),
                String(describing: MCPError.taskAdjustMarkerRequired),
                "Should throw taskAdjustMarkerRequired error"
            )
        }
    }
}
