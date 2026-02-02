# 実装プラン: タスク/チャットセッション分離

## 概要

設計書 [TASK_CHAT_SESSION_SEPARATION.md](../design/TASK_CHAT_SESSION_SEPARATION.md) に基づく実装プラン。
テストファーストアプローチで段階的に実装する。

---

## Phase 1: 権限変更のテストと実装

### 目的

タスクセッションからコミュニケーション系ツールを呼べないようにする。

### 1.1 テスト作成（RED）

**ファイル:** `Tests/MCPServerTests/TaskChatSeparationTests.swift`

```swift
// テストケース1: タスクセッションからstart_conversationを呼ぶとエラー
func testStartConversationFromTaskSessionFails() async throws {
    // Given: タスクセッション（purpose=task）で認証済み
    let taskSession = try await createTaskSession(agentId: "worker-a")

    // When: start_conversationを呼び出す
    // Then: chatSessionRequired エラーが発生
    await assertThrowsError(
        ToolAuthorizationError.chatSessionRequired("start_conversation", currentPurpose: .task)
    ) {
        try await mcpServer.handleStartConversation(session: taskSession, ...)
    }
}

// テストケース2: タスクセッションからend_conversationを呼ぶとエラー
func testEndConversationFromTaskSessionFails() async throws {
    // Given: タスクセッション（purpose=task）で認証済み
    let taskSession = try await createTaskSession(agentId: "worker-a")

    // When: end_conversationを呼び出す
    // Then: chatSessionRequired エラーが発生
    await assertThrowsError(
        ToolAuthorizationError.chatSessionRequired("end_conversation", currentPurpose: .task)
    ) {
        try await mcpServer.handleEndConversation(session: taskSession, ...)
    }
}

// テストケース3: タスクセッションからsend_messageを呼ぶとエラー
func testSendMessageFromTaskSessionFails() async throws {
    // Given: タスクセッション（purpose=task）で認証済み
    let taskSession = try await createTaskSession(agentId: "worker-a")

    // When: send_messageを呼び出す
    // Then: chatSessionRequired エラーが発生
    await assertThrowsError(
        ToolAuthorizationError.chatSessionRequired("send_message", currentPurpose: .task)
    ) {
        try await mcpServer.handleSendMessage(session: taskSession, ...)
    }
}

// テストケース4: チャットセッションからstart_conversationは成功
func testStartConversationFromChatSessionSucceeds() async throws {
    // Given: チャットセッション（purpose=chat）で認証済み
    let chatSession = try await createChatSession(agentId: "worker-a")

    // When: start_conversationを呼び出す
    // Then: 成功する
    let result = try await mcpServer.handleStartConversation(
        session: chatSession,
        targetAgentId: "worker-b",
        purpose: "テスト会話"
    )
    XCTAssertNotNil(result.conversationId)
}
```

### 1.2 実装（GREEN）

**ファイル:** `Sources/MCPServer/Authorization/ToolAuthorization.swift`

```swift
// 変更箇所
static let permissions: [String: ToolPermission] = [
    // ...既存...

    // 変更: .authenticated → .chatOnly
    "start_conversation": .chatOnly,
    "end_conversation": .chatOnly,
    "send_message": .chatOnly,

    // ...既存...
]
```

### 1.3 検証項目

- [ ] `testStartConversationFromTaskSessionFails` がGREEN
- [ ] `testEndConversationFromTaskSessionFails` がGREEN
- [ ] `testSendMessageFromTaskSessionFails` がGREEN
- [ ] `testStartConversationFromChatSessionSucceeds` がGREEN
- [ ] 既存のチャットセッションテストが引き続きGREEN

---

## Phase 2: 委譲テーブルの作成

### 目的

タスクセッションからチャットセッションへの委譲リクエストを永続化する。

### 2.1 テスト作成（RED）

**ファイル:** `Tests/InfrastructureTests/ChatDelegationRepositoryTests.swift`

```swift
// テストケース1: 委譲リクエストの保存
func testSaveDelegation() async throws {
    // Given: 委譲リクエスト
    let delegation = ChatDelegation(
        id: .generate(),
        agentId: AgentID("worker-a"),
        projectId: ProjectID("project-1"),
        targetAgentId: AgentID("worker-b"),
        purpose: "6往復しりとりをしてほしい",
        context: nil,
        status: .pending,
        createdAt: Date()
    )

    // When: 保存
    try await repository.save(delegation)

    // Then: 取得できる
    let fetched = try await repository.findById(delegation.id)
    XCTAssertEqual(fetched?.purpose, "6往復しりとりをしてほしい")
    XCTAssertEqual(fetched?.status, .pending)
}

// テストケース2: エージェントの保留中委譲を取得
func testFindPendingDelegationsForAgent() async throws {
    // Given: worker-aに2件、worker-bに1件の委譲
    try await repository.save(createDelegation(agentId: "worker-a", status: .pending))
    try await repository.save(createDelegation(agentId: "worker-a", status: .pending))
    try await repository.save(createDelegation(agentId: "worker-b", status: .pending))
    try await repository.save(createDelegation(agentId: "worker-a", status: .completed))

    // When: worker-aの保留中を取得
    let delegations = try await repository.findPendingByAgentId(AgentID("worker-a"))

    // Then: 2件
    XCTAssertEqual(delegations.count, 2)
}

// テストケース3: ステータス更新
func testUpdateDelegationStatus() async throws {
    // Given: 保留中の委譲
    let delegation = createDelegation(status: .pending)
    try await repository.save(delegation)

    // When: 処理中に更新
    try await repository.updateStatus(delegation.id, status: .processing)

    // Then: ステータスが変わる
    let fetched = try await repository.findById(delegation.id)
    XCTAssertEqual(fetched?.status, .processing)
}
```

### 2.2 実装（GREEN）

**ファイル:** `Sources/Domain/Entities/ChatDelegation.swift`（新規）

```swift
public typealias ChatDelegationID = EntityID<ChatDelegation>

public enum ChatDelegationStatus: String, Codable, Sendable {
    case pending
    case processing
    case completed
    case failed
}

public struct ChatDelegation: Identifiable, Codable, Sendable {
    public let id: ChatDelegationID
    public let agentId: AgentID           // 委譲元エージェント
    public let projectId: ProjectID
    public let targetAgentId: AgentID     // コミュニケーション相手
    public let purpose: String            // 依頼内容
    public let context: String?           // 追加コンテキスト
    public var status: ChatDelegationStatus
    public let createdAt: Date
    public var processedAt: Date?
    public var result: String?            // 実行結果（JSON）
}
```

**ファイル:** `Sources/Infrastructure/Database/DatabaseSetup.swift`

```swift
// chat_delegations テーブル追加
"""
CREATE TABLE IF NOT EXISTS chat_delegations (
    id TEXT PRIMARY KEY,
    agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    target_agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    purpose TEXT NOT NULL,
    context TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at DATETIME NOT NULL,
    processed_at DATETIME,
    result TEXT
);
CREATE INDEX IF NOT EXISTS idx_chat_delegations_agent_status
    ON chat_delegations(agent_id, status);
"""
```

**ファイル:** `Sources/Infrastructure/Database/ChatDelegationRepository.swift`（新規）

### 2.3 検証項目

- [ ] `testSaveDelegation` がGREEN
- [ ] `testFindPendingDelegationsForAgent` がGREEN
- [ ] `testUpdateDelegationStatus` がGREEN
- [ ] マイグレーションが正常に実行される

---

## Phase 3: delegate_to_chat_session ツール実装

### 目的

タスクセッションからチャットセッションへ委譲を依頼するツールを追加。

### 3.1 テスト作成（RED）

**ファイル:** `Tests/MCPServerTests/DelegateToChatSessionTests.swift`

```swift
// テストケース1: タスクセッションからの委譲が成功
func testDelegateFromTaskSessionSucceeds() async throws {
    // Given: タスクセッション
    let taskSession = try await createTaskSession(agentId: "worker-a", projectId: "project-1")

    // When: delegate_to_chat_sessionを呼び出す
    let result = try await mcpServer.handleDelegateToChatSession(
        session: taskSession,
        targetAgentId: "worker-b",
        purpose: "6往復しりとりをしてほしい",
        context: nil
    )

    // Then: 委譲IDが返る
    XCTAssertNotNil(result.delegationId)
    XCTAssertTrue(result.success)

    // And: DBに保存されている
    let delegation = try await delegationRepository.findById(result.delegationId)
    XCTAssertEqual(delegation?.status, .pending)
    XCTAssertEqual(delegation?.targetAgentId.value, "worker-b")
}

// テストケース2: チャットセッションからの委譲はエラー
func testDelegateFromChatSessionFails() async throws {
    // Given: チャットセッション
    let chatSession = try await createChatSession(agentId: "worker-a")

    // When: delegate_to_chat_sessionを呼び出す
    // Then: taskSessionRequired エラー
    await assertThrowsError(
        ToolAuthorizationError.taskSessionRequired("delegate_to_chat_session", currentPurpose: .chat)
    ) {
        try await mcpServer.handleDelegateToChatSession(session: chatSession, ...)
    }
}

// テストケース3: 存在しないエージェントへの委譲はエラー
func testDelegateToNonExistentAgentFails() async throws {
    // Given: タスクセッション
    let taskSession = try await createTaskSession(agentId: "worker-a")

    // When: 存在しないエージェントに委譲
    // Then: agentNotFound エラー
    await assertThrowsError(MCPError.agentNotFound("non-existent")) {
        try await mcpServer.handleDelegateToChatSession(
            session: taskSession,
            targetAgentId: "non-existent",
            purpose: "test"
        )
    }
}

// テストケース4: 自分自身への委譲はエラー
func testDelegateToSelfFails() async throws {
    // Given: タスクセッション
    let taskSession = try await createTaskSession(agentId: "worker-a")

    // When: 自分自身に委譲
    // Then: cannotDelegateToSelf エラー
    await assertThrowsError(MCPError.cannotDelegateToSelf) {
        try await mcpServer.handleDelegateToChatSession(
            session: taskSession,
            targetAgentId: "worker-a",
            purpose: "test"
        )
    }
}
```

### 3.2 実装（GREEN）

**ファイル:** `Sources/MCPServer/Authorization/ToolAuthorization.swift`

```swift
// 追加
"delegate_to_chat_session": .taskOnly,
```

**ファイル:** `Sources/MCPServer/Tools/ToolDefinitions.swift`

```swift
static let delegateToChatSession: [String: Any] = [
    "name": "delegate_to_chat_session",
    "description": """
        チャットセッションへコミュニケーションを委譲します。
        タスクセッションから他エージェントへのメッセージ送信や会話は直接行えないため、
        このツールでチャットセッションに依頼してください。
        チャットセッションが実行方法（会話 or 単発メッセージ）を判断します。
        """,
    "inputSchema": [
        "type": "object",
        "properties": [
            "session_token": [...],
            "target_agent_id": [...],
            "purpose": [...],
            "context": [...]
        ],
        "required": ["session_token", "target_agent_id", "purpose"]
    ]
]
```

**ファイル:** `Sources/MCPServer/MCPServer.swift`

```swift
private func handleDelegateToChatSession(
    session: AgentSession,
    targetAgentId: String,
    purpose: String,
    context: String?
) async throws -> [String: Any] {
    // 1. 自分自身への委譲は禁止
    guard targetAgentId != session.agentId.value else {
        throw MCPError.cannotDelegateToSelf
    }

    // 2. 送信先エージェントの存在確認
    guard let _ = try await agentRepository.findById(AgentID(targetAgentId)) else {
        throw MCPError.agentNotFound(targetAgentId)
    }

    // 3. 同一プロジェクト内のエージェントか確認
    let assignedAgents = try await projectRepository.getAssignedAgents(projectId: session.projectId)
    guard assignedAgents.contains(where: { $0.id.value == targetAgentId }) else {
        throw MCPError.targetAgentNotInProject(targetAgentId, projectId: session.projectId.value)
    }

    // 4. 委譲リクエスト作成
    let delegation = ChatDelegation(
        id: .generate(),
        agentId: session.agentId,
        projectId: session.projectId,
        targetAgentId: AgentID(targetAgentId),
        purpose: purpose,
        context: context,
        status: .pending,
        createdAt: Date()
    )

    // 5. 保存
    try await chatDelegationRepository.save(delegation)

    return [
        "success": true,
        "delegation_id": delegation.id.value,
        "message": "依頼をチャットセッションに登録しました。次回チャットセッション起動時に処理されます。"
    ]
}
```

### 3.3 検証項目

- [ ] `testDelegateFromTaskSessionSucceeds` がGREEN
- [ ] `testDelegateFromChatSessionFails` がGREEN
- [ ] `testDelegateToNonExistentAgentFails` がGREEN
- [ ] `testDelegateToSelfFails` がGREEN

---

## Phase 3.5: チャットセッション自動起動トリガー

### 目的

`delegate_to_chat_session` が呼ばれた際、チャットセッションが自動的に起動されるようにする。
Coordinatorは `get_agent_action` を通じて `hasChatWork()` をポーリングしており、この関数で委譲リクエストを検出できれば、チャットセッションがスポーンされる。

### 3.5.1 テスト作成（RED）

**ファイル:** `Tests/DomainTests/WorkDetectionServiceTests.swift`

```swift
// テストケース1: 委譲リクエストがあればチャット作業ありと判定
func testHasChatWorkWithPendingDelegation() async throws {
    // Given: worker-aにpendingの委譲がある
    let delegation = ChatDelegation(
        id: .generate(),
        agentId: AgentID("worker-a"),
        projectId: ProjectID("project-1"),
        targetAgentId: AgentID("worker-b"),
        purpose: "テスト",
        status: .pending,
        createdAt: Date()
    )
    try await delegationRepository.save(delegation)

    // And: アクティブなチャットセッションはない

    // When: hasChatWorkを呼び出す
    let hasWork = try await workDetectionService.hasChatWork(
        agentId: AgentID("worker-a"),
        projectId: ProjectID("project-1")
    )

    // Then: trueが返る
    XCTAssertTrue(hasWork)
}

// テストケース2: アクティブなチャットセッションがあれば作業なしと判定
func testHasChatWorkWithActiveSession() async throws {
    // Given: worker-aにpendingの委譲がある
    try await delegationRepository.save(createDelegation(status: .pending))

    // And: アクティブなチャットセッションがある
    let chatSession = AgentSession(
        agentId: AgentID("worker-a"),
        projectId: ProjectID("project-1"),
        purpose: .chat
    )
    try await sessionRepository.save(chatSession)

    // When: hasChatWorkを呼び出す
    let hasWork = try await workDetectionService.hasChatWork(
        agentId: AgentID("worker-a"),
        projectId: ProjectID("project-1")
    )

    // Then: falseが返る（既にチャットセッションがあるため）
    XCTAssertFalse(hasWork)
}

// テストケース3: processing状態の委譲は作業なしと判定
func testHasChatWorkWithProcessingDelegation() async throws {
    // Given: worker-aにprocessing状態の委譲がある（既に処理中）
    try await delegationRepository.save(createDelegation(status: .processing))

    // And: アクティブなチャットセッションはない

    // When: hasChatWorkを呼び出す
    let hasWork = try await workDetectionService.hasChatWork(
        agentId: AgentID("worker-a"),
        projectId: ProjectID("project-1")
    )

    // Then: falseが返る（pending以外はトリガーしない）
    XCTAssertFalse(hasWork)
}
```

### 3.5.2 実装（GREEN）

**ファイル:** `Sources/Domain/Services/WorkDetectionService.swift`

```swift
public func hasChatWork(agentId: AgentID, projectId: ProjectID) throws -> Bool {
    // 既存: 未読メッセージ
    let hasUnread = try chatRepository.hasUnreadMessages(
        projectId: projectId,
        agentId: agentId
    )

    // 新規: 委譲リクエスト（pending状態のみ）
    let hasPendingDelegation = try delegationRepository.hasPending(
        agentId: agentId,
        projectId: projectId
    )

    // アクティブなチャットセッションがあるか確認
    let sessions = try sessionRepository.findByAgentIdAndProjectId(agentId, projectId: projectId)
    let hasActiveChat = sessions.contains { $0.purpose == .chat && !$0.isExpired }

    // 未読メッセージ OR 委譲リクエストがあり、アクティブなチャットセッションがない場合
    return (hasUnread || hasPendingDelegation) && !hasActiveChat
}
```

**ファイル:** `Sources/Domain/Repositories/ChatDelegationRepositoryProtocol.swift`

```swift
public protocol ChatDelegationRepositoryProtocol: Sendable {
    // ... 既存メソッド ...

    /// 指定エージェント・プロジェクトにpending状態の委譲があるか
    func hasPending(agentId: AgentID, projectId: ProjectID) async throws -> Bool
}
```

### 3.5.3 起動フローの確認

```
1. タスクセッション: delegate_to_chat_session() を呼び出す
   └─ chat_delegations に status=pending で保存

2. Coordinator: 数秒後に get_agent_action をポーリング
   └─ MCPServer: hasChatWork() を呼び出す
      └─ delegationRepository.hasPending() → true
      └─ hasActiveChat → false
      └─ return true

3. Coordinator: action="start" (reason="chat_work") を受信
   └─ チャットセッションをスポーン

4. チャットセッション: authenticate() → get_pending_messages()
   └─ pending_delegations を取得し、会話/メッセージを実行
```

### 3.5.4 検証項目

- [x] `testHasChatWork_WithPendingDelegation_ReturnsTrue` がGREEN
- [x] `testHasChatWork_WithPendingDelegationAndActiveSession_ReturnsFalse` がGREEN
- [x] `testHasChatWork_WithProcessingDelegation_ReturnsFalse` がGREEN
- [x] `testHasChatWork_WithBothUnreadAndDelegation_ReturnsTrue` がGREEN
- [x] `testHasChatWork_WithPendingDelegationAndTaskSession_ReturnsTrue` がGREEN
- [x] `testHasChatWork_WithDelegationInDifferentProject_ReturnsFalse` がGREEN
- [ ] Coordinatorからのポーリングでチャットセッションが起動することを確認（統合テスト）

---

## Phase 4: チャットセッションでの委譲処理

### 目的

チャットセッションが委譲リクエストを受け取り、実行できるようにする。

### 4.1 テスト作成（RED）

**ファイル:** `Tests/MCPServerTests/ChatSessionDelegationProcessingTests.swift`

```swift
// テストケース1: get_pending_messagesに委譲リクエストが含まれる
func testGetPendingMessagesIncludesDelegations() async throws {
    // Given: worker-aに保留中の委譲がある
    let delegation = ChatDelegation(
        agentId: AgentID("worker-a"),
        projectId: ProjectID("project-1"),
        targetAgentId: AgentID("worker-b"),
        purpose: "6往復しりとりをしてほしい",
        status: .pending,
        createdAt: Date()
    )
    try await delegationRepository.save(delegation)

    // And: worker-aのチャットセッション
    let chatSession = try await createChatSession(agentId: "worker-a", projectId: "project-1")

    // When: get_pending_messagesを呼び出す
    let result = try await mcpServer.handleGetPendingMessages(session: chatSession)

    // Then: pending_delegationsに含まれる
    XCTAssertEqual(result.pendingDelegations.count, 1)
    XCTAssertEqual(result.pendingDelegations[0].targetAgentId, "worker-b")
    XCTAssertEqual(result.pendingDelegations[0].purpose, "6往復しりとりをしてほしい")
}

// テストケース2: 委譲リクエスト取得時にステータスがprocessingに更新
func testDelegationStatusUpdatedOnFetch() async throws {
    // Given: 保留中の委譲
    let delegation = createDelegation(agentId: "worker-a", status: .pending)
    try await delegationRepository.save(delegation)

    // When: get_pending_messagesで取得
    let chatSession = try await createChatSession(agentId: "worker-a")
    _ = try await mcpServer.handleGetPendingMessages(session: chatSession)

    // Then: ステータスがprocessingに更新
    let updated = try await delegationRepository.findById(delegation.id)
    XCTAssertEqual(updated?.status, .processing)
}

// テストケース3: 委譲完了の報告
func testReportDelegationCompleted() async throws {
    // Given: 処理中の委譲
    let delegation = createDelegation(agentId: "worker-a", status: .processing)
    try await delegationRepository.save(delegation)

    // When: 完了を報告
    let chatSession = try await createChatSession(agentId: "worker-a")
    try await mcpServer.handleReportDelegationCompleted(
        session: chatSession,
        delegationId: delegation.id.value,
        result: "会話が完了しました"
    )

    // Then: ステータスがcompletedに更新
    let updated = try await delegationRepository.findById(delegation.id)
    XCTAssertEqual(updated?.status, .completed)
    XCTAssertNotNil(updated?.processedAt)
}
```

### 4.2 実装（GREEN）

**ファイル:** `Sources/MCPServer/MCPServer.swift`

```swift
// get_pending_messages の拡張
private func handleGetPendingMessages(session: AgentSession) async throws -> GetPendingMessagesResponse {
    // 既存: メッセージ取得
    let messages = try await chatRepository.getPendingMessages(...)

    // 追加: 保留中の委譲を取得
    let delegations = try await chatDelegationRepository.findPendingByAgentId(session.agentId)

    // 委譲のステータスをprocessingに更新
    for delegation in delegations {
        try await chatDelegationRepository.updateStatus(delegation.id, status: .processing)
    }

    return GetPendingMessagesResponse(
        pendingMessages: messages,
        pendingDelegations: delegations.map { ... }
    )
}
```

**ファイル:** `Sources/MCPServer/Tools/ToolDefinitions.swift`

```swift
// 新規ツール（chatOnly）
static let reportDelegationCompleted: [String: Any] = [
    "name": "report_delegation_completed",
    "description": "委譲されたコミュニケーション処理の完了を報告します。",
    "inputSchema": [...]
]
```

### 4.3 検証項目

- [ ] `testGetPendingMessagesIncludesDelegations` がGREEN
- [ ] `testDelegationStatusUpdatedOnFetch` がGREEN
- [ ] `testReportDelegationCompleted` がGREEN

---

## Phase 5: 統合テスト

### 目的

エンドツーエンドで委譲フローが動作することを確認。

### 5.1 テスト作成（RED）

**ファイル:** `Tests/MCPServerTests/TaskChatDelegationIntegrationTests.swift`

```swift
// テストケース: タスクセッション→チャットセッション→会話の完全フロー
func testFullDelegationFlow() async throws {
    // Phase 1: タスクセッションが委譲を依頼
    let taskSession = try await createTaskSession(agentId: "worker-a", projectId: "project-1")
    let delegateResult = try await mcpServer.handleDelegateToChatSession(
        session: taskSession,
        targetAgentId: "worker-b",
        purpose: "しりとりをしてほしい"
    )
    XCTAssertTrue(delegateResult.success)

    // Phase 2: チャットセッションが委譲を取得
    let chatSession = try await createChatSession(agentId: "worker-a", projectId: "project-1")
    let pendingResult = try await mcpServer.handleGetPendingMessages(session: chatSession)
    XCTAssertEqual(pendingResult.pendingDelegations.count, 1)

    // Phase 3: チャットセッションが会話を開始
    let conversationResult = try await mcpServer.handleStartConversation(
        session: chatSession,
        targetAgentId: "worker-b",
        purpose: pendingResult.pendingDelegations[0].purpose
    )
    XCTAssertNotNil(conversationResult.conversationId)

    // Phase 4: 会話終了後、委譲完了を報告
    try await mcpServer.handleEndConversation(
        session: chatSession,
        conversationId: conversationResult.conversationId
    )
    try await mcpServer.handleReportDelegationCompleted(
        session: chatSession,
        delegationId: delegateResult.delegationId,
        result: "会話完了"
    )

    // Verify: 委譲がcompletedになっている
    let delegation = try await delegationRepository.findById(delegateResult.delegationId)
    XCTAssertEqual(delegation?.status, .completed)
}
```

### 5.2 検証項目

- [ ] `testFullDelegationFlow` がGREEN
- [ ] UC020テストが新しいフローで動作する（要テスト更新）

---

## Phase 6: 既存テストの更新

### 目的

権限変更により失敗するようになった既存テストを更新。

### 6.1 影響を受けるテスト

```
Tests/MCPServerTests/
├── AIConversationTests.swift        # タスクセッションからの会話テスト
├── SendMessageTests.swift           # タスクセッションからのメッセージ送信テスト
└── ...

web-ui/e2e/integration/
├── ai-conversation.spec.ts          # UC016
├── ai-conversation-b.spec.ts        # UC016-B
└── task-conversation.spec.ts        # UC020
```

### 6.2 更新方針

1. **単体テスト**: タスクセッションからの呼び出しテストは「エラーになること」を確認するテストに変更
2. **統合テスト**: チャットセッション経由のフローに変更（Coordinator設定の調整が必要）

---

## 実装順序サマリー

| Phase | 内容 | テスト数 | 見積もり | ステータス |
|-------|------|---------|---------|-----------|
| 1 | 権限変更 | 17 | 小 | ✅ 完了 |
| 2 | 委譲テーブル | 11 | 小 | ✅ 完了 |
| 3 | delegate_to_chat_session | 5 | 中 | ✅ 完了 |
| 3.5 | チャットセッション自動起動 | 6 | 小 | ✅ 完了 |
| 4 | チャットセッション処理 | 4 | 中 | ✅ 完了 |
| 5 | 統合テスト | 1 | 小 | ✅ 完了 |
| 6 | 既存テスト更新 | 多数 | 中 | 🔄 進行中 |

### 6.3 完了した更新

- [x] `testToolCount`: ツール数を36→38に更新（delegate_to_chat_session, report_delegation_completed追加）

---

## リスクと注意点

1. **既存機能への影響**
   - UC012/UC013（タスク→チャット非同期送信）が動作しなくなる
   - 関連する統合テストの更新が必要

2. **Coordinator設定**
   - チャットセッションが委譲を処理するためのスポーン条件の調整が必要
   - `get_agent_action` で `has_delegation_work` のような新しい理由を追加

3. **AIエージェントのプロンプト**
   - チャットセッション用CLAUDE.mdに委譲処理の指示を追加
   - 「委譲を受けたら会話 or メッセージを判断して実行」のガイダンス

---

## 関連ドキュメント

- [TASK_CHAT_SESSION_SEPARATION.md](../design/TASK_CHAT_SESSION_SEPARATION.md) - 設計書
- [AI_TO_AI_CONVERSATION.md](../design/AI_TO_AI_CONVERSATION.md) - AI間会話機能
- [TOOL_AUTHORIZATION_ENHANCEMENT.md](../design/TOOL_AUTHORIZATION_ENHANCEMENT.md) - ツール認可
