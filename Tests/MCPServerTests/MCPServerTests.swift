// Tests/MCPServerTests/MCPServerTests.swift
// MCP_DESIGN.md仕様に基づくMCPServer層のテスト

import XCTest
@testable import MCPServer
@testable import Domain
@testable import UseCase

/// MCP_DESIGN.md仕様に基づくMCPServerテスト
final class MCPServerTests: XCTestCase {

    // MARK: - ToolDefinitions Tests

    /// MCP_DESIGN.md: 全ツールが定義されていることを確認
    /// ステートレス設計: セッション管理ツール（start_session, end_session）は削除済み
    func testToolDefinitionsContainsAllTools() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        // PRD定義ツール（MCP_DESIGN.md）- ステートレス設計版
        // エージェント管理
        XCTAssertTrue(toolNames.contains("get_my_profile"), "get_my_profile should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("get_agent_profile"), "get_agent_profile should be defined for stateless design")
        XCTAssertTrue(toolNames.contains("list_agents"), "list_agents should be defined")

        // プロジェクト管理
        XCTAssertTrue(toolNames.contains("list_projects"), "list_projects should be defined")
        XCTAssertTrue(toolNames.contains("get_project"), "get_project should be defined")

        // タスク管理
        XCTAssertTrue(toolNames.contains("list_tasks"), "list_tasks should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("get_task"), "get_task should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("get_my_tasks"), "get_my_tasks should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("update_task_status"), "update_task_status should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("assign_task"), "assign_task should be defined per MCP_DESIGN.md")

        // コンテキスト・ハンドオフ
        XCTAssertTrue(toolNames.contains("save_context"), "save_context should be defined (add_context in MCP_DESIGN.md)")
        XCTAssertTrue(toolNames.contains("get_task_context"), "get_task_context should be defined (get_context in MCP_DESIGN.md)")
        XCTAssertTrue(toolNames.contains("create_handoff"), "create_handoff should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("get_pending_handoffs"), "get_pending_handoffs should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("accept_handoff"), "accept_handoff should be defined (acknowledge_handoff in MCP_DESIGN.md)")
    }

    /// ステートレス設計で削除されたツールが存在しないことを確認
    func testRemovedToolsFromStatelessDesign() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        // ステートレス設計により削除されたツール
        let removedTools = [
            "start_session",   // セッション管理は削除
            "end_session",     // セッション管理は削除
            "get_my_sessions", // セッション管理は削除
            "create_task",     // UIでのみ作成可能
            "update_task"      // UIでのみ編集可能
        ]

        for tool in removedTools {
            XCTAssertFalse(toolNames.contains(tool), "\(tool) should not exist in stateless design")
        }
    }

    /// ツール定義のスキーマが正しいことを確認
    func testToolDefinitionsHaveValidSchema() {
        let tools = ToolDefinitions.all()

        for tool in tools {
            XCTAssertNotNil(tool["name"] as? String, "Tool should have name")
            XCTAssertNotNil(tool["description"] as? String, "Tool should have description")
            XCTAssertNotNil(tool["inputSchema"] as? [String: Any], "Tool should have inputSchema")

            if let schema = tool["inputSchema"] as? [String: Any] {
                XCTAssertEqual(schema["type"] as? String, "object", "inputSchema type should be object")
                XCTAssertNotNil(schema["properties"], "inputSchema should have properties")
                XCTAssertNotNil(schema["required"], "inputSchema should have required")
            }
        }
    }

    /// get_my_profileツール定義（後方互換、ステートレス設計）
    func testGetMyProfileToolDefinition() {
        let tool = ToolDefinitions.getMyProfile

        XCTAssertEqual(tool["name"] as? String, "get_my_profile")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            // ステートレス設計: agent_idが必須
            XCTAssertTrue(required.contains("agent_id"), "get_my_profile should require agent_id in stateless design")
        }
    }

    /// get_agent_profileツール定義（ステートレス設計）
    func testGetAgentProfileToolDefinition() {
        let tool = ToolDefinitions.getAgentProfile

        XCTAssertEqual(tool["name"] as? String, "get_agent_profile")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("agent_id"), "get_agent_profile should require agent_id")
        }
    }

    /// list_agentsツール定義
    func testListAgentsToolDefinition() {
        let tool = ToolDefinitions.listAgents

        XCTAssertEqual(tool["name"] as? String, "list_agents")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.isEmpty, "list_agents should have no required parameters")
        }
    }

    /// list_projectsツール定義
    func testListProjectsToolDefinition() {
        let tool = ToolDefinitions.listProjects

        XCTAssertEqual(tool["name"] as? String, "list_projects")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.isEmpty, "list_projects should have no required parameters")
        }
    }

    /// get_projectツール定義
    func testGetProjectToolDefinition() {
        let tool = ToolDefinitions.getProject

        XCTAssertEqual(tool["name"] as? String, "get_project")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("project_id"), "get_project should require project_id")
        }
    }

    /// list_tasksツール定義
    func testListTasksToolDefinition() {
        let tool = ToolDefinitions.listTasks

        XCTAssertEqual(tool["name"] as? String, "list_tasks")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any],
           let properties = schema["properties"] as? [String: Any] {
            // status: 任意のフィルタパラメータ
            XCTAssertNotNil(properties["status"], "list_tasks should have optional status filter")
            if let statusProp = properties["status"] as? [String: Any],
               let enumValues = statusProp["enum"] as? [String] {
                // TaskStatus: backlog, todo, in_progress, in_review, blocked, done, cancelled
                XCTAssertTrue(enumValues.contains("backlog"))
                XCTAssertTrue(enumValues.contains("todo"))
                XCTAssertTrue(enumValues.contains("in_progress"))
                XCTAssertTrue(enumValues.contains("done"))
            }
        }
    }

    /// get_taskツール定義
    func testGetTaskToolDefinition() {
        let tool = ToolDefinitions.getTask

        XCTAssertEqual(tool["name"] as? String, "get_task")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("task_id"), "get_task should require task_id")
        }
    }

    /// get_my_tasksツール定義（後方互換、ステートレス設計）
    func testGetMyTasksToolDefinition() {
        let tool = ToolDefinitions.getMyTasks

        XCTAssertEqual(tool["name"] as? String, "get_my_tasks")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            // ステートレス設計: agent_idが必須
            XCTAssertTrue(required.contains("agent_id"), "get_my_tasks should require agent_id in stateless design")
        }
    }

    /// Phase 3-2: get_pending_tasksツール定義
    func testGetPendingTasksToolDefinition() {
        let tool = ToolDefinitions.getPendingTasks

        XCTAssertEqual(tool["name"] as? String, "get_pending_tasks")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("agent_id"), "get_pending_tasks should require agent_id")
        }
    }

    /// Phase 3-2: get_pending_tasksがall()に含まれている
    func testGetPendingTasksToolInAllTools() {
        let allTools = ToolDefinitions.all()
        let toolNames = allTools.compactMap { $0["name"] as? String }

        XCTAssertTrue(toolNames.contains("get_pending_tasks"), "get_pending_tasks should be in all tools")
    }

    /// update_task_statusツール定義
    func testUpdateTaskStatusToolDefinition() {
        let tool = ToolDefinitions.updateTaskStatus

        XCTAssertEqual(tool["name"] as? String, "update_task_status")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("task_id"), "update_task_status should require task_id")
            XCTAssertTrue(required.contains("status"), "update_task_status should require status")
        }
    }

    /// assign_taskツール定義
    func testAssignTaskToolDefinition() {
        let tool = ToolDefinitions.assignTask

        XCTAssertEqual(tool["name"] as? String, "assign_task")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("task_id"), "assign_task should require task_id")
            // assignee_id is optional (null = unassign)
        }
    }

    /// save_contextツール定義 (MCP_DESIGN.mdのadd_context)
    func testSaveContextToolDefinition() {
        let tool = ToolDefinitions.saveContext

        XCTAssertEqual(tool["name"] as? String, "save_context")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any],
           let properties = schema["properties"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("task_id"), "save_context should require task_id")

            // MCP_DESIGN.md: TaskContext { decisions, assumptions, blockers, artifacts, notes }
            // 実装: progress, findings, blockers, next_steps
            XCTAssertNotNil(properties["progress"])
            XCTAssertNotNil(properties["findings"])
            XCTAssertNotNil(properties["blockers"])
            XCTAssertNotNil(properties["next_steps"])
        }
    }

    /// get_task_contextツール定義 (MCP_DESIGN.mdのget_context)
    func testGetTaskContextToolDefinition() {
        let tool = ToolDefinitions.getTaskContext

        XCTAssertEqual(tool["name"] as? String, "get_task_context")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any],
           let properties = schema["properties"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("task_id"), "get_task_context should require task_id")
            XCTAssertNotNil(properties["include_history"])
        }
    }

    /// create_handoffツール定義
    func testCreateHandoffToolDefinition() {
        let tool = ToolDefinitions.createHandoff

        XCTAssertEqual(tool["name"] as? String, "create_handoff")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any],
           let properties = schema["properties"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("task_id"), "create_handoff should require task_id")
            XCTAssertTrue(required.contains("summary"), "create_handoff should require summary")

            // MCP_DESIGN.md: HandoffInfo { fromAgent, toAgent?, summary, nextSteps, warnings, timestamp }
            XCTAssertNotNil(properties["to_agent_id"])
            XCTAssertNotNil(properties["summary"])
            XCTAssertNotNil(properties["context"])
            XCTAssertNotNil(properties["recommendations"])
        }
    }

    /// accept_handoffツール定義 (MCP_DESIGN.mdのacknowledge_handoff)
    func testAcceptHandoffToolDefinition() {
        let tool = ToolDefinitions.acceptHandoff

        XCTAssertEqual(tool["name"] as? String, "accept_handoff")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("handoff_id"), "accept_handoff should require handoff_id")
        }
    }

    /// get_pending_handoffsツール定義
    func testGetPendingHandoffsToolDefinition() {
        let tool = ToolDefinitions.getPendingHandoffs

        XCTAssertEqual(tool["name"] as? String, "get_pending_handoffs")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.isEmpty, "get_pending_handoffs should have no required parameters")
        }
    }

    // MARK: - MCPError Tests

    /// MCPError.agentNotFoundのテスト
    func testMCPErrorAgentNotFound() {
        let error = MCPError.agentNotFound("agent-123")
        XCTAssertTrue(error.description.contains("agent-123"))
        XCTAssertTrue(error.description.contains("not found"))
    }

    /// MCPError.taskNotFoundのテスト
    func testMCPErrorTaskNotFound() {
        let error = MCPError.taskNotFound("task-456")
        XCTAssertTrue(error.description.contains("task-456"))
        XCTAssertTrue(error.description.contains("not found"))
    }

    /// MCPError.sessionAlreadyActiveのテスト
    func testMCPErrorSessionAlreadyActive() {
        let error = MCPError.sessionAlreadyActive("session-789")
        XCTAssertTrue(error.description.contains("session-789"))
        XCTAssertTrue(error.description.contains("already active"))
    }

    /// MCPError.noActiveSessionのテスト
    func testMCPErrorNoActiveSession() {
        let error = MCPError.noActiveSession
        XCTAssertTrue(error.description.contains("No active session"))
    }

    /// MCPError.invalidStatusのテスト
    func testMCPErrorInvalidStatus() {
        let error = MCPError.invalidStatus("invalid_status")
        XCTAssertTrue(error.description.contains("invalid_status"))
        XCTAssertTrue(error.description.contains("Invalid status"))
    }

    /// MCPError.invalidStatusTransitionのテスト
    func testMCPErrorInvalidStatusTransition() {
        let error = MCPError.invalidStatusTransition(from: "backlog", to: "done")
        XCTAssertTrue(error.description.contains("backlog"))
        XCTAssertTrue(error.description.contains("done"))
    }

    /// MCPError.unknownToolのテスト
    func testMCPErrorUnknownTool() {
        let error = MCPError.unknownTool("unknown_tool")
        XCTAssertTrue(error.description.contains("unknown_tool"))
        XCTAssertTrue(error.description.contains("Unknown tool"))
    }

    /// MCPError.missingArgumentsのテスト
    func testMCPErrorMissingArguments() {
        let error = MCPError.missingArguments(["task_id", "status"])
        XCTAssertTrue(error.description.contains("task_id"))
        XCTAssertTrue(error.description.contains("status"))
        XCTAssertTrue(error.description.contains("Missing"))
    }

    /// MCPError.handoffAlreadyAcceptedのテスト
    func testMCPErrorHandoffAlreadyAccepted() {
        let error = MCPError.handoffAlreadyAccepted("handoff-123")
        XCTAssertTrue(error.description.contains("handoff-123"))
        XCTAssertTrue(error.description.contains("already accepted"))
    }

    /// MCPError.handoffNotForYouのテスト
    func testMCPErrorHandoffNotForYou() {
        let error = MCPError.handoffNotForYou("handoff-456")
        XCTAssertTrue(error.description.contains("handoff-456"))
        XCTAssertTrue(error.description.contains("not addressed to you"))
    }

    /// MCPError.invalidResourceURIのテスト
    func testMCPErrorInvalidResourceURI() {
        let error = MCPError.invalidResourceURI("invalid://uri")
        XCTAssertTrue(error.description.contains("invalid://uri"))
        XCTAssertTrue(error.description.contains("Invalid resource URI"))
    }

    // MARK: - Status Enum Tests

    /// ToolDefinitionsのstatus enumがPRD仕様と一致することを確認
    /// PRD仕様: backlog, todo, in_progress, blocked, done, cancelled
    func testStatusEnumInToolDefinitions() {
        let tool = ToolDefinitions.listTasks

        if let schema = tool["inputSchema"] as? [String: Any],
           let properties = schema["properties"] as? [String: Any],
           let statusProp = properties["status"] as? [String: Any],
           let enumValues = statusProp["enum"] as? [String] {
            // PRD仕様通りのenum値を確認
            XCTAssertTrue(enumValues.contains("backlog"), "Should contain 'backlog' per PRD")
            XCTAssertTrue(enumValues.contains("todo"), "Should contain 'todo' per PRD")
            XCTAssertTrue(enumValues.contains("in_progress"), "Should contain 'in_progress' per PRD")
            XCTAssertTrue(enumValues.contains("blocked"), "Should contain 'blocked' per PRD")
            XCTAssertTrue(enumValues.contains("done"), "Should contain 'done' per PRD")
            XCTAssertTrue(enumValues.contains("cancelled"), "Should contain 'cancelled' per PRD")
            // in_review は削除済み
            XCTAssertFalse(enumValues.contains("in_review"), "Should not contain 'in_review' - removed per PRD")
        }
    }

    // MARK: - Tool Count Test

    /// 定義されているツール数を確認
    func testToolCount() {
        let tools = ToolDefinitions.all()

        // ステートレス設計版ツール: 16個
        // Authentication: 1 (authenticate) - Phase 3-1
        // Agent: 3 (get_agent_profile, get_my_profile, list_agents)
        // Project: 2 (list_projects, get_project)
        // Tasks: 6 (list_tasks, get_task, get_my_tasks, get_pending_tasks, update_task_status, assign_task)
        // Context: 2 (save_context, get_task_context)
        // Handoff: 3 (create_handoff, accept_handoff, get_pending_handoffs)
        XCTAssertEqual(tools.count, 17, "Should have 17 tools defined (including authenticate and get_pending_tasks)")
    }
}

// MARK: - PRD Compliance Summary Tests

/// ステートレス設計版PRD仕様との適合性サマリーテスト
final class MCPPRDComplianceTests: XCTestCase {

    /// ステートレス設計版MCP_DESIGN.md仕様との適合性サマリー
    func testPRDComplianceSummary() {
        let tools = ToolDefinitions.all()
        let toolNames = Set(tools.compactMap { $0["name"] as? String })

        // ステートレス設計版で実装されているツール
        let implementedTools = [
            // 認証 (Phase 3-1)
            "authenticate",

            // エージェント管理
            "get_agent_profile",  // 新規追加
            "get_my_profile",     // 後方互換
            "list_agents",

            // プロジェクト管理
            "list_projects",
            "get_project",

            // タスク管理
            "list_tasks",
            "get_task",
            "get_my_tasks",       // 後方互換
            "get_pending_tasks",  // Phase 3-2
            "update_task_status",
            "assign_task",

            // コンテキスト
            "save_context",
            "get_task_context",

            // ハンドオフ
            "create_handoff",
            "get_pending_handoffs",
            "accept_handoff"
        ]

        var implementedCount = 0
        for tool in implementedTools {
            if toolNames.contains(tool) {
                implementedCount += 1
            }
        }

        // ステートレス設計版 + 認証 + Phase 3-2: 17個のツールが実装されている
        XCTAssertEqual(implementedCount, 17, "Should have 17 tools implemented (including authenticate and get_pending_tasks)")

        // ステートレス設計で削除されたツール
        let removedTools = ["start_session", "end_session", "get_my_sessions", "create_task", "update_task"]
        for tool in removedTools {
            XCTAssertFalse(toolNames.contains(tool), "\(tool) should be removed in stateless design")
        }
    }
}

// MARK: - Authenticate Tool Tests

/// Phase 3-1: 認証ツールのテスト
final class AuthenticateToolTests: XCTestCase {

    // MARK: - Tool Definition Tests

    /// authenticate ツールが定義されていることを確認
    func testAuthenticateToolDefinition() {
        let tool = ToolDefinitions.authenticate

        XCTAssertEqual(tool["name"] as? String, "authenticate")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("agent_id"), "authenticate should require agent_id")
            XCTAssertTrue(required.contains("passkey"), "authenticate should require passkey")

            if let properties = schema["properties"] as? [String: Any] {
                XCTAssertNotNil(properties["agent_id"], "Should have agent_id property")
                XCTAssertNotNil(properties["passkey"], "Should have passkey property")
            }
        }
    }

    /// authenticate ツールが全ツール一覧に含まれることを確認
    func testAuthenticateToolInAllTools() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(toolNames.contains("authenticate"), "authenticate should be in all tools")
    }

    // MARK: - AuthenticateResult Tests

    /// 認証成功結果の生成テスト
    func testAuthenticateResultSuccess() {
        let result = AuthenticateResult.success(
            token: "sess_abc123",
            expiresIn: 3600,
            agentName: "Test Agent"
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.sessionToken, "sess_abc123")
        XCTAssertEqual(result.expiresIn, 3600)
        XCTAssertEqual(result.agentName, "Test Agent")
        XCTAssertNil(result.error)
    }

    /// 認証失敗結果の生成テスト
    func testAuthenticateResultFailure() {
        let result = AuthenticateResult.failure(error: "Invalid agent_id or passkey")

        XCTAssertFalse(result.success)
        XCTAssertNil(result.sessionToken)
        XCTAssertNil(result.expiresIn)
        XCTAssertNil(result.agentName)
        XCTAssertEqual(result.error, "Invalid agent_id or passkey")
    }
}

// MARK: - MCPError Authentication Tests

/// 認証関連エラーのテスト
extension MCPServerTests {

    /// MCPError.invalidCredentialsのテスト
    func testMCPErrorInvalidCredentials() {
        let error = MCPError.invalidCredentials
        XCTAssertTrue(error.description.contains("Invalid"))
    }
}
