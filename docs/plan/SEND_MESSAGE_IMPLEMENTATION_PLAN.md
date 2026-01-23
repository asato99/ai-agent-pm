# 実装プラン: send_message ツール

## 概要

タスクセッションから他エージェントにメッセージを送信する `send_message` ツールの実装プラン。
ユニットテストファーストで進める。

---

## 変更対象ファイル

| ファイル | 変更内容 |
|----------|----------|
| `Tests/MCPServerTests/MCPServerTests.swift` | ユニットテスト追加 |
| `Sources/MCPServer/Tools/ToolDefinitions.swift` | ツール定義追加 |
| `Sources/MCPServer/Authorization/ToolAuthorization.swift` | 権限定義追加 |
| `Sources/MCPServer/MCPServer.swift` | ハンドラー実装 |

---

## Phase 1: ユニットテスト作成（RED）

### 1.1 ツール定義テスト

```swift
// MARK: - send_message Tool Tests

final class SendMessageToolTests: XCTestCase {

    // MARK: - Tool Definition Tests

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
}
```

### 1.2 権限テスト

```swift
// MARK: - send_message Authorization Tests

extension ToolAuthorizationTests {

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
}
```

### 1.3 統合テスト（MCPServer）

```swift
// MARK: - send_message Integration Tests

final class SendMessageIntegrationTests: XCTestCase {

    var db: DatabaseQueue!
    var mcpServer: MCPServer!
    var chatRepository: ChatFileRepository!
    var agentRepository: AgentRepositoryProtocol!
    var projectRepository: ProjectRepositoryProtocol!
    var agentSessionRepository: AgentSessionRepositoryProtocol!
    var projectAgentAssignmentRepository: ProjectAgentAssignmentRepositoryProtocol!

    var senderAgentId: AgentID!
    var receiverAgentId: AgentID!
    var testProjectId: ProjectID!
    var sessionToken: String!
    var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // DB setup
        db = try DatabaseQueue()
        try AppDatabase.migrator.migrate(db)

        // Repository setup
        // ... (略: 既存パターンに従う)

        // Test data setup
        try setupTestData()
    }

    override func tearDownWithError() throws {
        // Clean up temp directory
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func setupTestData() throws {
        // Create temp directory for chat files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("send_message_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Create project with working directory
        testProjectId = ProjectID(value: "prj-test")
        let project = Project(
            id: testProjectId,
            name: "Test Project",
            workingDirectory: tempDirectory.path
        )
        try projectRepository.save(project)

        // Create sender agent
        senderAgentId = AgentID(value: "sender-agent")
        let senderAgent = Agent(id: senderAgentId, name: "Sender", agentType: .worker)
        try agentRepository.save(senderAgent)

        // Create receiver agent
        receiverAgentId = AgentID(value: "receiver-agent")
        let receiverAgent = Agent(id: receiverAgentId, name: "Receiver", agentType: .worker)
        try agentRepository.save(receiverAgent)

        // Assign both to project
        try projectAgentAssignmentRepository.assign(agentId: senderAgentId, to: testProjectId)
        try projectAgentAssignmentRepository.assign(agentId: receiverAgentId, to: testProjectId)

        // Create session for sender (task session)
        let session = AgentSession(
            agentId: senderAgentId,
            projectId: testProjectId,
            purpose: .task
        )
        sessionToken = try agentSessionRepository.save(session)
    }

    // MARK: - Success Cases

    /// 正常系: メッセージ送信成功
    func testSendMessageSuccess() async throws {
        let result = try await mcpServer.callTool(
            name: "send_message",
            arguments: [
                "session_token": sessionToken!,
                "target_agent_id": receiverAgentId.value,
                "content": "テストメッセージ"
            ]
        )

        // Verify response
        XCTAssertTrue(result["success"] as? Bool ?? false)
        XCTAssertNotNil(result["message_id"])
        XCTAssertEqual(result["target_agent_id"] as? String, receiverAgentId.value)
    }

    /// 正常系: 送信者のファイルにreceiverIdが含まれる
    func testSendMessageSavesToSenderFile() async throws {
        _ = try await mcpServer.callTool(
            name: "send_message",
            arguments: [
                "session_token": sessionToken!,
                "target_agent_id": receiverAgentId.value,
                "content": "テストメッセージ"
            ]
        )

        let messages = try chatRepository.findMessages(projectId: testProjectId, agentId: senderAgentId)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].senderId, senderAgentId)
        XCTAssertEqual(messages[0].receiverId, receiverAgentId)
        XCTAssertEqual(messages[0].content, "テストメッセージ")
    }

    /// 正常系: 受信者のファイルにreceiverIdが含まれない
    func testSendMessageSavesToReceiverFile() async throws {
        _ = try await mcpServer.callTool(
            name: "send_message",
            arguments: [
                "session_token": sessionToken!,
                "target_agent_id": receiverAgentId.value,
                "content": "テストメッセージ"
            ]
        )

        let messages = try chatRepository.findMessages(projectId: testProjectId, agentId: receiverAgentId)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].senderId, senderAgentId)
        XCTAssertNil(messages[0].receiverId)  // 受信者ファイルにはreceiverIdなし
        XCTAssertEqual(messages[0].content, "テストメッセージ")
    }

    /// 正常系: related_task_idが保存される
    func testSendMessageWithRelatedTaskId() async throws {
        let taskId = "task-123"
        _ = try await mcpServer.callTool(
            name: "send_message",
            arguments: [
                "session_token": sessionToken!,
                "target_agent_id": receiverAgentId.value,
                "content": "タスク関連メッセージ",
                "related_task_id": taskId
            ]
        )

        let messages = try chatRepository.findMessages(projectId: testProjectId, agentId: senderAgentId)
        XCTAssertEqual(messages[0].relatedTaskId?.value, taskId)
    }

    // MARK: - Error Cases

    /// 異常系: 自分自身への送信は拒否
    func testSendMessageRejectsSelfMessage() async throws {
        do {
            _ = try await mcpServer.callTool(
                name: "send_message",
                arguments: [
                    "session_token": sessionToken!,
                    "target_agent_id": senderAgentId.value,  // 自分自身
                    "content": "自分へ"
                ]
            )
            XCTFail("Expected error for self-message")
        } catch let error as MCPError {
            XCTAssertTrue(error.localizedDescription.contains("self"))
        }
    }

    /// 異常系: プロジェクト外エージェントへの送信は拒否
    func testSendMessageRejectsOutsideProjectAgent() async throws {
        // Create agent not in project
        let outsideAgentId = AgentID(value: "outside-agent")
        let outsideAgent = Agent(id: outsideAgentId, name: "Outside", agentType: .worker)
        try agentRepository.save(outsideAgent)
        // NOT assigned to project

        do {
            _ = try await mcpServer.callTool(
                name: "send_message",
                arguments: [
                    "session_token": sessionToken!,
                    "target_agent_id": outsideAgentId.value,
                    "content": "外部エージェントへ"
                ]
            )
            XCTFail("Expected error for outside project agent")
        } catch let error as MCPError {
            XCTAssertTrue(error.localizedDescription.contains("project"))
        }
    }

    /// 異常系: 存在しないエージェントへの送信は拒否
    func testSendMessageRejectsNonExistentAgent() async throws {
        do {
            _ = try await mcpServer.callTool(
                name: "send_message",
                arguments: [
                    "session_token": sessionToken!,
                    "target_agent_id": "non-existent-agent",
                    "content": "存在しないエージェントへ"
                ]
            )
            XCTFail("Expected error for non-existent agent")
        } catch let error as MCPError {
            XCTAssertTrue(error.localizedDescription.contains("not found"))
        }
    }

    /// 異常系: コンテンツ長超過は拒否
    func testSendMessageRejectsContentTooLong() async throws {
        let longContent = String(repeating: "あ", count: 4001)  // 4000文字超過

        do {
            _ = try await mcpServer.callTool(
                name: "send_message",
                arguments: [
                    "session_token": sessionToken!,
                    "target_agent_id": receiverAgentId.value,
                    "content": longContent
                ]
            )
            XCTFail("Expected error for content too long")
        } catch let error as MCPError {
            XCTAssertTrue(error.localizedDescription.contains("4000") || error.localizedDescription.contains("long"))
        }
    }

    /// 異常系: 必須パラメータ不足
    func testSendMessageRequiresAllParameters() async throws {
        // Missing target_agent_id
        do {
            _ = try await mcpServer.callTool(
                name: "send_message",
                arguments: [
                    "session_token": sessionToken!,
                    "content": "メッセージ"
                ]
            )
            XCTFail("Expected error for missing target_agent_id")
        } catch {
            // Expected
        }

        // Missing content
        do {
            _ = try await mcpServer.callTool(
                name: "send_message",
                arguments: [
                    "session_token": sessionToken!,
                    "target_agent_id": receiverAgentId.value
                ]
            )
            XCTFail("Expected error for missing content")
        } catch {
            // Expected
        }
    }
}
```

---

## Phase 2: 実装（GREEN）

### 2.1 ToolDefinitions.swift

```swift
// ツール定義追加
static let sendMessage: [String: Any] = [
    "name": "send_message",
    "description": """
        プロジェクト内の他のエージェントにメッセージを送信します（非同期）。
        受信者は get_pending_messages またはチャット画面で確認できます。
        タスクセッション・チャットセッションの両方で使用可能です。
        """,
    "inputSchema": [
        "type": "object",
        "properties": [
            "session_token": [
                "type": "string",
                "description": "authenticateツールで取得したセッショントークン"
            ],
            "target_agent_id": [
                "type": "string",
                "description": "送信先エージェントID（同一プロジェクト内のエージェントのみ指定可能）"
            ],
            "content": [
                "type": "string",
                "description": "メッセージ内容（最大4,000文字）"
            ],
            "related_task_id": [
                "type": "string",
                "description": "関連タスクID（任意）"
            ]
        ],
        "required": ["session_token", "target_agent_id", "content"]
    ]
]

// all() メソッドに追加
static func all() -> [[String: Any]] {
    return [
        // ... 既存ツール ...
        sendMessage,  // 追加
    ]
}
```

### 2.2 ToolAuthorization.swift

```swift
// permissions辞書に追加
static let permissions: [String: ToolPermission] = [
    // ... 既存 ...

    // メッセージ送信（タスク・チャット両方で使用可能）
    "send_message": .authenticated,
]
```

### 2.3 MCPServer.swift

```swift
// MCPError に追加
enum MCPError: Error, LocalizedError {
    // ... 既存 ...
    case cannotMessageSelf
    case targetAgentNotInProject(String, projectId: String)
    case contentTooLong(maxLength: Int)

    var errorDescription: String? {
        switch self {
        // ... 既存 ...
        case .cannotMessageSelf:
            return "Cannot send message to yourself"
        case .targetAgentNotInProject(let agentId, let projectId):
            return "Agent '\(agentId)' is not assigned to project '\(projectId)'"
        case .contentTooLong(let maxLength):
            return "Content exceeds maximum length of \(maxLength) characters"
        }
    }
}

// ハンドラー実装
private func handleSendMessage(
    session: AgentSession,
    arguments: [String: Any]
) throws -> [String: Any] {
    // 1. パラメータ取得
    guard let targetAgentIdStr = arguments["target_agent_id"] as? String else {
        throw MCPError.missingArgument("target_agent_id")
    }
    guard let content = arguments["content"] as? String else {
        throw MCPError.missingArgument("content")
    }
    let relatedTaskIdStr = arguments["related_task_id"] as? String

    // 2. コンテンツ長チェック
    guard content.count <= 4000 else {
        throw MCPError.contentTooLong(maxLength: 4000)
    }

    // 3. 自分自身への送信は禁止
    let targetAgentId = AgentID(value: targetAgentIdStr)
    guard targetAgentId != session.agentId else {
        throw MCPError.cannotMessageSelf
    }

    // 4. 送信先エージェントの存在確認
    guard let _ = try agentRepository.findById(targetAgentId) else {
        throw MCPError.agentNotFound(targetAgentIdStr)
    }

    // 5. 同一プロジェクト内のエージェントか確認
    let assignedAgents = try projectAgentAssignmentRepository.findByProjectId(session.projectId)
    guard assignedAgents.contains(where: { $0.agentId == targetAgentId }) else {
        throw MCPError.targetAgentNotInProject(targetAgentIdStr, projectId: session.projectId.value)
    }

    // 6. メッセージ作成
    let message = ChatMessage(
        id: ChatMessageID(value: UUID().uuidString),
        senderId: session.agentId,
        receiverId: targetAgentId,
        content: content,
        createdAt: Date(),
        relatedTaskId: relatedTaskIdStr.map { TaskID(value: $0) },
        relatedHandoffId: nil
    )

    // 7. 双方向保存
    try chatRepository.saveMessageDualWrite(
        message,
        projectId: session.projectId,
        senderAgentId: session.agentId,
        receiverAgentId: targetAgentId
    )

    return [
        "success": true,
        "message_id": message.id.value,
        "target_agent_id": targetAgentIdStr
    ]
}

// callTool内のルーティングに追加
case "send_message":
    return try handleSendMessage(session: session, arguments: arguments)
```

---

## Phase 3: リファクタリング（REFACTOR）

必要に応じて：
- エラーメッセージの日本語対応
- ログ出力追加
- パフォーマンス最適化

---

## 実装順序

| Step | 内容 | テスト | 実装 |
|------|------|--------|------|
| 1 | ツール定義テスト追加 | ❌ RED | - |
| 2 | ToolDefinitions.swift 修正 | ✅ GREEN | ✅ |
| 3 | 権限テスト追加 | ❌ RED | - |
| 4 | ToolAuthorization.swift 修正 | ✅ GREEN | ✅ |
| 5 | 統合テスト追加 | ❌ RED | - |
| 6 | MCPServer.swift 修正 | ✅ GREEN | ✅ |
| 7 | 全テスト実行・確認 | ✅ ALL GREEN | ✅ |

---

## テスト実行コマンド

```bash
# 新規テストのみ実行
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:MCPServerTests/SendMessageToolTests \
  -only-testing:MCPServerTests/SendMessageIntegrationTests

# 全MCPServerテスト実行
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:MCPServerTests
```

---

## 関連ドキュメント

- [docs/design/SEND_MESSAGE_FROM_TASK_SESSION.md](../design/SEND_MESSAGE_FROM_TASK_SESSION.md) - 機能設計書
- [docs/usecase/UC012_SendMessageFromTaskSession.md](../usecase/UC012_SendMessageFromTaskSession.md) - UC012
- [docs/usecase/UC013_WorkerToWorkerMessageRelay.md](../usecase/UC013_WorkerToWorkerMessageRelay.md) - UC013
