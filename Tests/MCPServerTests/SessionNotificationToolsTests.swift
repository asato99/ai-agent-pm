// Tests/MCPServerTests/SessionNotificationToolsTests.swift
// セッション間通知ツールのテスト
// 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 4

import XCTest
@testable import Domain

// MARK: - Phase 4: セッション間通知ツール

/// notify_task_session / get_conversation_messages ツールの定義テスト
final class SessionNotificationToolsDefinitionTests: XCTestCase {

    // MARK: - notify_task_session Tests

    /// notify_task_session ツールが定義されていることを確認
    func testNotifyTaskSessionToolDefined() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(
            toolNames.contains("notify_task_session"),
            "notify_task_session should be defined"
        )
    }

    /// notify_task_session ツールスキーマが正しいことを確認
    func testNotifyTaskSessionToolSchema() {
        let tool = ToolDefinitions.notifyTaskSession

        XCTAssertEqual(tool["name"] as? String, "notify_task_session")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")

            // 必須パラメータ
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "session_token is required")
            XCTAssertTrue(required.contains("message"), "message is required")

            // プロパティ確認
            if let properties = schema["properties"] as? [String: Any] {
                XCTAssertNotNil(properties["session_token"])
                XCTAssertNotNil(properties["message"])
                XCTAssertNotNil(properties["conversation_id"], "conversation_id should be available")
                XCTAssertNotNil(properties["related_task_id"], "related_task_id should be available")
                XCTAssertNotNil(properties["priority"], "priority should be available")
            }
        }
    }

    // MARK: - get_conversation_messages Tests

    /// get_conversation_messages ツールが定義されていることを確認
    func testGetConversationMessagesToolDefined() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(
            toolNames.contains("get_conversation_messages"),
            "get_conversation_messages should be defined"
        )
    }

    /// get_conversation_messages ツールスキーマが正しいことを確認
    func testGetConversationMessagesToolSchema() {
        let tool = ToolDefinitions.getConversationMessages

        XCTAssertEqual(tool["name"] as? String, "get_conversation_messages")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")

            // 必須パラメータ
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "session_token is required")
            XCTAssertTrue(required.contains("conversation_id"), "conversation_id is required")

            // プロパティ確認
            if let properties = schema["properties"] as? [String: Any] {
                XCTAssertNotNil(properties["session_token"])
                XCTAssertNotNil(properties["conversation_id"])
                XCTAssertNotNil(properties["limit"], "limit should be available")
            }
        }
    }
}

// MARK: - 権限テスト

/// セッション間通知ツールの権限テスト
final class SessionNotificationToolsAuthorizationTests: XCTestCase {

    // MARK: - notify_task_session Authorization

    /// notify_task_session が chatOnly 権限であることを確認
    func testNotifyTaskSessionIsChatOnly() {
        XCTAssertEqual(
            ToolAuthorization.permissions["notify_task_session"],
            .chatOnly,
            "notify_task_session should be chatOnly (chat session only)"
        )
    }

    /// チャットセッションから notify_task_session を呼び出せる
    func testNotifyTaskSessionAllowedInChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let workerCaller = CallerType.worker(agentId: chatSession.agentId, session: chatSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "notify_task_session", caller: workerCaller),
            "notify_task_session should be allowed in chat session"
        )
    }

    /// タスクセッションから notify_task_session を呼び出せない
    func testNotifyTaskSessionDeniedInTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        XCTAssertThrowsError(
            try ToolAuthorization.authorize(tool: "notify_task_session", caller: workerCaller),
            "notify_task_session should be denied in task session"
        ) { error in
            guard let authError = error as? ToolAuthorizationError,
                  case .chatSessionRequired = authError else {
                XCTFail("Expected chatSessionRequired error")
                return
            }
        }
    }

    // MARK: - get_conversation_messages Authorization

    /// get_conversation_messages が taskOnly 権限であることを確認
    func testGetConversationMessagesIsTaskOnly() {
        XCTAssertEqual(
            ToolAuthorization.permissions["get_conversation_messages"],
            .taskOnly,
            "get_conversation_messages should be taskOnly (task session only)"
        )
    }

    /// タスクセッションから get_conversation_messages を呼び出せる
    func testGetConversationMessagesAllowedInTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "get_conversation_messages", caller: workerCaller),
            "get_conversation_messages should be allowed in task session"
        )
    }

    /// チャットセッションから get_conversation_messages を呼び出せない
    func testGetConversationMessagesDeniedInChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let workerCaller = CallerType.worker(agentId: chatSession.agentId, session: chatSession)

        XCTAssertThrowsError(
            try ToolAuthorization.authorize(tool: "get_conversation_messages", caller: workerCaller),
            "get_conversation_messages should be denied in chat session"
        ) { error in
            guard let authError = error as? ToolAuthorizationError,
                  case .taskSessionRequired = authError else {
                XCTFail("Expected taskSessionRequired error")
                return
            }
        }
    }
}
