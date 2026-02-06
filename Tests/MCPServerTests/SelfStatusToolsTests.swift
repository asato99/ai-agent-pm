// Tests/MCPServerTests/SelfStatusToolsTests.swift
// 自己状況確認ツールのテスト
// 参照: docs/plan/CHAT_TASK_EXECUTION.md - Phase 2

import XCTest
@testable import Domain

// MARK: - Phase 2: 自己状況確認ツール

/// 自己状況確認ツールの定義テスト
final class SelfStatusToolsDefinitionTests: XCTestCase {

    // MARK: - get_my_execution_history Tests

    /// get_my_execution_history ツールが定義されていることを確認
    func testGetMyExecutionHistoryToolDefined() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(
            toolNames.contains("get_my_execution_history"),
            "get_my_execution_history should be defined"
        )
    }

    /// get_my_execution_history ツールスキーマが正しいことを確認
    func testGetMyExecutionHistoryToolSchema() {
        let tool = ToolDefinitions.getMyExecutionHistory

        XCTAssertEqual(tool["name"] as? String, "get_my_execution_history")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")

            // session_token は必須
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"))

            // オプションパラメータ: task_id, limit
            if let properties = schema["properties"] as? [String: Any] {
                XCTAssertNotNil(properties["session_token"])
                XCTAssertNotNil(properties["task_id"], "task_id filter should be available")
                XCTAssertNotNil(properties["limit"], "limit parameter should be available")
            }
        }
    }

    // MARK: - get_execution_log Tests

    /// get_execution_log ツールが定義されていることを確認
    func testGetExecutionLogToolDefined() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(
            toolNames.contains("get_execution_log"),
            "get_execution_log should be defined"
        )
    }

    /// get_execution_log ツールスキーマが正しいことを確認
    func testGetExecutionLogToolSchema() {
        let tool = ToolDefinitions.getExecutionLog

        XCTAssertEqual(tool["name"] as? String, "get_execution_log")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")

            // session_token と execution_id は必須
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"))
            XCTAssertTrue(required.contains("execution_id"))
        }
    }
}

// MARK: - 権限テスト

/// 自己状況確認ツールの権限テスト
final class SelfStatusToolsAuthorizationTests: XCTestCase {

    // MARK: - get_my_execution_history Authorization

    /// get_my_execution_history が authenticated 権限であることを確認
    func testGetMyExecutionHistoryIsAuthenticated() {
        XCTAssertEqual(
            ToolAuthorization.permissions["get_my_execution_history"],
            .authenticated,
            "get_my_execution_history should be authenticated (both task and chat sessions)"
        )
    }

    /// タスクセッションから get_my_execution_history を呼び出せる
    func testGetMyExecutionHistoryAllowedInTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "get_my_execution_history", caller: workerCaller),
            "get_my_execution_history should be allowed in task session"
        )
    }

    /// チャットセッションから get_my_execution_history を呼び出せる
    func testGetMyExecutionHistoryAllowedInChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let workerCaller = CallerType.worker(agentId: chatSession.agentId, session: chatSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "get_my_execution_history", caller: workerCaller),
            "get_my_execution_history should be allowed in chat session"
        )
    }

    // MARK: - get_execution_log Authorization

    /// get_execution_log が authenticated 権限であることを確認
    func testGetExecutionLogIsAuthenticated() {
        XCTAssertEqual(
            ToolAuthorization.permissions["get_execution_log"],
            .authenticated,
            "get_execution_log should be authenticated (both task and chat sessions)"
        )
    }

    /// タスクセッションから get_execution_log を呼び出せる
    func testGetExecutionLogAllowedInTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "get_execution_log", caller: workerCaller),
            "get_execution_log should be allowed in task session"
        )
    }

    /// チャットセッションから get_execution_log を呼び出せる
    func testGetExecutionLogAllowedInChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let workerCaller = CallerType.worker(agentId: chatSession.agentId, session: chatSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "get_execution_log", caller: workerCaller),
            "get_execution_log should be allowed in chat session"
        )
    }
}
