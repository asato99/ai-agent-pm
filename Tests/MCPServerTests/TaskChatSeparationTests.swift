// Tests/MCPServerTests/TaskChatSeparationTests.swift
// タスク/チャットセッション分離機能のテスト
// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md

import XCTest
@testable import Domain

/// Phase 1: コミュニケーションツールの権限変更テスト
/// start_conversation, end_conversation, send_message を chatOnly に変更
final class CommunicationToolAuthorizationTests: XCTestCase {

    // MARK: - Permission Mapping Tests

    /// start_conversation が chatOnly 権限であることを確認
    func testStartConversationIsChatOnly() {
        XCTAssertEqual(
            ToolAuthorization.permissions["start_conversation"],
            .chatOnly,
            "start_conversation should be chatOnly (not authenticated)"
        )
    }

    /// end_conversation が chatOnly 権限であることを確認
    func testEndConversationIsChatOnly() {
        XCTAssertEqual(
            ToolAuthorization.permissions["end_conversation"],
            .chatOnly,
            "end_conversation should be chatOnly (not authenticated)"
        )
    }

    /// send_message が chatOnly 権限であることを確認
    func testSendMessageIsChatOnly() {
        XCTAssertEqual(
            ToolAuthorization.permissions["send_message"],
            .chatOnly,
            "send_message should be chatOnly (not authenticated)"
        )
    }

    // MARK: - Chat Session Authorization Tests

    /// チャットセッションから start_conversation を呼び出せることを確認
    func testStartConversationAllowedInChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let workerChatCaller = CallerType.worker(agentId: chatSession.agentId, session: chatSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "start_conversation", caller: workerChatCaller),
            "start_conversation should be allowed in chat session"
        )
    }

    /// チャットセッションから end_conversation を呼び出せることを確認
    func testEndConversationAllowedInChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let workerChatCaller = CallerType.worker(agentId: chatSession.agentId, session: chatSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "end_conversation", caller: workerChatCaller),
            "end_conversation should be allowed in chat session"
        )
    }

    /// チャットセッションから send_message を呼び出せることを確認
    func testSendMessageAllowedInChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let workerChatCaller = CallerType.worker(agentId: chatSession.agentId, session: chatSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "send_message", caller: workerChatCaller),
            "send_message should be allowed in chat session"
        )
    }

    // MARK: - Task Session Rejection Tests

    /// タスクセッションから start_conversation を呼ぶとエラー
    func testStartConversationRejectedInTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerTaskCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        XCTAssertThrowsError(
            try ToolAuthorization.authorize(tool: "start_conversation", caller: workerTaskCaller)
        ) { error in
            guard case ToolAuthorizationError.chatSessionRequired(let tool, let currentPurpose) = error else {
                XCTFail("Expected chatSessionRequired error, got \(error)")
                return
            }
            XCTAssertEqual(tool, "start_conversation")
            XCTAssertEqual(currentPurpose, .task)
        }
    }

    /// タスクセッションから end_conversation を呼ぶとエラー
    func testEndConversationRejectedInTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerTaskCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        XCTAssertThrowsError(
            try ToolAuthorization.authorize(tool: "end_conversation", caller: workerTaskCaller)
        ) { error in
            guard case ToolAuthorizationError.chatSessionRequired(let tool, let currentPurpose) = error else {
                XCTFail("Expected chatSessionRequired error, got \(error)")
                return
            }
            XCTAssertEqual(tool, "end_conversation")
            XCTAssertEqual(currentPurpose, .task)
        }
    }

    /// タスクセッションから send_message を呼ぶとエラー
    func testSendMessageRejectedInTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerTaskCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        XCTAssertThrowsError(
            try ToolAuthorization.authorize(tool: "send_message", caller: workerTaskCaller)
        ) { error in
            guard case ToolAuthorizationError.chatSessionRequired(let tool, let currentPurpose) = error else {
                XCTFail("Expected chatSessionRequired error, got \(error)")
                return
            }
            XCTAssertEqual(tool, "send_message")
            XCTAssertEqual(currentPurpose, .task)
        }
    }

    // MARK: - Manager Chat Session Tests

    /// Managerのチャットセッションからもコミュニケーションツールを呼び出せることを確認
    func testCommunicationToolsAllowedForManagerChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "manager-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let managerChatCaller = CallerType.manager(agentId: chatSession.agentId, session: chatSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "start_conversation", caller: managerChatCaller)
        )
        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "end_conversation", caller: managerChatCaller)
        )
        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "send_message", caller: managerChatCaller)
        )
    }

    /// Managerのタスクセッションからはコミュニケーションツールを呼び出せないことを確認
    func testCommunicationToolsRejectedForManagerTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "manager-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let managerTaskCaller = CallerType.manager(agentId: taskSession.agentId, session: taskSession)

        XCTAssertThrowsError(
            try ToolAuthorization.authorize(tool: "start_conversation", caller: managerTaskCaller)
        )
        XCTAssertThrowsError(
            try ToolAuthorization.authorize(tool: "end_conversation", caller: managerTaskCaller)
        )
        XCTAssertThrowsError(
            try ToolAuthorization.authorize(tool: "send_message", caller: managerTaskCaller)
        )
    }

    // MARK: - Tools List Tests

    /// chatOnlyツール一覧にコミュニケーションツールが含まれることを確認
    func testChatOnlyToolsIncludeCommunicationTools() {
        let chatOnlyTools = ToolAuthorization.tools(for: .chatOnly)

        XCTAssertTrue(chatOnlyTools.contains("start_conversation"))
        XCTAssertTrue(chatOnlyTools.contains("end_conversation"))
        XCTAssertTrue(chatOnlyTools.contains("send_message"))
        XCTAssertTrue(chatOnlyTools.contains("get_pending_messages"))
    }
}

/// Phase 3: delegate_to_chat_session ツールの権限テスト
final class DelegateToChatSessionAuthorizationTests: XCTestCase {

    /// delegate_to_chat_session が taskOnly 権限であることを確認
    func testDelegateToChatSessionIsTaskOnly() {
        XCTAssertEqual(
            ToolAuthorization.permissions["delegate_to_chat_session"],
            .taskOnly,
            "delegate_to_chat_session should be taskOnly"
        )
    }

    /// タスクセッションから delegate_to_chat_session を呼び出せることを確認
    func testDelegateToChatSessionAllowedInTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerTaskCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "delegate_to_chat_session", caller: workerTaskCaller),
            "delegate_to_chat_session should be allowed in task session"
        )
    }

    /// チャットセッションから delegate_to_chat_session を呼ぶとエラー
    func testDelegateToChatSessionRejectedInChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let workerChatCaller = CallerType.worker(agentId: chatSession.agentId, session: chatSession)

        XCTAssertThrowsError(
            try ToolAuthorization.authorize(tool: "delegate_to_chat_session", caller: workerChatCaller)
        ) { error in
            guard case ToolAuthorizationError.taskSessionRequired(let tool, let currentPurpose) = error else {
                XCTFail("Expected taskSessionRequired error, got \(error)")
                return
            }
            XCTAssertEqual(tool, "delegate_to_chat_session")
            XCTAssertEqual(currentPurpose, .chat)
        }
    }

    /// Managerのタスクセッションからも delegate_to_chat_session を呼び出せることを確認
    func testDelegateToChatSessionAllowedForManagerTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "manager-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let managerTaskCaller = CallerType.manager(agentId: taskSession.agentId, session: taskSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "delegate_to_chat_session", caller: managerTaskCaller)
        )
    }

    /// taskOnlyツール一覧に delegate_to_chat_session が含まれることを確認
    func testTaskOnlyToolsIncludeDelegateToChatSession() {
        let taskOnlyTools = ToolAuthorization.tools(for: .taskOnly)

        XCTAssertTrue(taskOnlyTools.contains("delegate_to_chat_session"))
    }
}

/// Phase 4: report_delegation_completed ツールの権限テスト
/// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
final class ReportDelegationCompletedAuthorizationTests: XCTestCase {

    /// report_delegation_completed が chatOnly 権限であることを確認
    func testReportDelegationCompletedIsChatOnly() {
        XCTAssertEqual(
            ToolAuthorization.permissions["report_delegation_completed"],
            .chatOnly,
            "report_delegation_completed should be chatOnly"
        )
    }

    /// チャットセッションから report_delegation_completed を呼び出せることを確認
    func testReportDelegationCompletedAllowedInChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let workerChatCaller = CallerType.worker(agentId: chatSession.agentId, session: chatSession)

        XCTAssertNoThrow(
            try ToolAuthorization.authorize(tool: "report_delegation_completed", caller: workerChatCaller),
            "report_delegation_completed should be allowed in chat session"
        )
    }

    /// タスクセッションから report_delegation_completed を呼ぶとエラー
    func testReportDelegationCompletedRejectedInTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "worker-a"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerTaskCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        XCTAssertThrowsError(
            try ToolAuthorization.authorize(tool: "report_delegation_completed", caller: workerTaskCaller)
        ) { error in
            guard case ToolAuthorizationError.chatSessionRequired(let tool, let currentPurpose) = error else {
                XCTFail("Expected chatSessionRequired error, got \(error)")
                return
            }
            XCTAssertEqual(tool, "report_delegation_completed")
            XCTAssertEqual(currentPurpose, .task)
        }
    }

    /// chatOnlyツール一覧に report_delegation_completed が含まれることを確認
    func testChatOnlyToolsIncludeReportDelegationCompleted() {
        let chatOnlyTools = ToolAuthorization.tools(for: .chatOnly)

        XCTAssertTrue(chatOnlyTools.contains("report_delegation_completed"))
    }
}
