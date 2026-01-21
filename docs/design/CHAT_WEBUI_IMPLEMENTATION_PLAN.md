# チャット機能 Web UI対応 - テストファースト実装プラン

## 概要

チャット機能をWeb UIから利用可能にするため、REST APIエンドポイントとフロントエンドコンポーネントを追加する。

**前提条件**:
- チャットファイル保存場所は既存のまま（`{project.workingDirectory}/.ai-pm/agents/{agent-id}/chat.jsonl`）
- ネイティブアプリのチャット機能は実装済み
- `ChatFileRepository`、`ProjectDirectoryManager` は既存

---

## データサイズ制限

| 用途 | 項目 | 制限値 | 備考 |
|------|------|--------|------|
| **REST API (Web UI)** | デフォルト取得件数 | 50件 | 初回読み込み |
| | 最大取得件数 | 200件 | `limit` パラメータ上限 |
| | ポーリング時 | 新着のみ | `after` パラメータ使用 |
| **MCP** | コンテキスト | 直近20件 | 文脈理解用 |
| | 未読メッセージ | 最大10件 | 応答対象 |
| | 合計 | 最大30件 | コンテキストウィンドウ考慮 |
| **共通** | メッセージ本文 | 最大4,000文字 | 送信時バリデーション |

---

## Phase 0: ドメイン/インフラ ユニットテスト

REST APIやMCPが依存する基盤ロジックのユニットテストを先に作成する。

### 0.1 ChatFileRepository テスト

**ファイル**: `Tests/InfrastructureTests/ChatFileRepositoryTests.swift`

```swift
final class ChatFileRepositoryTests: XCTestCase {

    var tempDirectory: URL!
    var sut: ChatFileRepository!

    override func setUp() {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        sut = ChatFileRepository(baseDirectory: tempDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - 基本操作

    func testSaveMessage_AppendsToFile() throws {
        // Given: 空のチャットファイル
        let projectId = ProjectID("project-1")
        let agentId = AgentID("agent-1")
        let message = ChatMessage(
            id: ChatMessageID("msg-1"),
            sender: .user,
            content: "Hello",
            createdAt: Date()
        )

        // When: メッセージを保存
        try sut.saveMessage(message, projectId: projectId, agentId: agentId)

        // Then: ファイルに追記されている
        let messages = try sut.findMessages(projectId: projectId, agentId: agentId)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].content, "Hello")
    }

    func testFindMessages_ReturnsChronologicalOrder() throws {
        // Given: 複数のメッセージを異なる時間で保存
        // When: findMessages を呼び出す
        // Then: 古い順に並んでいる
    }

    func testFindMessages_EmptyFile_ReturnsEmptyArray() throws {
        // Given: 存在しないチャットファイル
        // When: findMessages を呼び出す
        // Then: 空配列が返る（エラーではない）
    }

    func testFindMessages_CorruptedLine_SkipsAndContinues() throws {
        // Given: 一部の行が壊れているJSONLファイル
        // When: findMessages を呼び出す
        // Then: 壊れた行はスキップし、他のメッセージは取得できる
    }

    // MARK: - ページネーション

    func testFindMessages_WithLimit_ReturnsLimitedCount() throws {
        // Given: 100件のメッセージ
        // When: limit=50 で取得
        // Then: 50件のみ返る
    }

    func testFindMessages_WithAfter_ReturnsMessagesAfterCursor() throws {
        // Given: msg-1, msg-2, msg-3 の3件
        // When: after="msg-1" で取得
        // Then: msg-2, msg-3 のみ返る
    }

    func testFindMessages_WithBefore_ReturnsMessagesBeforeCursor() throws {
        // Given: msg-1, msg-2, msg-3 の3件
        // When: before="msg-3" で取得
        // Then: msg-1, msg-2 のみ返る
    }

    // MARK: - コンテキスト取得（MCP用）

    func testGetMessagesWithContext_ReturnsContextAndPending() throws {
        // Given: 25件の会話（user/agent交互）、最後3件がuser
        let projectId = ProjectID("project-1")
        let agentId = AgentID("agent-1")
        // ... テストデータ作成

        // When: コンテキスト付きで取得
        let result = try sut.getMessagesWithContext(
            projectId: projectId,
            agentId: agentId,
            contextLimit: 20,
            pendingLimit: 10
        )

        // Then: context に20件、pending に3件
        XCTAssertEqual(result.contextMessages.count, 20)
        XCTAssertEqual(result.pendingMessages.count, 3)
        XCTAssertTrue(result.contextTruncated)
    }

    func testGetMessagesWithContext_AllRead_EmptyPending() throws {
        // Given: 最後のメッセージがagent（全て既読）
        // When: コンテキスト付きで取得
        // Then: pending は空
    }

    func testGetMessagesWithContext_ManyPending_LimitApplied() throws {
        // Given: 15件の未読メッセージ
        // When: pendingLimit=10 で取得
        // Then: 最新10件のみ pending に含まれる
    }
}
```

### 0.2 未読判定ロジック テスト

**ファイル**: `Tests/InfrastructureTests/PendingMessageIdentifierTests.swift`

```swift
final class PendingMessageIdentifierTests: XCTestCase {

    func testIdentifyPending_LastMessageIsUser_IsPending() {
        // Given: [user, agent, user]
        let messages = [
            ChatMessage(id: "1", sender: .user, content: "A", createdAt: date(0)),
            ChatMessage(id: "2", sender: .agent, content: "B", createdAt: date(1)),
            ChatMessage(id: "3", sender: .user, content: "C", createdAt: date(2)),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages)

        // Then: 最後のuserメッセージが未読
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].id, "3")
    }

    func testIdentifyPending_LastMessageIsAgent_NoPending() {
        // Given: [user, agent]
        let messages = [
            ChatMessage(id: "1", sender: .user, content: "A", createdAt: date(0)),
            ChatMessage(id: "2", sender: .agent, content: "B", createdAt: date(1)),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages)

        // Then: 未読なし
        XCTAssertTrue(pending.isEmpty)
    }

    func testIdentifyPending_ConsecutiveUserMessages_AllPending() {
        // Given: [user, agent, user, user, user]
        let messages = [
            ChatMessage(id: "1", sender: .user, content: "A", createdAt: date(0)),
            ChatMessage(id: "2", sender: .agent, content: "B", createdAt: date(1)),
            ChatMessage(id: "3", sender: .user, content: "C", createdAt: date(2)),
            ChatMessage(id: "4", sender: .user, content: "D", createdAt: date(3)),
            ChatMessage(id: "5", sender: .user, content: "E", createdAt: date(4)),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages)

        // Then: 連続するuserメッセージが全て未読
        XCTAssertEqual(pending.count, 3)
        XCTAssertEqual(pending.map { $0.id.value }, ["3", "4", "5"])
    }

    func testIdentifyPending_EmptyMessages_NoPending() {
        // Given: 空の配列
        let messages: [ChatMessage] = []

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages)

        // Then: 未読なし
        XCTAssertTrue(pending.isEmpty)
    }

    func testIdentifyPending_OnlyUserMessages_AllPending() {
        // Given: [user, user, user]（agentの応答なし）
        let messages = [
            ChatMessage(id: "1", sender: .user, content: "A", createdAt: date(0)),
            ChatMessage(id: "2", sender: .user, content: "B", createdAt: date(1)),
            ChatMessage(id: "3", sender: .user, content: "C", createdAt: date(2)),
        ]

        // When: 未読を判定
        let pending = PendingMessageIdentifier.identify(messages)

        // Then: 全て未読
        XCTAssertEqual(pending.count, 3)
    }

    private func date(_ offset: Int) -> Date {
        Date().addingTimeInterval(TimeInterval(offset))
    }
}
```

### 0.3 バリデーション テスト

**ファイル**: `Tests/DomainTests/ChatMessageValidatorTests.swift`

```swift
final class ChatMessageValidatorTests: XCTestCase {

    // MARK: - コンテンツ長

    func testValidate_EmptyContent_ReturnsError() {
        // Given: 空のコンテンツ
        let result = ChatMessageValidator.validate(content: "")

        // Then: エラー
        XCTAssertEqual(result, .invalid(.emptyContent))
    }

    func testValidate_WhitespaceOnly_ReturnsError() {
        // Given: 空白のみ
        let result = ChatMessageValidator.validate(content: "   \n\t  ")

        // Then: エラー
        XCTAssertEqual(result, .invalid(.emptyContent))
    }

    func testValidate_ContentAtLimit_ReturnsValid() {
        // Given: ちょうど4,000文字
        let content = String(repeating: "あ", count: 4000)

        // When: バリデーション
        let result = ChatMessageValidator.validate(content: content)

        // Then: 有効
        XCTAssertEqual(result, .valid)
    }

    func testValidate_ContentOverLimit_ReturnsError() {
        // Given: 4,001文字
        let content = String(repeating: "あ", count: 4001)

        // When: バリデーション
        let result = ChatMessageValidator.validate(content: content)

        // Then: エラー
        XCTAssertEqual(result, .invalid(.contentTooLong(maxLength: 4000, actualLength: 4001)))
    }

    // MARK: - limit パラメータ

    func testValidateLimit_WithinRange_ReturnsValid() {
        XCTAssertEqual(ChatMessageValidator.validateLimit(50), .valid)
        XCTAssertEqual(ChatMessageValidator.validateLimit(200), .valid)
        XCTAssertEqual(ChatMessageValidator.validateLimit(1), .valid)
    }

    func testValidateLimit_ExceedsMax_ReturnsClamped() {
        // Given: 300（最大200を超える）
        let result = ChatMessageValidator.validateLimit(300)

        // Then: 200に制限される
        XCTAssertEqual(result, .clamped(200))
    }

    func testValidateLimit_Zero_ReturnsDefault() {
        // Given: 0
        let result = ChatMessageValidator.validateLimit(0)

        // Then: デフォルト50
        XCTAssertEqual(result, .default(50))
    }

    func testValidateLimit_Negative_ReturnsDefault() {
        // Given: 負の値
        let result = ChatMessageValidator.validateLimit(-10)

        // Then: デフォルト50
        XCTAssertEqual(result, .default(50))
    }
}
```

### 0.4 実装

**ファイル**: `Sources/Domain/Validators/ChatMessageValidator.swift`

```swift
public enum ChatMessageValidator {
    public static let maxContentLength = 4000
    public static let defaultLimit = 50
    public static let maxLimit = 200

    public enum ValidationResult: Equatable {
        case valid
        case invalid(ValidationError)
    }

    public enum ValidationError: Equatable {
        case emptyContent
        case contentTooLong(maxLength: Int, actualLength: Int)
    }

    public enum LimitResult: Equatable {
        case valid
        case clamped(Int)
        case `default`(Int)
    }

    public static func validate(content: String) -> ValidationResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .invalid(.emptyContent)
        }
        if content.count > maxContentLength {
            return .invalid(.contentTooLong(maxLength: maxContentLength, actualLength: content.count))
        }
        return .valid
    }

    public static func validateLimit(_ limit: Int?) -> LimitResult {
        guard let limit = limit, limit > 0 else {
            return .default(defaultLimit)
        }
        if limit > maxLimit {
            return .clamped(maxLimit)
        }
        return .valid
    }
}
```

**ファイル**: `Sources/Infrastructure/FileStorage/PendingMessageIdentifier.swift`

```swift
public enum PendingMessageIdentifier {
    /// 最後のagent応答より後のuserメッセージを未読として返す
    public static func identify(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard !messages.isEmpty else { return [] }

        // 最後のagent応答のインデックスを探す
        let lastAgentIndex = messages.lastIndex { $0.sender == .agent }

        if let lastAgentIndex = lastAgentIndex {
            // agent応答より後のuserメッセージを返す
            return messages.suffix(from: lastAgentIndex + 1)
                .filter { $0.sender == .user }
        } else {
            // agent応答がない場合、全てのuserメッセージが未読
            return messages.filter { $0.sender == .user }
        }
    }
}
```

### 0.5 実行コマンド

```bash
# 全ユニットテスト実行
swift test --filter ChatFileRepositoryTests
swift test --filter PendingMessageIdentifierTests
swift test --filter ChatMessageValidatorTests

# または一括
swift test --filter "ChatFileRepository|PendingMessageIdentifier|ChatMessageValidator"
```

---

## Phase 1: REST API - メッセージ取得

### 1.1 REDテスト作成

**ファイル**: `Tests/RESTServerTests/ChatRoutesTests.swift`

```swift
final class ChatRoutesTests: XCTestCase {

    func testGetChatMessages_ReturnsMessages() async throws {
        // Given: プロジェクトとエージェントが存在し、チャットメッセージがある
        let projectId = "project-1"
        let agentId = "agent-1"
        // チャットファイルにテストデータを準備

        // When: GET /projects/{projectId}/agents/{agentId}/chat/messages
        let response = try await app.sendRequest(.GET, "/projects/\(projectId)/agents/\(agentId)/chat/messages")

        // Then: 200 OK でメッセージ配列が返る
        XCTAssertEqual(response.status, .ok)
        let result = try response.content.decode(ChatMessagesResponse.self)
        XCTAssertFalse(result.messages.isEmpty)
        XCTAssertEqual(result.messages[0].sender, "user")
    }

    func testGetChatMessages_WithAfterParameter_ReturnsNewMessagesOnly() async throws {
        // Given: 複数のメッセージが存在
        // When: GET /projects/{id}/agents/{id}/chat/messages?after=msg_02
        // Then: msg_02 より後のメッセージのみ返る
    }

    func testGetChatMessages_ProjectNotFound_Returns404() async throws {
        // Given: 存在しないプロジェクトID
        // When: GET /projects/invalid/agents/agent-1/chat/messages
        // Then: 404 Not Found
    }

    func testGetChatMessages_NoWorkingDirectory_Returns400() async throws {
        // Given: ワーキングディレクトリが未設定のプロジェクト
        // When: GET /projects/{id}/agents/{id}/chat/messages
        // Then: 400 Bad Request
    }

    func testGetChatMessages_LimitParameter_RespectsMaximum() async throws {
        // Given: 300件のメッセージが存在
        // When: GET ...?limit=300
        // Then: 最大200件のみ返る
    }

    func testGetChatMessages_DefaultLimit_Returns50() async throws {
        // Given: 100件のメッセージが存在
        // When: GET ... (limitパラメータなし)
        // Then: 50件返る、hasMore=true
    }
}
```

### 1.2 GREEN実装

**ファイル**: `Sources/RESTServer/Routes/ChatRoutes.swift`

```swift
import Vapor

struct ChatRoutes: RouteCollection {
    let chatRepository: ChatRepositoryProtocol
    let projectRepository: ProjectRepositoryProtocol

    func boot(routes: RoutesBuilder) throws {
        let chat = routes.grouped("projects", ":projectId", "agents", ":agentId", "chat")
        chat.get("messages", use: getMessages)
    }

    func getMessages(req: Request) async throws -> ChatMessagesResponse {
        // 実装
    }
}
```

**ファイル**: `Sources/RESTServer/DTOs/ChatDTOs.swift`

```swift
struct ChatMessagesResponse: Content {
    let messages: [ChatMessageDTO]
    let hasMore: Bool
}

struct ChatMessageDTO: Content {
    let id: String
    let sender: String
    let content: String
    let createdAt: Date
    let relatedTaskId: String?
}
```

### 1.3 実行コマンド

```bash
# テスト実行
swift test --filter ChatRoutesTests/testGetChatMessages
```

---

## Phase 2: REST API - メッセージ送信

### 2.1 REDテスト作成

**ファイル**: `Tests/RESTServerTests/ChatRoutesTests.swift`（追加）

```swift
func testPostChatMessage_CreatesMessage() async throws {
    // Given: プロジェクトとエージェントが存在
    let projectId = "project-1"
    let agentId = "agent-1"
    let requestBody = SendMessageRequest(content: "テストメッセージ", relatedTaskId: nil)

    // When: POST /projects/{projectId}/agents/{agentId}/chat/messages
    let response = try await app.sendRequest(
        .POST,
        "/projects/\(projectId)/agents/\(agentId)/chat/messages",
        body: requestBody
    )

    // Then: 201 Created で作成されたメッセージが返る
    XCTAssertEqual(response.status, .created)
    let result = try response.content.decode(ChatMessageDTO.self)
    XCTAssertEqual(result.content, "テストメッセージ")
    XCTAssertEqual(result.sender, "user")
    XCTAssertNotNil(result.id)
}

func testPostChatMessage_EmptyContent_Returns400() async throws {
    // Given: 空のコンテンツ
    let requestBody = SendMessageRequest(content: "", relatedTaskId: nil)

    // When: POST
    // Then: 400 Bad Request
}

func testPostChatMessage_ContentTooLong_Returns400() async throws {
    // Given: 4,001文字のコンテンツ
    let longContent = String(repeating: "あ", count: 4001)
    let requestBody = SendMessageRequest(content: longContent, relatedTaskId: nil)

    // When: POST
    // Then: 400 Bad Request with error "content_too_long"
}

func testPostChatMessage_ContentAtLimit_Succeeds() async throws {
    // Given: ちょうど4,000文字のコンテンツ
    let maxContent = String(repeating: "あ", count: 4000)
    let requestBody = SendMessageRequest(content: maxContent, relatedTaskId: nil)

    // When: POST
    // Then: 201 Created
}

func testPostChatMessage_WritesToFile() async throws {
    // Given: 空のチャットファイル
    // When: POST でメッセージ送信
    // Then: チャットファイルにJSONLとして追記されている
}
```

### 2.2 GREEN実装

**ファイル**: `Sources/RESTServer/Routes/ChatRoutes.swift`（追加）

```swift
func boot(routes: RoutesBuilder) throws {
    // ...
    chat.post("messages", use: postMessage)
}

func postMessage(req: Request) async throws -> Response {
    // 実装
}
```

**ファイル**: `Sources/RESTServer/DTOs/ChatDTOs.swift`（追加）

```swift
struct SendMessageRequest: Content {
    let content: String
    let relatedTaskId: String?
}
```

### 2.3 実行コマンド

```bash
swift test --filter ChatRoutesTests/testPostChatMessage
```

---

## Phase 3: MCP - get_pending_messages 更新

既存の `get_pending_messages` ツールを更新し、文脈理解用のコンテキストを含めて返すようにする。

### 3.1 REDテスト作成

**ファイル**: `Tests/MCPServerTests/ChatToolsTests.swift`

```swift
final class ChatToolsTests: XCTestCase {

    func testGetPendingMessages_ReturnsContextAndPending() async throws {
        // Given: 25件の会話履歴があり、最後の3件が未読
        // When: get_pending_messages を実行
        // Then: context_messages に直近20件、pending_messages に未読3件が含まれる
        let result = try await mcpServer.executeGetPendingMessages(session: session)

        XCTAssertEqual(result.contextMessages.count, 20)  // 最大20件
        XCTAssertEqual(result.pendingMessages.count, 3)   // 未読全件
        XCTAssertEqual(result.totalHistoryCount, 25)
        XCTAssertTrue(result.contextTruncated)
    }

    func testGetPendingMessages_NoPending_ReturnsEmptyPending() async throws {
        // Given: 全メッセージが既読
        // When: get_pending_messages を実行
        // Then: pending_messages は空、context_messages のみ返る
    }

    func testGetPendingMessages_ManyPending_LimitsTo10() async throws {
        // Given: 15件の未読メッセージ
        // When: get_pending_messages を実行
        // Then: pending_messages は最新10件のみ
    }

    func testGetPendingMessages_FewMessages_NoTruncation() async throws {
        // Given: 5件の会話履歴
        // When: get_pending_messages を実行
        // Then: context_truncated = false
    }

    func testGetPendingMessages_ContextIncludesAgentReplies() async throws {
        // Given: user→agent→user→agent のやり取り
        // When: get_pending_messages を実行
        // Then: context_messages に両者のメッセージが含まれる
    }
}
```

### 3.2 GREEN実装

**ファイル**: `Sources/MCPServer/Tools/ChatTools.swift`

```swift
struct GetPendingMessagesResponse: Codable {
    let contextMessages: [ChatMessageDTO]
    let pendingMessages: [ChatMessageDTO]
    let totalHistoryCount: Int
    let contextTruncated: Bool
}

func getPendingMessages(session: AgentSession) throws -> GetPendingMessagesResponse {
    let allMessages = try chatRepository.findMessages(
        projectId: session.projectId,
        agentId: session.agentId
    )

    // 未読メッセージを特定（最後のagent応答より後のuserメッセージ）
    let pendingMessages = identifyPendingMessages(allMessages)
        .suffix(10)  // 最大10件

    // コンテキスト（未読を除く直近20件）
    let contextEndIndex = allMessages.count - pendingMessages.count
    let contextMessages = allMessages
        .prefix(contextEndIndex)
        .suffix(20)  // 最大20件

    return GetPendingMessagesResponse(
        contextMessages: Array(contextMessages).map { $0.toDTO() },
        pendingMessages: Array(pendingMessages).map { $0.toDTO() },
        totalHistoryCount: allMessages.count,
        contextTruncated: contextEndIndex > 20
    )
}
```

### 3.3 実行コマンド

```bash
swift test --filter ChatToolsTests
```

---

## Phase 4: Web UI - APIクライアント

### 4.1 REDテスト作成

**ファイル**: `web-ui/src/api/__tests__/chatApi.test.ts`

```typescript
import { rest } from 'msw'
import { setupServer } from 'msw/node'
import { chatApi } from '../chatApi'

const server = setupServer()

beforeAll(() => server.listen())
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

describe('chatApi', () => {
  describe('getMessages', () => {
    it('returns messages for project and agent', async () => {
      // Given: APIがメッセージを返す
      server.use(
        rest.get('*/projects/:projectId/agents/:agentId/chat/messages', (req, res, ctx) => {
          return res(ctx.json({
            messages: [
              { id: 'msg-1', sender: 'user', content: 'Hello', createdAt: '2026-01-21T10:00:00Z' }
            ],
            hasMore: false
          }))
        })
      )

      // When: getMessages を呼び出す
      const result = await chatApi.getMessages('project-1', 'agent-1')

      // Then: メッセージが返る
      expect(result.messages).toHaveLength(1)
      expect(result.messages[0].content).toBe('Hello')
    })

    it('passes after parameter for polling', async () => {
      // Given/When/Then: after パラメータが正しく渡される
    })
  })

  describe('sendMessage', () => {
    it('posts message and returns created message', async () => {
      // Given: APIが成功レスポンスを返す
      server.use(
        rest.post('*/projects/:projectId/agents/:agentId/chat/messages', async (req, res, ctx) => {
          const body = await req.json()
          return res(ctx.status(201), ctx.json({
            id: 'msg-new',
            sender: 'user',
            content: body.content,
            createdAt: '2026-01-21T10:00:00Z'
          }))
        })
      )

      // When: sendMessage を呼び出す
      const result = await chatApi.sendMessage('project-1', 'agent-1', 'Test message')

      // Then: 作成されたメッセージが返る
      expect(result.id).toBe('msg-new')
      expect(result.content).toBe('Test message')
    })
  })
})
```

### 4.2 GREEN実装

**ファイル**: `web-ui/src/api/chatApi.ts`

```typescript
import { api } from './client'
import type { ChatMessage, ChatMessagesResponse } from '@/types'

export const chatApi = {
  async getMessages(
    projectId: string,
    agentId: string,
    options?: { after?: string; limit?: number }
  ): Promise<ChatMessagesResponse> {
    const params = new URLSearchParams()
    if (options?.after) params.set('after', options.after)
    if (options?.limit) params.set('limit', String(options.limit))

    const query = params.toString() ? `?${params}` : ''
    const result = await api.get<ChatMessagesResponse>(
      `/projects/${projectId}/agents/${agentId}/chat/messages${query}`
    )
    if (result.error) throw new Error(result.error.message)
    return result.data!
  },

  async sendMessage(
    projectId: string,
    agentId: string,
    content: string,
    relatedTaskId?: string
  ): Promise<ChatMessage> {
    const result = await api.post<ChatMessage>(
      `/projects/${projectId}/agents/${agentId}/chat/messages`,
      { content, relatedTaskId }
    )
    if (result.error) throw new Error(result.error.message)
    return result.data!
  }
}
```

### 4.3 実行コマンド

```bash
cd web-ui && npm test -- chatApi.test.ts
```

---

## Phase 5: Web UI - useChat フック

### 5.1 REDテスト作成

**ファイル**: `web-ui/src/hooks/__tests__/useChat.test.ts`

```typescript
import { renderHook, act, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useChat } from '../useChat'
import { chatApi } from '@/api/chatApi'

jest.mock('@/api/chatApi')
const mockChatApi = chatApi as jest.Mocked<typeof chatApi>

describe('useChat', () => {
  const wrapper = ({ children }) => (
    <QueryClientProvider client={new QueryClient()}>
      {children}
    </QueryClientProvider>
  )

  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('fetches messages on mount', async () => {
    // Given: APIがメッセージを返す
    mockChatApi.getMessages.mockResolvedValue({
      messages: [{ id: 'msg-1', sender: 'user', content: 'Hello', createdAt: new Date().toISOString() }],
      hasMore: false
    })

    // When: フックをレンダー
    const { result } = renderHook(() => useChat('project-1', 'agent-1'), { wrapper })

    // Then: メッセージが取得される
    await waitFor(() => {
      expect(result.current.messages).toHaveLength(1)
    })
  })

  it('sendMessage adds message to list', async () => {
    // Given: 送信APIが成功
    mockChatApi.getMessages.mockResolvedValue({ messages: [], hasMore: false })
    mockChatApi.sendMessage.mockResolvedValue({
      id: 'msg-new', sender: 'user', content: 'New message', createdAt: new Date().toISOString()
    })

    // When: sendMessage を呼び出す
    const { result } = renderHook(() => useChat('project-1', 'agent-1'), { wrapper })
    await act(async () => {
      await result.current.sendMessage('New message')
    })

    // Then: メッセージがリストに追加される
    expect(mockChatApi.sendMessage).toHaveBeenCalledWith('project-1', 'agent-1', 'New message', undefined)
  })

  it('polls for new messages', async () => {
    // Given: ポーリング間隔を短く設定
    // When: 時間経過
    // Then: getMessages が再度呼ばれる（after パラメータ付き）
  })
})
```

### 5.2 GREEN実装

**ファイル**: `web-ui/src/hooks/useChat.ts`

```typescript
import { useState, useEffect, useCallback } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { chatApi } from '@/api/chatApi'
import type { ChatMessage } from '@/types'

export function useChat(projectId: string, agentId: string) {
  const queryClient = useQueryClient()
  const queryKey = ['chat', projectId, agentId]

  const { data, isLoading } = useQuery({
    queryKey,
    queryFn: () => chatApi.getMessages(projectId, agentId),
    refetchInterval: 3000, // 3秒ポーリング
  })

  const sendMutation = useMutation({
    mutationFn: (content: string) => chatApi.sendMessage(projectId, agentId, content),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey })
    }
  })

  return {
    messages: data?.messages ?? [],
    isLoading,
    sendMessage: sendMutation.mutateAsync,
    isSending: sendMutation.isPending
  }
}
```

### 5.3 実行コマンド

```bash
cd web-ui && npm test -- useChat.test.ts
```

---

## Phase 6: Web UI - ChatPanel コンポーネント

### 6.1 REDテスト作成

**ファイル**: `web-ui/src/components/chat/__tests__/ChatPanel.test.tsx`

```typescript
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ChatPanel } from '../ChatPanel'
import { useChat } from '@/hooks/useChat'

jest.mock('@/hooks/useChat')
const mockUseChat = useChat as jest.MockedFunction<typeof useChat>

describe('ChatPanel', () => {
  const mockAgent = { id: 'agent-1', name: 'Test Agent', role: 'worker' }

  beforeEach(() => {
    mockUseChat.mockReturnValue({
      messages: [],
      isLoading: false,
      sendMessage: jest.fn(),
      isSending: false
    })
  })

  it('renders agent name in header', () => {
    render(<ChatPanel projectId="p1" agent={mockAgent} onClose={jest.fn()} />)
    expect(screen.getByText('Test Agent')).toBeInTheDocument()
  })

  it('displays messages', () => {
    mockUseChat.mockReturnValue({
      messages: [
        { id: 'msg-1', sender: 'user', content: 'Hello', createdAt: '2026-01-21T10:00:00Z' },
        { id: 'msg-2', sender: 'agent', content: 'Hi there!', createdAt: '2026-01-21T10:00:05Z' }
      ],
      isLoading: false,
      sendMessage: jest.fn(),
      isSending: false
    })

    render(<ChatPanel projectId="p1" agent={mockAgent} onClose={jest.fn()} />)

    expect(screen.getByText('Hello')).toBeInTheDocument()
    expect(screen.getByText('Hi there!')).toBeInTheDocument()
  })

  it('sends message on form submit', async () => {
    const mockSendMessage = jest.fn()
    mockUseChat.mockReturnValue({
      messages: [],
      isLoading: false,
      sendMessage: mockSendMessage,
      isSending: false
    })

    render(<ChatPanel projectId="p1" agent={mockAgent} onClose={jest.fn()} />)

    const input = screen.getByPlaceholderText(/メッセージを入力/i)
    await userEvent.type(input, 'Test message')

    const sendButton = screen.getByRole('button', { name: /送信/i })
    await userEvent.click(sendButton)

    expect(mockSendMessage).toHaveBeenCalledWith('Test message')
  })

  it('calls onClose when close button clicked', async () => {
    const mockOnClose = jest.fn()
    render(<ChatPanel projectId="p1" agent={mockAgent} onClose={mockOnClose} />)

    const closeButton = screen.getByRole('button', { name: /閉じる/i })
    await userEvent.click(closeButton)

    expect(mockOnClose).toHaveBeenCalled()
  })

  it('shows loading state', () => {
    mockUseChat.mockReturnValue({
      messages: [],
      isLoading: true,
      sendMessage: jest.fn(),
      isSending: false
    })

    render(<ChatPanel projectId="p1" agent={mockAgent} onClose={jest.fn()} />)
    expect(screen.getByTestId('chat-loading')).toBeInTheDocument()
  })
})
```

### 6.2 GREEN実装

**ファイル**: `web-ui/src/components/chat/ChatPanel.tsx`

```typescript
import { useState } from 'react'
import { useChat } from '@/hooks/useChat'
import { ChatMessage } from './ChatMessage'
import { ChatInput } from './ChatInput'
import type { Agent } from '@/types'

interface ChatPanelProps {
  projectId: string
  agent: Agent
  onClose: () => void
}

export function ChatPanel({ projectId, agent, onClose }: ChatPanelProps) {
  const { messages, isLoading, sendMessage, isSending } = useChat(projectId, agent.id)

  const handleSend = async (content: string) => {
    await sendMessage(content)
  }

  return (
    <div className="flex flex-col h-full bg-white border-l">
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b">
        <div>
          <h3 className="font-semibold">{agent.name}</h3>
          <span className="text-sm text-gray-500">{agent.role}</span>
        </div>
        <button onClick={onClose} aria-label="閉じる">×</button>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-4">
        {isLoading ? (
          <div data-testid="chat-loading">Loading...</div>
        ) : (
          messages.map(msg => <ChatMessage key={msg.id} message={msg} />)
        )}
      </div>

      {/* Input */}
      <ChatInput onSend={handleSend} disabled={isSending} />
    </div>
  )
}
```

### 6.3 実行コマンド

```bash
cd web-ui && npm test -- ChatPanel.test.tsx
```

---

## Phase 7: 統合テスト

### 7.1 E2Eテスト（Playwright）

**ファイル**: `web-ui/e2e/chat.spec.ts`

```typescript
import { test, expect } from '@playwright/test'

test.describe('Chat Feature', () => {
  test('user can send message to agent', async ({ page }) => {
    // Given: プロジェクトページにアクセス
    await page.goto('/projects/test-project')

    // When: エージェントアバターをクリック
    await page.click('[data-testid="agent-avatar-agent-1"]')

    // Then: チャットパネルが開く
    await expect(page.locator('[data-testid="chat-panel"]')).toBeVisible()

    // When: メッセージを入力して送信
    await page.fill('[data-testid="chat-input"]', 'Hello Agent!')
    await page.click('[data-testid="chat-send-button"]')

    // Then: メッセージが表示される
    await expect(page.locator('text=Hello Agent!')).toBeVisible()
  })

  test('chat panel shows message history', async ({ page }) => {
    // Given: 既存のチャット履歴がある状態
    // When: チャットパネルを開く
    // Then: 過去のメッセージが表示される
  })
})
```

---

## 実装順序サマリー

| Phase | テスト | 実装 | 確認コマンド |
|-------|--------|------|-------------|
| 0 | ChatFileRepositoryTests, PendingMessageIdentifierTests, ChatMessageValidatorTests | Repository, Validator | `swift test --filter "ChatFileRepository\|PendingMessageIdentifier\|ChatMessageValidator"` |
| 1 | ChatRoutesTests (GET) | ChatRoutes.swift | `swift test --filter testGetChatMessages` |
| 2 | ChatRoutesTests (POST) | ChatRoutes.swift | `swift test --filter testPostChatMessage` |
| 3 | ChatToolsTests | ChatTools.swift (MCP) | `swift test --filter ChatToolsTests` |
| 4 | chatApi.test.ts | chatApi.ts | `npm test -- chatApi.test.ts` |
| 5 | useChat.test.ts | useChat.ts | `npm test -- useChat.test.ts` |
| 6 | ChatPanel.test.tsx | ChatPanel.tsx | `npm test -- ChatPanel.test.tsx` |
| 7 | chat.spec.ts (E2E) | 統合確認 | `npx playwright test chat.spec.ts` |

---

## ファイル一覧

### 新規作成

| ファイル | Phase |
|----------|-------|
| `Tests/InfrastructureTests/ChatFileRepositoryTests.swift` | 0 |
| `Tests/InfrastructureTests/PendingMessageIdentifierTests.swift` | 0 |
| `Tests/DomainTests/ChatMessageValidatorTests.swift` | 0 |
| `Sources/Domain/Validators/ChatMessageValidator.swift` | 0 |
| `Sources/Infrastructure/FileStorage/PendingMessageIdentifier.swift` | 0 |
| `Tests/RESTServerTests/ChatRoutesTests.swift` | 1-2 |
| `Sources/RESTServer/Routes/ChatRoutes.swift` | 1-2 |
| `Sources/RESTServer/DTOs/ChatDTOs.swift` | 1-2 |
| `Tests/MCPServerTests/ChatToolsTests.swift` | 3 |
| `Sources/MCPServer/Tools/ChatTools.swift` | 3 |
| `web-ui/src/api/chatApi.ts` | 4 |
| `web-ui/src/api/__tests__/chatApi.test.ts` | 4 |
| `web-ui/src/hooks/useChat.ts` | 5 |
| `web-ui/src/hooks/__tests__/useChat.test.ts` | 5 |
| `web-ui/src/components/chat/ChatPanel.tsx` | 6 |
| `web-ui/src/components/chat/ChatMessage.tsx` | 6 |
| `web-ui/src/components/chat/ChatInput.tsx` | 6 |
| `web-ui/src/components/chat/__tests__/ChatPanel.test.tsx` | 6 |
| `web-ui/e2e/chat.spec.ts` | 7 |

### 修正

| ファイル | 変更内容 | Phase |
|----------|----------|-------|
| `Sources/Infrastructure/FileStorage/ChatFileRepository.swift` | getMessagesWithContext 追加 | 0 |
| `Sources/RESTServer/RESTServer.swift` | ChatRoutes 登録 | 1 |
| `Sources/MCPServer/MCPServer.swift` | get_pending_messages 更新 | 3 |
| `web-ui/src/types/index.ts` | ChatMessage 型追加 | 4 |
| `web-ui/src/pages/TaskBoardPage.tsx` | ChatPanel 統合 | 6 |
| `web-ui/src/mocks/handlers.ts` | チャットAPI モック追加 | 4 |

---

## 見積もり

| Phase | 内容 | 規模 |
|-------|------|------|
| 0 | ドメイン/インフラ ユニットテスト | M |
| 1 | REST GET API | S |
| 2 | REST POST API | S |
| 3 | MCP get_pending_messages 更新 | M |
| 4 | Web UI APIクライアント | S |
| 5 | useChat フック | M |
| 6 | ChatPanel コンポーネント | M |
| 7 | E2E統合テスト | S |

**合計**: 8フェーズ、中〜大規模（M-L）
