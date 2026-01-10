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
    /// Phase 5: 権限ベース認可システム導入により変更
    func testToolCount() {
        let tools = ToolDefinitions.all()

        // Phase 5 権限ベース認可システム版ツール: 22個
        // Unauthenticated: 1 (authenticate)
        // Coordinator-only: 6 (health_check, list_managed_agents, list_active_projects_with_agents, get_agent_action, register_execution_log_file, invalidate_session)
        // Manager-only: 4 (list_subordinates, get_subordinate_profile, create_task, assign_task)
        // Worker-only: 1 (report_completed)
        // Authenticated (Manager + Worker): 10 (report_model, get_my_profile, get_my_task, get_next_action, update_task_status, get_project, list_tasks, get_task, report_execution_start, report_execution_complete)
        // 注: list_agents, get_agent_profile, list_projects は削除済み
        // 注: get_my_tasks, get_pending_tasks はget_my_taskに統合済み
        // 注: save_context, get_task_context, create_handoff, get_pending_handoffs, accept_handoff は将来追加予定
        XCTAssertEqual(tools.count, 22, "Should have 22 tools defined (Phase 5 authorization system)")
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
        XCTAssertEqual(ToolAuthorization.permissions["create_task"], .managerOnly)
        XCTAssertEqual(ToolAuthorization.permissions["assign_task"], .managerOnly)
    }

    /// Worker専用ツールの権限確認
    func testWorkerOnlyToolPermissions() {
        XCTAssertEqual(ToolAuthorization.permissions["report_completed"], .workerOnly)
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

    // MARK: - Tools Helper Tests

    /// 特定権限のツール一覧取得
    func testToolsForPermission() {
        let coordinatorTools = ToolAuthorization.tools(for: .coordinatorOnly)
        XCTAssertTrue(coordinatorTools.contains("health_check"))
        XCTAssertTrue(coordinatorTools.contains("get_agent_action"))

        let managerTools = ToolAuthorization.tools(for: .managerOnly)
        XCTAssertTrue(managerTools.contains("list_subordinates"))
        XCTAssertTrue(managerTools.contains("create_task"))
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
    }
}
