// Tests/MCPServerTests/ToolAuthorizationTests.swift
// ToolAuthorizationTests - extracted from MCPServerTests.swift

import XCTest
import GRDB
@testable import Domain
@testable import UseCase
@testable import Infrastructure

// MARK: - Tool Authorization Tests

/// Phase 5: ツール認可システムのテスト
final class ToolAuthorizationTests: XCTestCase {

    // MARK: - CallerType Tests

    /// CallerTypeのagentIdプロパティテスト
    func testCallerTypeAgentIdProperty() {
        // Coordinator has no agentId
        XCTAssertNil(CallerType.coordinator.agentId)

        // Unauthenticated has no agentId
        XCTAssertNil(CallerType.unauthenticated.agentId)
    }

    /// CallerTypeのisManager/isWorkerプロパティテスト
    func testCallerTypeHierarchyProperties() {
        XCTAssertFalse(CallerType.coordinator.isManager)
        XCTAssertFalse(CallerType.coordinator.isWorker)
        XCTAssertFalse(CallerType.unauthenticated.isManager)
        XCTAssertFalse(CallerType.unauthenticated.isWorker)
    }

    // MARK: - ToolPermission Tests

    /// ToolPermissionのrawValue確認
    func testToolPermissionRawValues() {
        XCTAssertEqual(ToolPermission.coordinatorOnly.rawValue, "coordinator_only")
        XCTAssertEqual(ToolPermission.managerOnly.rawValue, "manager_only")
        XCTAssertEqual(ToolPermission.workerOnly.rawValue, "worker_only")
        XCTAssertEqual(ToolPermission.authenticated.rawValue, "authenticated")
        XCTAssertEqual(ToolPermission.unauthenticated.rawValue, "unauthenticated")
        // Purpose-based permissions (Phase: Tool Authorization Enhancement)
        XCTAssertEqual(ToolPermission.chatOnly.rawValue, "chat_only")
        XCTAssertEqual(ToolPermission.taskOnly.rawValue, "task_only")
    }

    // MARK: - Authorization Permission Tests

    /// 認証不要ツールの権限確認
    func testUnauthenticatedToolPermissions() {
        XCTAssertEqual(ToolAuthorization.permissions["authenticate"], .unauthenticated)
    }

    /// Coordinator専用ツールの権限確認
    func testCoordinatorOnlyToolPermissions() {
        XCTAssertEqual(ToolAuthorization.permissions["health_check"], .coordinatorOnly)
        XCTAssertEqual(ToolAuthorization.permissions["list_active_projects_with_agents"], .coordinatorOnly)
        XCTAssertEqual(ToolAuthorization.permissions["get_agent_action"], .coordinatorOnly)
        XCTAssertEqual(ToolAuthorization.permissions["register_execution_log_file"], .coordinatorOnly)
        XCTAssertEqual(ToolAuthorization.permissions["report_process_exit"], .coordinatorOnly)
        XCTAssertEqual(ToolAuthorization.permissions["list_managed_agents"], .coordinatorOnly)
    }

    /// Manager専用ツールの権限確認
    func testManagerOnlyToolPermissions() {
        XCTAssertEqual(ToolAuthorization.permissions["list_subordinates"], .managerOnly)
        XCTAssertEqual(ToolAuthorization.permissions["get_subordinate_profile"], .managerOnly)
        XCTAssertEqual(ToolAuthorization.permissions["assign_task"], .managerOnly)
    }

    /// Worker専用ツールの権限確認（現在は空 - report_completedはauthenticatedに移動）
    func testWorkerOnlyToolPermissions() {
        // workerOnly権限のツールは現在なし（Phase: Tool Authorization Enhancement で整理）
        // report_completedはManagerも自分のタスクを完了報告する必要があるためauthenticatedに移動
        let workerOnlyTools = ToolAuthorization.tools(for: .workerOnly)
        XCTAssertTrue(workerOnlyTools.isEmpty, "Currently no worker-only tools")
    }

    /// チャット専用ツールの権限確認（purpose=chatセッションのみ）
    /// 参照: docs/design/TOOL_AUTHORIZATION_ENHANCEMENT.md
    func testChatOnlyToolPermissions() {
        XCTAssertEqual(ToolAuthorization.permissions["get_pending_messages"], .chatOnly)
        XCTAssertEqual(ToolAuthorization.permissions["send_message"], .chatOnly)
    }

    /// ヘルプツールの権限確認（未認証でも利用可能）
    func testHelpToolPermission() {
        XCTAssertEqual(ToolAuthorization.permissions["help"], .unauthenticated)
    }

    /// 認証済み共通ツールの権限確認
    func testAuthenticatedToolPermissions() {
        XCTAssertEqual(ToolAuthorization.permissions["get_my_profile"], .authenticated)
        XCTAssertEqual(ToolAuthorization.permissions["list_tasks"], .authenticated)
        XCTAssertEqual(ToolAuthorization.permissions["get_task"], .authenticated)
        // update_task_status は taskOnly に変更済み
        XCTAssertEqual(ToolAuthorization.permissions["update_task_status"], .taskOnly)
    }

    // MARK: - Authorization Logic Tests

    /// 未認証でもauthenticateは呼び出し可能
    func testAuthenticateAllowedForUnauthenticated() {
        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "authenticate", caller: .unauthenticated))
        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "authenticate", caller: .coordinator))
    }

    /// Coordinator専用ツールはCoordinatorのみ呼び出し可能
    func testCoordinatorOnlyToolsRequireCoordinator() {
        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "health_check", caller: .coordinator))
        XCTAssertThrowsError(try ToolAuthorization.authorize(tool: "health_check", caller: .unauthenticated)) { error in
            XCTAssertTrue(error is ToolAuthorizationError)
        }
    }

    /// 未登録ツールは拒否される
    func testUnregisteredToolRejected() {
        XCTAssertThrowsError(try ToolAuthorization.authorize(tool: "unknown_tool", caller: .coordinator)) { error in
            guard case ToolAuthorizationError.toolNotRegistered(let tool) = error else {
                XCTFail("Expected toolNotRegistered error")
                return
            }
            XCTAssertEqual(tool, "unknown_tool")
        }
    }

    // MARK: - Purpose-Based Authorization Tests
    // 参照: docs/design/TOOL_AUTHORIZATION_ENHANCEMENT.md

    /// chatOnlyツールはchatセッションで呼び出し可能
    func testChatOnlyToolRequiresChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "agent-001"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let workerChatCaller = CallerType.worker(agentId: chatSession.agentId, session: chatSession)
        let managerChatCaller = CallerType.manager(agentId: chatSession.agentId, session: chatSession)

        // Worker with chat session can access chat tools
        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "get_pending_messages", caller: workerChatCaller))
        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "send_message", caller: workerChatCaller))

        // Manager with chat session can also access chat tools
        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "get_pending_messages", caller: managerChatCaller))
        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "send_message", caller: managerChatCaller))
    }

    /// chatOnlyツールはtaskセッションでは拒否される
    func testChatOnlyToolRejectsTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "agent-001"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerTaskCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        XCTAssertThrowsError(try ToolAuthorization.authorize(tool: "get_pending_messages", caller: workerTaskCaller)) { error in
            guard case ToolAuthorizationError.chatSessionRequired(let tool, let currentPurpose) = error else {
                XCTFail("Expected chatSessionRequired error, got \(error)")
                return
            }
            XCTAssertEqual(tool, "get_pending_messages")
            XCTAssertEqual(currentPurpose, .task)
        }

        XCTAssertThrowsError(try ToolAuthorization.authorize(tool: "send_message", caller: workerTaskCaller)) { error in
            guard case ToolAuthorizationError.chatSessionRequired(let tool, let currentPurpose) = error else {
                XCTFail("Expected chatSessionRequired error, got \(error)")
                return
            }
            XCTAssertEqual(tool, "send_message")
            XCTAssertEqual(currentPurpose, .task)
        }
    }

    /// chatOnlyツールは未認証では拒否される
    func testChatOnlyToolRejectsUnauthenticated() {
        XCTAssertThrowsError(try ToolAuthorization.authorize(tool: "get_pending_messages", caller: .unauthenticated)) { error in
            guard case ToolAuthorizationError.authenticationRequired = error else {
                XCTFail("Expected authenticationRequired error, got \(error)")
                return
            }
        }
    }

    /// chatOnlyツールはCoordinatorでも拒否される
    func testChatOnlyToolRejectsCoordinator() {
        XCTAssertThrowsError(try ToolAuthorization.authorize(tool: "get_pending_messages", caller: .coordinator)) { error in
            guard case ToolAuthorizationError.authenticationRequired = error else {
                XCTFail("Expected authenticationRequired error, got \(error)")
                return
            }
        }
    }

    // MARK: - Tools Helper Tests

    /// 特定権限のツール一覧取得
    func testToolsForPermission() {
        let coordinatorTools = ToolAuthorization.tools(for: .coordinatorOnly)
        XCTAssertTrue(coordinatorTools.contains("health_check"))
        XCTAssertTrue(coordinatorTools.contains("get_agent_action"))

        let managerTools = ToolAuthorization.tools(for: .managerOnly)
        XCTAssertTrue(managerTools.contains("list_subordinates"))
        XCTAssertTrue(managerTools.contains("assign_task"))

        // Chat-only tools (Phase: Tool Authorization Enhancement)
        let chatTools = ToolAuthorization.tools(for: .chatOnly)
        XCTAssertTrue(chatTools.contains("get_pending_messages"))
        XCTAssertTrue(chatTools.contains("send_message"))

        // Unauthenticated tools
        let unauthenticatedTools = ToolAuthorization.tools(for: .unauthenticated)
        XCTAssertTrue(unauthenticatedTools.contains("authenticate"))
        XCTAssertTrue(unauthenticatedTools.contains("help"))
    }

    // MARK: - Error Message Tests

    /// 認可エラーメッセージの確認
    func testAuthorizationErrorMessages() {
        let toolNotRegistered = ToolAuthorizationError.toolNotRegistered("test_tool")
        XCTAssertTrue(toolNotRegistered.errorDescription?.contains("test_tool") ?? false)
        XCTAssertTrue(toolNotRegistered.errorDescription?.contains("not registered") ?? false)

        let coordinatorRequired = ToolAuthorizationError.coordinatorRequired("test_tool")
        XCTAssertTrue(coordinatorRequired.errorDescription?.contains("Coordinator") ?? false)

        let managerRequired = ToolAuthorizationError.managerRequired("test_tool")
        XCTAssertTrue(managerRequired.errorDescription?.contains("Manager") ?? false)

        let workerRequired = ToolAuthorizationError.workerRequired("test_tool")
        XCTAssertTrue(workerRequired.errorDescription?.contains("Worker") ?? false)

        let authRequired = ToolAuthorizationError.authenticationRequired("test_tool")
        XCTAssertTrue(authRequired.errorDescription?.contains("authentication") ?? false)

        let notSubordinate = ToolAuthorizationError.notSubordinate(managerId: "mgr-1", targetId: "wkr-1")
        XCTAssertTrue(notSubordinate.errorDescription?.contains("mgr-1") ?? false)
        XCTAssertTrue(notSubordinate.errorDescription?.contains("wkr-1") ?? false)

        // Purpose-based authorization errors (Phase: Tool Authorization Enhancement)
        let chatRequired = ToolAuthorizationError.chatSessionRequired("test_tool", currentPurpose: .task)
        XCTAssertTrue(chatRequired.errorDescription?.contains("chat session") ?? false)
        XCTAssertTrue(chatRequired.errorDescription?.contains("purpose=chat") ?? false)
        XCTAssertTrue(chatRequired.errorDescription?.contains("task") ?? false)

        let taskRequired = ToolAuthorizationError.taskSessionRequired("test_tool", currentPurpose: .chat)
        XCTAssertTrue(taskRequired.errorDescription?.contains("task session") ?? false)
        XCTAssertTrue(taskRequired.errorDescription?.contains("purpose=task") ?? false)
        XCTAssertTrue(taskRequired.errorDescription?.contains("chat") ?? false)
    }
}
