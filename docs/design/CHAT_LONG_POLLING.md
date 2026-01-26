# 設計書: チャット機能 Long Polling 実装

## 概要

チャット機能における `get_next_action` のポーリング頻度を削減するため、サーバーサイドでの待機（Long Polling）を導入する。これにより、Gemini API のレート制限を回避しつつ、リアルタイムなチャット体験を維持する。

## 問題

### 現状の問題

**症状**: チャットセッション開始後、約30秒でエージェントプロセスが終了し「準備中」状態に戻る

**根本原因**: Gemini API レート制限
```log
Attempt 1 failed: You have exhausted your capacity on this model. Your quota will reset after 2s.
```

**原因分析**:
1. エージェントは `get_next_action` を短い間隔（約3秒）でポーリング
2. 各ポーリングは Gemini API を消費
3. レート制限に到達 → リトライ → さらに負荷 → 最終的にプロセス終了

### 解決アプローチ: Long Polling

**概念**: サーバーが応答を保持し、データが利用可能になるかタイムアウトするまで待機

**効果**:
- API 呼び出し: 10回/30秒 → 1回/30秒
- エージェントは「ツール結果待ち」状態 = API 呼び出しなし
- レート制限を大幅に回避

---

## テストファースト実装計画

### Phase 1: MCPServer 待機ロジック

#### テスト 1.1: 新しいメッセージがない場合の待機

```swift
// Tests/MCPServerTests/LongPollingTests.swift

func testGetNextAction_WaitsForMessageWhenNoneAvailable() async throws {
    // Arrange
    let server = createTestMCPServer()
    let agentId = "test-agent"
    let projectId = "test-project"

    // チャットセッションをセットアップ（メッセージなし）
    try await setupChatSession(server: server, agentId: agentId, projectId: projectId)

    // Act
    let startTime = Date()
    let params: [String: JSONValue] = [
        "session_id": .string("test-session"),
        "timeout_seconds": .number(5)  // テスト用に短いタイムアウト
    ]
    let result = try await server.handleGetNextAction(params: params)
    let elapsedTime = Date().timeIntervalSince(startTime)

    // Assert
    XCTAssertGreaterThanOrEqual(elapsedTime, 4.5)  // 少なくとも4.5秒待機
    XCTAssertLessThan(elapsedTime, 6.0)  // タイムアウト + バッファ以内
    XCTAssertEqual(result.action, "wait")  // 新しいメッセージなし
}
```

**実装**:
```swift
// Sources/MCPServer/MCPServer.swift

private func handleGetNextAction(params: [String: JSONValue]) async throws -> GetNextActionResult {
    let sessionId = try extractSessionId(from: params)
    let timeoutSeconds = extractTimeout(from: params, default: 30)

    let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

    // Long Polling: メッセージが来るかタイムアウトまで待機
    while Date() < deadline {
        if let message = try checkForNewMessage(sessionId: sessionId) {
            return GetNextActionResult(action: "respond", message: message)
        }

        // 非同期で1秒待機（CPU負荷なし）
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    // タイムアウト: 再度ポーリングを要求
    return GetNextActionResult(action: "wait", message: nil)
}
```

#### テスト 1.2: 待機中にメッセージが到着した場合

```swift
func testGetNextAction_ReturnsImmediatelyWhenMessageArrives() async throws {
    // Arrange
    let server = createTestMCPServer()
    let agentId = "test-agent"
    let projectId = "test-project"

    try await setupChatSession(server: server, agentId: agentId, projectId: projectId)

    // 2秒後にメッセージを送信するタスクをスケジュール
    Task {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        try await sendTestMessage(server: server, sessionId: "test-session", content: "Hello")
    }

    // Act
    let startTime = Date()
    let params: [String: JSONValue] = [
        "session_id": .string("test-session"),
        "timeout_seconds": .number(30)
    ]
    let result = try await server.handleGetNextAction(params: params)
    let elapsedTime = Date().timeIntervalSince(startTime)

    // Assert
    XCTAssertGreaterThanOrEqual(elapsedTime, 1.5)  // 少なくとも送信前に待機
    XCTAssertLessThan(elapsedTime, 4.0)  // タイムアウト前に応答
    XCTAssertEqual(result.action, "respond")
    XCTAssertEqual(result.message?.content, "Hello")
}
```

**実装** (通知ベース最適化):
```swift
// Sources/MCPServer/MCPServer.swift

/// セッションごとの待機中リクエストを管理
private var pendingRequests: [String: CheckedContinuation<ChatMessage?, Never>] = [:]
private let pendingRequestsLock = NSLock()

/// メッセージ送信時に待機中のリクエストを起こす
func notifyNewMessage(sessionId: String, message: ChatMessage) {
    pendingRequestsLock.lock()
    if let continuation = pendingRequests.removeValue(forKey: sessionId) {
        pendingRequestsLock.unlock()
        continuation.resume(returning: message)
    } else {
        pendingRequestsLock.unlock()
    }
}

private func waitForMessageOrTimeout(sessionId: String, timeout: TimeInterval) async -> ChatMessage? {
    return await withCheckedContinuation { continuation in
        pendingRequestsLock.lock()
        pendingRequests[sessionId] = continuation
        pendingRequestsLock.unlock()

        // タイムアウト処理
        Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            pendingRequestsLock.lock()
            if let cont = pendingRequests.removeValue(forKey: sessionId) {
                pendingRequestsLock.unlock()
                cont.resume(returning: nil)
            } else {
                pendingRequestsLock.unlock()
            }
        }
    }
}
```

#### テスト 1.3: セッション終了時の即座のリターン

```swift
func testGetNextAction_ReturnsImmediatelyWhenSessionEnds() async throws {
    // Arrange
    let server = createTestMCPServer()
    try await setupChatSession(server: server, agentId: "test-agent", projectId: "test-project")

    // 2秒後にセッション終了
    Task {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        try await server.endChatSession(sessionId: "test-session")
    }

    // Act
    let startTime = Date()
    let params: [String: JSONValue] = [
        "session_id": .string("test-session"),
        "timeout_seconds": .number(30)
    ]
    let result = try await server.handleGetNextAction(params: params)
    let elapsedTime = Date().timeIntervalSince(startTime)

    // Assert
    XCTAssertLessThan(elapsedTime, 5.0)  // タイムアウト前に応答
    XCTAssertEqual(result.action, "end_session")
}
```

---

### Phase 2: タイムアウト設定

#### テスト 2.1: デフォルトタイムアウト (30秒)

```swift
func testGetNextAction_DefaultTimeout() async throws {
    let server = createTestMCPServer()
    try await setupChatSession(server: server, agentId: "test-agent", projectId: "test-project")

    // パラメータにtimeoutを指定しない
    let params: [String: JSONValue] = [
        "session_id": .string("test-session")
    ]

    let startTime = Date()
    _ = try await server.handleGetNextAction(params: params)
    let elapsedTime = Date().timeIntervalSince(startTime)

    // デフォルト30秒タイムアウト
    XCTAssertGreaterThanOrEqual(elapsedTime, 29.0)
    XCTAssertLessThan(elapsedTime, 35.0)
}
```

#### テスト 2.2: カスタムタイムアウト

```swift
func testGetNextAction_CustomTimeout() async throws {
    let server = createTestMCPServer()
    try await setupChatSession(server: server, agentId: "test-agent", projectId: "test-project")

    let params: [String: JSONValue] = [
        "session_id": .string("test-session"),
        "timeout_seconds": .number(10)
    ]

    let startTime = Date()
    _ = try await server.handleGetNextAction(params: params)
    let elapsedTime = Date().timeIntervalSince(startTime)

    XCTAssertGreaterThanOrEqual(elapsedTime, 9.0)
    XCTAssertLessThan(elapsedTime, 15.0)
}
```

---

### Phase 3: 統合テスト (Pilot)

#### テスト 3.1: チャットセッション全体フロー

```typescript
// web-ui/e2e/pilot/tests/uc020-chat-long-polling.spec.ts

test.describe('UC020: Chat Long Polling', () => {
  test('Agent waits server-side for new messages', async ({ pilotContext }) => {
    const { agentManager, chatClient } = pilotContext;

    // Arrange: エージェントとチャットセッションを準備
    const agent = await agentManager.spawnAgent('Worker-01');
    const session = await chatClient.startChatSession(agent.id);

    // Act: メッセージを送信し、エージェントの応答を待つ
    const sendTime = Date.now();
    await chatClient.sendMessage(session.id, 'Hello, agent!');

    // エージェントからの応答を待機
    const response = await chatClient.waitForResponse(session.id, { timeout: 60000 });
    const responseTime = Date.now();

    // Assert
    expect(response).toBeTruthy();
    expect(response.content).toContain('Hello');

    // エージェントがレート制限に達していないことを確認
    // (ログにrate limit errorがないことを確認)
    const agentLogs = await agentManager.getAgentLogs(agent.id);
    expect(agentLogs).not.toContain('exhausted your capacity');
  });

  test('Multiple messages in sequence without rate limiting', async ({ pilotContext }) => {
    const { agentManager, chatClient } = pilotContext;

    const agent = await agentManager.spawnAgent('Worker-01');
    const session = await chatClient.startChatSession(agent.id);

    // 5回連続でメッセージを送信
    for (let i = 0; i < 5; i++) {
      await chatClient.sendMessage(session.id, `Message ${i + 1}`);
      const response = await chatClient.waitForResponse(session.id, { timeout: 60000 });
      expect(response).toBeTruthy();
    }

    // レート制限エラーがないことを確認
    const agentLogs = await agentManager.getAgentLogs(agent.id);
    expect(agentLogs).not.toContain('exhausted your capacity');
  });
});
```

---

## 実装ステップ

### Step 1: テスト作成 (RED)

1. `Tests/MCPServerTests/LongPollingTests.swift` を作成
2. 上記テスト 1.1, 1.2, 1.3 を実装
3. テスト実行 → すべて失敗を確認

### Step 2: 基本実装 (GREEN)

1. `MCPServer.swift` に Long Polling ロジックを追加
   - `handleGetNextAction` を async に変更
   - `Task.sleep` による待機ループ実装
2. テスト実行 → テスト 1.1 が通過を確認

### Step 3: 通知ベース最適化 (REFACTOR)

1. `pendingRequests` 管理を追加
2. `notifyNewMessage` を `sendMessage` から呼び出し
3. テスト 1.2 が通過を確認

### Step 4: セッション終了対応

1. `endChatSession` で待機中リクエストを解除
2. テスト 1.3 が通過を確認

### Step 5: タイムアウト設定

1. デフォルト/カスタムタイムアウトを実装
2. テスト 2.1, 2.2 が通過を確認

### Step 6: 統合テスト

1. Pilot テストを追加
2. 実際の Gemini エージェントで動作確認

---

## 技術詳細

### 非同期待機の仕組み

```
[Agent]          [MCP Server]           [Database]          [User/WebUI]
   |                   |                     |                    |
   |-- get_next_action |                     |                    |
   |    (timeout=30s)  |                     |                    |
   |                   |-- check messages -->|                    |
   |                   |<-- none ------------|                    |
   |                   |                     |                    |
   |                   |   [await Task.sleep]|                    |
   |                   |   (1秒ごとにチェック)|                    |
   |                   |                     |<-- sendMessage ----|
   |                   |                     |                    |
   |                   |<-- new message -----|                    |
   |<-- respond -------|                     |                    |
   |                   |                     |                    |
```

### Swiftでの非同期実装

```swift
// Task.sleep: CPUを消費せずに待機
try await Task.sleep(nanoseconds: 1_000_000_000)

// CheckedContinuation: 通知ベースの待機
await withCheckedContinuation { continuation in
    // 後でcontinuation.resume()で起こす
}
```

### 30秒タイムアウトの理由

1. **HTTP接続管理**: 長すぎるとHTTP接続がタイムアウト
2. **セッション終了検知**: 定期的な再接続で状態を確認
3. **バランス**: 短すぎ→API負荷、長すぎ→反応遅延

---

## 設定オプション

### coordinator.yaml への追加 (将来)

```yaml
ai_providers:
  gemini:
    cli_command: gemini
    cli_args:
      - "-y"
      - "-d"
    # Long Polling設定
    chat_polling:
      timeout_seconds: 30
      check_interval_ms: 1000
```

---

## リスクと対策

### リスク 1: HTTPタイムアウト
- **対策**: タイムアウトを30秒に制限、クライアント側も対応

### リスク 2: 待機中のメモリリーク
- **対策**: セッション終了時に確実にクリーンアップ

### リスク 3: 並行リクエスト
- **対策**: NSLockで`pendingRequests`を保護

---

## 参考

- [CHAT_FEATURE.md](./CHAT_FEATURE.md) - チャット機能全体設計
- [CHAT_TIMEOUT.md](./CHAT_TIMEOUT.md) - チャットタイムアウト設計
