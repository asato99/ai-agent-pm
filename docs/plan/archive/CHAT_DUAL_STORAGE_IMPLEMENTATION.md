# Chat Dual Storage Implementation Plan

## 概要

チャット機能のストレージモデルを「双方向保存」方式に変更する実装計画。
送信者と受信者の両方のストレージにメッセージを保存し、`senderId` / `receiverId` で送受信を識別する。

**参照**: `docs/design/CHAT_FEATURE.md` - Section 2.3.1

## 背景

### 現在の実装

```swift
// 現在の ChatMessage
public struct ChatMessage {
    public let id: ChatMessageID
    public let sender: SenderType  // "user" | "agent" | "system"
    public let content: String
    ...
}
```

**問題点**:
- `sender: "user"` では、どの人間エージェント（Owner/Manager）からのメッセージか区別できない
- 人間↔人間、AI↔AI のチャットに対応できない

### 新しい設計

```swift
// 新しい ChatMessage
public struct ChatMessage {
    public let id: ChatMessageID
    public let senderId: AgentID      // 送信者のエージェントID
    public let receiverId: AgentID?   // 受信者のエージェントID（送信者のストレージのみ）
    public let content: String
    ...
}
```

**双方向保存ルール**:

| 書き込み先 | senderId | receiverId |
|------------|----------|------------|
| 送信者のストレージ | 送信者ID | 受信者ID（必須） |
| 受信者のストレージ | 送信者ID | なし |

---

## 実装フェーズ

### Phase 1: Domain Layer (テストファースト)

#### 1.1 ChatMessage エンティティ変更

**テスト (RED)**:
```swift
// Tests/DomainTests/ChatMessageTests.swift

func testChatMessageHasSenderId() {
    let message = ChatMessage(
        id: ChatMessageID("msg-1"),
        senderId: AgentID("owner-1"),
        receiverId: AgentID("worker-1"),
        content: "Hello"
    )

    XCTAssertEqual(message.senderId.value, "owner-1")
}

func testChatMessageReceiverIdIsOptional() {
    // 受信者のストレージでは receiverId は nil
    let message = ChatMessage(
        id: ChatMessageID("msg-1"),
        senderId: AgentID("owner-1"),
        receiverId: nil,
        content: "Hello"
    )

    XCTAssertNil(message.receiverId)
}

func testChatMessageIsSentByMe() {
    let myAgentId = AgentID("owner-1")
    let message = ChatMessage(
        id: ChatMessageID("msg-1"),
        senderId: AgentID("owner-1"),
        receiverId: AgentID("worker-1"),
        content: "Hello"
    )

    XCTAssertTrue(message.isSentBy(myAgentId))
    XCTAssertFalse(message.isReceivedBy(myAgentId))
}

func testChatMessageIsReceivedByMe() {
    let myAgentId = AgentID("worker-1")
    let message = ChatMessage(
        id: ChatMessageID("msg-1"),
        senderId: AgentID("owner-1"),
        receiverId: nil,  // 受信者のストレージでは nil
        content: "Hello"
    )

    XCTAssertFalse(message.isSentBy(myAgentId))
    XCTAssertTrue(message.isReceivedBy(myAgentId))
}
```

**実装 (GREEN)**:
```swift
// Sources/Domain/Entities/ChatMessage.swift

public struct ChatMessage: Identifiable, Equatable, Sendable, Codable {
    public let id: ChatMessageID
    public let senderId: AgentID
    public let receiverId: AgentID?
    public let content: String
    public let createdAt: Date
    public let relatedTaskId: TaskID?
    public let relatedHandoffId: HandoffID?

    public func isSentBy(_ agentId: AgentID) -> Bool {
        return senderId == agentId
    }

    public func isReceivedBy(_ agentId: AgentID) -> Bool {
        return senderId != agentId
    }
}
```

**削除対象**:
- `SenderType` enum（`user` | `agent` | `system`）
- `isFromUser`, `isFromAgent` computed properties

#### 1.2 ChatRepositoryProtocol 変更

**テスト (RED)**:
```swift
// Tests/DomainTests/ChatRepositoryProtocolTests.swift

// Protocol定義のテストは不要だが、Mock実装のテストを追加
func testSaveMessageToSenderAndReceiver() {
    let mockRepo = MockChatRepository()
    let message = ChatMessage(
        id: ChatMessageID("msg-1"),
        senderId: AgentID("owner-1"),
        receiverId: AgentID("worker-1"),
        content: "Hello"
    )

    try mockRepo.saveMessageDualWrite(
        message,
        projectId: ProjectID("proj-1"),
        senderAgentId: AgentID("owner-1"),
        receiverAgentId: AgentID("worker-1")
    )

    // 送信者のストレージを確認
    let senderMessages = try mockRepo.findMessages(
        projectId: ProjectID("proj-1"),
        agentId: AgentID("owner-1")
    )
    XCTAssertEqual(senderMessages.count, 1)
    XCTAssertEqual(senderMessages[0].receiverId?.value, "worker-1")

    // 受信者のストレージを確認
    let receiverMessages = try mockRepo.findMessages(
        projectId: ProjectID("proj-1"),
        agentId: AgentID("worker-1")
    )
    XCTAssertEqual(receiverMessages.count, 1)
    XCTAssertNil(receiverMessages[0].receiverId)
}
```

**実装 (GREEN)**:
```swift
// Sources/Domain/Repositories/ChatRepositoryProtocol.swift

public protocol ChatRepositoryProtocol: Sendable {
    // 既存（1つのストレージに保存）
    func findMessages(projectId: ProjectID, agentId: AgentID) throws -> [ChatMessage]
    func saveMessage(_ message: ChatMessage, projectId: ProjectID, agentId: AgentID) throws

    // 新規（双方向保存）
    func saveMessageDualWrite(
        _ message: ChatMessage,
        projectId: ProjectID,
        senderAgentId: AgentID,
        receiverAgentId: AgentID
    ) throws
}
```

---

### Phase 2: Infrastructure Layer (テストファースト)

#### 2.1 ChatFileRepository 双方向保存

**テスト (RED)**:
```swift
// Tests/InfrastructureTests/ChatFileRepositoryTests.swift

func testSaveMessageDualWrite() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Setup
    let mockProjectRepo = MockProjectRepository()
    mockProjectRepo.projects = [
        Project(id: ProjectID("proj-1"), name: "Test", workingDirectory: tempDir.path)
    ]
    let directoryManager = ProjectDirectoryManager()
    let chatRepo = ChatFileRepository(
        directoryManager: directoryManager,
        projectRepository: mockProjectRepo
    )

    let message = ChatMessage(
        id: ChatMessageID("msg-1"),
        senderId: AgentID("owner-1"),
        receiverId: AgentID("worker-1"),
        content: "Hello",
        createdAt: Date()
    )

    // Execute
    try chatRepo.saveMessageDualWrite(
        message,
        projectId: ProjectID("proj-1"),
        senderAgentId: AgentID("owner-1"),
        receiverAgentId: AgentID("worker-1")
    )

    // Verify sender storage
    let senderMessages = try chatRepo.findMessages(
        projectId: ProjectID("proj-1"),
        agentId: AgentID("owner-1")
    )
    XCTAssertEqual(senderMessages.count, 1)
    XCTAssertEqual(senderMessages[0].senderId.value, "owner-1")
    XCTAssertEqual(senderMessages[0].receiverId?.value, "worker-1")

    // Verify receiver storage
    let receiverMessages = try chatRepo.findMessages(
        projectId: ProjectID("proj-1"),
        agentId: AgentID("worker-1")
    )
    XCTAssertEqual(receiverMessages.count, 1)
    XCTAssertEqual(receiverMessages[0].senderId.value, "owner-1")
    XCTAssertNil(receiverMessages[0].receiverId)  // 受信者のストレージでは nil
}

func testFindUnreadMessages_NewFormat() throws {
    // senderId を使用した未読判定のテスト
    // 自分(worker-1)のストレージで、senderId != 自分ID かつ
    // 最後の自分のメッセージ以降のものが未読
}
```

**実装 (GREEN)**:
```swift
// Sources/Infrastructure/FileStorage/ChatFileRepository.swift

public func saveMessageDualWrite(
    _ message: ChatMessage,
    projectId: ProjectID,
    senderAgentId: AgentID,
    receiverAgentId: AgentID
) throws {
    lock.lock()
    defer { lock.unlock() }

    let workingDir = try getWorkingDirectory(projectId: projectId)

    // 1. 送信者のストレージに保存（receiverId あり）
    let senderFileURL = try directoryManager.getChatFilePath(
        workingDirectory: workingDir,
        agentId: senderAgentId
    )
    try appendMessageToFile(message, at: senderFileURL)

    // 2. 受信者のストレージに保存（receiverId なし）
    let receiverMessage = ChatMessage(
        id: message.id,
        senderId: message.senderId,
        receiverId: nil,  // 受信者のストレージでは nil
        content: message.content,
        createdAt: message.createdAt,
        relatedTaskId: message.relatedTaskId,
        relatedHandoffId: message.relatedHandoffId
    )
    let receiverFileURL = try directoryManager.getChatFilePath(
        workingDirectory: workingDir,
        agentId: receiverAgentId
    )
    try appendMessageToFile(receiverMessage, at: receiverFileURL)
}

public func findUnreadMessages(
    projectId: ProjectID,
    agentId: AgentID
) throws -> [ChatMessage] {
    let allMessages = try findMessages(projectId: projectId, agentId: agentId)

    // 自分が最後に送ったメッセージのインデックスを探す
    guard let lastSentIndex = allMessages.lastIndex(where: { $0.senderId == agentId }) else {
        // 自分からのメッセージがない場合、相手からのメッセージが全て未読
        return allMessages.filter { $0.senderId != agentId }
    }

    // 最後の自分のメッセージ以降の、相手からのメッセージを取得
    let messagesAfterLastSent = allMessages[(lastSentIndex + 1)...]
    return messagesAfterLastSent.filter { $0.senderId != agentId }
}
```

---

### Phase 3: REST API Layer (テストファースト)

#### 3.1 ChatDTO 変更

**テスト (RED)**:
```swift
// Tests/RESTServerTests/ChatDTOTests.swift

func testChatMessageDTOFromNewFormat() {
    let message = ChatMessage(
        id: ChatMessageID("msg-1"),
        senderId: AgentID("owner-1"),
        receiverId: AgentID("worker-1"),
        content: "Hello",
        createdAt: Date()
    )

    let dto = ChatMessageDTO(from: message)

    XCTAssertEqual(dto.senderId, "owner-1")
    XCTAssertEqual(dto.receiverId, "worker-1")
    XCTAssertNil(dto.sender)  // 旧フィールドは廃止
}

func testChatMessageDTOWithoutReceiverId() {
    let message = ChatMessage(
        id: ChatMessageID("msg-1"),
        senderId: AgentID("owner-1"),
        receiverId: nil,
        content: "Hello",
        createdAt: Date()
    )

    let dto = ChatMessageDTO(from: message)

    XCTAssertEqual(dto.senderId, "owner-1")
    XCTAssertNil(dto.receiverId)
}
```

**実装 (GREEN)**:
```swift
// Sources/RESTServer/DTOs/ChatDTO.swift

public struct ChatMessageDTO: Codable {
    public let id: String
    public let senderId: String
    public let receiverId: String?
    public let content: String
    public let createdAt: String
    public let relatedTaskId: String?

    public init(from message: ChatMessage) {
        self.id = message.id.value
        self.senderId = message.senderId.value
        self.receiverId = message.receiverId?.value
        self.content = message.content
        self.createdAt = ISO8601DateFormatter().string(from: message.createdAt)
        self.relatedTaskId = message.relatedTaskId?.value
    }
}
```

#### 3.2 ChatRoutes 変更

**テスト (RED)**:
```swift
// Tests/RESTServerTests/ChatRoutesTests.swift

func testPostMessage_DualWrite() async throws {
    // Setup: 送信者(owner-1) → 受信者(worker-1) へメッセージ送信
    let request = SendMessageRequest(content: "Hello", relatedTaskId: nil)

    // POST /projects/{projectId}/agents/{receiverAgentId}/chat/messages
    // Header: X-Agent-ID: owner-1 (送信者)
    let response = try await app.test(.POST, "/projects/proj-1/agents/worker-1/chat/messages") { req in
        req.headers.add(name: "X-Agent-ID", value: "owner-1")
        try req.content.encode(request)
    }

    XCTAssertEqual(response.status, .created)

    // Verify: 送信者と受信者の両方のストレージにメッセージが保存される
    let senderMessages = try chatRepo.findMessages(projectId: ProjectID("proj-1"), agentId: AgentID("owner-1"))
    let receiverMessages = try chatRepo.findMessages(projectId: ProjectID("proj-1"), agentId: AgentID("worker-1"))

    XCTAssertEqual(senderMessages.count, 1)
    XCTAssertEqual(receiverMessages.count, 1)
}
```

---

### Phase 4: Web UI Layer (テストファースト)

#### 4.1 型定義変更

**テスト (RED)**:
```typescript
// web-ui/src/types/chat.test.ts

import { ChatMessage } from './chat'

describe('ChatMessage type', () => {
  it('should have senderId instead of sender', () => {
    const message: ChatMessage = {
      id: 'msg-1',
      senderId: 'owner-1',
      receiverId: 'worker-1',
      content: 'Hello',
      createdAt: '2026-01-21T10:00:00Z',
    }

    expect(message.senderId).toBe('owner-1')
    expect(message.receiverId).toBe('worker-1')
    // @ts-expect-error sender should not exist
    expect(message.sender).toBeUndefined()
  })
})
```

**実装 (GREEN)**:
```typescript
// web-ui/src/types/chat.ts

export interface ChatMessage {
  id: string
  senderId: string
  receiverId?: string
  content: string
  createdAt: string // ISO8601形式
  relatedTaskId?: string
}
```

#### 4.2 ChatMessage コンポーネント変更

**テスト (RED)**:
```typescript
// web-ui/src/components/chat/ChatMessage.test.tsx

describe('ChatMessage', () => {
  it('renders user message on the right when senderId matches currentAgentId', () => {
    render(
      <ChatMessage
        message={{
          id: 'msg-1',
          senderId: 'owner-1',
          receiverId: 'worker-1',
          content: 'Hello',
          createdAt: '2026-01-21T10:00:00Z',
        }}
        currentAgentId="owner-1"
      />
    )

    // 自分が送ったメッセージは右側に表示
    expect(screen.getByTestId('chat-message')).toHaveClass('justify-end')
  })

  it('renders received message on the left when senderId differs from currentAgentId', () => {
    render(
      <ChatMessage
        message={{
          id: 'msg-1',
          senderId: 'worker-1',
          content: 'Hi there!',
          createdAt: '2026-01-21T10:00:00Z',
        }}
        currentAgentId="owner-1"
      />
    )

    // 相手からのメッセージは左側に表示
    expect(screen.getByTestId('chat-message')).toHaveClass('justify-start')
  })
})
```

**実装 (GREEN)**:
```tsx
// web-ui/src/components/chat/ChatMessage.tsx

interface ChatMessageProps {
  message: ChatMessageType
  currentAgentId: string
}

export function ChatMessage({ message, currentAgentId }: ChatMessageProps) {
  const isSentByMe = message.senderId === currentAgentId

  return (
    <div
      className={`flex mb-4 ${isSentByMe ? 'justify-end' : 'justify-start'}`}
      data-testid="chat-message"
    >
      {/* ... */}
    </div>
  )
}
```

#### 4.3 ChatPanel 変更

**テスト (RED)**:
```typescript
// web-ui/src/components/chat/ChatPanel.test.tsx

describe('ChatPanel', () => {
  it('passes currentAgentId to ChatMessage components', () => {
    // ChatPanel は currentAgentId を props で受け取り、
    // 子の ChatMessage に渡す
    render(
      <ChatPanel
        projectId="proj-1"
        receiverAgentId="worker-1"
        currentAgentId="owner-1"
        onClose={vi.fn()}
      />
    )

    // メッセージが正しい向きで表示されることを確認
    // ...
  })

  it('sends message with correct senderId and receiverId', async () => {
    const user = userEvent.setup()

    render(
      <ChatPanel
        projectId="proj-1"
        receiverAgentId="worker-1"
        currentAgentId="owner-1"
        onClose={vi.fn()}
      />
    )

    // メッセージ送信
    await user.type(screen.getByTestId('chat-input'), 'Hello')
    await user.click(screen.getByTestId('chat-send-button'))

    // API呼び出しを確認
    expect(mockSendMessage).toHaveBeenCalledWith({
      content: 'Hello',
      receiverId: 'worker-1',
    })
  })
})
```

---

### Phase 5: MCP Layer (テストファースト)

#### 5.1 get_pending_messages 変更

**テスト (RED)**:
```swift
// Tests/MCPServerTests/ChatToolsTests.swift

func testGetPendingMessages_ReturnsMyAgentId() async throws {
    // Setup: worker-1 のセッションで get_pending_messages を呼び出し
    let session = AgentSession(
        id: AgentSessionID("session-1"),
        token: "token",
        agentId: AgentID("worker-1"),
        projectId: ProjectID("proj-1"),
        purpose: "chat",
        expiresAt: Date().addingTimeInterval(3600),
        createdAt: Date()
    )

    let result = try await mcpServer.getPendingMessages(session: session)

    // my_agent_id が含まれることを確認
    XCTAssertEqual(result["my_agent_id"] as? String, "worker-1")
}

func testGetPendingMessages_ReturnsSenderIdFormat() async throws {
    // Setup: メッセージを作成
    let message = ChatMessage(
        id: ChatMessageID("msg-1"),
        senderId: AgentID("owner-1"),
        content: "Hello",
        createdAt: Date()
    )
    try chatRepo.saveMessage(message, projectId: ProjectID("proj-1"), agentId: AgentID("worker-1"))

    let session = AgentSession(/* worker-1 */)
    let result = try await mcpServer.getPendingMessages(session: session)

    let pendingMessages = result["pending_messages"] as! [[String: Any]]
    XCTAssertEqual(pendingMessages[0]["senderId"] as? String, "owner-1")
    XCTAssertNil(pendingMessages[0]["sender"])  // 旧フィールドは存在しない
}
```

#### 5.2 respond_chat 変更

**テスト (RED)**:
```swift
// Tests/MCPServerTests/ChatToolsTests.swift

func testRespondChat_RequiresReceiverId() async throws {
    let session = AgentSession(/* worker-1 */)

    // receiver_id なしで呼び出し → エラー
    do {
        _ = try await mcpServer.respondChat(
            session: session,
            content: "Hello",
            receiverId: nil
        )
        XCTFail("Should throw error")
    } catch {
        XCTAssertTrue(error.localizedDescription.contains("receiver_id"))
    }
}

func testRespondChat_DualWrite() async throws {
    let session = AgentSession(
        agentId: AgentID("worker-1"),
        projectId: ProjectID("proj-1"),
        /* ... */
    )

    _ = try await mcpServer.respondChat(
        session: session,
        content: "Response",
        receiverId: "owner-1"
    )

    // 送信者(worker-1)のストレージを確認
    let senderMessages = try chatRepo.findMessages(
        projectId: ProjectID("proj-1"),
        agentId: AgentID("worker-1")
    )
    XCTAssertEqual(senderMessages[0].senderId.value, "worker-1")
    XCTAssertEqual(senderMessages[0].receiverId?.value, "owner-1")

    // 受信者(owner-1)のストレージを確認
    let receiverMessages = try chatRepo.findMessages(
        projectId: ProjectID("proj-1"),
        agentId: AgentID("owner-1")
    )
    XCTAssertEqual(receiverMessages[0].senderId.value, "worker-1")
    XCTAssertNil(receiverMessages[0].receiverId)
}
```

---

## 実装ファイル一覧

### 修正対象

| レイヤー | ファイル | 変更内容 |
|---------|----------|----------|
| Domain | `Sources/Domain/Entities/ChatMessage.swift` | `sender` → `senderId`/`receiverId` |
| Domain | `Sources/Domain/Repositories/ChatRepositoryProtocol.swift` | `saveMessageDualWrite` 追加 |
| Infra | `Sources/Infrastructure/FileStorage/ChatFileRepository.swift` | 双方向保存実装 |
| REST | `Sources/RESTServer/DTOs/ChatDTO.swift` | DTO変更 |
| REST | `Sources/RESTServer/Routes/ChatRoutes.swift` | エンドポイント変更 |
| MCP | `Sources/MCPServer/Tools/ChatTools.swift` | ツール実装変更 |
| Web UI | `web-ui/src/types/chat.ts` | 型定義変更 |
| Web UI | `web-ui/src/components/chat/ChatMessage.tsx` | currentAgentId 対応 |
| Web UI | `web-ui/src/components/chat/ChatPanel.tsx` | props 変更 |
| Web UI | `web-ui/src/api/chatApi.ts` | API呼び出し変更 |

### テストファイル

| レイヤー | ファイル |
|---------|----------|
| Domain | `Tests/DomainTests/ChatMessageTests.swift` |
| Infra | `Tests/InfrastructureTests/ChatFileRepositoryTests.swift` |
| REST | `Tests/RESTServerTests/ChatDTOTests.swift` |
| REST | `Tests/RESTServerTests/ChatRoutesTests.swift` |
| MCP | `Tests/MCPServerTests/ChatToolsTests.swift` |
| Web UI | `web-ui/src/types/chat.test.ts` |
| Web UI | `web-ui/src/components/chat/ChatMessage.test.tsx` |
| Web UI | `web-ui/src/components/chat/ChatPanel.test.tsx` |

---

## 後方互換性

### マイグレーション不要

- 既存の chat.jsonl ファイルは読み込み時に変換
- `sender: "user"` → `senderId: (対象エージェントのparent ID)`
- `sender: "agent"` → `senderId: (対象エージェントID)`

```swift
// ChatFileRepository での後方互換対応
private func decodeMessage(from data: Data) throws -> ChatMessage {
    // 新形式を試す
    if let newMessage = try? decoder.decode(ChatMessageNewFormat.self, from: data) {
        return newMessage.toChatMessage()
    }

    // 旧形式にフォールバック
    let oldMessage = try decoder.decode(ChatMessageOldFormat.self, from: data)
    return oldMessage.toNewFormat(agentId: currentAgentId)
}
```

---

## 実装順序

1. **Phase 1**: Domain Layer
   - ChatMessage エンティティ変更
   - ChatRepositoryProtocol 変更
   - テスト追加

2. **Phase 2**: Infrastructure Layer
   - ChatFileRepository 双方向保存実装
   - 後方互換性対応
   - テスト追加

3. **Phase 3**: REST API Layer
   - ChatDTO 変更
   - ChatRoutes 変更
   - テスト追加

4. **Phase 4**: Web UI Layer
   - 型定義変更
   - コンポーネント変更
   - テスト追加

5. **Phase 5**: MCP Layer
   - get_pending_messages 変更
   - respond_chat 変更
   - テスト追加

---

## 完了条件

- [ ] 全テストが GREEN
- [ ] 既存の chat.jsonl が読み込み可能（後方互換性）
- [ ] 新規メッセージが双方向保存される
- [ ] Web UI で senderId ベースの表示が動作
- [ ] MCP ツールが新形式で動作
