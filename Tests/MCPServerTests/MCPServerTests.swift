// Tests/MCPServerTests/MCPServerTests.swift
// MCP_DESIGN.md仕様に基づくMCPServer層のテスト

import XCTest
@testable import MCPServer
@testable import Domain

/// MCP_DESIGN.md仕様に基づくMCPServerテスト
final class MCPServerTests: XCTestCase {

    // MARK: - ToolDefinitions Tests

    /// MCP_DESIGN.md: 全ツールが定義されていることを確認
    func testToolDefinitionsContainsAllTools() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        // PRD定義ツール（MCP_DESIGN.md）
        // エージェント・セッション管理
        XCTAssertTrue(toolNames.contains("get_my_profile"), "get_my_profile should be defined per MCP_DESIGN.md")
        // list_agents - PRD仕様にあるが未実装（後で実装が必要）
        // get_agent - PRD仕様にあるが未実装（後で実装が必要）
        XCTAssertTrue(toolNames.contains("start_session"), "start_session should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("end_session"), "end_session should be defined per MCP_DESIGN.md")
        // get_my_sessions - PRD仕様にあるが未実装（後で実装が必要）

        // プロジェクト・タスク管理
        // list_projects - PRD仕様にあるが未実装（後で実装が必要）
        // get_project - PRD仕様にあるが未実装（後で実装が必要）
        XCTAssertTrue(toolNames.contains("list_tasks"), "list_tasks should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("get_task"), "get_task should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("get_my_tasks"), "get_my_tasks should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("update_task_status"), "update_task_status should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("assign_task"), "assign_task should be defined per MCP_DESIGN.md")

        // コンテキスト・ハンドオフ
        // add_context → save_context として実装
        XCTAssertTrue(toolNames.contains("save_context"), "save_context should be defined (add_context in MCP_DESIGN.md)")
        // get_context → get_task_context として実装
        XCTAssertTrue(toolNames.contains("get_task_context"), "get_task_context should be defined (get_context in MCP_DESIGN.md)")
        XCTAssertTrue(toolNames.contains("create_handoff"), "create_handoff should be defined per MCP_DESIGN.md")
        XCTAssertTrue(toolNames.contains("get_pending_handoffs"), "get_pending_handoffs should be defined per MCP_DESIGN.md")
        // acknowledge_handoff → accept_handoff として実装
        XCTAssertTrue(toolNames.contains("accept_handoff"), "accept_handoff should be defined (acknowledge_handoff in MCP_DESIGN.md)")
    }

    /// MCP_DESIGN.md仕様にある未実装ツールを記録（将来の実装タスク）
    func testMissingToolsFromPRD() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        // MCP_DESIGN.mdに定義されているが未実装のツール
        let missingTools = [
            "list_agents",     // プロジェクトのエージェント一覧
            "get_agent",       // 特定エージェントの詳細
            "get_my_sessions", // 自分の過去セッション一覧
            "list_projects",   // プロジェクト一覧取得
            "get_project"      // プロジェクト詳細取得
        ]

        for tool in missingTools {
            XCTAssertFalse(toolNames.contains(tool), "\(tool) is defined in MCP_DESIGN.md but not yet implemented - needs implementation")
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

    /// get_my_profileツール定義
    func testGetMyProfileToolDefinition() {
        let tool = ToolDefinitions.getMyProfile

        XCTAssertEqual(tool["name"] as? String, "get_my_profile")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.isEmpty, "get_my_profile should have no required parameters")
        }
    }

    /// start_sessionツール定義
    func testStartSessionToolDefinition() {
        let tool = ToolDefinitions.startSession

        XCTAssertEqual(tool["name"] as? String, "start_session")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            XCTAssertEqual(schema["type"] as? String, "object")
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.isEmpty, "start_session should have no required parameters")
        }
    }

    /// end_sessionツール定義
    func testEndSessionToolDefinition() {
        let tool = ToolDefinitions.endSession

        XCTAssertEqual(tool["name"] as? String, "end_session")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any],
           let properties = schema["properties"] as? [String: Any] {
            // status: completed | abandoned
            XCTAssertNotNil(properties["status"], "end_session should have status property")
            if let statusProp = properties["status"] as? [String: Any],
               let enumValues = statusProp["enum"] as? [String] {
                XCTAssertTrue(enumValues.contains("completed"))
                XCTAssertTrue(enumValues.contains("abandoned"))
            }
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

    /// get_my_tasksツール定義
    func testGetMyTasksToolDefinition() {
        let tool = ToolDefinitions.getMyTasks

        XCTAssertEqual(tool["name"] as? String, "get_my_tasks")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.isEmpty, "get_my_tasks should have no required parameters")
        }
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

    // MARK: - Additional Tool Tests

    /// create_taskツール定義
    func testCreateTaskToolDefinition() {
        let tool = ToolDefinitions.createTask

        XCTAssertEqual(tool["name"] as? String, "create_task")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any],
           let properties = schema["properties"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("title"), "create_task should require title")

            XCTAssertNotNil(properties["title"])
            XCTAssertNotNil(properties["description"])
            XCTAssertNotNil(properties["priority"])
            XCTAssertNotNil(properties["assignee_id"])
        }
    }

    /// update_taskツール定義
    func testUpdateTaskToolDefinition() {
        let tool = ToolDefinitions.updateTask

        XCTAssertEqual(tool["name"] as? String, "update_task")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any],
           let properties = schema["properties"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("task_id"), "update_task should require task_id")

            XCTAssertNotNil(properties["title"])
            XCTAssertNotNil(properties["description"])
            XCTAssertNotNil(properties["priority"])
            XCTAssertNotNil(properties["estimated_minutes"])
            XCTAssertNotNil(properties["actual_minutes"])
        }
    }

    // MARK: - Priority Enum Tests

    /// ToolDefinitionsのpriority enumがPRD仕様と一致することを確認
    /// PRD仕様: low, medium, high, urgent
    func testPriorityEnumInToolDefinitions() {
        let tool = ToolDefinitions.createTask

        if let schema = tool["inputSchema"] as? [String: Any],
           let properties = schema["properties"] as? [String: Any],
           let priorityProp = properties["priority"] as? [String: Any],
           let enumValues = priorityProp["enum"] as? [String] {
            // PRD仕様通りのenum値を確認
            XCTAssertTrue(enumValues.contains("urgent"), "Should contain 'urgent' per PRD")
            XCTAssertTrue(enumValues.contains("high"), "Should contain 'high' per PRD")
            XCTAssertTrue(enumValues.contains("medium"), "Should contain 'medium' per PRD")
            XCTAssertTrue(enumValues.contains("low"), "Should contain 'low' per PRD")
            XCTAssertFalse(enumValues.contains("critical"), "Should not contain 'critical' - use 'urgent' per PRD")
        }
    }

    // MARK: - Tool Count Test

    /// 定義されているツール数を確認
    func testToolCount() {
        let tools = ToolDefinitions.all()

        // 現在実装されているツール: 15個
        // Profile: 1 (get_my_profile)
        // Session: 2 (start_session, end_session)
        // Tasks: 7 (list_tasks, get_task, get_my_tasks, create_task, update_task, update_task_status, assign_task)
        // Context: 2 (save_context, get_task_context)
        // Handoff: 3 (create_handoff, accept_handoff, get_pending_handoffs)
        XCTAssertEqual(tools.count, 15, "Should have 15 tools defined")
    }
}

// MARK: - PRD Compliance Summary Tests

/// PRD仕様との適合性サマリーテスト
final class MCPPRDComplianceTests: XCTestCase {

    /// MCP_DESIGN.md仕様との適合性サマリー
    func testPRDComplianceSummary() {
        let tools = ToolDefinitions.all()
        let toolNames = Set(tools.compactMap { $0["name"] as? String })

        // MCP_DESIGN.mdで定義されているツール
        let prdTools = [
            // エージェント・セッション管理
            "get_my_profile",
            "list_agents",      // 未実装
            "get_agent",        // 未実装
            "start_session",
            "end_session",
            "get_my_sessions",  // 未実装

            // プロジェクト・タスク管理
            "list_projects",    // 未実装
            "get_project",      // 未実装
            "list_tasks",
            "get_task",
            "get_my_tasks",
            "update_task_status",
            "assign_task",

            // コンテキスト・ハンドオフ
            // add_context → save_context
            // get_context → get_task_context
            "create_handoff",
            "get_pending_handoffs",
            // acknowledge_handoff → accept_handoff
        ]

        // 実装済みのPRDツール（名前が異なるものを含む）
        let implementedPRDTools = [
            "get_my_profile",
            "start_session",
            "end_session",
            "list_tasks",
            "get_task",
            "get_my_tasks",
            "update_task_status",
            "assign_task",
            "save_context",      // add_context
            "get_task_context",  // get_context
            "create_handoff",
            "get_pending_handoffs",
            "accept_handoff"     // acknowledge_handoff
        ]

        var implementedCount = 0
        for tool in implementedPRDTools {
            if toolNames.contains(tool) {
                implementedCount += 1
            }
        }

        // 13個のPRDツールが実装されている（名前変更を含む）
        XCTAssertEqual(implementedCount, 13, "Should have 13 PRD-defined tools implemented")

        // 未実装のPRDツール
        let missingTools = ["list_agents", "get_agent", "get_my_sessions", "list_projects", "get_project"]
        for tool in missingTools {
            XCTAssertFalse(toolNames.contains(tool), "\(tool) is in PRD but not implemented")
        }
    }
}
