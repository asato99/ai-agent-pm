// Tests/MCPServerTests/MCPServerTests.swift
// MCP_DESIGN.md仕様に基づくMCPServer層のテスト

import XCTest
import GRDB
// MCPServerのソースはテストターゲットに直接含まれている（toolタイプのため@testable import不可）
@testable import Domain
@testable import UseCase
@testable import Infrastructure

/// MCP_DESIGN.md仕様に基づくMCPServerテスト
final class MCPServerTests: XCTestCase {

    // MARK: - ToolDefinitions Tests

    /// MCP_DESIGN.md: 全ツールが定義されていることを確認
    /// ステートレス設計: セッション管理ツール（start_session, end_session）は削除済み
    /// Phase 5: 権限ベース認可システム導入
    func testToolDefinitionsContainsAllTools() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        // PRD定義ツール（MCP_DESIGN.md）- ステートレス設計版 + Phase 5権限システム
        // エージェント管理（Phase 5: Manager用ツール追加）
        XCTAssertTrue(toolNames.contains("get_my_profile"), "get_my_profile should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("list_subordinates"), "list_subordinates should be defined for Manager hierarchy (Phase 5)")
        XCTAssertTrue(toolNames.contains("get_subordinate_profile"), "get_subordinate_profile should be defined for Manager hierarchy (Phase 5)")

        // プロジェクト管理
        XCTAssertTrue(toolNames.contains("get_project"), "get_project should be defined")
        XCTAssertTrue(toolNames.contains("list_active_projects_with_agents"), "list_active_projects_with_agents should be defined")

        // タスク管理
        XCTAssertTrue(toolNames.contains("list_tasks"), "list_tasks should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("get_task"), "get_task should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("get_my_task"), "get_my_task should be defined (Phase 4 replacement for get_my_tasks)")
        XCTAssertTrue(toolNames.contains("update_task_status"), "update_task_status should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("assign_task"), "assign_task should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("create_task"), "create_task should be defined for Managers (Phase 5)")

        // Phase 4: Worker報告
        XCTAssertTrue(toolNames.contains("report_completed"), "report_completed should be defined (Phase 4 Worker API)")

        // Help tool (Phase: Tool Authorization Enhancement)
        XCTAssertTrue(toolNames.contains("help"), "help should be defined for context-aware tool discovery")
    }

    /// ステートレス設計で削除されたツールが存在しないことを確認
    /// Phase 5: 権限システムにより削除されたツールを追加
    func testRemovedToolsFromStatelessDesign() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        // ステートレス設計およびPhase 5で削除されたツール
        let removedTools = [
            "start_session",   // セッション管理は削除
            "end_session",     // セッション管理は削除
            "get_my_sessions", // セッション管理は削除
            "update_task",     // UIでのみ編集可能
            // Phase 5: 権限システムにより削除されたツール
            "list_agents",     // Coordinator専用のlist_managed_agentsに置き換え
            "get_agent_profile", // Manager専用のget_subordinate_profileに置き換え
            "list_projects",   // 削除（プロジェクト情報はget_projectで取得）
            // Phase 5: get_my_tasksとget_pending_tasksはget_my_taskに統合
            "get_my_tasks",
            "get_pending_tasks"
        ]

        for tool in removedTools {
            XCTAssertFalse(toolNames.contains(tool), "\(tool) should not exist in Phase 5 authorization design")
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

    /// get_my_profileツール定義（Phase 5: session_token認証）
    func testGetMyProfileToolDefinition() {
        let tool = ToolDefinitions.getMyProfile

        XCTAssertEqual(tool["name"] as? String, "get_my_profile")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            // Phase 5: session_tokenで認証（agent_idはセッションから取得）
            XCTAssertTrue(required.contains("session_token"), "get_my_profile should require session_token in Phase 5")
        }
    }

    /// Phase 5: list_subordinatesツール定義（Manager専用）
    func testListSubordinatesToolDefinition() {
        let tool = ToolDefinitions.listSubordinates

        XCTAssertEqual(tool["name"] as? String, "list_subordinates")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "list_subordinates should require session_token")
        }
    }

    /// Phase 5: get_subordinate_profileツール定義（Manager専用）
    func testGetSubordinateProfileToolDefinition() {
        let tool = ToolDefinitions.getSubordinateProfile

        XCTAssertEqual(tool["name"] as? String, "get_subordinate_profile")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "get_subordinate_profile should require session_token")
            XCTAssertTrue(required.contains("agent_id"), "get_subordinate_profile should require agent_id")
        }
    }

    /// Phase 5: list_managed_agentsツール定義（Coordinator専用）
    func testListManagedAgentsToolDefinition() {
        let tool = ToolDefinitions.listManagedAgents

        XCTAssertEqual(tool["name"] as? String, "list_managed_agents")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            // coordinator_tokenはオプショナル（環境変数からも取得可能）
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

    /// list_active_projects_with_agentsツール定義（Phase 4: Coordinator用API）
    func testListActiveProjectsWithAgentsToolDefinition() {
        let tool = ToolDefinitions.listActiveProjectsWithAgents

        XCTAssertEqual(tool["name"] as? String, "list_active_projects_with_agents")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.isEmpty, "list_active_projects_with_agents should have no required parameters")
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
    /// Phase 3-4: session_token検証必須（agent_idはセッションから取得）
    func testGetPendingTasksToolDefinition() {
        let tool = ToolDefinitions.getPendingTasks

        XCTAssertEqual(tool["name"] as? String, "get_pending_tasks")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "get_pending_tasks should require session_token")
        }
    }

    /// Phase 3-2: get_pending_tasksがall()に含まれている
    /// Phase 5: get_pending_tasksはget_my_taskに統合されたため削除
    func testGetPendingTasksToolRemovedInPhase5() {
        let allTools = ToolDefinitions.all()
        let toolNames = allTools.compactMap { $0["name"] as? String }

        // Phase 5: get_pending_tasksはget_my_taskに統合され削除
        XCTAssertFalse(toolNames.contains("get_pending_tasks"), "get_pending_tasks should NOT be in all tools (replaced by get_my_task in Phase 5)")
        XCTAssertTrue(toolNames.contains("get_my_task"), "get_my_task should be in all tools (Phase 5 replacement)")
    }

    /// Phase 3-3: report_execution_startツール定義
    /// Phase 3-4: session_token検証必須
    func testReportExecutionStartToolDefinition() {
        let tool = ToolDefinitions.reportExecutionStart

        XCTAssertEqual(tool["name"] as? String, "report_execution_start")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "report_execution_start should require session_token")
            XCTAssertTrue(required.contains("task_id"), "report_execution_start should require task_id")

            if let properties = schema["properties"] as? [String: Any] {
                XCTAssertNotNil(properties["session_token"], "Should have session_token property")
                XCTAssertNotNil(properties["task_id"], "Should have task_id property")
            }
        }
    }

    /// Phase 3-3: report_execution_completeツール定義
    func testReportExecutionCompleteToolDefinition() {
        let tool = ToolDefinitions.reportExecutionComplete

        XCTAssertEqual(tool["name"] as? String, "report_execution_complete")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("execution_log_id"), "report_execution_complete should require execution_log_id")
            XCTAssertTrue(required.contains("exit_code"), "report_execution_complete should require exit_code")
            XCTAssertTrue(required.contains("duration_seconds"), "report_execution_complete should require duration_seconds")

            if let properties = schema["properties"] as? [String: Any] {
                XCTAssertNotNil(properties["execution_log_id"], "Should have execution_log_id property")
                XCTAssertNotNil(properties["exit_code"], "Should have exit_code property")
                XCTAssertNotNil(properties["duration_seconds"], "Should have duration_seconds property")
                XCTAssertNotNil(properties["log_file_path"], "Should have log_file_path property")
                XCTAssertNotNil(properties["error_message"], "Should have error_message property")
            }
        }
    }

    /// Phase 3-3: 実行ログツールがall()に含まれている
    func testExecutionLogToolsInAllTools() {
        let allTools = ToolDefinitions.all()
        let toolNames = allTools.compactMap { $0["name"] as? String }

        XCTAssertTrue(toolNames.contains("report_execution_start"), "report_execution_start should be in all tools")
        XCTAssertTrue(toolNames.contains("report_execution_complete"), "report_execution_complete should be in all tools")
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

    /// MCPError.agentNotAssignedToProjectのテスト（Phase 4）
    func testMCPErrorAgentNotAssignedToProject() {
        let error = MCPError.agentNotAssignedToProject(agentId: "agt_dev", projectId: "prj_frontend")
        XCTAssertTrue(error.description.contains("agt_dev"))
        XCTAssertTrue(error.description.contains("prj_frontend"))
        XCTAssertTrue(error.description.contains("not assigned"))
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
    /// 参照: Sources/MCPServer/Authorization/ToolAuthorization.swift - 権限定義
    func testToolCount() {
        let tools = ToolDefinitions.all()

        // 現在のツール一覧: 35個
        // Unauthenticated: 2 (help, authenticate)
        // Coordinator-only: 7 (health_check, list_managed_agents, list_active_projects_with_agents, get_agent_action, register_execution_log_file, invalidate_session, report_agent_error)
        // Manager-only: 7 (list_subordinates, get_subordinate_profile, create_task, create_tasks_batch, assign_task, approve_task_request, reject_task_request)
        // Worker-only: 1 (report_completed)
        // Authenticated (Manager + Worker): 15 (logout, report_model, get_my_profile, get_my_task, get_notifications, get_next_action, update_task_status, get_project, list_tasks, get_task, report_execution_start, report_execution_complete, send_message, start_conversation, end_conversation, request_task)
        // Chat-only: 2 (get_pending_messages, respond_chat)
        // 注: list_agents, get_agent_profile, list_projects は削除済み
        // 注: get_my_tasks, get_pending_tasks はget_my_taskに統合済み
        // 注: start_conversation, end_conversation はAI-to-AI会話用（UC016）
        // 注: request_task, approve_task_request, reject_task_request はタスク依頼機能用
        XCTAssertEqual(tools.count, 35, "Should have 35 tools defined")
    }
}

// MARK: - PRD Compliance Summary Tests

/// Phase 5: 権限ベース認可システムのPRD適合性テスト
final class MCPPRDComplianceTests: XCTestCase {

    /// Phase 5: 権限ベース認可システムの適合性サマリー
    func testPRDComplianceSummary() {
        let tools = ToolDefinitions.all()
        let toolNames = Set(tools.compactMap { $0["name"] as? String })

        // Phase 5 権限ベース認可システムで実装されているツール
        let implementedTools = [
            // Unauthenticated (Phase 3-1)
            "authenticate",

            // Coordinator-only (Phase 5)
            "health_check",
            "list_managed_agents",
            "list_active_projects_with_agents",
            "get_agent_action",
            "register_execution_log_file",
            "invalidate_session",

            // Manager-only (Phase 5)
            "list_subordinates",
            "get_subordinate_profile",
            "create_task",
            "assign_task",

            // Worker-only (Phase 5)
            "report_completed",

            // Authenticated (Manager + Worker)
            "report_model",
            "get_my_profile",
            "get_my_task",
            "get_next_action",
            "update_task_status",
            "get_project",
            "list_tasks",
            "get_task",
            "report_execution_start",
            "report_execution_complete"
        ]

        var implementedCount = 0
        for tool in implementedTools {
            if toolNames.contains(tool) {
                implementedCount += 1
            }
        }

        // Phase 5: 主要ツール24個が実装されている
        XCTAssertGreaterThanOrEqual(implementedCount, 22, "Should have at least 22 core tools implemented in Phase 5")

        // Phase 5で削除されたツール
        let removedTools = [
            "start_session", "end_session", "get_my_sessions",  // ステートレス設計で削除
            "update_task",                                        // UIでのみ編集可能
            "list_agents", "get_agent_profile", "list_projects"   // Phase 5権限システムで削除
        ]
        for tool in removedTools {
            XCTAssertFalse(toolNames.contains(tool), "\(tool) should be removed in Phase 5 authorization design")
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
            agentName: "Test Agent",
            systemPrompt: "You are a developer agent."
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.sessionToken, "sess_abc123")
        XCTAssertEqual(result.expiresIn, 3600)
        XCTAssertEqual(result.agentName, "Test Agent")
        XCTAssertEqual(result.systemPrompt, "You are a developer agent.")
        XCTAssertNil(result.error)
    }

    /// 認証成功結果（systemPrompt なし）の生成テスト
    func testAuthenticateResultSuccessWithoutSystemPrompt() {
        let result = AuthenticateResult.success(
            token: "sess_abc123",
            expiresIn: 3600,
            agentName: "Test Agent",
            systemPrompt: nil
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.sessionToken, "sess_abc123")
        XCTAssertEqual(result.expiresIn, 3600)
        XCTAssertEqual(result.agentName, "Test Agent")
        XCTAssertNil(result.systemPrompt)
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

// MARK: - Model Verification Tool Tests

/// モデル検証ツールのテスト
final class ModelVerificationToolTests: XCTestCase {

    // MARK: - Tool Definition Tests

    /// report_model ツールが定義されていることを確認
    func testReportModelToolDefinition() {
        let tool = ToolDefinitions.reportModel

        XCTAssertEqual(tool["name"] as? String, "report_model")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "report_model should require session_token")
            XCTAssertTrue(required.contains("provider"), "report_model should require provider")
            XCTAssertTrue(required.contains("model_id"), "report_model should require model_id")

            if let properties = schema["properties"] as? [String: Any] {
                XCTAssertNotNil(properties["session_token"], "Should have session_token property")
                XCTAssertNotNil(properties["provider"], "Should have provider property")
                XCTAssertNotNil(properties["model_id"], "Should have model_id property")
            }
        }
    }

    /// report_model ツールが全ツール一覧に含まれることを確認
    func testReportModelToolInAllTools() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(toolNames.contains("report_model"), "report_model should be in all tools")
    }

    /// get_next_action ツールが定義されていることを確認（モデル検証フローの一部）
    func testGetNextActionToolDefinition() {
        let tool = ToolDefinitions.getNextAction

        XCTAssertEqual(tool["name"] as? String, "get_next_action")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "get_next_action should require session_token")
        }
    }

    /// get_next_action ツールが全ツール一覧に含まれることを確認
    func testGetNextActionToolInAllTools() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(toolNames.contains("get_next_action"), "get_next_action should be in all tools")
    }
}

// MARK: - ExecutionLog Model Verification Tests

/// ExecutionLogのモデル検証フィールドテスト
final class ExecutionLogModelVerificationTests: XCTestCase {

    /// ExecutionLogにモデル検証フィールドが存在することを確認
    func testExecutionLogHasModelVerificationFields() {
        let log = ExecutionLog(
            taskId: TaskID(value: "task-123"),
            agentId: AgentID(value: "agent-456"),
            reportedProvider: "claude",
            reportedModel: "claude-opus-4-20250514",
            modelVerified: true
        )

        XCTAssertEqual(log.reportedProvider, "claude")
        XCTAssertEqual(log.reportedModel, "claude-opus-4-20250514")
        XCTAssertEqual(log.modelVerified, true)
    }

    /// ExecutionLogのsetModelInfoメソッドが正しく動作することを確認
    func testExecutionLogSetModelInfo() {
        var log = ExecutionLog(
            taskId: TaskID(value: "task-123"),
            agentId: AgentID(value: "agent-456")
        )

        // 初期状態ではnil
        XCTAssertNil(log.reportedProvider)
        XCTAssertNil(log.reportedModel)
        XCTAssertNil(log.modelVerified)

        // setModelInfoでモデル情報を設定
        log.setModelInfo(provider: "gemini", model: "gemini-2.0-flash", verified: false)

        XCTAssertEqual(log.reportedProvider, "gemini")
        XCTAssertEqual(log.reportedModel, "gemini-2.0-flash")
        XCTAssertEqual(log.modelVerified, false)
    }

    /// ExecutionLogの完全なイニシャライザでモデル検証フィールドが設定できることを確認
    func testExecutionLogFullInitializerWithModelFields() {
        let log = ExecutionLog(
            id: ExecutionLogID(value: "log-789"),
            taskId: TaskID(value: "task-123"),
            agentId: AgentID(value: "agent-456"),
            status: .completed,
            startedAt: Date(),
            completedAt: Date(),
            exitCode: 0,
            durationSeconds: 120.5,
            logFilePath: "/tmp/log.txt",
            errorMessage: nil,
            reportedProvider: "openai",
            reportedModel: "gpt-4o",
            modelVerified: nil  // 未検証
        )

        XCTAssertEqual(log.reportedProvider, "openai")
        XCTAssertEqual(log.reportedModel, "gpt-4o")
        XCTAssertNil(log.modelVerified)
    }
}

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
        XCTAssertEqual(ToolAuthorization.permissions["invalidate_session"], .coordinatorOnly)
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
        XCTAssertEqual(ToolAuthorization.permissions["respond_chat"], .chatOnly)
    }

    /// ヘルプツールの権限確認（未認証でも利用可能）
    func testHelpToolPermission() {
        XCTAssertEqual(ToolAuthorization.permissions["help"], .unauthenticated)
    }

    /// 認証済み共通ツールの権限確認
    func testAuthenticatedToolPermissions() {
        XCTAssertEqual(ToolAuthorization.permissions["get_my_profile"], .authenticated)
        XCTAssertEqual(ToolAuthorization.permissions["update_task_status"], .authenticated)
        XCTAssertEqual(ToolAuthorization.permissions["list_tasks"], .authenticated)
        XCTAssertEqual(ToolAuthorization.permissions["get_task"], .authenticated)
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
        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "respond_chat", caller: workerChatCaller))

        // Manager with chat session can also access chat tools
        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "get_pending_messages", caller: managerChatCaller))
        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "respond_chat", caller: managerChatCaller))
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

        XCTAssertThrowsError(try ToolAuthorization.authorize(tool: "respond_chat", caller: workerTaskCaller)) { error in
            guard case ToolAuthorizationError.chatSessionRequired(let tool, let currentPurpose) = error else {
                XCTFail("Expected chatSessionRequired error, got \(error)")
                return
            }
            XCTAssertEqual(tool, "respond_chat")
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
        XCTAssertTrue(chatTools.contains("respond_chat"))

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

// MARK: - Help Tool Tests
// 参照: docs/design/TOOL_AUTHORIZATION_ENHANCEMENT.md

/// helpツールのテスト
final class HelpToolTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!

    override func setUpWithError() throws {
        // テスト用インメモリDBを作成
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_help_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // MCPServer作成
        mcpServer = MCPServer(database: db)
    }

    override func tearDownWithError() throws {
        mcpServer = nil
        db = nil
    }

    // MARK: - Help List Tests

    /// 未認証でhelpを呼び出すと、未認証で利用可能なツールのみ返す
    func testHelpListForUnauthenticated() throws {
        let result = try mcpServer.executeTool(
            name: "help",
            arguments: [:],
            caller: .unauthenticated
        ) as! [String: Any]

        // contextの確認
        let context = result["context"] as! [String: Any]
        XCTAssertEqual(context["caller_type"] as? String, "unauthenticated")

        // 利用可能なツール
        let availableTools = result["available_tools"] as! [[String: Any]]
        let toolNames = availableTools.map { $0["name"] as! String }

        // 未認証では authenticate と help のみ利用可能
        XCTAssertTrue(toolNames.contains("authenticate"))
        XCTAssertTrue(toolNames.contains("help"))

        // Coordinator専用ツールは含まれない
        XCTAssertFalse(toolNames.contains("health_check"))
        XCTAssertFalse(toolNames.contains("get_agent_action"))

        // 認証済みツールは含まれない
        XCTAssertFalse(toolNames.contains("get_my_profile"))
        XCTAssertFalse(toolNames.contains("list_tasks"))

        // unavailable_infoが含まれる
        let unavailableInfo = result["unavailable_info"] as! [String: String]
        XCTAssertNotNil(unavailableInfo["authenticated_tools"])
    }

    /// Workerのtaskセッションでhelpを呼び出すと、chatOnlyツールは含まれない
    func testHelpListForWorkerTaskSession() throws {
        let taskSession = AgentSession(
            agentId: AgentID(value: "agent-001"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        let result = try mcpServer.executeTool(
            name: "help",
            arguments: [:],
            caller: workerCaller
        ) as! [String: Any]

        // contextの確認
        let context = result["context"] as! [String: Any]
        XCTAssertEqual(context["caller_type"] as? String, "worker")
        XCTAssertEqual(context["session_purpose"] as? String, "task")

        // 利用可能なツール
        let availableTools = result["available_tools"] as! [[String: Any]]
        let toolNames = availableTools.map { $0["name"] as! String }

        // 認証済みツールは含まれる
        XCTAssertTrue(toolNames.contains("get_my_profile"))
        XCTAssertTrue(toolNames.contains("list_tasks"))
        XCTAssertTrue(toolNames.contains("help"))
        XCTAssertTrue(toolNames.contains("authenticate"))

        // chatOnlyツールは含まれない
        XCTAssertFalse(toolNames.contains("get_pending_messages"))
        XCTAssertFalse(toolNames.contains("respond_chat"))

        // Coordinator専用ツールは含まれない
        XCTAssertFalse(toolNames.contains("health_check"))

        // unavailable_infoにchat_toolsが含まれる
        let unavailableInfo = result["unavailable_info"] as! [String: String]
        XCTAssertNotNil(unavailableInfo["chat_tools"])
    }

    /// Workerのchatセッションでhelpを呼び出すと、chatOnlyツールも含まれる
    func testHelpListForWorkerChatSession() throws {
        let chatSession = AgentSession(
            agentId: AgentID(value: "agent-001"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let workerCaller = CallerType.worker(agentId: chatSession.agentId, session: chatSession)

        let result = try mcpServer.executeTool(
            name: "help",
            arguments: [:],
            caller: workerCaller
        ) as! [String: Any]

        // contextの確認
        let context = result["context"] as! [String: Any]
        XCTAssertEqual(context["session_purpose"] as? String, "chat")

        // 利用可能なツール
        let availableTools = result["available_tools"] as! [[String: Any]]
        let toolNames = availableTools.map { $0["name"] as! String }

        // chatOnlyツールが含まれる
        XCTAssertTrue(toolNames.contains("get_pending_messages"))
        XCTAssertTrue(toolNames.contains("respond_chat"))
    }

    /// Coordinatorでhelpを呼び出すと、Coordinator専用ツールも含まれる
    func testHelpListForCoordinator() throws {
        let result = try mcpServer.executeTool(
            name: "help",
            arguments: [:],
            caller: .coordinator
        ) as! [String: Any]

        // contextの確認
        let context = result["context"] as! [String: Any]
        XCTAssertEqual(context["caller_type"] as? String, "coordinator")

        // 利用可能なツール
        let availableTools = result["available_tools"] as! [[String: Any]]
        let toolNames = availableTools.map { $0["name"] as! String }

        // Coordinator専用ツールが含まれる
        XCTAssertTrue(toolNames.contains("health_check"))
        XCTAssertTrue(toolNames.contains("get_agent_action"))
        XCTAssertTrue(toolNames.contains("list_managed_agents"))
    }

    // MARK: - Help Detail Tests

    /// 利用可能なツールの詳細を取得
    func testHelpDetailForAvailableTool() throws {
        let result = try mcpServer.executeTool(
            name: "help",
            arguments: ["tool_name": "authenticate"],
            caller: .unauthenticated
        ) as! [String: Any]

        // 基本情報
        XCTAssertEqual(result["name"] as? String, "authenticate")
        XCTAssertTrue(result["available"] as! Bool)
        XCTAssertNotNil(result["description"])

        // パラメータ情報
        let parameters = result["parameters"] as! [[String: Any]]
        let paramNames = parameters.map { $0["name"] as! String }
        XCTAssertTrue(paramNames.contains("agent_id"))
        XCTAssertTrue(paramNames.contains("passkey"))
        XCTAssertTrue(paramNames.contains("project_id"))
    }

    /// 利用不可なツールの詳細を取得すると、reasonが含まれる
    func testHelpDetailForUnavailableTool() throws {
        let result = try mcpServer.executeTool(
            name: "help",
            arguments: ["tool_name": "health_check"],
            caller: .unauthenticated
        ) as! [String: Any]

        // 基本情報
        XCTAssertEqual(result["name"] as? String, "health_check")
        XCTAssertFalse(result["available"] as! Bool)

        // 利用不可の理由
        let reason = result["reason"] as! String
        XCTAssertTrue(reason.contains("Coordinator"))
    }

    /// 存在しないツールの詳細を取得するとエラー
    func testHelpDetailForUnknownTool() throws {
        let result = try mcpServer.executeTool(
            name: "help",
            arguments: ["tool_name": "unknown_tool"],
            caller: .unauthenticated
        ) as! [String: Any]

        // エラーメッセージ
        let error = result["error"] as! String
        XCTAssertTrue(error.contains("unknown_tool"))
        XCTAssertTrue(error.contains("not found"))
    }
}

// MARK: - MCPServer Integration Tests

/// MCPServer統合テスト - reportCompletedのstatusChangedByAgentId設定バグ修正
/// 参照: TDD RED-GREEN アプローチ
final class MCPServerReportCompletedTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var taskRepository: TaskRepository!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var agentSessionRepository: AgentSessionRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!

    // テストデータ
    let testAgentId = AgentID(value: "agt_test_worker")
    let testProjectId = ProjectID(value: "prj_test")
    let testTaskId = TaskID(value: "tsk_test")

    override func setUpWithError() throws {
        // テスト用インメモリDBを作成
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_mcp_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // リポジトリを初期化
        taskRepository = TaskRepository(database: db)
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)
        agentCredentialRepository = AgentCredentialRepository(database: db)
        agentSessionRepository = AgentSessionRepository(database: db)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: db)

        // MCPServerを初期化
        mcpServer = MCPServer(database: db)

        // テストデータを作成
        try setupTestData()
    }

    override func tearDownWithError() throws {
        db = nil
        mcpServer = nil
    }

    private func setupTestData() throws {
        // プロジェクトを作成
        let project = Project(
            id: testProjectId,
            name: "Test Project",
            description: "Integration test project"
        )
        try projectRepository.save(project)

        // エージェントを作成（Worker）
        let agent = Agent(
            id: testAgentId,
            name: "Test Worker",
            role: "Worker agent for testing",
            hierarchyType: .worker,
            systemPrompt: "You are a test worker"
        )
        try agentRepository.save(agent)

        // プロジェクトにエージェントを割り当て
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: testAgentId
        )

        // エージェント認証情報を作成（rawPasskeyを使用）
        let credential = AgentCredential(
            agentId: testAgentId,
            rawPasskey: "test_passkey_12345"
        )
        try agentCredentialRepository.save(credential)

        // サブタスク付きのタスクを作成（in_progress状態）
        // メインタスク
        let mainTask = Task(
            id: testTaskId,
            projectId: testProjectId,
            title: "Main Test Task",
            description: "Main task for testing",
            status: .inProgress,
            priority: .medium,
            assigneeId: testAgentId
        )
        try taskRepository.save(mainTask)

        // サブタスク（完了済み - メインタスクの完了条件）
        let subTask = Task(
            id: TaskID.generate(),
            projectId: testProjectId,
            title: "Subtask 1",
            description: "Completed subtask",
            status: .done,
            priority: .medium,
            assigneeId: testAgentId,
            parentTaskId: testTaskId
        )
        try taskRepository.save(subTask)
    }

    /// RED: reportCompletedがstatusChangedByAgentIdを設定することを検証
    /// 期待: result="blocked"でタスクをブロック状態に変更した時、
    ///       statusChangedByAgentIdに報告者のagentIdが設定される
    func testReportCompletedSetsStatusChangedByAgentId() throws {
        // Arrange: セッションを作成（認証状態をシミュレート）
        let session = AgentSession(
            agentId: testAgentId,
            projectId: testProjectId,
            purpose: .task
        )
        try agentSessionRepository.save(session)

        // Act: report_completedツールを呼び出し（result=blocked）
        // MCPServerのexecuteToolを使用してreport_completedを実行
        // Note: summaryを省略（contextテーブルのFK制約回避のため）
        let arguments: [String: Any] = [
            "session_token": session.token,
            "result": "blocked"
        ]

        // CallerTypeを設定（Worker認証済み）
        let caller = CallerType.worker(agentId: testAgentId, session: session)

        // ツール実行
        let result = try mcpServer.executeTool(
            name: "report_completed",
            arguments: arguments,
            caller: caller
        )

        // Assert: タスクのstatusChangedByAgentIdが報告者のエージェントIDに設定されている
        let updatedTask = try taskRepository.findById(testTaskId)
        XCTAssertNotNil(updatedTask, "Task should exist after report_completed")
        XCTAssertEqual(updatedTask?.status, .blocked, "Task status should be blocked")

        // ★ これがREDになる検証ポイント ★
        // 現在のバグ: statusChangedByAgentIdが設定されていない
        XCTAssertEqual(
            updatedTask?.statusChangedByAgentId,
            testAgentId,
            "statusChangedByAgentId should be set to the reporting agent's ID, not nil or system:user"
        )

        // statusChangedAtも設定されていることを確認
        XCTAssertNotNil(
            updatedTask?.statusChangedAt,
            "statusChangedAt should be set when status is changed"
        )

        // 成功レスポンスの確認
        if let resultDict = result as? [String: Any],
           let successFlag = resultDict["success"] as? Bool {
            XCTAssertTrue(successFlag, "report_completed should succeed")
        }
    }

    /// Context作成時にFK制約違反が発生しないことを検証
    /// Bug fix: SessionID.generate()ではなく、有効なワークフローセッションを使用
    func testReportCompletedWithSummaryDoesNotCauseFKError() throws {
        // Arrange: AgentSessionを作成
        let agentSession = AgentSession(
            agentId: testAgentId,
            projectId: testProjectId,
            purpose: .task
        )
        try agentSessionRepository.save(agentSession)

        // ワークフローセッションも作成（Context作成に必要）
        let sessionRepository = SessionRepository(database: db)
        let workflowSession = Session(
            id: SessionID.generate(),
            projectId: testProjectId,
            agentId: testAgentId,
            startedAt: Date()
        )
        try sessionRepository.save(workflowSession)

        // Act: summaryを含めてreport_completedを呼び出し
        let arguments: [String: Any] = [
            "session_token": agentSession.token,
            "result": "blocked",
            "summary": "This is a test summary that should be saved to context"
        ]

        let caller = CallerType.worker(agentId: testAgentId, session: agentSession)

        // Assert: FK制約違反なく成功すること
        XCTAssertNoThrow(
            try mcpServer.executeTool(
                name: "report_completed",
                arguments: arguments,
                caller: caller
            ),
            "report_completed with summary should not throw FK constraint error"
        )

        // Contextが正しく保存されていることを確認
        let contextRepository = ContextRepository(database: db)
        let contexts = try contextRepository.findByTask(testTaskId)
        XCTAssertFalse(contexts.isEmpty, "Context should be saved when summary is provided")
        XCTAssertEqual(contexts.first?.sessionId, workflowSession.id, "Context should use the active workflow session ID")
    }
}

// MARK: - register_execution_log_file Tool Tests

/// register_execution_log_file MCPツールの統合テスト
final class MCPServerRegisterExecutionLogFileTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var taskRepository: TaskRepository!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var executionLogRepository: ExecutionLogRepository!

    // テストデータ
    let testAgentId = AgentID(value: "agt_test_log")
    let testProjectId = ProjectID(value: "prj_test_log")
    let testTaskId = TaskID(value: "tsk_test_log")

    override func setUpWithError() throws {
        // テスト用インメモリDBを作成
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_mcp_log_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // リポジトリを初期化
        taskRepository = TaskRepository(database: db)
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)
        executionLogRepository = ExecutionLogRepository(database: db)

        // MCPServerを初期化
        mcpServer = MCPServer(database: db)

        // テストデータを作成
        try setupTestData()
    }

    override func tearDownWithError() throws {
        db = nil
        mcpServer = nil
    }

    private func setupTestData() throws {
        // プロジェクトを作成
        let project = Project(
            id: testProjectId,
            name: "Test Project for Log",
            description: "Test project for execution log tests"
        )
        try projectRepository.save(project)

        // エージェントを作成
        let agent = Agent(
            id: testAgentId,
            name: "Test Agent",
            role: "Worker agent for log testing",
            hierarchyType: .worker
        )
        try agentRepository.save(agent)

        // タスクを作成
        let task = Task(
            id: testTaskId,
            projectId: testProjectId,
            title: "Test Task for Log",
            status: .inProgress,
            assigneeId: testAgentId
        )
        try taskRepository.save(task)
    }

    /// register_execution_log_file がログファイルパスを正しく登録することを検証
    func testRegisterExecutionLogFileUpdatesLogPath() throws {
        // Arrange: 実行ログを作成（通常は report_execution_start で作成される）
        let executionLog = ExecutionLog(
            taskId: testTaskId,
            agentId: testAgentId
        )
        try executionLogRepository.save(executionLog)

        let logFilePath = "/tmp/test_agent_logs/20260116_120000.log"

        // Act: Coordinatorとしてツールを呼び出し
        let arguments: [String: Any] = [
            "agent_id": testAgentId.value,
            "task_id": testTaskId.value,
            "log_file_path": logFilePath
        ]

        let result = try mcpServer.executeTool(
            name: "register_execution_log_file",
            arguments: arguments,
            caller: .coordinator
        )

        // Assert: 成功レスポンスを確認
        guard let resultDict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(resultDict["success"] as? Bool, true)
        XCTAssertEqual(resultDict["log_file_path"] as? String, logFilePath)

        // Assert: DBに保存されたログファイルパスを確認
        let updatedLog = try executionLogRepository.findById(executionLog.id)
        XCTAssertNotNil(updatedLog, "Execution log should exist")
        XCTAssertEqual(updatedLog?.logFilePath, logFilePath, "Log file path should be updated")
    }

    /// 実行ログが存在しない場合にエラーを返すことを検証
    func testRegisterExecutionLogFileReturnsErrorWhenLogNotFound() throws {
        // Arrange: 実行ログを作成しない
        let logFilePath = "/tmp/test_agent_logs/not_found.log"

        // Act: 存在しないエージェント/タスクで呼び出し
        let arguments: [String: Any] = [
            "agent_id": "agt_nonexistent",
            "task_id": "tsk_nonexistent",
            "log_file_path": logFilePath
        ]

        let result = try mcpServer.executeTool(
            name: "register_execution_log_file",
            arguments: arguments,
            caller: .coordinator
        )

        // Assert: エラーレスポンスを確認
        guard let resultDict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(resultDict["success"] as? Bool, false)
        XCTAssertEqual(resultDict["error"] as? String, "execution_log_not_found")
    }

    /// Coordinator以外からの呼び出しを拒否することを検証
    /// Note: executeTool は認可後の入り口なので、認可テストは ToolAuthorization.authorize を使用
    func testRegisterExecutionLogFileRequiresCoordinator() throws {
        // Act & Assert: Coordinatorからの呼び出しは許可される
        XCTAssertNoThrow(
            try ToolAuthorization.authorize(
                tool: "register_execution_log_file",
                caller: .coordinator
            )
        )

        // Act & Assert: Unauthenticatedからの呼び出しは拒否される
        XCTAssertThrowsError(
            try ToolAuthorization.authorize(
                tool: "register_execution_log_file",
                caller: .unauthenticated
            )
        ) { error in
            guard case ToolAuthorizationError.coordinatorRequired(let tool) = error else {
                XCTFail("Should throw ToolAuthorizationError.coordinatorRequired, got: \(error)")
                return
            }
            XCTAssertEqual(tool, "register_execution_log_file")
        }
    }

    /// 必須パラメータが欠けている場合のエラーを検証
    func testRegisterExecutionLogFileMissingArguments() throws {
        // Act & Assert: agent_idが欠けている
        XCTAssertThrowsError(
            try mcpServer.executeTool(
                name: "register_execution_log_file",
                arguments: ["task_id": "tsk_1", "log_file_path": "/tmp/test.log"],
                caller: .coordinator
            )
        ) { error in
            if case MCPError.missingArguments(let args) = error {
                XCTAssertTrue(args.contains("agent_id"))
            } else {
                XCTFail("Should throw MCPError.missingArguments")
            }
        }
    }
}

// MARK: - findLatestByAgentAndTask Repository Tests

/// ExecutionLogRepository.findLatestByAgentAndTask の単体テスト
final class ExecutionLogRepositoryFindLatestTests: XCTestCase {

    var db: DatabaseQueue!
    var executionLogRepository: ExecutionLogRepository!
    var taskRepository: TaskRepository!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!

    let testAgentId = AgentID(value: "agt_latest_test")
    let testProjectId = ProjectID(value: "prj_latest_test")
    let testTaskId = TaskID(value: "tsk_latest_test")

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_exec_log_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        executionLogRepository = ExecutionLogRepository(database: db)
        taskRepository = TaskRepository(database: db)
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)

        try setupTestData()
    }

    override func tearDownWithError() throws {
        db = nil
    }

    private func setupTestData() throws {
        let project = Project(id: testProjectId, name: "Test Project")
        try projectRepository.save(project)

        let agent = Agent(id: testAgentId, name: "Test Agent", role: "Worker")
        try agentRepository.save(agent)

        let task = Task(id: testTaskId, projectId: testProjectId, title: "Test Task")
        try taskRepository.save(task)
    }

    /// 最新の実行ログを正しく取得することを検証
    func testFindLatestByAgentAndTaskReturnsLatest() throws {
        // Arrange: 複数の実行ログを作成（異なる開始時刻で）
        let oldLog = ExecutionLog(
            id: ExecutionLogID.generate(),
            taskId: testTaskId,
            agentId: testAgentId,
            startedAt: Date().addingTimeInterval(-3600)  // 1時間前
        )
        try executionLogRepository.save(oldLog)

        // 少し待機して新しいログを作成
        let newLog = ExecutionLog(
            id: ExecutionLogID.generate(),
            taskId: testTaskId,
            agentId: testAgentId,
            startedAt: Date()  // 現在
        )
        try executionLogRepository.save(newLog)

        // Act
        let result = try executionLogRepository.findLatestByAgentAndTask(
            agentId: testAgentId,
            taskId: testTaskId
        )

        // Assert: 最新のログが返される
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, newLog.id, "Should return the most recent log")
    }

    /// 該当するログが存在しない場合にnilを返すことを検証
    func testFindLatestByAgentAndTaskReturnsNilWhenNotFound() throws {
        // Act: 存在しないエージェント/タスクで検索
        let result = try executionLogRepository.findLatestByAgentAndTask(
            agentId: AgentID(value: "agt_nonexistent"),
            taskId: TaskID(value: "tsk_nonexistent")
        )

        // Assert
        XCTAssertNil(result, "Should return nil when no log exists")
    }

    /// エージェントIDとタスクIDの両方が一致するログのみを返すことを検証
    func testFindLatestByAgentAndTaskMatchesBothIds() throws {
        // Arrange: 同じタスクで異なるエージェントのログ
        let otherAgentId = AgentID(value: "agt_other")
        let otherAgent = Agent(id: otherAgentId, name: "Other Agent", role: "Worker")
        try agentRepository.save(otherAgent)

        let otherAgentLog = ExecutionLog(
            taskId: testTaskId,
            agentId: otherAgentId,
            startedAt: Date()  // 最新
        )
        try executionLogRepository.save(otherAgentLog)

        let myLog = ExecutionLog(
            taskId: testTaskId,
            agentId: testAgentId,
            startedAt: Date().addingTimeInterval(-60)  // 1分前
        )
        try executionLogRepository.save(myLog)

        // Act
        let result = try executionLogRepository.findLatestByAgentAndTask(
            agentId: testAgentId,
            taskId: testTaskId
        )

        // Assert: 自分のエージェントのログが返される
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.agentId, testAgentId, "Should return log for the specified agent")
        XCTAssertEqual(result?.id, myLog.id)
    }
}

// MARK: - Working Directory Resolution Tests

/// ワーキングディレクトリ解決のテスト
/// Bug: getMyTask が AgentWorkingDirectory を参照せず、Project.workingDirectory のみを使用している
/// 期待: AgentWorkingDirectory > Project.workingDirectory の優先順位で解決されるべき
final class WorkingDirectoryResolutionTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var taskRepository: TaskRepository!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var agentSessionRepository: AgentSessionRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!
    var workingDirectoryRepository: AgentWorkingDirectoryRepository!
    var executionLogRepository: ExecutionLogRepository!

    // テストデータ
    let testAgentId = AgentID(value: "agt_working_dir_test")
    let testProjectId = ProjectID(value: "prj_working_dir_test")
    let testTaskId = TaskID(value: "tsk_working_dir_test")

    // ワーキングディレクトリのテスト値
    let projectWorkingDirectory = "/project/default/path"
    let agentWorkingDirectory = "/agent/specific/path"  // この値が返されるべき

    override func setUpWithError() throws {
        // テスト用インメモリDBを作成
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_wd_\(UUID().uuidString).db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // リポジトリを初期化
        taskRepository = TaskRepository(database: db)
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)
        agentCredentialRepository = AgentCredentialRepository(database: db)
        agentSessionRepository = AgentSessionRepository(database: db)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: db)
        workingDirectoryRepository = AgentWorkingDirectoryRepository(database: db)
        executionLogRepository = ExecutionLogRepository(database: db)

        // MCPServerを初期化
        mcpServer = MCPServer(database: db)

        // テストデータを作成
        try setupTestData()
    }

    override func tearDownWithError() throws {
        db = nil
        mcpServer = nil
    }

    private func setupTestData() throws {
        // プロジェクトを作成（workingDirectoryを設定）
        var project = Project(
            id: testProjectId,
            name: "Working Dir Test Project",
            description: "Test project for working directory resolution"
        )
        project.workingDirectory = projectWorkingDirectory
        try projectRepository.save(project)

        // エージェントを作成（Worker）
        let agent = Agent(
            id: testAgentId,
            name: "Test Worker",
            role: "Worker agent for working directory testing",
            hierarchyType: .worker,
            systemPrompt: "You are a test worker"
        )
        try agentRepository.save(agent)

        // プロジェクトにエージェントを割り当て
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: testAgentId
        )

        // エージェント認証情報を作成
        let credential = AgentCredential(
            agentId: testAgentId,
            rawPasskey: "test_wd_passkey_12345"
        )
        try agentCredentialRepository.save(credential)

        // タスクを作成（in_progress状態）
        let task = Task(
            id: testTaskId,
            projectId: testProjectId,
            title: "Working Directory Test Task",
            description: "Task for testing working directory resolution",
            status: .inProgress,
            priority: .medium,
            assigneeId: testAgentId
        )
        try taskRepository.save(task)

        // ★重要★ AgentWorkingDirectoryを設定（これが優先されるべき）
        let agentWD = AgentWorkingDirectory.create(
            agentId: testAgentId,
            projectId: testProjectId,
            workingDirectory: agentWorkingDirectory
        )
        try workingDirectoryRepository.save(agentWD)
    }

    // 削除済み: testGetMyTaskReturnsAgentWorkingDirectory
    // 削除済み: testGetMyTaskFallsBackToProjectWorkingDirectoryWhenAgentWDNotSet
    // 理由: get_my_task は設計上 working_directory を返さない
    // (Coordinator が cwd パラメータで管理するため)
    // 参照: commit 9b0ad78 "Remove working_directory from MCP API responses"

    /// list_active_projects_with_agents が agentId パラメータで AgentWorkingDirectory を返すことを検証
    /// （これは正しく実装されているはず - 参考のため）
    func testListActiveProjectsWithAgentsReturnsAgentWorkingDirectory() throws {
        // Act: list_active_projects_with_agents を agentId 付きで呼び出し
        let arguments: [String: Any] = [
            "agent_id": testAgentId.value
        ]

        let result = try mcpServer.executeTool(
            name: "list_active_projects_with_agents",
            arguments: arguments,
            caller: .coordinator
        )

        // Assert: AgentWorkingDirectoryが返される
        guard let resultDict = result as? [String: Any],
              let projects = resultDict["projects"] as? [[String: Any]] else {
            XCTFail("Projects should be present in result")
            return
        }

        let targetProject = projects.first { ($0["project_id"] as? String) == testProjectId.value }
        XCTAssertNotNil(targetProject, "Test project should be in list")

        let returnedWorkingDir = targetProject?["working_directory"] as? String
        XCTAssertEqual(
            returnedWorkingDir,
            agentWorkingDirectory,
            "list_active_projects_with_agents should return AgentWorkingDirectory when agentId is provided"
        )
    }
}

// MARK: - Worker Blocked State Management Tests

/// ワーカーブロック時のマネージャー即時起動機能のテスト
/// Feature: ワーカーがブロックされた場合、マネージャーを即座に起動してブロック対処を行う
/// States: waiting_for_workers → worker_blocked → handled_blocked
final class WorkerBlockedStateManagementTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var taskRepository: TaskRepository!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var agentSessionRepository: AgentSessionRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!
    var sessionRepository: SessionRepository!
    var contextRepository: ContextRepository!
    var tempDirectory: URL!

    // テストデータ
    let managerAgentId = AgentID(value: "agt_manager_blocked_test")
    let workerAgentId = AgentID(value: "agt_worker_blocked_test")
    let testProjectId = ProjectID(value: "prj_blocked_test")
    let mainTaskId = TaskID(value: "tsk_main_blocked")
    let subTaskId = TaskID(value: "tsk_sub_blocked")

    override func setUpWithError() throws {
        // Create temp directory for working directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("blocked_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let dbPath = tempDirectory.appendingPathComponent("test.db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // リポジトリを初期化
        taskRepository = TaskRepository(database: db)
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)
        agentCredentialRepository = AgentCredentialRepository(database: db)
        agentSessionRepository = AgentSessionRepository(database: db)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: db)
        sessionRepository = SessionRepository(database: db)
        contextRepository = ContextRepository(database: db)

        // MCPServerを初期化
        mcpServer = MCPServer(database: db)

        // テストデータを作成
        try setupTestData()
    }

    override func tearDownWithError() throws {
        mcpServer = nil
        db = nil
        // Clean up temp directory
        Thread.sleep(forTimeInterval: 0.3)
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func setupTestData() throws {
        // プロジェクトを作成（workingDirectory必須）
        let project = Project(
            id: testProjectId,
            name: "Blocked Test Project",
            description: "Test project for worker blocked state management",
            workingDirectory: tempDirectory.path
        )
        try projectRepository.save(project)

        // マネージャーエージェントを作成
        let manager = Agent(
            id: managerAgentId,
            name: "Test Manager",
            role: "Manager agent for testing blocked handling",
            hierarchyType: .manager,
            systemPrompt: "You are a test manager"
        )
        try agentRepository.save(manager)

        // ワーカーエージェントを作成（マネージャーの部下）
        let worker = Agent(
            id: workerAgentId,
            name: "Test Worker",
            role: "Worker agent for testing blocked reporting",
            hierarchyType: .worker,
            parentAgentId: managerAgentId,
            systemPrompt: "You are a test worker"
        )
        try agentRepository.save(worker)

        // プロジェクトにエージェントを割り当て
        _ = try projectAgentAssignmentRepository.assign(projectId: testProjectId, agentId: managerAgentId)
        _ = try projectAgentAssignmentRepository.assign(projectId: testProjectId, agentId: workerAgentId)

        // エージェント認証情報を作成
        let managerCred = AgentCredential(agentId: managerAgentId, rawPasskey: "manager_passkey_12345")
        let workerCred = AgentCredential(agentId: workerAgentId, rawPasskey: "worker_passkey_12345")
        try agentCredentialRepository.save(managerCred)
        try agentCredentialRepository.save(workerCred)

        // メインタスク（マネージャー担当、進行中）
        let mainTask = Task(
            id: mainTaskId,
            projectId: testProjectId,
            title: "Main Task for Blocked Test",
            description: "Main task to test blocked handling",
            status: .inProgress,
            priority: .medium,
            assigneeId: managerAgentId
        )
        try taskRepository.save(mainTask)

        // サブタスク（ワーカー担当、進行中）
        let subTask = Task(
            id: subTaskId,
            projectId: testProjectId,
            title: "Sub Task for Blocked Test",
            description: "Sub task to report blocked",
            status: .inProgress,
            priority: .medium,
            assigneeId: workerAgentId,
            parentTaskId: mainTaskId
        )
        try taskRepository.save(subTask)
    }

    // MARK: - report_completed Updates Parent Context to worker_blocked

    /// ワーカーがブロック報告時に親タスクのコンテキストが worker_blocked に更新されることを検証
    func testReportCompletedBlockedUpdatesParentContextToWorkerBlocked() throws {
        // Arrange: マネージャーを waiting_for_workers 状態に
        let managerSession = Session(
            id: SessionID.generate(),
            projectId: testProjectId,
            agentId: managerAgentId,
            startedAt: Date(),
            status: .active
        )
        try sessionRepository.save(managerSession)

        let waitingContext = Context(
            id: ContextID.generate(),
            taskId: mainTaskId,
            sessionId: managerSession.id,
            agentId: managerAgentId,
            progress: "workflow:waiting_for_workers"
        )
        try contextRepository.save(waitingContext)

        // ワーカーのAgentSessionを作成
        let workerAgentSession = AgentSession(
            agentId: workerAgentId,
            projectId: testProjectId,
            purpose: .task
        )
        try agentSessionRepository.save(workerAgentSession)

        // Act: ワーカーがブロック報告
        let arguments: [String: Any] = [
            "session_token": workerAgentSession.token,
            "result": "blocked",
            "summary": "Blocked because of external dependency"
        ]
        let caller = CallerType.worker(agentId: workerAgentId, session: workerAgentSession)

        _ = try mcpServer.executeTool(name: "report_completed", arguments: arguments, caller: caller)

        // Assert: 親タスク（マネージャー）のコンテキストが worker_blocked に更新されている
        let parentContext = try contextRepository.findLatest(taskId: mainTaskId)
        XCTAssertNotNil(parentContext, "Parent task should have context")
        XCTAssertEqual(
            parentContext?.progress,
            "workflow:worker_blocked",
            "Parent context should be updated to worker_blocked when worker reports blocked"
        )
        XCTAssertNotNil(parentContext?.blockers, "Blockers should contain information about blocked subtask")
    }

    /// waiting_for_workers 以外の状態では親コンテキストが更新されないことを検証
    func testReportCompletedBlockedDoesNotUpdateParentIfNotWaiting() throws {
        // Arrange: マネージャーを handled_blocked 状態に（既に対処済み）
        let managerSession = Session(
            id: SessionID.generate(),
            projectId: testProjectId,
            agentId: managerAgentId,
            startedAt: Date(),
            status: .active
        )
        try sessionRepository.save(managerSession)

        let handledContext = Context(
            id: ContextID.generate(),
            taskId: mainTaskId,
            sessionId: managerSession.id,
            agentId: managerAgentId,
            progress: "workflow:handled_blocked"
        )
        try contextRepository.save(handledContext)

        // ワーカーのAgentSessionを作成
        let workerAgentSession = AgentSession(
            agentId: workerAgentId,
            projectId: testProjectId,
            purpose: .task
        )
        try agentSessionRepository.save(workerAgentSession)

        // Act: ワーカーがブロック報告
        let arguments: [String: Any] = [
            "session_token": workerAgentSession.token,
            "result": "blocked"
        ]
        let caller = CallerType.worker(agentId: workerAgentId, session: workerAgentSession)

        _ = try mcpServer.executeTool(name: "report_completed", arguments: arguments, caller: caller)

        // Assert: 親コンテキストは handled_blocked のまま（変更されない）
        let parentContext = try contextRepository.findLatest(taskId: mainTaskId)
        XCTAssertEqual(
            parentContext?.progress,
            "workflow:handled_blocked",
            "Parent context should NOT be updated if not in waiting_for_workers state"
        )
    }

    // MARK: - get_agent_action Returns start for worker_blocked State

    /// worker_blocked 状態のマネージャーに対して get_agent_action が start を返すことを検証
    func testGetAgentActionReturnsStartForWorkerBlockedState() throws {
        // Arrange: マネージャーを worker_blocked 状態に
        let managerSession = Session(
            id: SessionID.generate(),
            projectId: testProjectId,
            agentId: managerAgentId,
            startedAt: Date(),
            status: .active
        )
        try sessionRepository.save(managerSession)

        let blockedContext = Context(
            id: ContextID.generate(),
            taskId: mainTaskId,
            sessionId: managerSession.id,
            agentId: managerAgentId,
            progress: "workflow:worker_blocked"
        )
        try contextRepository.save(blockedContext)

        // Act: get_agent_action を呼び出し
        let arguments: [String: Any] = [
            "agent_id": managerAgentId.value,
            "project_id": testProjectId.value
        ]
        let result = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: arguments,
            caller: .coordinator
        )

        // Assert: action が start で、理由が worker_blocked
        guard let resultDict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(resultDict["action"] as? String, "start", "Should return 'start' action for worker_blocked state")
        XCTAssertEqual(resultDict["reason"] as? String, "worker_blocked", "Reason should be 'worker_blocked'")
    }

    /// handled_blocked 状態のマネージャーに対して get_agent_action が hold を返すことを検証
    func testGetAgentActionReturnsHoldForHandledBlockedState() throws {
        // Arrange: マネージャーを handled_blocked 状態に
        let managerSession = Session(
            id: SessionID.generate(),
            projectId: testProjectId,
            agentId: managerAgentId,
            startedAt: Date(),
            status: .active
        )
        try sessionRepository.save(managerSession)

        let handledContext = Context(
            id: ContextID.generate(),
            taskId: mainTaskId,
            sessionId: managerSession.id,
            agentId: managerAgentId,
            progress: "workflow:handled_blocked"
        )
        try contextRepository.save(handledContext)

        // Act: get_agent_action を呼び出し
        let arguments: [String: Any] = [
            "agent_id": managerAgentId.value,
            "project_id": testProjectId.value
        ]
        let result = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: arguments,
            caller: .coordinator
        )

        // Assert: action が hold で、理由が handled_blocked
        guard let resultDict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(resultDict["action"] as? String, "hold", "Should return 'hold' action for handled_blocked state")
        XCTAssertEqual(resultDict["reason"] as? String, "handled_blocked", "Reason should be 'handled_blocked'")
    }

    // MARK: - Blocked Task with In-Progress Task

    /// 複数タスクが割り当てられている場合、in_progressタスクがあればblockedタスクの起動チェックをスキップ
    func testGetAgentActionSkipsBlockedCheckWhenInProgressTaskExists() throws {
        // Arrange: ワーカーに2つのタスクを割り当て
        // Task 1: in_progress（実行中）
        // Task 2: blocked
        let secondTaskId = TaskID(value: "tsk_second_blocked")

        // 1つ目のタスク（in_progress）
        var subTask = try taskRepository.findById(subTaskId)!
        subTask = Task(
            id: subTask.id,
            projectId: subTask.projectId,
            title: subTask.title,
            description: subTask.description,
            status: .inProgress,  // 実行中
            priority: subTask.priority,
            assigneeId: workerAgentId,
            parentTaskId: subTask.parentTaskId
        )
        try taskRepository.save(subTask)

        // 2つ目のタスク（blocked）
        let secondTask = Task(
            id: secondTaskId,
            projectId: testProjectId,
            title: "Second Task (blocked)",
            description: "This task is blocked",
            status: .blocked,
            priority: .medium,
            assigneeId: workerAgentId,
            parentTaskId: mainTaskId,
            blockedReason: "Test blocked reason"
        )
        try taskRepository.save(secondTask)

        // Act: get_agent_action を呼び出し
        let arguments: [String: Any] = [
            "agent_id": workerAgentId.value,
            "project_id": testProjectId.value
        ]
        let result = try mcpServer.executeTool(
            name: "get_agent_action",
            arguments: arguments,
            caller: .coordinator
        )

        // Assert: blockedタスクではなく、in_progressタスクがあるのでstartを返す
        // （blockedチェックがスキップされ、通常の起動フローに進む）
        guard let resultDict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        // in_progressタスクがあるので、blockedタスクの起動理由ではなく
        // 通常のin_progressタスクに対するstartが返る
        XCTAssertEqual(resultDict["action"] as? String, "start", "Should return 'start' for in_progress task")
        // blockedタスク起動の理由（has_self_blocked_task等）ではないことを確認
        let reason = resultDict["reason"] as? String
        XCTAssertNotEqual(reason, "has_self_blocked_task", "Should not be triggered by blocked task")
        XCTAssertNotEqual(reason, "subordinate_blocked_by_user", "Should not be triggered by blocked task")
    }

    // MARK: - getManagerNextAction Transitions from worker_blocked to handled_blocked

    /// マネージャーがブロック対処を行う際に worker_blocked → handled_blocked に遷移することを検証
    func testGetManagerNextActionTransitionsToHandledBlocked() throws {
        // Arrange: サブタスクをブロック状態に変更
        var subTask = try taskRepository.findById(subTaskId)!
        subTask = Task(
            id: subTask.id,
            projectId: subTask.projectId,
            title: subTask.title,
            description: subTask.description,
            status: .blocked,
            priority: subTask.priority,
            assigneeId: subTask.assigneeId,
            parentTaskId: subTask.parentTaskId,
            blockedReason: "Test blocked reason"
        )
        try taskRepository.save(subTask)

        // マネージャーを worker_blocked 状態に
        let managerSession = Session(
            id: SessionID.generate(),
            projectId: testProjectId,
            agentId: managerAgentId,
            startedAt: Date(),
            status: .active
        )
        try sessionRepository.save(managerSession)

        let workerBlockedContext = Context(
            id: ContextID.generate(),
            taskId: mainTaskId,
            sessionId: managerSession.id,
            agentId: managerAgentId,
            progress: "workflow:worker_blocked"
        )
        try contextRepository.save(workerBlockedContext)

        // マネージャーのAgentSessionを作成（モデル検証済みとして設定）
        let managerAgentSession = AgentSession(
            id: .generate(),
            token: "sess_test_manager_verified",
            agentId: managerAgentId,
            projectId: testProjectId,
            purpose: .task,
            expiresAt: Date().addingTimeInterval(3600),
            createdAt: Date(),
            reportedProvider: "claude",
            reportedModel: "claude-sonnet-4-5-20250929",
            modelVerified: true,  // モデル検証済み
            modelVerifiedAt: Date()
        )
        try agentSessionRepository.save(managerAgentSession)

        // Act: get_next_action を呼び出し（マネージャーがブロック対処に入る）
        let arguments: [String: Any] = [
            "session_token": managerAgentSession.token
        ]
        let caller = CallerType.manager(agentId: managerAgentId, session: managerAgentSession)

        let result = try mcpServer.executeTool(name: "get_next_action", arguments: arguments, caller: caller)

        // Assert: action が review_and_resolve_blocks で、コンテキストが handled_blocked に更新
        guard let resultDict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(resultDict["action"] as? String, "review_and_resolve_blocks", "Should return review_and_resolve_blocks action")

        // コンテキストが handled_blocked に更新されていることを確認
        let updatedContext = try contextRepository.findLatest(taskId: mainTaskId)
        XCTAssertEqual(
            updatedContext?.progress,
            "workflow:handled_blocked",
            "Context should transition from worker_blocked to handled_blocked"
        )
    }

    /// マネージャーがブロック解決後に waiting_for_workers に戻ることを検証
    func testGetManagerNextActionTransitionsBackToWaitingAfterResolve() throws {
        // Arrange: handled_blocked 状態で、サブタスクを in_progress に変更（解決済み）
        var subTask = try taskRepository.findById(subTaskId)!
        subTask = Task(
            id: subTask.id,
            projectId: subTask.projectId,
            title: subTask.title,
            description: subTask.description,
            status: .inProgress,  // ブロック解除済み
            priority: subTask.priority,
            assigneeId: subTask.assigneeId,
            parentTaskId: subTask.parentTaskId
        )
        try taskRepository.save(subTask)

        // マネージャーを handled_blocked 状態に
        let managerSession = Session(
            id: SessionID.generate(),
            projectId: testProjectId,
            agentId: managerAgentId,
            startedAt: Date(),
            status: .active
        )
        try sessionRepository.save(managerSession)

        let handledContext = Context(
            id: ContextID.generate(),
            taskId: mainTaskId,
            sessionId: managerSession.id,
            agentId: managerAgentId,
            progress: "workflow:handled_blocked"
        )
        try contextRepository.save(handledContext)

        // マネージャーのAgentSessionを作成（モデル検証済みとして設定）
        let managerAgentSession = AgentSession(
            id: .generate(),
            token: "sess_test_manager_verified_2",
            agentId: managerAgentId,
            projectId: testProjectId,
            purpose: .task,
            expiresAt: Date().addingTimeInterval(3600),
            createdAt: Date(),
            reportedProvider: "claude",
            reportedModel: "claude-sonnet-4-5-20250929",
            modelVerified: true,  // モデル検証済み
            modelVerifiedAt: Date()
        )
        try agentSessionRepository.save(managerAgentSession)

        // Act: get_next_action を呼び出し
        let arguments: [String: Any] = [
            "session_token": managerAgentSession.token
        ]
        let caller = CallerType.manager(agentId: managerAgentId, session: managerAgentSession)

        let result = try mcpServer.executeTool(name: "get_next_action", arguments: arguments, caller: caller)

        // Assert: action が exit（ワーカー待機）で、コンテキストが waiting_for_workers に更新
        guard let resultDict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }
        XCTAssertEqual(resultDict["action"] as? String, "exit", "Should return exit action when waiting for workers")
        XCTAssertEqual(resultDict["state"] as? String, "waiting_for_workers", "State should be waiting_for_workers")

        // コンテキストが waiting_for_workers に更新されていることを確認
        let updatedContext = try contextRepository.findLatest(taskId: mainTaskId)
        XCTAssertEqual(
            updatedContext?.progress,
            "workflow:waiting_for_workers",
            "Context should transition back to waiting_for_workers after resolve"
        )
    }
}

// MARK: - Chat Tools Tests
// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 3

/// Phase 3: get_pending_messages ツールのテスト
final class ChatToolsTests: XCTestCase {

    // MARK: - Tool Definition Tests

    /// get_pending_messages ツールが定義されていることを確認
    func testGetPendingMessagesToolDefinition() {
        let tool = ToolDefinitions.getPendingMessages

        XCTAssertEqual(tool["name"] as? String, "get_pending_messages")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "get_pending_messages should require session_token")
        }
    }

    /// get_pending_messages ツールが全ツール一覧に含まれることを確認
    func testGetPendingMessagesToolInAllTools() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(toolNames.contains("get_pending_messages"), "get_pending_messages should be in all tools")
    }

    /// get_pending_messages ツールの説明に新しいレスポンス構造が記載されていることを確認
    func testGetPendingMessagesDescriptionIncludesResponseStructure() {
        let tool = ToolDefinitions.getPendingMessages
        let description = tool["description"] as? String ?? ""

        // 新しいレスポンス構造のキーが説明に含まれることを確認
        XCTAssertTrue(description.contains("context_messages"), "Description should mention context_messages")
        XCTAssertTrue(description.contains("pending_messages"), "Description should mention pending_messages")
        XCTAssertTrue(description.contains("total_history_count"), "Description should mention total_history_count")
        XCTAssertTrue(description.contains("context_truncated"), "Description should mention context_truncated")
    }

    /// respond_chat ツールが定義されていることを確認
    func testRespondChatToolDefinition() {
        let tool = ToolDefinitions.respondChat

        XCTAssertEqual(tool["name"] as? String, "respond_chat")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "respond_chat should require session_token")
            XCTAssertTrue(required.contains("content"), "respond_chat should require content")
        }
    }

    /// respond_chat ツールが全ツール一覧に含まれることを確認
    func testRespondChatToolInAllTools() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(toolNames.contains("respond_chat"), "respond_chat should be in all tools")
    }
}

// MARK: - Notification System Tests
// 参照: docs/design/NOTIFICATION_SYSTEM.md

/// get_notifications ツール定義テスト
final class NotificationToolDefinitionTests: XCTestCase {

    func testGetNotificationsToolDefinition() {
        let tools = ToolDefinitions.all()
        let tool = tools.first { ($0["name"] as? String) == "get_notifications" }

        XCTAssertNotNil(tool, "get_notifications tool should be defined")
        XCTAssertNotNil(tool?["description"])

        if let schema = tool?["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "get_notifications should require session_token")
        }
    }

    func testGetNotificationsToolInAllTools() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(toolNames.contains("get_notifications"), "get_notifications should be in all tools")
    }

    func testGetNotificationsToolHasMarkAsReadParameter() {
        let tools = ToolDefinitions.all()
        let tool = tools.first { ($0["name"] as? String) == "get_notifications" }

        XCTAssertNotNil(tool, "get_notifications tool should be defined")

        if let schema = tool?["inputSchema"] as? [String: Any],
           let properties = schema["properties"] as? [String: Any] {
            XCTAssertNotNil(properties["mark_as_read"], "get_notifications should have mark_as_read parameter")
        }
    }
}

/// get_notifications ツール認可テスト
final class NotificationToolAuthorizationTests: XCTestCase {

    func testGetNotificationsRequiresAuthentication() {
        let permission = ToolAuthorization.permissions["get_notifications"]
        XCTAssertEqual(permission, .authenticated, "get_notifications should require authentication")
    }
}

/// 通知システム統合テスト
final class NotificationSystemIntegrationTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var notificationRepository: NotificationRepository!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var taskRepository: TaskRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var agentSessionRepository: AgentSessionRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!

    let testAgentId = AgentID(value: "agt_notif_test")
    let testProjectId = ProjectID(value: "prj_notif_test")
    var sessionToken: String?
    var tempDirectory: URL!

    override func setUpWithError() throws {
        // Create temp directory for working directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notif_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let dbPath = tempDirectory.appendingPathComponent("test.db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        notificationRepository = NotificationRepository(database: db)
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)
        taskRepository = TaskRepository(database: db)
        agentCredentialRepository = AgentCredentialRepository(database: db)
        agentSessionRepository = AgentSessionRepository(database: db)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: db)

        mcpServer = MCPServer(database: db)

        try setupTestData()
    }

    override func tearDownWithError() throws {
        mcpServer = nil
        db = nil
        sessionToken = nil
        // Clean up temp directory
        Thread.sleep(forTimeInterval: 0.3)
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func setupTestData() throws {
        // プロジェクトを作成（workingDirectory必須）
        let project = Project(
            id: testProjectId,
            name: "Notification Test Project",
            description: "Project for notification testing",
            workingDirectory: tempDirectory.path
        )
        try projectRepository.save(project)

        // エージェントを作成
        let agent = Agent(
            id: testAgentId,
            name: "Notification Test Agent",
            role: "Test agent",
            hierarchyType: .worker,
            systemPrompt: "Test prompt"
        )
        try agentRepository.save(agent)

        // プロジェクトにエージェントを割り当て
        _ = try projectAgentAssignmentRepository.assign(
            projectId: testProjectId,
            agentId: testAgentId
        )

        // 認証情報を作成
        let credential = AgentCredential(
            agentId: testAgentId,
            rawPasskey: "test_passkey_notif"
        )
        try agentCredentialRepository.save(credential)

        // Session Spawn Architecture: Create in_progress task for task session authentication
        let task = Domain.Task(
            id: TaskID(value: "tsk_test_notif"),
            projectId: testProjectId,
            title: "Test Task for Notification",
            status: .inProgress,
            assigneeId: testAgentId
        )
        try taskRepository.save(task)

        // 認証してセッショントークンを取得
        let result = try mcpServer.executeTool(
            name: "authenticate",
            arguments: [
                "agent_id": testAgentId.value,
                "passkey": "test_passkey_notif",
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        if let dict = result as? [String: Any],
           let token = dict["session_token"] as? String {
            sessionToken = token
        }
    }

    // MARK: - get_notifications Tests

    func testGetNotificationsReturnsEmptyWhenNoNotifications() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        let session = try agentSessionRepository.findByToken(token)!
        let result = try mcpServer.executeTool(
            name: "get_notifications",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        XCTAssertEqual(dict["success"] as? Bool, true)
        XCTAssertEqual(dict["count"] as? Int, 0)
        XCTAssertEqual((dict["notifications"] as? [[String: Any]])?.count, 0)
    }

    func testGetNotificationsReturnsUnreadNotifications() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        // 未読通知を作成
        let notification = AgentNotification.createStatusChangeNotification(
            targetAgentId: testAgentId,
            targetProjectId: testProjectId,
            taskId: TaskID(value: "tsk_test"),
            newStatus: "blocked"
        )
        try notificationRepository.save(notification)

        let session = try agentSessionRepository.findByToken(token)!
        let result = try mcpServer.executeTool(
            name: "get_notifications",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        XCTAssertEqual(dict["success"] as? Bool, true)
        XCTAssertEqual(dict["count"] as? Int, 1)

        let notifications = dict["notifications"] as? [[String: Any]]
        XCTAssertEqual(notifications?.count, 1)
        XCTAssertEqual(notifications?.first?["type"] as? String, "status_change")
        XCTAssertEqual(notifications?.first?["action"] as? String, "blocked")
    }

    func testGetNotificationsMarksAsReadByDefault() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        // 未読通知を作成
        let notification = AgentNotification.createStatusChangeNotification(
            targetAgentId: testAgentId,
            targetProjectId: testProjectId,
            taskId: TaskID(value: "tsk_test"),
            newStatus: "blocked"
        )
        try notificationRepository.save(notification)

        let session = try agentSessionRepository.findByToken(token)!

        // 最初の取得
        _ = try mcpServer.executeTool(
            name: "get_notifications",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        // 2回目の取得 - 既読になっているはず
        let result = try mcpServer.executeTool(
            name: "get_notifications",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        XCTAssertEqual(dict["count"] as? Int, 0, "Notifications should be marked as read")
    }

    func testGetNotificationsWithMarkAsReadFalse() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        // 未読通知を作成
        let notification = AgentNotification.createStatusChangeNotification(
            targetAgentId: testAgentId,
            targetProjectId: testProjectId,
            taskId: TaskID(value: "tsk_test"),
            newStatus: "blocked"
        )
        try notificationRepository.save(notification)

        let session = try agentSessionRepository.findByToken(token)!

        // mark_as_read=false で取得
        _ = try mcpServer.executeTool(
            name: "get_notifications",
            arguments: ["session_token": token, "mark_as_read": false],
            caller: .worker(agentId: testAgentId, session: session)
        )

        // 2回目の取得 - まだ未読のはず
        let result = try mcpServer.executeTool(
            name: "get_notifications",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        XCTAssertEqual(dict["count"] as? Int, 1, "Notifications should still be unread")
    }

    func testGetNotificationsOnlyReturnsForCurrentAgentAndProject() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        // 別のエージェント宛の通知
        let otherAgentNotification = AgentNotification.createStatusChangeNotification(
            targetAgentId: AgentID(value: "agt_other"),
            targetProjectId: testProjectId,
            taskId: TaskID(value: "tsk_test"),
            newStatus: "blocked"
        )
        try notificationRepository.save(otherAgentNotification)

        // 別のプロジェクト宛の通知
        let otherProjectNotification = AgentNotification.createStatusChangeNotification(
            targetAgentId: testAgentId,
            targetProjectId: ProjectID(value: "prj_other"),
            taskId: TaskID(value: "tsk_test"),
            newStatus: "blocked"
        )
        try notificationRepository.save(otherProjectNotification)

        // 正しい宛先の通知
        let correctNotification = AgentNotification.createStatusChangeNotification(
            targetAgentId: testAgentId,
            targetProjectId: testProjectId,
            taskId: TaskID(value: "tsk_test"),
            newStatus: "done"
        )
        try notificationRepository.save(correctNotification)

        let session = try agentSessionRepository.findByToken(token)!
        let result = try mcpServer.executeTool(
            name: "get_notifications",
            arguments: ["session_token": token],
            caller: .worker(agentId: testAgentId, session: session)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        XCTAssertEqual(dict["count"] as? Int, 1, "Should only return notification for current agent and project")

        let notifications = dict["notifications"] as? [[String: Any]]
        XCTAssertEqual(notifications?.first?["action"] as? String, "done")
    }
}

// MARK: - send_message Tool Tests
// 参照: docs/design/SEND_MESSAGE_FROM_TASK_SESSION.md

/// send_message ツール定義テスト
final class SendMessageToolDefinitionTests: XCTestCase {

    /// send_message ツールが定義されていることを確認
    func testSendMessageToolDefinition() {
        let tool = ToolDefinitions.sendMessage

        XCTAssertEqual(tool["name"] as? String, "send_message")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"), "send_message should require session_token")
            XCTAssertTrue(required.contains("target_agent_id"), "send_message should require target_agent_id")
            XCTAssertTrue(required.contains("content"), "send_message should require content")
        }
    }

    /// send_message ツールが全ツール一覧に含まれることを確認
    func testSendMessageToolInAllTools() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(toolNames.contains("send_message"), "send_message should be in all tools")
    }

    /// send_message ツールにrelated_task_idパラメータがあることを確認
    func testSendMessageToolHasRelatedTaskIdParameter() {
        let tool = ToolDefinitions.sendMessage

        if let schema = tool["inputSchema"] as? [String: Any],
           let properties = schema["properties"] as? [String: Any] {
            XCTAssertNotNil(properties["related_task_id"], "send_message should have related_task_id parameter")
        } else {
            XCTFail("Could not find properties in inputSchema")
        }
    }

    /// send_message ツールの説明に非同期である旨が記載されていることを確認
    func testSendMessageToolDescriptionMentionsAsync() {
        let tool = ToolDefinitions.sendMessage
        let description = tool["description"] as? String ?? ""

        XCTAssertTrue(description.contains("非同期"), "Description should mention async nature")
    }
}

/// send_message ツール認可テスト
final class SendMessageToolAuthorizationTests: XCTestCase {

    /// send_message ツールが authenticated 権限であることを確認
    func testSendMessageToolPermission() {
        XCTAssertEqual(ToolAuthorization.permissions["send_message"], .authenticated)
    }

    /// send_message がタスクセッションで使用可能なことを確認
    func testSendMessageAllowedInTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "agent-001"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerTaskCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "send_message", caller: workerTaskCaller))
    }

    /// send_message がチャットセッションでも使用可能なことを確認
    func testSendMessageAllowedInChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "agent-001"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let workerChatCaller = CallerType.worker(agentId: chatSession.agentId, session: chatSession)

        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "send_message", caller: workerChatCaller))
    }

    /// send_message が未認証では拒否されることを確認
    func testSendMessageRejectsUnauthenticated() {
        XCTAssertThrowsError(try ToolAuthorization.authorize(tool: "send_message", caller: .unauthenticated)) { error in
            guard case ToolAuthorizationError.authenticationRequired = error else {
                XCTFail("Expected authenticationRequired error, got \(error)")
                return
            }
        }
    }

    /// send_message がManagerでも使用可能なことを確認
    func testSendMessageAllowedForManager() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "manager-001"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let managerCaller = CallerType.manager(agentId: taskSession.agentId, session: taskSession)

        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "send_message", caller: managerCaller))
    }
}

/// send_message 統合テスト
final class SendMessageIntegrationTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var chatRepository: ChatFileRepository!
    var agentRepository: AgentRepository!
    var projectRepository: ProjectRepository!
    var agentCredentialRepository: AgentCredentialRepository!
    var agentSessionRepository: AgentSessionRepository!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepository!
    var taskRepository: TaskRepository!

    let senderAgentId = AgentID(value: "agt_sender")
    let receiverAgentId = AgentID(value: "agt_receiver")
    let testProjectId = ProjectID(value: "prj_send_msg_test")
    var sessionToken: String?
    var tempDirectory: URL!

    override func setUpWithError() throws {
        // Create temp directory for chat files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("send_message_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Setup database
        let dbPath = tempDirectory.appendingPathComponent("test.db").path
        db = try DatabaseSetup.createDatabase(at: dbPath)

        // Setup repositories
        agentRepository = AgentRepository(database: db)
        projectRepository = ProjectRepository(database: db)
        agentCredentialRepository = AgentCredentialRepository(database: db)
        agentSessionRepository = AgentSessionRepository(database: db)
        projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: db)
        taskRepository = TaskRepository(database: db)

        // Setup chat repository with directory manager
        let directoryManager = ProjectDirectoryManager()
        chatRepository = ChatFileRepository(
            directoryManager: directoryManager,
            projectRepository: projectRepository
        )

        // Setup MCP server
        mcpServer = MCPServer(database: db)

        try setupTestData()
    }

    override func tearDownWithError() throws {
        // Clean up temp directory
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        db = nil
        mcpServer = nil
        sessionToken = nil
    }

    private func setupTestData() throws {
        // Create project with working directory
        let project = Project(
            id: testProjectId,
            name: "SendMessage Test Project",
            description: "Project for send_message testing",
            workingDirectory: tempDirectory.path
        )
        try projectRepository.save(project)

        // Create sender agent (Human type to test Human-to-AI messaging without conversation)
        let senderAgent = Agent(
            id: senderAgentId,
            name: "Sender Agent",
            role: "Test sender",
            type: .human,  // Human type: can send messages without conversation
            hierarchyType: .worker,
            systemPrompt: "Test prompt"
        )
        try agentRepository.save(senderAgent)

        // Create receiver agent
        let receiverAgent = Agent(
            id: receiverAgentId,
            name: "Receiver Agent",
            role: "Test receiver",
            hierarchyType: .worker,
            systemPrompt: "Test prompt"
        )
        try agentRepository.save(receiverAgent)

        // Assign both to project
        _ = try projectAgentAssignmentRepository.assign(projectId: testProjectId, agentId: senderAgentId)
        _ = try projectAgentAssignmentRepository.assign(projectId: testProjectId, agentId: receiverAgentId)

        // Create credential for sender
        let credential = AgentCredential(agentId: senderAgentId, rawPasskey: "test_passkey_sender")
        try agentCredentialRepository.save(credential)

        // Session Spawn Architecture: Create in_progress task for sender to enable task session creation
        let task = Domain.Task(
            id: TaskID(value: "tsk_test_sender"),
            projectId: testProjectId,
            title: "Test Task for SendMessage",
            status: .inProgress,
            assigneeId: senderAgentId
        )
        try taskRepository.save(task)

        // Authenticate sender (task session)
        let result = try mcpServer.executeTool(
            name: "authenticate",
            arguments: [
                "agent_id": senderAgentId.value,
                "passkey": "test_passkey_sender",
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )

        if let dict = result as? [String: Any],
           let token = dict["session_token"] as? String {
            sessionToken = token
        }
    }

    // MARK: - Success Cases

    /// 正常系: メッセージ送信成功
    func testSendMessageSuccess() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        let session = try agentSessionRepository.findByToken(token)!
        let result = try mcpServer.executeTool(
            name: "send_message",
            arguments: [
                "session_token": token,
                "target_agent_id": receiverAgentId.value,
                "content": "テストメッセージ"
            ],
            caller: .worker(agentId: senderAgentId, session: session)
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        XCTAssertEqual(dict["success"] as? Bool, true)
        XCTAssertNotNil(dict["message_id"])
        XCTAssertEqual(dict["target_agent_id"] as? String, receiverAgentId.value)
    }

    /// 正常系: 送信者のファイルにreceiverIdが含まれる
    func testSendMessageSavesToSenderFile() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        let session = try agentSessionRepository.findByToken(token)!
        _ = try mcpServer.executeTool(
            name: "send_message",
            arguments: [
                "session_token": token,
                "target_agent_id": receiverAgentId.value,
                "content": "テストメッセージ"
            ],
            caller: .worker(agentId: senderAgentId, session: session)
        )

        let messages = try chatRepository.findMessages(projectId: testProjectId, agentId: senderAgentId)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].senderId, senderAgentId)
        XCTAssertEqual(messages[0].receiverId, receiverAgentId)
        XCTAssertEqual(messages[0].content, "テストメッセージ")
    }

    /// 正常系: 受信者のファイルにreceiverIdが含まれない
    func testSendMessageSavesToReceiverFile() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        let session = try agentSessionRepository.findByToken(token)!
        _ = try mcpServer.executeTool(
            name: "send_message",
            arguments: [
                "session_token": token,
                "target_agent_id": receiverAgentId.value,
                "content": "テストメッセージ"
            ],
            caller: .worker(agentId: senderAgentId, session: session)
        )

        let messages = try chatRepository.findMessages(projectId: testProjectId, agentId: receiverAgentId)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].senderId, senderAgentId)
        XCTAssertNil(messages[0].receiverId)  // 受信者ファイルにはreceiverIdなし
        XCTAssertEqual(messages[0].content, "テストメッセージ")
    }

    /// 正常系: related_task_idが保存される
    func testSendMessageWithRelatedTaskId() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        let taskId = "task-123"
        let session = try agentSessionRepository.findByToken(token)!
        _ = try mcpServer.executeTool(
            name: "send_message",
            arguments: [
                "session_token": token,
                "target_agent_id": receiverAgentId.value,
                "content": "タスク関連メッセージ",
                "related_task_id": taskId
            ],
            caller: .worker(agentId: senderAgentId, session: session)
        )

        let messages = try chatRepository.findMessages(projectId: testProjectId, agentId: senderAgentId)
        XCTAssertEqual(messages[0].relatedTaskId?.value, taskId)
    }

    // MARK: - Error Cases

    /// 異常系: 自分自身への送信は拒否
    func testSendMessageRejectsSelfMessage() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        let session = try agentSessionRepository.findByToken(token)!

        XCTAssertThrowsError(try mcpServer.executeTool(
            name: "send_message",
            arguments: [
                "session_token": token,
                "target_agent_id": senderAgentId.value,  // 自分自身
                "content": "自分へ"
            ],
            caller: .worker(agentId: senderAgentId, session: session)
        )) { error in
            let errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(errorMessage.lowercased().contains("self") || errorMessage.contains("自分"))
        }
    }

    /// 異常系: プロジェクト外エージェントへの送信は拒否
    func testSendMessageRejectsOutsideProjectAgent() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        // Create agent not in project
        let outsideAgentId = AgentID(value: "agt_outside")
        let outsideAgent = Agent(
            id: outsideAgentId,
            name: "Outside Agent",
            role: "Outside",
            hierarchyType: .worker,
            systemPrompt: "Test"
        )
        try agentRepository.save(outsideAgent)
        // NOT assigned to project

        let session = try agentSessionRepository.findByToken(token)!

        XCTAssertThrowsError(try mcpServer.executeTool(
            name: "send_message",
            arguments: [
                "session_token": token,
                "target_agent_id": outsideAgentId.value,
                "content": "外部エージェントへ"
            ],
            caller: .worker(agentId: senderAgentId, session: session)
        )) { error in
            let errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(errorMessage.lowercased().contains("project") || errorMessage.contains("プロジェクト"))
        }
    }

    /// 異常系: 存在しないエージェントへの送信は拒否
    func testSendMessageRejectsNonExistentAgent() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        let session = try agentSessionRepository.findByToken(token)!

        XCTAssertThrowsError(try mcpServer.executeTool(
            name: "send_message",
            arguments: [
                "session_token": token,
                "target_agent_id": "non-existent-agent",
                "content": "存在しないエージェントへ"
            ],
            caller: .worker(agentId: senderAgentId, session: session)
        )) { error in
            let errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(errorMessage.lowercased().contains("not found") || errorMessage.contains("見つかり"))
        }
    }

    /// 異常系: コンテンツ長超過は拒否
    func testSendMessageRejectsContentTooLong() throws {
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        let longContent = String(repeating: "あ", count: 4001)  // 4000文字超過
        let session = try agentSessionRepository.findByToken(token)!

        XCTAssertThrowsError(try mcpServer.executeTool(
            name: "send_message",
            arguments: [
                "session_token": token,
                "target_agent_id": receiverAgentId.value,
                "content": longContent
            ],
            caller: .worker(agentId: senderAgentId, session: session)
        )) { error in
            let errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(errorMessage.contains("4000") || errorMessage.lowercased().contains("long") || errorMessage.contains("超過"))
        }
    }

    // MARK: - AI-to-AI Conversation Constraint Tests
    // 参照: docs/design/AI_TO_AI_CONVERSATION.md - send_message 制約

    /// 異常系: AI間メッセージで会話なしは拒否
    /// AIエージェント同士のメッセージ送信には、事前にstart_conversationでの会話開始が必要
    func testSendMessageRejectsAIToAIWithoutConversation() throws {
        // Create AI sender agent (different from the Human sender in setup)
        let aiSenderId = AgentID(value: "agt_ai_sender")
        let aiSender = Agent(
            id: aiSenderId,
            name: "AI Sender",
            role: "Test AI sender",
            type: .ai,  // AI type
            hierarchyType: .worker,
            systemPrompt: "Test prompt"
        )
        try agentRepository.save(aiSender)
        _ = try projectAgentAssignmentRepository.assign(projectId: testProjectId, agentId: aiSenderId)

        // Create credential and authenticate AI sender
        let credential = AgentCredential(agentId: aiSenderId, rawPasskey: "ai_sender_passkey")
        try agentCredentialRepository.save(credential)

        // Session Spawn Architecture: Create in_progress task for AI sender
        let aiTask = Domain.Task(
            id: TaskID(value: "tsk_ai_sender"),
            projectId: testProjectId,
            title: "Test Task for AI Sender",
            status: .inProgress,
            assigneeId: aiSenderId
        )
        try taskRepository.save(aiTask)

        let authResult = try mcpServer.executeTool(
            name: "authenticate",
            arguments: [
                "agent_id": aiSenderId.value,
                "passkey": "ai_sender_passkey",
                "project_id": testProjectId.value
            ],
            caller: .unauthenticated
        )
        guard let dict = authResult as? [String: Any],
              let aiToken = dict["session_token"] as? String else {
            XCTFail("AI sender authentication failed")
            return
        }

        let aiSession = try agentSessionRepository.findByToken(aiToken)!

        // Attempt to send message from AI to AI (receiver is also AI from setup)
        // This should fail because there's no active conversation
        XCTAssertThrowsError(try mcpServer.executeTool(
            name: "send_message",
            arguments: [
                "session_token": aiToken,
                "target_agent_id": receiverAgentId.value,  // AI receiver
                "content": "AIからAIへのメッセージ"
            ],
            caller: .worker(agentId: aiSenderId, session: aiSession)
        )) { error in
            let errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // エラーメッセージに会話が必要であることが含まれることを確認
            XCTAssertTrue(
                errorMessage.contains("start_conversation") ||
                errorMessage.contains("会話") ||
                errorMessage.contains("conversation"),
                "Error message should mention conversation requirement: \(errorMessage)"
            )
        }
    }

    /// 正常系: Human-to-AIメッセージは会話なしでもOK
    /// Human-AIのやりとりには会話開始は不要
    func testSendMessageAllowsHumanToAIWithoutConversation() throws {
        // sender is Human (from setup), receiver is AI
        guard let token = sessionToken else {
            XCTFail("Session token should be available")
            return
        }

        let session = try agentSessionRepository.findByToken(token)!

        // Human to AI should work without conversation
        let result = try mcpServer.executeTool(
            name: "send_message",
            arguments: [
                "session_token": token,
                "target_agent_id": receiverAgentId.value,  // AI receiver
                "content": "HumanからAIへのメッセージ"
            ],
            caller: .worker(agentId: senderAgentId, session: session)  // Human sender
        )

        guard let dict = result as? [String: Any] else {
            XCTFail("Result should be a dictionary")
            return
        }

        XCTAssertEqual(dict["success"] as? Bool, true)
        XCTAssertNotNil(dict["message_id"])
    }
}
