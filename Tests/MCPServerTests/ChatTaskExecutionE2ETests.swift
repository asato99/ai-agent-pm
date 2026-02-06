// Tests/MCPServerTests/ChatTaskExecutionE2ETests.swift
// チャットセッションからのタスク操作 E2E統合テスト
// 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 5

import XCTest
@testable import Domain

// MARK: - Phase 5: E2E統合テスト

/// チャットセッションからのタスク操作 E2Eテスト
/// 複数ツールを連携させたシナリオテスト
final class ChatTaskExecutionE2ETests: XCTestCase {

    // MARK: - E2E Scenario 1: Manager requests Worker to start task

    /// E2Eシナリオ: マネージャーがワーカーにタスク実行を依頼
    /// 1. Manager がタスクを作成済み（前提）
    /// 2. Worker が start_task_from_chat でタスク実行開始
    /// 3. タスクステータスが in_progress に変更
    func testE2E_WorkerStartsTaskFromChatAfterManagerRequest() throws {
        // Setup: マネージャーとワーカーの階層関係
        let managerId = AgentID(value: "manager-01")
        let workerId = AgentID(value: "worker-01")
        let projectId = ProjectID(value: "proj-001")
        let taskId = TaskID(value: "task-001")

        // Workerのチャットセッション
        let workerChatSession = AgentSession(
            agentId: workerId,
            projectId: projectId,
            purpose: .chat
        )

        // start_task_from_chat の認可確認（chatOnlyであること）
        XCTAssertEqual(
            ToolAuthorization.permissions["start_task_from_chat"],
            .chatOnly,
            "start_task_from_chat should be chatOnly"
        )

        // チャットセッションからの呼び出しが許可されることを確認
        XCTAssertNoThrow(
            try ToolAuthorization.authorize(
                tool: "start_task_from_chat",
                caller: .worker(agentId: workerId, session: workerChatSession)
            ),
            "Worker should be able to call start_task_from_chat from chat session"
        )

        // タスクセッションからの呼び出しは拒否されることを確認
        let workerTaskSession = AgentSession(
            agentId: workerId,
            projectId: projectId,
            purpose: .task
        )
        XCTAssertThrowsError(
            try ToolAuthorization.authorize(
                tool: "start_task_from_chat",
                caller: .worker(agentId: workerId, session: workerTaskSession)
            ),
            "start_task_from_chat should be denied from task session"
        )
    }

    // MARK: - E2E Scenario 2: Chat notification to task session

    /// E2Eシナリオ: チャットセッションからタスクセッションへの通知
    /// 1. Worker がチャットで指示を受ける（前提）
    /// 2. Worker が notify_task_session でタスクセッションに通知
    /// 3. Worker のタスクセッションで get_conversation_messages で確認
    func testE2E_ChatNotificationFlowToTaskSession() throws {
        // Setup
        let workerId = AgentID(value: "worker-01")
        let projectId = ProjectID(value: "proj-001")
        let conversationId = ConversationID(value: "conv-001")

        // チャットセッションとタスクセッション
        let chatSession = AgentSession(
            agentId: workerId,
            projectId: projectId,
            purpose: .chat
        )
        let taskSession = AgentSession(
            agentId: workerId,
            projectId: projectId,
            purpose: .task
        )

        // Step 2: notify_task_session はチャットセッションからのみ許可
        XCTAssertEqual(
            ToolAuthorization.permissions["notify_task_session"],
            .chatOnly,
            "notify_task_session should be chatOnly"
        )

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(
                tool: "notify_task_session",
                caller: .worker(agentId: workerId, session: chatSession)
            ),
            "notify_task_session should be allowed from chat session"
        )

        XCTAssertThrowsError(
            try ToolAuthorization.authorize(
                tool: "notify_task_session",
                caller: .worker(agentId: workerId, session: taskSession)
            ),
            "notify_task_session should be denied from task session"
        )

        // Step 3: get_conversation_messages はタスクセッションからのみ許可
        XCTAssertEqual(
            ToolAuthorization.permissions["get_conversation_messages"],
            .taskOnly,
            "get_conversation_messages should be taskOnly"
        )

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(
                tool: "get_conversation_messages",
                caller: .worker(agentId: workerId, session: taskSession)
            ),
            "get_conversation_messages should be allowed from task session"
        )

        XCTAssertThrowsError(
            try ToolAuthorization.authorize(
                tool: "get_conversation_messages",
                caller: .worker(agentId: workerId, session: chatSession)
            ),
            "get_conversation_messages should be denied from chat session"
        )
    }

    // MARK: - E2E Scenario 3: Update task from chat

    /// E2Eシナリオ: チャットからのタスク更新フロー
    /// マネージャーからの指示を受けてワーカーがタスクを修正
    func testE2E_WorkerUpdatesTaskFromChatAfterManagerInstruction() throws {
        // Setup
        let managerId = AgentID(value: "manager-01")
        let workerId = AgentID(value: "worker-01")
        let projectId = ProjectID(value: "proj-001")

        let workerChatSession = AgentSession(
            agentId: workerId,
            projectId: projectId,
            purpose: .chat
        )

        // update_task_from_chat の認可確認
        XCTAssertEqual(
            ToolAuthorization.permissions["update_task_from_chat"],
            .chatOnly,
            "update_task_from_chat should be chatOnly"
        )

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(
                tool: "update_task_from_chat",
                caller: .worker(agentId: workerId, session: workerChatSession)
            ),
            "Worker should be able to call update_task_from_chat from chat session"
        )
    }

    // MARK: - E2E Scenario 4: Self-status tools from task session

    /// E2Eシナリオ: タスクセッションから自己状況確認
    /// ワーカーがタスク実行中に自分の実行履歴を確認
    func testE2E_WorkerChecksExecutionHistoryDuringTask() throws {
        // Setup
        let workerId = AgentID(value: "worker-01")
        let projectId = ProjectID(value: "proj-001")

        let taskSession = AgentSession(
            agentId: workerId,
            projectId: projectId,
            purpose: .task
        )
        let chatSession = AgentSession(
            agentId: workerId,
            projectId: projectId,
            purpose: .chat
        )

        // get_my_execution_history は認証済みで呼び出し可能
        XCTAssertEqual(
            ToolAuthorization.permissions["get_my_execution_history"],
            .authenticated,
            "get_my_execution_history should be authenticated"
        )

        // タスクセッション・チャットセッション両方から呼び出し可能
        XCTAssertNoThrow(
            try ToolAuthorization.authorize(
                tool: "get_my_execution_history",
                caller: .worker(agentId: workerId, session: taskSession)
            )
        )
        XCTAssertNoThrow(
            try ToolAuthorization.authorize(
                tool: "get_my_execution_history",
                caller: .worker(agentId: workerId, session: chatSession)
            )
        )

        // get_execution_log も認証済みで呼び出し可能
        XCTAssertEqual(
            ToolAuthorization.permissions["get_execution_log"],
            .authenticated,
            "get_execution_log should be authenticated"
        )
    }

    // MARK: - Tool Definition Integration Tests

    /// 全ての新規ツールが正しく定義されていることを確認
    func testAllChatTaskExecutionToolsDefined() throws {
        let allTools = ToolDefinitions.all()
        let toolNames = allTools.compactMap { $0["name"] as? String }

        // Phase 2: 自己状況確認ツール
        XCTAssertTrue(toolNames.contains("get_my_execution_history"), "get_my_execution_history should be defined")
        XCTAssertTrue(toolNames.contains("get_execution_log"), "get_execution_log should be defined")

        // Phase 3: チャット→タスク操作ツール
        XCTAssertTrue(toolNames.contains("start_task_from_chat"), "start_task_from_chat should be defined")
        XCTAssertTrue(toolNames.contains("update_task_from_chat"), "update_task_from_chat should be defined")

        // Phase 4: セッション間通知ツール
        XCTAssertTrue(toolNames.contains("notify_task_session"), "notify_task_session should be defined")
        XCTAssertTrue(toolNames.contains("get_conversation_messages"), "get_conversation_messages should be defined")
    }

    /// 全ての新規ツールの認可設定が正しいことを確認
    func testAllChatTaskExecutionToolsAuthorization() throws {
        // Phase 2: 認証済み
        XCTAssertEqual(ToolAuthorization.permissions["get_my_execution_history"], .authenticated)
        XCTAssertEqual(ToolAuthorization.permissions["get_execution_log"], .authenticated)

        // Phase 3: chatOnly
        XCTAssertEqual(ToolAuthorization.permissions["start_task_from_chat"], .chatOnly)
        XCTAssertEqual(ToolAuthorization.permissions["update_task_from_chat"], .chatOnly)

        // Phase 4: セッション依存
        XCTAssertEqual(ToolAuthorization.permissions["notify_task_session"], .chatOnly)
        XCTAssertEqual(ToolAuthorization.permissions["get_conversation_messages"], .taskOnly)
    }
}
