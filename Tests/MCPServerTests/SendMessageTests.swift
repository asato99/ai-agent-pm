// Tests/MCPServerTests/SendMessageTests.swift
// SendMessageToolDefinitionTests, SendMessageToolAuthorizationTests, SendMessageIntegrationTests
// - extracted from MCPServerTests.swift

import XCTest
import GRDB
@testable import Domain
@testable import UseCase
@testable import Infrastructure

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
/// 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
final class SendMessageToolAuthorizationTests: XCTestCase {

    /// send_message ツールが chatOnly 権限であることを確認
    func testSendMessageToolPermission() {
        XCTAssertEqual(ToolAuthorization.permissions["send_message"], .chatOnly)
    }

    /// send_message がタスクセッションでは拒否されることを確認
    func testSendMessageRejectedInTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "agent-001"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let workerTaskCaller = CallerType.worker(agentId: taskSession.agentId, session: taskSession)

        XCTAssertThrowsError(try ToolAuthorization.authorize(tool: "send_message", caller: workerTaskCaller)) { error in
            guard case ToolAuthorizationError.chatSessionRequired(let tool, let currentPurpose) = error else {
                XCTFail("Expected chatSessionRequired error, got \(error)")
                return
            }
            XCTAssertEqual(tool, "send_message")
            XCTAssertEqual(currentPurpose, .task)
        }
    }

    /// send_message がチャットセッションで使用可能なことを確認
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

    /// send_message がManagerのチャットセッションで使用可能なことを確認
    func testSendMessageAllowedForManagerChatSession() {
        let chatSession = AgentSession(
            agentId: AgentID(value: "manager-001"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .chat
        )
        let managerCaller = CallerType.manager(agentId: chatSession.agentId, session: chatSession)

        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "send_message", caller: managerCaller))
    }

    /// send_message がManagerのタスクセッションでは拒否されることを確認
    func testSendMessageRejectedForManagerTaskSession() {
        let taskSession = AgentSession(
            agentId: AgentID(value: "manager-001"),
            projectId: ProjectID(value: "proj-001"),
            purpose: .task
        )
        let managerCaller = CallerType.manager(agentId: taskSession.agentId, session: taskSession)

        XCTAssertThrowsError(try ToolAuthorization.authorize(tool: "send_message", caller: managerCaller)) { error in
            guard case ToolAuthorizationError.chatSessionRequired(let tool, let currentPurpose) = error else {
                XCTFail("Expected chatSessionRequired error, got \(error)")
                return
            }
            XCTAssertEqual(tool, "send_message")
            XCTAssertEqual(currentPurpose, .task)
        }
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
