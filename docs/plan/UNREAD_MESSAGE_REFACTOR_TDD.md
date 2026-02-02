# 未読メッセージ判定リファクタリング - TDD実装計画

## 概要

未読メッセージの判定ロジックを「返信ベース」から「既読時刻ベース」に変更する。

### 現状の問題

- 現在: 「最後の返信より後のメッセージ」を未読と判定
- 問題: メッセージを読んだが返信しないケースで、永続的に未読扱いになる
- 影響: エージェントが不要に起動し続ける

### 変更後の動作

- 新方式: 「既読時刻より後のメッセージ」を未読と判定
- メッセージ取得時に自動で既読更新
- 返信の有無に依存しない

---

## 変更対象

| ファイル | 変更内容 |
|----------|----------|
| `ChatFileRepository.findUnreadMessages` | 既読時刻ベースのロジックに変更 |
| `PendingMessageIdentifier.identify` | 既読時刻を考慮（オプション引数追加） |
| `MCPServer.getPendingMessages` | メッセージ取得後に `markAsRead` 呼び出し |
| `RESTServer.getChatMessages` | メッセージ取得後に `markAsRead` 呼び出し |

---

## Phase 1: ChatFileRepository.findUnreadMessages のリファクタリング

### 1.1 RED: 失敗するテストを作成

**ファイル**: `Tests/InfrastructureTests/ChatFileRepositoryUnreadTests.swift`

```swift
import XCTest
@testable import Infrastructure
@testable import Domain

final class ChatFileRepositoryUnreadTests: XCTestCase {
    var repository: ChatFileRepository!
    var tempDir: URL!
    let myAgentId = AgentID(value: "my-agent")
    let otherAgentId = AgentID(value: "other-agent")
    let projectId = ProjectID(value: "test-project")

    override func setUp() {
        super.setUp()
        // テスト用一時ディレクトリ作成
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        // repository初期化...
    }

    override func tearDown() {
        // クリーンアップ
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - 既読時刻ベースの未読判定テスト

    /// テスト1: 既読時刻より後のメッセージのみが未読
    func testFindUnreadMessages_ReturnsOnlyMessagesAfterLastReadTime() throws {
        // Given: 3件のメッセージと既読時刻
        let msg1 = createMessage(id: "1", senderId: otherAgentId, createdAt: date("10:00"))
        let msg2 = createMessage(id: "2", senderId: otherAgentId, createdAt: date("10:05"))
        let msg3 = createMessage(id: "3", senderId: otherAgentId, createdAt: date("10:10"))
        saveMessages([msg1, msg2, msg3])

        // 10:07に既読 → msg1, msg2は既読、msg3は未読
        try repository.markAsRead(
            projectId: projectId,
            currentAgentId: myAgentId,
            senderAgentId: otherAgentId
        )
        // 既読時刻を10:07に手動設定（テスト用）
        setLastReadTime(for: otherAgentId, at: date("10:07"))

        // When
        let unread = try repository.findUnreadMessages(
            projectId: projectId,
            agentId: myAgentId
        )

        // Then: msg3のみが未読
        XCTAssertEqual(unread.count, 1)
        XCTAssertEqual(unread[0].id.value, "3")
    }

    /// テスト2: 既読時刻がない場合は全メッセージが未読
    func testFindUnreadMessages_AllUnreadWhenNoLastReadTime() throws {
        // Given: 2件のメッセージ、既読時刻なし
        let msg1 = createMessage(id: "1", senderId: otherAgentId, createdAt: date("10:00"))
        let msg2 = createMessage(id: "2", senderId: otherAgentId, createdAt: date("10:05"))
        saveMessages([msg1, msg2])
        // 既読時刻は設定しない

        // When
        let unread = try repository.findUnreadMessages(
            projectId: projectId,
            agentId: myAgentId
        )

        // Then: 全メッセージが未読
        XCTAssertEqual(unread.count, 2)
    }

    /// テスト3: 自分が送ったメッセージは未読対象外
    func testFindUnreadMessages_ExcludesOwnMessages() throws {
        // Given: 自分のメッセージと相手のメッセージ
        let msg1 = createMessage(id: "1", senderId: myAgentId, createdAt: date("10:00"))
        let msg2 = createMessage(id: "2", senderId: otherAgentId, createdAt: date("10:05"))
        saveMessages([msg1, msg2])

        // When
        let unread = try repository.findUnreadMessages(
            projectId: projectId,
            agentId: myAgentId
        )

        // Then: 相手のメッセージのみが未読
        XCTAssertEqual(unread.count, 1)
        XCTAssertEqual(unread[0].senderId, otherAgentId)
    }

    /// テスト4: 返信がなくても既読なら未読0件
    func testFindUnreadMessages_NoUnreadAfterMarkAsRead_EvenWithoutReply() throws {
        // Given: 相手からのメッセージ
        let msg1 = createMessage(id: "1", senderId: otherAgentId, createdAt: date("10:00"))
        saveMessages([msg1])

        // When: 返信せずに既読にする
        try repository.markAsRead(
            projectId: projectId,
            currentAgentId: myAgentId,
            senderAgentId: otherAgentId
        )

        // Then: 未読0件（返信していなくても）
        let unread = try repository.findUnreadMessages(
            projectId: projectId,
            agentId: myAgentId
        )
        XCTAssertTrue(unread.isEmpty)
    }

    /// テスト5: 複数の送信者の未読を正しく判定
    func testFindUnreadMessages_MultiplesSenders() throws {
        // Given: 2人の送信者からのメッセージ
        let sender1 = AgentID(value: "sender-1")
        let sender2 = AgentID(value: "sender-2")

        let msg1 = createMessage(id: "1", senderId: sender1, createdAt: date("10:00"))
        let msg2 = createMessage(id: "2", senderId: sender2, createdAt: date("10:05"))
        let msg3 = createMessage(id: "3", senderId: sender1, createdAt: date("10:10"))
        saveMessages([msg1, msg2, msg3])

        // sender1のみ既読にする
        try repository.markAsRead(
            projectId: projectId,
            currentAgentId: myAgentId,
            senderAgentId: sender1
        )

        // When
        let unread = try repository.findUnreadMessages(
            projectId: projectId,
            agentId: myAgentId
        )

        // Then: sender2のメッセージのみ未読
        XCTAssertEqual(unread.count, 1)
        XCTAssertEqual(unread[0].senderId, sender2)
    }

    // MARK: - Helper Methods

    private func createMessage(id: String, senderId: AgentID, createdAt: Date) -> ChatMessage {
        ChatMessage(
            id: ChatMessageID(value: id),
            senderId: senderId,
            receiverId: nil,
            content: "Test message \(id)",
            createdAt: createdAt
        )
    }

    private func date(_ time: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let base = Calendar.current.startOfDay(for: Date())
        let timeDate = formatter.date(from: time)!
        return Calendar.current.date(
            byAdding: .second,
            value: Int(timeDate.timeIntervalSince(Calendar.current.startOfDay(for: timeDate))),
            to: base
        )!
    }

    private func saveMessages(_ messages: [ChatMessage]) {
        // repository にメッセージを保存
    }

    private func setLastReadTime(for senderId: AgentID, at time: Date) {
        // テスト用に既読時刻を直接設定
    }
}
```

### 1.2 GREEN: テストが通る最小限の実装

**ファイル**: `Sources/Infrastructure/FileStorage/ChatFileRepository.swift`

```swift
/// Find unread messages based on last read times
/// Reference: docs/design/CHAT_FEATURE.md - Section 9.11
public func findUnreadMessages(projectId: ProjectID, agentId: AgentID) throws -> [ChatMessage] {
    let allMessages = try findMessages(projectId: projectId, agentId: agentId)
    let lastReadTimes = try getLastReadTimes(projectId: projectId, agentId: agentId)

    return allMessages.filter { message in
        // 自分が送ったメッセージは未読対象外
        guard message.senderId != agentId else { return false }

        // 送信者の既読時刻を取得
        let lastReadTime = lastReadTimes[message.senderId.value]

        // 既読時刻がない → 未読
        // メッセージ作成時刻 > 既読時刻 → 未読
        if let lastRead = lastReadTime {
            return message.createdAt > lastRead
        } else {
            return true
        }
    }
}
```

### 1.3 REFACTOR: リファクタリング

- 重複コードの抽出
- エラーハンドリングの改善
- ドキュメントコメントの追加

---

## Phase 2: PendingMessageIdentifier の更新

### 2.1 RED: 失敗するテストを作成

**ファイル**: `Tests/InfrastructureTests/PendingMessageIdentifierTests.swift` に追加

```swift
// MARK: - 既読時刻ベースのテスト

func testIdentify_WithLastReadTimes_ReturnsOnlyUnreadMessages() {
    // Given: メッセージと既読時刻
    let myAgentId = AgentID(value: "my-agent")
    let otherAgentId = AgentID(value: "other-agent")

    let messages = [
        createMessage(id: "1", senderId: otherAgentId, offset: 0),  // 10:00
        createMessage(id: "2", senderId: otherAgentId, offset: 5),  // 10:05
        createMessage(id: "3", senderId: otherAgentId, offset: 10), // 10:10
    ]

    // 10:07に既読
    let lastReadTimes = [otherAgentId.value: date(offset: 7)]

    // When
    let pending = PendingMessageIdentifier.identify(
        messages,
        agentId: myAgentId,
        lastReadTimes: lastReadTimes
    )

    // Then: msg3のみが未読
    XCTAssertEqual(pending.count, 1)
    XCTAssertEqual(pending[0].id.value, "3")
}

func testIdentify_WithoutLastReadTimes_FallsBackToReplyBased() {
    // Given: 既読時刻なし（後方互換性）
    let myAgentId = AgentID(value: "my-agent")
    let otherAgentId = AgentID(value: "other-agent")

    let messages = [
        createMessage(id: "1", senderId: otherAgentId, offset: 0),
        createMessage(id: "2", senderId: myAgentId, offset: 5),     // 自分の返信
        createMessage(id: "3", senderId: otherAgentId, offset: 10),
    ]

    // When: lastReadTimes を渡さない（デフォルト引数）
    let pending = PendingMessageIdentifier.identify(
        messages,
        agentId: myAgentId
    )

    // Then: 返信後のメッセージのみが未読（後方互換）
    XCTAssertEqual(pending.count, 1)
    XCTAssertEqual(pending[0].id.value, "3")
}
```

### 2.2 GREEN: 実装

**ファイル**: `Sources/Infrastructure/FileStorage/PendingMessageIdentifier.swift`

```swift
/// 未読メッセージを特定する
///
/// - Parameters:
///   - messages: 全メッセージ（時系列順）
///   - agentId: 自分のエージェントID（未読判定の基準）
///   - lastReadTimes: 送信者ID -> 最終既読時刻 のマッピング（オプション）
///   - limit: 返す未読メッセージの最大件数（nilの場合は全件）
/// - Returns: 未読の受信メッセージ（時系列順）
public static func identify(
    _ messages: [ChatMessage],
    agentId: AgentID,
    lastReadTimes: [String: Date] = [:],
    limit: Int? = nil
) -> [ChatMessage] {
    guard !messages.isEmpty else { return [] }

    let pendingMessages: [ChatMessage]

    if lastReadTimes.isEmpty {
        // 後方互換: 既読時刻がない場合は従来の返信ベースロジック
        pendingMessages = identifyByReply(messages, agentId: agentId)
    } else {
        // 新方式: 既読時刻ベース
        pendingMessages = identifyByLastReadTime(messages, agentId: agentId, lastReadTimes: lastReadTimes)
    }

    // limit が指定されている場合は最新のものに制限
    if let limit = limit, pendingMessages.count > limit {
        return Array(pendingMessages.suffix(limit))
    }

    return pendingMessages
}

/// 既読時刻ベースの未読判定
private static func identifyByLastReadTime(
    _ messages: [ChatMessage],
    agentId: AgentID,
    lastReadTimes: [String: Date]
) -> [ChatMessage] {
    messages.filter { message in
        guard message.senderId != agentId else { return false }

        if let lastRead = lastReadTimes[message.senderId.value] {
            return message.createdAt > lastRead
        } else {
            return true
        }
    }
}

/// 返信ベースの未読判定（後方互換）
private static func identifyByReply(
    _ messages: [ChatMessage],
    agentId: AgentID
) -> [ChatMessage] {
    // 既存のロジック
    let lastMyMessageIndex = messages.lastIndex { $0.senderId == agentId }

    if let lastMyMessageIndex = lastMyMessageIndex {
        return messages.suffix(from: lastMyMessageIndex + 1)
            .filter { $0.senderId != agentId }
    } else {
        return messages.filter { $0.senderId != agentId }
    }
}
```

---

## Phase 3: MCPServer.getPendingMessages の更新

### 3.1 RED: 失敗するテストを作成

**ファイル**: `Tests/MCPServerTests/GetPendingMessagesTests.swift`

```swift
/// テスト: get_pending_messages 呼び出し後に既読が更新される
func testGetPendingMessages_MarksMessagesAsRead() throws {
    // Given: 未読メッセージあり
    let session = createChatSession(agentId: "worker-1", projectId: "prj-1")
    let message = createMessageFrom(senderId: "owner-1", content: "Hello")
    saveMessage(message, to: session)

    // When: get_pending_messages を呼び出し
    let result1 = try server.handleToolCall(
        name: "get_pending_messages",
        arguments: [:],
        session: session
    )

    // Then: 未読メッセージが返される
    let pending1 = extractPendingMessages(from: result1)
    XCTAssertEqual(pending1.count, 1)

    // When: 再度呼び出し
    let result2 = try server.handleToolCall(
        name: "get_pending_messages",
        arguments: [:],
        session: session
    )

    // Then: 既読になっているので未読0件
    let pending2 = extractPendingMessages(from: result2)
    XCTAssertTrue(pending2.isEmpty)
}

/// テスト: 新しいメッセージが来たら再度未読になる
func testGetPendingMessages_NewMessageBecomesUnread() throws {
    // Given: 既読状態
    let session = createChatSession(agentId: "worker-1", projectId: "prj-1")
    let message1 = createMessageFrom(senderId: "owner-1", content: "Hello")
    saveMessage(message1, to: session)

    // 一度取得して既読にする
    _ = try server.handleToolCall(
        name: "get_pending_messages",
        arguments: [:],
        session: session
    )

    // When: 新しいメッセージが来る
    let message2 = createMessageFrom(senderId: "owner-1", content: "Are you there?")
    saveMessage(message2, to: session)

    // Then: 新しいメッセージのみ未読
    let result = try server.handleToolCall(
        name: "get_pending_messages",
        arguments: [:],
        session: session
    )
    let pending = extractPendingMessages(from: result)
    XCTAssertEqual(pending.count, 1)
    XCTAssertEqual(pending[0]["content"] as? String, "Are you there?")
}
```

### 3.2 GREEN: 実装

**ファイル**: `Sources/MCPServer/MCPServer.swift` の `getPendingMessages` メソッド

```swift
private func getPendingMessages(session: AgentSession) throws -> [String: Any] {
    // 1. 全メッセージを取得
    let allMessages = try chatRepository.findMessages(
        projectId: session.projectId,
        agentId: session.agentId
    )

    // 2. 全送信者を既読に更新（取得 = 既読）
    let senderIds = Set(allMessages.filter { $0.senderId != session.agentId }.map { $0.senderId })
    for senderId in senderIds {
        try chatRepository.markAsRead(
            projectId: session.projectId,
            currentAgentId: session.agentId,
            senderAgentId: senderId
        )
    }

    // 3. 既読時刻を取得して未読判定
    let lastReadTimes = try chatRepository.getLastReadTimes(
        projectId: session.projectId,
        agentId: session.agentId
    )

    // 4. PendingMessageIdentifier で分離
    let result = PendingMessageIdentifier.separateContextAndPending(
        allMessages,
        agentId: session.agentId,
        lastReadTimes: lastReadTimes,
        contextLimit: PendingMessageIdentifier.defaultContextLimit,
        pendingLimit: PendingMessageIdentifier.defaultPendingLimit
    )

    // 5. レスポンス構築
    // ...
}
```

---

## Phase 4: RESTServer.getChatMessages の更新

### 4.1 RED: 失敗するテストを作成

**ファイル**: `Tests/RESTServerTests/ChatMessagesTests.swift`

```swift
/// テスト: GET /chat/messages 呼び出し後に既読が更新される
func testGetChatMessages_MarksMessagesAsRead() async throws {
    // Given: currentAgent=owner-1, targetAgent=worker-1 のチャット
    let currentAgentId = "owner-1"
    let targetAgentId = "worker-1"
    let projectId = "prj-1"

    // worker-1からのメッセージを保存
    let message = createMessage(senderId: targetAgentId, content: "Task completed")
    await saveMessage(message, projectId: projectId, agentId: currentAgentId)

    // When: メッセージ取得
    let response1 = try await app.test(.GET,
        "/api/projects/\(projectId)/agents/\(targetAgentId)/chat/messages",
        headers: authHeaders(for: currentAgentId)
    )
    XCTAssertEqual(response1.status, .ok)

    // Then: 未読カウントが0になる
    let unreadResponse = try await app.test(.GET,
        "/api/projects/\(projectId)/unread-counts",
        headers: authHeaders(for: currentAgentId)
    )
    let unreadCounts = try unreadResponse.content.decode(UnreadCountsResponse.self)
    XCTAssertEqual(unreadCounts.counts[targetAgentId], nil) // 0件なのでキーがない
}

/// テスト: ポーリングでも既読が更新される
func testGetChatMessages_PollingUpdatesReadStatus() async throws {
    // Given: 既読状態
    let currentAgentId = "owner-1"
    let targetAgentId = "worker-1"
    let projectId = "prj-1"

    // 初回取得で既読にする
    _ = try await app.test(.GET,
        "/api/projects/\(projectId)/agents/\(targetAgentId)/chat/messages",
        headers: authHeaders(for: currentAgentId)
    )

    // When: 新しいメッセージが来る
    let newMessage = createMessage(senderId: targetAgentId, content: "Update")
    await saveMessage(newMessage, projectId: projectId, agentId: currentAgentId)

    // When: ポーリング（after パラメータ付き）
    _ = try await app.test(.GET,
        "/api/projects/\(projectId)/agents/\(targetAgentId)/chat/messages?after=\(newMessage.id.value)",
        headers: authHeaders(for: currentAgentId)
    )

    // Then: 新しいメッセージも既読になる
    let unreadResponse = try await app.test(.GET,
        "/api/projects/\(projectId)/unread-counts",
        headers: authHeaders(for: currentAgentId)
    )
    let unreadCounts = try unreadResponse.content.decode(UnreadCountsResponse.self)
    XCTAssertEqual(unreadCounts.counts[targetAgentId], nil) // 0件
}
```

### 4.2 GREEN: 実装

**ファイル**: `Sources/RESTServer/RESTServer.swift` の `getChatMessages` メソッド

```swift
private func getChatMessages(request: Request, context: AuthenticatedContext) async throws -> Response {
    guard let currentAgentId = context.agentId else {
        return errorResponse(status: .unauthorized, message: "Not authenticated")
    }

    // パラメータ抽出
    guard let projectIdStr = context.parameters.get("projectId"),
          let agentIdStr = context.parameters.get("agentId") else {
        return errorResponse(status: .badRequest, message: "Missing project or agent ID")
    }

    let projectId = ProjectID(value: projectIdStr)
    let targetAgentId = AgentID(value: agentIdStr)

    // アクセス権限チェック
    guard try canChatWithAgent(currentAgentId: currentAgentId, targetAgentId: targetAgentId, projectId: projectId) else {
        return errorResponse(status: .forbidden, message: "Cannot access this agent's chat")
    }

    do {
        // 1. メッセージ取得
        let page = try chatRepository.findMessagesWithCursor(
            projectId: projectId,
            agentId: currentAgentId,  // 自分のストレージから取得
            limit: limit,
            after: afterId,
            before: beforeId
        )

        // 2. 対象エージェントからのメッセージを既読に更新
        //    （チャットパネルを開いている = そのエージェントのメッセージを見ている）
        try chatRepository.markAsRead(
            projectId: projectId,
            currentAgentId: currentAgentId,
            senderAgentId: targetAgentId
        )

        // 3. レスポンス構築
        // ...
    } catch {
        debugLog("Failed to get chat messages: \(error)")
        return errorResponse(status: .internalServerError, message: "Failed to retrieve messages")
    }
}
```

---

## Phase 5: WorkDetectionService の統合テスト

### 5.1 RED: 失敗するテストを作成

**ファイル**: `Tests/UseCaseTests/WorkDetectionServiceTests.swift` に追加

```swift
// MARK: - 既読時刻ベースの統合テスト

/// テスト: 既読後は hasChatWork が false を返す（返信不要）
func testHasChatWork_ReturnsFalse_AfterMarkAsRead_WithoutReply() throws {
    // Given: 未読メッセージあり
    let message = ChatMessage(
        id: ChatMessageID(value: UUID().uuidString),
        senderId: AgentID(value: "other-agent"),
        receiverId: testAgentId,
        content: "Hello",
        createdAt: Date()
    )
    chatRepo.setUnreadMessages(testProjectId, testAgentId, [message])

    // 最初は仕事あり
    XCTAssertTrue(try workService.hasChatWork(agentId: testAgentId, projectId: testProjectId))

    // When: 既読にする（返信せず）
    chatRepo.markAsRead(testProjectId, testAgentId, senderId: AgentID(value: "other-agent"))

    // Then: 仕事なし（返信していなくても）
    XCTAssertFalse(try workService.hasChatWork(agentId: testAgentId, projectId: testProjectId))
}
```

---

## 実行順序

1. **Phase 1**: `ChatFileRepository.findUnreadMessages` の変更
   - 既存テストの修正が必要な場合あり
   - 影響範囲が最も大きいため最初に実施

2. **Phase 2**: `PendingMessageIdentifier` の変更
   - Phase 1 に依存
   - オプション引数追加で後方互換性を維持

3. **Phase 3**: `MCPServer.getPendingMessages` の変更
   - Phase 1, 2 に依存
   - AIエージェントの動作に影響

4. **Phase 4**: `RESTServer.getChatMessages` の変更
   - Phase 1 に依存
   - Web UIの動作に影響

5. **Phase 5**: 統合テスト
   - 全フェーズ完了後に実施
   - エンドツーエンドの動作確認

---

## 注意事項

### 後方互換性

- `PendingMessageIdentifier.identify` の `lastReadTimes` はオプション引数
- 既存の呼び出し元は変更不要

### マイグレーション

- 既存の `last_read.json` がない場合、全メッセージが未読扱い
- 初回の `get_pending_messages` または `GET /chat/messages` 呼び出しで既読が設定される
- 特別なマイグレーション処理は不要

### テスト実行コマンド

```bash
# Phase 1 のテスト
swift test --filter ChatFileRepositoryUnreadTests

# Phase 2 のテスト
swift test --filter PendingMessageIdentifierTests

# Phase 3 のテスト
swift test --filter GetPendingMessagesTests

# Phase 4 のテスト
swift test --filter ChatMessagesTests

# 全テスト
swift test
```

---

## 完了条件

- [ ] 全テストがパス
- [ ] 既存のテストが壊れていない
- [ ] Web UIでチャットパネルを開くと既読になる
- [ ] AIエージェントが `get_pending_messages` 呼び出し後に既読になる
- [ ] 返信なしで既読にした場合、エージェントが再起動しない
