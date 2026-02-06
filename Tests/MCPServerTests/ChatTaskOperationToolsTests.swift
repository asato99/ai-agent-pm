// Tests/MCPServerTests/ChatTaskOperationToolsTests.swift
// チャット→タスク操作ツールのテスト
// 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 3

import XCTest
@testable import Domain

// MARK: - Phase 3: チャット→タスク操作ツール

/// start_task_from_chat / update_task_from_chat ツールの定義テスト
final class ChatTaskOperationToolsDefinitionTests: XCTestCase {

    // MARK: - start_task_from_chat Tests

    /// start_task_from_chat ツールが定義されていることを確認
    func testStartTaskFromChatToolDefined() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(
            toolNames.contains("start_task_from_chat"),
            "start_task_from_chat should be defined"
        )
    }

    /// start_task_from_chat ツールスキーマが正しいことを確認
    func testStartTaskFromChatToolSchema() {
        let tool = ToolDefinitions.startTaskFromChat

        XCTAssertEqual(tool["name"] as? String, "start_task_from_chat")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")

            // 必須パラメータ
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "session_token is required")
            XCTAssertTrue(required.contains("task_id"), "task_id is required")
            XCTAssertTrue(required.contains("requester_id"), "requester_id is required")

            // プロパティ確認
            if let properties = schema["properties"] as? [String: Any] {
                XCTAssertNotNil(properties["session_token"])
                XCTAssertNotNil(properties["task_id"])
                XCTAssertNotNil(properties["requester_id"])
            }
        }
    }

    // MARK: - update_task_from_chat Tests

    /// update_task_from_chat ツールが定義されていることを確認
    func testUpdateTaskFromChatToolDefined() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(
            toolNames.contains("update_task_from_chat"),
            "update_task_from_chat should be defined"
        )
    }

    /// update_task_from_chat ツールスキーマが正しいことを確認
    func testUpdateTaskFromChatToolSchema() {
        let tool = ToolDefinitions.updateTaskFromChat

        XCTAssertEqual(tool["name"] as? String, "update_task_from_chat")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")

            // 必須パラメータ
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "session_token is required")
            XCTAssertTrue(required.contains("task_id"), "task_id is required")
            XCTAssertTrue(required.contains("requester_id"), "requester_id is required")

            // オプションパラメータ
            if let properties = schema["properties"] as? [String: Any] {
                XCTAssertNotNil(properties["session_token"])
                XCTAssertNotNil(properties["task_id"])
                XCTAssertNotNil(properties["requester_id"])
                XCTAssertNotNil(properties["description"], "description should be available")
                XCTAssertNotNil(properties["status"], "status should be available")
            }
        }
    }
}

// MARK: - 権限テスト

/// チャット→タスク操作ツールの権限テスト
final class ChatTaskOperationToolsAuthorizationTests: XCTestCase {

    // MARK: - start_task_from_chat Authorization

    /// start_task_from_chat が chatOnly 権限であることを確認
    func testStartTaskFromChatIsChatOnly() {
        XCTAssertEqual(
            ToolAuthorization.permissions["start_task_from_chat"],
            .chatOnly,
            "start_task_from_chat should be chatOnly (chat session only)"
        )
    }

    /// チャットセッションから start_task_from_chat を呼び出せる
    func testStartTaskFromChatAllowedInChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let workerCaller = CallerType.worker(agentId: chatSession.agentId, session: chatSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "start_task_from_chat", caller: workerCaller),
            "start_task_from_chat should be allowed in chat session"
        )
    }

    /// タスクセッションから start_task_from_chat を呼び出せない
    func testStartTaskFromChatDeniedInTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        XCTAssertThrowsError(
            try ToolAuthorization.authorize(tool: "start_task_from_chat", caller: workerCaller),
            "start_task_from_chat should be denied in task session"
        ) { error in
            guard let authError = error as? ToolAuthorizationError,
                  case .chatSessionRequired = authError else {
                XCTFail("Expected chatSessionRequired error")
                return
            }
        }
    }

    // MARK: - update_task_from_chat Authorization

    /// update_task_from_chat が chatOnly 権限であることを確認
    func testUpdateTaskFromChatIsChatOnly() {
        XCTAssertEqual(
            ToolAuthorization.permissions["update_task_from_chat"],
            .chatOnly,
            "update_task_from_chat should be chatOnly (chat session only)"
        )
    }

    /// チャットセッションから update_task_from_chat を呼び出せる
    func testUpdateTaskFromChatAllowedInChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let workerCaller = CallerType.worker(agentId: chatSession.agentId, session: chatSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "update_task_from_chat", caller: workerCaller),
            "update_task_from_chat should be allowed in chat session"
        )
    }

    /// タスクセッションから update_task_from_chat を呼び出せない
    func testUpdateTaskFromChatDeniedInTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        XCTAssertThrowsError(
            try ToolAuthorization.authorize(tool: "update_task_from_chat", caller: workerCaller),
            "update_task_from_chat should be denied in task session"
        ) { error in
            guard let authError = error as? ToolAuthorizationError,
                  case .chatSessionRequired = authError else {
                XCTFail("Expected chatSessionRequired error")
                return
            }
        }
    }
}
