# 実装プラン: AIエージェント間会話機能

## 概要

設計書 `docs/design/AI_TO_AI_CONVERSATION.md` に基づく実装プラン。
単体テストファーストで進める。

---

## 変更対象ファイル

### 新規作成

| ファイル | 内容 |
|----------|------|
| `Sources/Domain/Entities/Conversation.swift` | Conversationエンティティ |
| `Sources/Infrastructure/Repositories/ConversationRepository.swift` | リポジトリ実装 |
| `Tests/DomainTests/ConversationTests.swift` | Domainテスト |
| `Tests/MCPServerTests/AIConversationTests.swift` | MCPツールテスト |

### 修正

| ファイル | 変更内容 |
|----------|----------|
| `Sources/Domain/Entities/ChatMessage.swift` | `conversationId`フィールド追加 |
| `Sources/Domain/Entities/PendingAgentPurpose.swift` | `conversationId`フィールド追加 |
| `Sources/Domain/Repositories/RepositoryProtocols.swift` | `ConversationRepository`プロトコル追加 |
| `Sources/Infrastructure/Database/DatabaseSetup.swift` | マイグレーション追加 |
| `Sources/MCPServer/Tools/ToolDefinitions.swift` | 新ツール定義 |
| `Sources/MCPServer/Authorization/ToolAuthorization.swift` | 権限定義 |
| `Sources/MCPServer/MCPServer.swift` | ツール実装、getNextAction拡張 |

---

## Phase 1: Domain層

### 1.1 Conversation エンティティ

#### テスト（RED）

```swift
// Tests/DomainTests/ConversationTests.swift

import XCTest
@testable import Domain

final class ConversationTests: XCTestCase {

    // MARK: - Entity Tests

    func testConversationInitialization() {
        let conv = Conversation(
            projectId: ProjectID("prj-001"),
            initiatorAgentId: AgentID("agent-a"),
            participantAgentId: AgentID("agent-b"),
            purpose: "しりとり"
        )

        XCTAssertNotNil(conv.id)
        XCTAssertEqual(conv.state, .pending)
        XCTAssertEqual(conv.initiatorAgentId.value, "agent-a")
        XCTAssertEqual(conv.participantAgentId.value, "agent-b")
        XCTAssertEqual(conv.purpose, "しりとり")
        XCTAssertNil(conv.endedAt)
    }

    func testConversationStateValues() {
        XCTAssertEqual(ConversationState.pending.rawValue, "pending")
        XCTAssertEqual(ConversationState.active.rawValue, "active")
        XCTAssertEqual(ConversationState.terminating.rawValue, "terminating")
        XCTAssertEqual(ConversationState.ended.rawValue, "ended")
        XCTAssertEqual(ConversationState.expired.rawValue, "expired")
    }

    func testConversationCodable() throws {
        let original = Conversation(
            projectId: ProjectID("prj-001"),
            initiatorAgentId: AgentID("agent-a"),
            participantAgentId: AgentID("agent-b"),
            state: .active,
            purpose: "テスト会話"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Conversation.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.state, .active)
        XCTAssertEqual(decoded.purpose, "テスト会話")
    }
}
```

#### 実装（GREEN）

```swift
// Sources/Domain/Entities/Conversation.swift

import Foundation

public typealias ConversationID = EntityID<Conversation>

public struct Conversation: Identifiable, Codable, Sendable {
    public let id: ConversationID
    public let projectId: ProjectID
    public let initiatorAgentId: AgentID
    public let participantAgentId: AgentID
    public var state: ConversationState
    public let purpose: String?
    public let createdAt: Date
    public var endedAt: Date?

    public init(
        id: ConversationID = .generate(),
        projectId: ProjectID,
        initiatorAgentId: AgentID,
        participantAgentId: AgentID,
        state: ConversationState = .pending,
        purpose: String? = nil,
        createdAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.initiatorAgentId = initiatorAgentId
        self.participantAgentId = participantAgentId
        self.state = state
        self.purpose = purpose
        self.createdAt = createdAt
        self.endedAt = endedAt
    }
}

public enum ConversationState: String, Codable, Sendable {
    case pending
    case active
    case terminating
    case ended
    case expired
}
```

---

### 1.2 ChatMessage 拡張（conversationId追加）

#### テスト（RED）

```swift
// Tests/DomainTests/ChatMessageTests.swift に追加

func testChatMessageWithConversationId() {
    let convId = ConversationID("conv-001")
    let message = ChatMessage(
        id: ChatMessageID("msg-001"),
        senderId: AgentID("agent-a"),
        recipientId: AgentID("agent-b"),
        content: "テスト",
        createdAt: Date(),
        conversationId: convId
    )

    XCTAssertEqual(message.conversationId, convId)
}

func testChatMessageConversationIdIsOptional() {
    let message = ChatMessage(
        id: ChatMessageID("msg-001"),
        senderId: AgentID("agent-a"),
        recipientId: AgentID("agent-b"),
        content: "テスト",
        createdAt: Date()
    )

    XCTAssertNil(message.conversationId)
}
```

#### 実装（GREEN）

```swift
// Sources/Domain/Entities/ChatMessage.swift に追加

public struct ChatMessage: Identifiable, Codable, Sendable {
    // ... 既存フィールド ...
    public let conversationId: ConversationID?  // 追加

    public init(
        // ... 既存パラメータ ...
        conversationId: ConversationID? = nil  // 追加
    ) {
        // ... 既存初期化 ...
        self.conversationId = conversationId
    }
}
```

---

### 1.3 PendingAgentPurpose 拡張（conversationId追加）

#### テスト（RED）

```swift
// Tests/DomainTests/PendingAgentPurposeTests.swift に追加

func testPendingAgentPurposeWithConversationId() {
    let convId = ConversationID("conv-001")
    let purpose = PendingAgentPurpose(
        agentId: AgentID("agent-b"),
        projectId: ProjectID("prj-001"),
        purpose: .chat,
        conversationId: convId
    )

    XCTAssertEqual(purpose.conversationId, convId)
}
```

#### 実装（GREEN）

```swift
// Sources/Domain/Entities/PendingAgentPurpose.swift に追加

public struct PendingAgentPurpose: ... {
    // ... 既存フィールド ...
    public let conversationId: ConversationID?  // 追加
}
```

---

### 1.4 ConversationRepository プロトコル

#### テスト（RED）

```swift
// Tests/DomainTests/ConversationRepositoryTests.swift

func testConversationRepositoryProtocolExists() {
    // プロトコルが存在し、必要なメソッドが定義されていることを確認
    // （コンパイルが通ればOK）
    let _: any ConversationRepository.Type = MockConversationRepository.self
}

// Mock for compilation check
class MockConversationRepository: ConversationRepository {
    func save(_ conversation: Conversation) throws {}
    func findById(_ id: ConversationID) throws -> Conversation? { nil }
    func findActiveByAgentId(_ agentId: AgentID, projectId: ProjectID) throws -> [Conversation] { [] }
    func findPendingForParticipant(_ agentId: AgentID, projectId: ProjectID) throws -> [Conversation] { [] }
    func updateState(_ id: ConversationID, state: ConversationState) throws {}
    func updateState(_ id: ConversationID, state: ConversationState, endedAt: Date?) throws {}
}
```

#### 実装（GREEN）

```swift
// Sources/Domain/Repositories/RepositoryProtocols.swift に追加

public protocol ConversationRepository: Sendable {
    func save(_ conversation: Conversation) throws
    func findById(_ id: ConversationID) throws -> Conversation?
    func findActiveByAgentId(_ agentId: AgentID, projectId: ProjectID) throws -> [Conversation]
    func findPendingForParticipant(_ agentId: AgentID, projectId: ProjectID) throws -> [Conversation]
    func updateState(_ id: ConversationID, state: ConversationState) throws
    func updateState(_ id: ConversationID, state: ConversationState, endedAt: Date?) throws
}
```

---

## Phase 2: Infrastructure層

### 2.1 DBマイグレーション

#### テスト（RED）

```swift
// Tests/InfrastructureTests/MigrationTests.swift に追加

func testConversationsTableExists() throws {
    let db = try DatabaseQueue()
    try AppDatabase.migrator.migrate(db)

    try db.read { db in
        let exists = try db.tableExists("conversations")
        XCTAssertTrue(exists, "conversations table should exist")
    }
}

func testConversationsTableColumns() throws {
    let db = try DatabaseQueue()
    try AppDatabase.migrator.migrate(db)

    try db.read { db in
        let columns = try db.columns(in: "conversations")
        let columnNames = columns.map { $0.name }

        XCTAssertTrue(columnNames.contains("id"))
        XCTAssertTrue(columnNames.contains("project_id"))
        XCTAssertTrue(columnNames.contains("initiator_agent_id"))
        XCTAssertTrue(columnNames.contains("participant_agent_id"))
        XCTAssertTrue(columnNames.contains("state"))
        XCTAssertTrue(columnNames.contains("purpose"))
        XCTAssertTrue(columnNames.contains("created_at"))
        XCTAssertTrue(columnNames.contains("ended_at"))
    }
}
```

#### 実装（GREEN）

```swift
// Sources/Infrastructure/Database/DatabaseSetup.swift に追加

// マイグレーション vXX (次のバージョン番号)
migrator.registerMigration("createConversationsTable") { db in
    try db.create(table: "conversations") { t in
        t.column("id", .text).primaryKey()
        t.column("project_id", .text).notNull()
            .references("projects", onDelete: .cascade)
        t.column("initiator_agent_id", .text).notNull()
            .references("agents", onDelete: .cascade)
        t.column("participant_agent_id", .text).notNull()
            .references("agents", onDelete: .cascade)
        t.column("state", .text).notNull().defaults(to: "pending")
        t.column("purpose", .text)
        t.column("created_at", .text).notNull()
        t.column("ended_at", .text)
    }

    try db.create(
        index: "idx_conversations_project",
        on: "conversations",
        columns: ["project_id"]
    )
    try db.create(
        index: "idx_conversations_initiator",
        on: "conversations",
        columns: ["initiator_agent_id", "state"]
    )
    try db.create(
        index: "idx_conversations_participant",
        on: "conversations",
        columns: ["participant_agent_id", "state"]
    )
}
```

---

### 2.2 ConversationRepository 実装

#### テスト（RED）

```swift
// Tests/InfrastructureTests/ConversationRepositoryTests.swift

final class ConversationRepositoryTests: XCTestCase {

    var db: DatabaseQueue!
    var repository: GRDBConversationRepository!
    var projectId: ProjectID!
    var agentAId: AgentID!
    var agentBId: AgentID!

    override func setUpWithError() throws {
        db = try DatabaseQueue()
        try AppDatabase.migrator.migrate(db)
        repository = GRDBConversationRepository(database: db)

        // テストデータ作成
        projectId = ProjectID("prj-test")
        agentAId = AgentID("agent-a")
        agentBId = AgentID("agent-b")

        try db.write { db in
            try db.execute(sql: "INSERT INTO projects (id, name, status) VALUES (?, ?, ?)",
                           arguments: [projectId.value, "Test", "active"])
            try db.execute(sql: "INSERT INTO agents (id, name, type, status) VALUES (?, ?, ?, ?)",
                           arguments: [agentAId.value, "Agent A", "ai", "active"])
            try db.execute(sql: "INSERT INTO agents (id, name, type, status) VALUES (?, ?, ?, ?)",
                           arguments: [agentBId.value, "Agent B", "ai", "active"])
        }
    }

    func testSaveAndFindById() throws {
        let conv = Conversation(
            projectId: projectId,
            initiatorAgentId: agentAId,
            participantAgentId: agentBId,
            purpose: "テスト"
        )

        try repository.save(conv)

        let found = try repository.findById(conv.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.initiatorAgentId, agentAId)
        XCTAssertEqual(found?.participantAgentId, agentBId)
        XCTAssertEqual(found?.state, .pending)
    }

    func testFindActiveByAgentId() throws {
        // pending状態の会話を作成
        let pendingConv = Conversation(
            projectId: projectId,
            initiatorAgentId: agentAId,
            participantAgentId: agentBId,
            state: .pending
        )
        try repository.save(pendingConv)

        // active状態の会話を作成
        let activeConv = Conversation(
            projectId: projectId,
            initiatorAgentId: agentAId,
            participantAgentId: agentBId,
            state: .active
        )
        try repository.save(activeConv)

        // initiatorとして検索
        let activeConvs = try repository.findActiveByAgentId(agentAId, projectId: projectId)
        XCTAssertEqual(activeConvs.count, 1)
        XCTAssertEqual(activeConvs[0].state, .active)
    }

    func testFindPendingForParticipant() throws {
        let conv = Conversation(
            projectId: projectId,
            initiatorAgentId: agentAId,
            participantAgentId: agentBId,
            state: .pending
        )
        try repository.save(conv)

        // 参加者(agentB)として検索
        let pending = try repository.findPendingForParticipant(agentBId, projectId: projectId)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].initiatorAgentId, agentAId)
    }

    func testUpdateState() throws {
        let conv = Conversation(
            projectId: projectId,
            initiatorAgentId: agentAId,
            participantAgentId: agentBId,
            state: .pending
        )
        try repository.save(conv)

        try repository.updateState(conv.id, state: .active)

        let updated = try repository.findById(conv.id)
        XCTAssertEqual(updated?.state, .active)
    }

    func testUpdateStateWithEndedAt() throws {
        let conv = Conversation(
            projectId: projectId,
            initiatorAgentId: agentAId,
            participantAgentId: agentBId,
            state: .active
        )
        try repository.save(conv)

        let endedAt = Date()
        try repository.updateState(conv.id, state: .ended, endedAt: endedAt)

        let updated = try repository.findById(conv.id)
        XCTAssertEqual(updated?.state, .ended)
        XCTAssertNotNil(updated?.endedAt)
    }
}
```

#### 実装（GREEN）

```swift
// Sources/Infrastructure/Repositories/ConversationRepository.swift

import Foundation
import GRDB

public final class GRDBConversationRepository: ConversationRepository, Sendable {
    private let database: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.database = database
    }

    public func save(_ conversation: Conversation) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO conversations
                    (id, project_id, initiator_agent_id, participant_agent_id, state, purpose, created_at, ended_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    conversation.id.value,
                    conversation.projectId.value,
                    conversation.initiatorAgentId.value,
                    conversation.participantAgentId.value,
                    conversation.state.rawValue,
                    conversation.purpose,
                    ISO8601DateFormatter().string(from: conversation.createdAt),
                    conversation.endedAt.map { ISO8601DateFormatter().string(from: $0) }
                ]
            )
        }
    }

    public func findById(_ id: ConversationID) throws -> Conversation? {
        try database.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM conversations WHERE id = ?",
                arguments: [id.value]
            ).map { try mapRow($0) }
        }
    }

    public func findActiveByAgentId(_ agentId: AgentID, projectId: ProjectID) throws -> [Conversation] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM conversations
                    WHERE project_id = ?
                    AND (initiator_agent_id = ? OR participant_agent_id = ?)
                    AND state IN ('active', 'terminating')
                    """,
                arguments: [projectId.value, agentId.value, agentId.value]
            )
            return try rows.map { try mapRow($0) }
        }
    }

    public func findPendingForParticipant(_ agentId: AgentID, projectId: ProjectID) throws -> [Conversation] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM conversations
                    WHERE project_id = ?
                    AND participant_agent_id = ?
                    AND state = 'pending'
                    ORDER BY created_at ASC
                    """,
                arguments: [projectId.value, agentId.value]
            )
            return try rows.map { try mapRow($0) }
        }
    }

    public func updateState(_ id: ConversationID, state: ConversationState) throws {
        try updateState(id, state: state, endedAt: nil)
    }

    public func updateState(_ id: ConversationID, state: ConversationState, endedAt: Date?) throws {
        try database.write { db in
            if let endedAt = endedAt {
                try db.execute(
                    sql: "UPDATE conversations SET state = ?, ended_at = ? WHERE id = ?",
                    arguments: [state.rawValue, ISO8601DateFormatter().string(from: endedAt), id.value]
                )
            } else {
                try db.execute(
                    sql: "UPDATE conversations SET state = ? WHERE id = ?",
                    arguments: [state.rawValue, id.value]
                )
            }
        }
    }

    private func mapRow(_ row: Row) throws -> Conversation {
        let formatter = ISO8601DateFormatter()
        return Conversation(
            id: ConversationID(row["id"]),
            projectId: ProjectID(row["project_id"]),
            initiatorAgentId: AgentID(row["initiator_agent_id"]),
            participantAgentId: AgentID(row["participant_agent_id"]),
            state: ConversationState(rawValue: row["state"]) ?? .pending,
            purpose: row["purpose"],
            createdAt: formatter.date(from: row["created_at"]) ?? Date(),
            endedAt: (row["ended_at"] as String?).flatMap { formatter.date(from: $0) }
        )
    }
}
```

---

## Phase 3: MCP Tools

### 3.1 start_conversation ツール

#### テスト（RED）

```swift
// Tests/MCPServerTests/AIConversationTests.swift

final class StartConversationTests: XCTestCase {

    // MARK: - Tool Definition

    func testStartConversationToolDefinition() {
        let tool = ToolDefinitions.startConversation

        XCTAssertEqual(tool["name"] as? String, "start_conversation")
        XCTAssertNotNil(tool["description"])

        if let schema = tool["inputSchema"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"))
            XCTAssertTrue(required.contains("target_agent_id"))
        }
    }

    func testStartConversationToolInAllTools() {
        let tools = ToolDefinitions.all()
        let names = tools.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("start_conversation"))
    }

    // MARK: - Authorization

    func testStartConversationRequiresAuthentication() {
        XCTAssertEqual(ToolAuthorization.permissions["start_conversation"], .authenticated)
    }

    func testStartConversationAllowedInChatSession() {
        let session = AgentSession(
            agentId: AgentID("agent-a"),
            projectId: ProjectID("prj-001"),
            purpose: .chat
        )
        let caller = CallerType.worker(agentId: session.agentId, session: session)

        XCTAssertNoThrow(try ToolAuthorization.authorize(tool: "start_conversation", caller: caller))
    }

    // MARK: - Integration Tests

    func testStartConversationSuccess() async throws {
        // Setup: 2つのAIエージェントを同じプロジェクトに配置
        // ...

        let result = try await mcpServer.callTool(
            name: "start_conversation",
            arguments: [
                "session_token": sessionToken,
                "target_agent_id": "agent-b",
                "purpose": "しりとり"
            ]
        )

        XCTAssertTrue(result["success"] as? Bool ?? false)
        XCTAssertNotNil(result["conversation_id"])
        XCTAssertEqual(result["status"] as? String, "pending")
    }

    func testStartConversationRejectsSelf() async throws {
        do {
            _ = try await mcpServer.callTool(
                name: "start_conversation",
                arguments: [
                    "session_token": sessionToken,
                    "target_agent_id": agentAId.value  // 自分自身
                ]
            )
            XCTFail("Expected error")
        } catch {
            // Expected: cannot_conversation_with_self
        }
    }

    func testStartConversationRejectsHuman() async throws {
        // humanAgentIdはtype=humanのエージェント
        do {
            _ = try await mcpServer.callTool(
                name: "start_conversation",
                arguments: [
                    "session_token": sessionToken,
                    "target_agent_id": humanAgentId.value
                ]
            )
            XCTFail("Expected error")
        } catch {
            // Expected: cannot_start_conversation_with_human
        }
    }

    func testStartConversationRejectsOutsideProject() async throws {
        do {
            _ = try await mcpServer.callTool(
                name: "start_conversation",
                arguments: [
                    "session_token": sessionToken,
                    "target_agent_id": outsideAgentId.value
                ]
            )
            XCTFail("Expected error")
        } catch {
            // Expected: target_agent_not_in_project
        }
    }

    func testStartConversationRejectsDuplicate() async throws {
        // 1回目: 成功
        _ = try await mcpServer.callTool(
            name: "start_conversation",
            arguments: [
                "session_token": sessionToken,
                "target_agent_id": "agent-b"
            ]
        )

        // 2回目: 既にactive/pendingな会話があるため失敗
        do {
            _ = try await mcpServer.callTool(
                name: "start_conversation",
                arguments: [
                    "session_token": sessionToken,
                    "target_agent_id": "agent-b"
                ]
            )
            XCTFail("Expected error")
        } catch {
            // Expected: conversation_already_active
        }
    }

    func testStartConversationCreatesPendingPurpose() async throws {
        _ = try await mcpServer.callTool(
            name: "start_conversation",
            arguments: [
                "session_token": sessionToken,
                "target_agent_id": "agent-b",
                "purpose": "しりとり"
            ]
        )

        // PendingAgentPurposeが作成されたことを確認
        let pending = try pendingPurposeRepository.findByAgentId(AgentID("agent-b"))
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].purpose, .chat)
        XCTAssertNotNil(pending[0].conversationId)
    }
}
```

---

### 3.2 end_conversation ツール

#### テスト（RED）

```swift
final class EndConversationTests: XCTestCase {

    func testEndConversationToolDefinition() {
        let tool = ToolDefinitions.endConversation

        XCTAssertEqual(tool["name"] as? String, "end_conversation")
        if let schema = tool["inputSchema"] as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            XCTAssertTrue(required.contains("session_token"))
        }
    }

    func testEndConversationSuccess() async throws {
        // 会話を開始
        let startResult = try await mcpServer.callTool(
            name: "start_conversation",
            arguments: ["session_token": sessionToken, "target_agent_id": "agent-b"]
        )
        let convId = startResult["conversation_id"] as! String

        // 会話を終了
        let endResult = try await mcpServer.callTool(
            name: "end_conversation",
            arguments: [
                "session_token": sessionToken,
                "conversation_id": convId
            ]
        )

        XCTAssertTrue(endResult["success"] as? Bool ?? false)
        XCTAssertEqual(endResult["status"] as? String, "terminating")
    }

    func testEndConversationWithoutIdUsesActive() async throws {
        // 会話を開始してactiveにする
        // ...

        // conversation_idなしで終了（アクティブな会話を自動検出）
        let result = try await mcpServer.callTool(
            name: "end_conversation",
            arguments: ["session_token": sessionToken]
        )

        XCTAssertTrue(result["success"] as? Bool ?? false)
    }

    func testEndConversationRejectsNonParticipant() async throws {
        // agent-aとagent-bの会話を開始
        // agent-cのセッションで終了を試みる → 失敗
    }

    func testEndConversationRejectsNoActiveConversation() async throws {
        do {
            _ = try await mcpServer.callTool(
                name: "end_conversation",
                arguments: ["session_token": sessionToken]
            )
            XCTFail("Expected error")
        } catch {
            // Expected: no_active_conversation
        }
    }
}
```

---

### 3.3 send_message 拡張（conversationId自動付与）

#### テスト（RED）

```swift
final class SendMessageConversationTests: XCTestCase {

    func testSendMessageSetsConversationId() async throws {
        // 会話を開始
        let startResult = try await mcpServer.callTool(
            name: "start_conversation",
            arguments: ["session_token": sessionToken, "target_agent_id": "agent-b"]
        )
        let convId = startResult["conversation_id"] as! String

        // メッセージ送信
        let msgResult = try await mcpServer.callTool(
            name: "send_message",
            arguments: [
                "session_token": sessionToken,
                "target_agent_id": "agent-b",
                "content": "りんご"
            ]
        )

        // レスポンスにconversation_idが含まれる
        XCTAssertEqual(msgResult["conversation_id"] as? String, convId)

        // chat.jsonlに保存されたメッセージにconversationIdがある
        let messages = try chatRepository.findMessages(projectId: projectId, agentId: agentAId)
        XCTAssertEqual(messages[0].conversationId?.value, convId)
    }

    func testSendMessageWithoutConversationHasNilConversationId() async throws {
        // 会話を開始せずにメッセージ送信
        let result = try await mcpServer.callTool(
            name: "send_message",
            arguments: [
                "session_token": sessionToken,
                "target_agent_id": "agent-b",
                "content": "テスト"
            ]
        )

        // conversation_idはnilまたは存在しない
        XCTAssertNil(result["conversation_id"])
    }
}
```

---

## Phase 4: getNextAction 拡張

### 4.1 conversation_request

#### テスト（RED）

```swift
final class GetNextActionConversationTests: XCTestCase {

    func testGetNextActionReturnsConversationRequest() async throws {
        // agent-aがagent-bとの会話を開始
        _ = try await mcpServerA.callTool(
            name: "start_conversation",
            arguments: ["session_token": tokenA, "target_agent_id": "agent-b", "purpose": "しりとり"]
        )

        // agent-bがauthenticate後にget_next_actionを呼ぶ
        let result = try await mcpServerB.callTool(
            name: "get_next_action",
            arguments: ["session_token": tokenB]
        )

        XCTAssertEqual(result["action"] as? String, "conversation_request")
        XCTAssertNotNil(result["conversation_id"])
        XCTAssertEqual(result["from_agent_id"] as? String, "agent-a")
        XCTAssertEqual(result["purpose"] as? String, "しりとり")
    }

    func testConversationRequestUpdatesStateToActive() async throws {
        // 会話開始
        let startResult = try await mcpServerA.callTool(
            name: "start_conversation",
            arguments: ["session_token": tokenA, "target_agent_id": "agent-b"]
        )
        let convId = startResult["conversation_id"] as! String

        // agent-bがget_next_action
        _ = try await mcpServerB.callTool(
            name: "get_next_action",
            arguments: ["session_token": tokenB]
        )

        // 会話状態がactiveになっている
        let conv = try conversationRepository.findById(ConversationID(convId))
        XCTAssertEqual(conv?.state, .active)
    }
}
```

---

### 4.2 conversation_ended

#### テスト（RED）

```swift
func testGetNextActionReturnsConversationEnded() async throws {
    // 会話を開始してactive状態にする
    // ...

    // agent-aが終了
    _ = try await mcpServerA.callTool(
        name: "end_conversation",
        arguments: ["session_token": tokenA]
    )

    // agent-bがget_next_action
    let result = try await mcpServerB.callTool(
        name: "get_next_action",
        arguments: ["session_token": tokenB]
    )

    XCTAssertEqual(result["action"] as? String, "conversation_ended")
    XCTAssertEqual(result["ended_by"] as? String, "agent-a")
    XCTAssertEqual(result["reason"] as? String, "initiator_ended")
}

func testConversationEndedUpdatesStateToEnded() async throws {
    // 会話をterminatingにする
    // ...

    // get_next_actionで通知を受け取る
    _ = try await mcpServerB.callTool(
        name: "get_next_action",
        arguments: ["session_token": tokenB]
    )

    // 状態がendedになっている
    let conv = try conversationRepository.findById(convId)
    XCTAssertEqual(conv?.state, .ended)
}
```

---

### 4.3 タイムアウト

#### テスト（RED）

```swift
func testConversationActiveTimeout() async throws {
    // 環境変数でタイムアウトを5秒に設定
    setenv("CONVERSATION_ACTIVE_TIMEOUT_SECONDS", "5", 1)

    // 会話を開始してactiveにする
    // ...

    // 6秒待機
    try await Task.sleep(nanoseconds: 6_000_000_000)

    // get_next_action
    let result = try await mcpServerA.callTool(
        name: "get_next_action",
        arguments: ["session_token": tokenA]
    )

    XCTAssertEqual(result["action"] as? String, "conversation_ended")
    XCTAssertEqual(result["reason"] as? String, "timeout")
}
```

---

## Phase 5: 統合テスト（しりとりシナリオ）

### 5.1 5ターンしりとり

#### テスト（RED → GREEN）

```swift
final class ShiritoriIntegrationTests: XCTestCase {

    func testFiveTurnShiritori() async throws {
        // 1. Worker-Aが会話開始
        let startResult = try await mcpServerA.callTool(
            name: "start_conversation",
            arguments: ["session_token": tokenA, "target_agent_id": "agent-b", "purpose": "しりとり"]
        )
        let convId = startResult["conversation_id"] as! String

        // 2. Worker-Bがconversation_requestを受信
        let requestResult = try await mcpServerB.callTool(
            name: "get_next_action",
            arguments: ["session_token": tokenB]
        )
        XCTAssertEqual(requestResult["action"] as? String, "conversation_request")

        // 3. 5往復のしりとり
        let words = [
            ("りんご", "ごりら"),
            ("らっぱ", "ぱんだ"),
            ("だちょう", "うさぎ"),
            ("ぎんこう", "うま"),
            ("まくら", "らいおん")
        ]

        for (wordA, wordB) in words {
            // Worker-A送信
            _ = try await mcpServerA.callTool(
                name: "send_message",
                arguments: ["session_token": tokenA, "target_agent_id": "agent-b", "content": wordA]
            )

            // Worker-B受信＆応答
            _ = try await mcpServerB.callTool(
                name: "get_pending_messages",
                arguments: ["session_token": tokenB]
            )
            _ = try await mcpServerB.callTool(
                name: "respond_chat",
                arguments: ["session_token": tokenB, "target_agent_id": "agent-a", "content": wordB]
            )
        }

        // 4. Worker-Aが会話終了
        _ = try await mcpServerA.callTool(
            name: "end_conversation",
            arguments: ["session_token": tokenA]
        )

        // 5. Worker-Bがconversation_endedを受信
        let endedResult = try await mcpServerB.callTool(
            name: "get_next_action",
            arguments: ["session_token": tokenB]
        )
        XCTAssertEqual(endedResult["action"] as? String, "conversation_ended")

        // 6. 検証: 10メッセージすべてに同一conversationIdがある
        let messagesA = try chatRepository.findMessages(projectId: projectId, agentId: agentAId)
        let messagesB = try chatRepository.findMessages(projectId: projectId, agentId: agentBId)

        let allMessages = messagesA + messagesB
        let uniqueConvIds = Set(allMessages.compactMap { $0.conversationId?.value })
        XCTAssertEqual(uniqueConvIds.count, 1)
        XCTAssertEqual(uniqueConvIds.first, convId)

        // 7. 検証: 会話状態がended
        let conv = try conversationRepository.findById(ConversationID(convId))
        XCTAssertEqual(conv?.state, .ended)
    }
}
```

---

## 実装順序サマリー

| Step | Phase | 内容 | テスト | 実装 |
|------|-------|------|--------|------|
| 1 | Domain | Conversationエンティティテスト | RED | - |
| 2 | Domain | Conversationエンティティ実装 | GREEN | ✅ |
| 3 | Domain | ChatMessage拡張テスト | RED | - |
| 4 | Domain | ChatMessage拡張実装 | GREEN | ✅ |
| 5 | Domain | PendingAgentPurpose拡張テスト | RED | - |
| 6 | Domain | PendingAgentPurpose拡張実装 | GREEN | ✅ |
| 7 | Domain | ConversationRepositoryプロトコルテスト | RED | - |
| 8 | Domain | ConversationRepositoryプロトコル実装 | GREEN | ✅ |
| 9 | Infra | マイグレーションテスト | RED | - |
| 10 | Infra | マイグレーション実装 | GREEN | ✅ |
| 11 | Infra | ConversationRepositoryテスト | RED | - |
| 12 | Infra | ConversationRepository実装 | GREEN | ✅ |
| 13 | MCP | start_conversationテスト | RED | - |
| 14 | MCP | start_conversation実装 | GREEN | ✅ |
| 15 | MCP | end_conversationテスト | RED | - |
| 16 | MCP | end_conversation実装 | GREEN | ✅ |
| 17 | MCP | send_message拡張テスト | RED | - |
| 18 | MCP | send_message拡張実装 | GREEN | ✅ |
| 19 | MCP | getNextAction拡張テスト | RED | - |
| 20 | MCP | getNextAction拡張実装 | GREEN | ✅ |
| 21 | 統合 | しりとりシナリオテスト | RED | - |
| 22 | 統合 | 全機能統合 | GREEN | ✅ |

---

## テスト実行コマンド

```bash
# Domain層テスト
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:DomainTests/ConversationTests

# Infrastructure層テスト
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:InfrastructureTests/ConversationRepositoryTests

# MCPツールテスト
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:MCPServerTests/StartConversationTests \
  -only-testing:MCPServerTests/EndConversationTests \
  -only-testing:MCPServerTests/SendMessageConversationTests \
  -only-testing:MCPServerTests/GetNextActionConversationTests

# 統合テスト
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:MCPServerTests/ShiritoriIntegrationTests

# 全AIConversationテスト
xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' \
  -only-testing:DomainTests/ConversationTests \
  -only-testing:InfrastructureTests/ConversationRepositoryTests \
  -only-testing:MCPServerTests/AIConversationTests
```

---

## 関連ドキュメント

- [docs/design/AI_TO_AI_CONVERSATION.md](../design/AI_TO_AI_CONVERSATION.md) - 設計書
- [docs/usecase/UC016_AIToAIConversation.md](../usecase/UC016_AIToAIConversation.md) - ユースケース
