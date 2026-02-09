// Tests/MCPServerTests/HelpToolTests.swift
// HelpToolTests - extracted from MCPServerTests.swift

import XCTest
import GRDB
@testable import Domain
@testable import UseCase
@testable import Infrastructure

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
        XCTAssertFalse(toolNames.contains("send_message"))

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
        XCTAssertTrue(toolNames.contains("send_message"))
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
