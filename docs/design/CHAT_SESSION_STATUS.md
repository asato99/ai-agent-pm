# 設計書: チャットセッション状態表示の改善

## 概要

チャットパネルの送信ボタン状態を、より詳細なセッション状態に基づいて表示する。
現在の「送信可能」「準備中」の2状態から、「接続中」「接続済み」「セッション切れ」の3状態に拡張する。

## 問題

### 現状の問題

**症状**: チャットパネルで「準備中」表示が以下のすべてを表している
1. エージェントが起動中（接続中）
2. セッションがタイムアウトした（切れた）
3. エラーで接続できなかった

**ユーザー体験の問題**:
- 「準備中」が何を意味するか分からない
- 再接続が必要なのか、待てばいいのか判断できない

### 解決アプローチ: 3状態の明確化

| 状態 | 条件 | UIでの表示 |
|------|------|-----------|
| `disconnected` | chat用PendingAgentPurpose なし & chatセッションなし | 「再接続」ボタン |
| `connecting` | chat用PendingAgentPurpose あり & chatセッションなし | 「接続中...」(スピナー) |
| `connected` | chatセッションあり (state=active) | 「送信」ボタン |

---

## テストファースト実装計画

### Phase 1: バックエンド - API拡張

#### テスト 1.1: chatStatus フィールドの追加

```swift
// Tests/RESTServerTests/ChatSessionStatusTests.swift

func testAgentSessionsAPI_ReturnsChatStatusConnected() throws {
    // Arrange: エージェントにアクティブなchatセッションがある
    let session = AgentSession(agentId: testAgentId, projectId: testProjectId, purpose: .chat)
    try sessionRepository.save(session)

    // Act: API呼び出し
    let response = try app.sendRequest(.GET, "/api/projects/\(testProjectId.value)/agent-sessions")

    // Assert: chatStatus が "connected"
    let dto = try response.content.decode(AgentSessionCountsDTO.self)
    XCTAssertEqual(dto.agentSessions[testAgentId.value]?.chat.status, "connected")
}
```

#### テスト 1.2: connecting 状態の検出

```swift
func testAgentSessionsAPI_ReturnsChatStatusConnecting() throws {
    // Arrange: PendingAgentPurpose があるがセッションはない
    let pending = PendingAgentPurpose(agentId: testAgentId, projectId: testProjectId, purpose: .chat)
    try pendingAgentPurposeRepository.save(pending)
    // セッションは作成しない

    // Act: API呼び出し
    let response = try app.sendRequest(.GET, "/api/projects/\(testProjectId.value)/agent-sessions")

    // Assert: chatStatus が "connecting"
    let dto = try response.content.decode(AgentSessionCountsDTO.self)
    XCTAssertEqual(dto.agentSessions[testAgentId.value]?.chat.status, "connecting")
}
```

#### テスト 1.3: disconnected 状態の検出

```swift
func testAgentSessionsAPI_ReturnsChatStatusDisconnected() throws {
    // Arrange: PendingAgentPurpose もセッションもない
    // (何も作成しない)

    // Act: API呼び出し
    let response = try app.sendRequest(.GET, "/api/projects/\(testProjectId.value)/agent-sessions")

    // Assert: chatStatus が "disconnected"
    let dto = try response.content.decode(AgentSessionCountsDTO.self)
    XCTAssertEqual(dto.agentSessions[testAgentId.value]?.chat.status, "disconnected")
}
```

#### テスト 1.4: task は status を持たない

```swift
func testAgentSessionsAPI_TaskHasNoStatus() throws {
    // Arrange: taskセッションがある
    let session = AgentSession(agentId: testAgentId, projectId: testProjectId, purpose: .task)
    try sessionRepository.save(session)

    // Act: API呼び出し
    let response = try app.sendRequest(.GET, "/api/projects/\(testProjectId.value)/agent-sessions")

    // Assert: task には status がない（count のみ）
    let dto = try response.content.decode(AgentSessionCountsDTO.self)
    XCTAssertEqual(dto.agentSessions[testAgentId.value]?.task.count, 1)
    XCTAssertNil(dto.agentSessions[testAgentId.value]?.task.status)
}
```

---

### Phase 2: フロントエンド - 型定義とフック更新

#### テスト 2.1: useAgentSessions の chatStatus 取得

```typescript
// web-ui/src/hooks/useAgentSessions.test.ts

describe('useAgentSessions', () => {
  it('returns chatStatus for each agent', async () => {
    // Arrange: API モック
    server.use(
      rest.get('/api/projects/:projectId/agent-sessions', (req, res, ctx) => {
        return res(ctx.json({
          agentSessions: {
            'agt_001': {
              chat: { count: 1, status: 'connected' },
              task: { count: 0 }
            }
          }
        }))
      })
    )

    // Act
    const { result } = renderHook(() => useAgentSessions('prj_001'))
    await waitFor(() => expect(result.current.isLoading).toBe(false))

    // Assert
    expect(result.current.getChatStatus('agt_001')).toBe('connected')
  })

  it('returns "disconnected" when agent has no chat session', async () => {
    server.use(
      rest.get('/api/projects/:projectId/agent-sessions', (req, res, ctx) => {
        return res(ctx.json({
          agentSessions: {
            'agt_001': {
              chat: { count: 0, status: 'disconnected' },
              task: { count: 1 }
            }
          }
        }))
      })
    )

    const { result } = renderHook(() => useAgentSessions('prj_001'))
    await waitFor(() => expect(result.current.isLoading).toBe(false))

    expect(result.current.getChatStatus('agt_001')).toBe('disconnected')
  })
})
```

---

### Phase 3: フロントエンド - UI コンポーネント更新

#### テスト 3.1: ChatInput の状態別表示

```typescript
// web-ui/src/components/chat/ChatInput.test.tsx

describe('ChatInput', () => {
  it('shows "送信" button when status is connected', () => {
    render(<ChatInput onSend={jest.fn()} chatStatus="connected" />)
    expect(screen.getByRole('button')).toHaveTextContent('送信')
    expect(screen.getByRole('button')).not.toBeDisabled()
  })

  it('shows "接続中..." with spinner when status is connecting', () => {
    render(<ChatInput onSend={jest.fn()} chatStatus="connecting" />)
    expect(screen.getByRole('button')).toHaveTextContent('接続中...')
    expect(screen.getByRole('button')).toBeDisabled()
    expect(screen.getByTestId('spinner')).toBeInTheDocument()
  })

  it('shows "再接続" button when status is disconnected', () => {
    render(<ChatInput onSend={jest.fn()} chatStatus="disconnected" onReconnect={jest.fn()} />)
    expect(screen.getByRole('button', { name: '再接続' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '再接続' })).not.toBeDisabled()
  })

  it('calls onReconnect when reconnect button is clicked', async () => {
    const onReconnect = jest.fn()
    render(<ChatInput onSend={jest.fn()} chatStatus="disconnected" onReconnect={onReconnect} />)

    await userEvent.click(screen.getByRole('button', { name: '再接続' }))

    expect(onReconnect).toHaveBeenCalled()
  })
})
```

#### テスト 3.2: ChatPanel の再接続機能

```typescript
// web-ui/src/components/chat/ChatPanel.test.tsx

describe('ChatPanel reconnection', () => {
  it('calls startSession when reconnect button is clicked', async () => {
    // Arrange: disconnected 状態
    server.use(
      rest.get('/api/projects/:projectId/agent-sessions', (req, res, ctx) => {
        return res(ctx.json({
          agentSessions: {
            'agt_001': { chat: { count: 0, status: 'disconnected' }, task: { count: 0 } }
          }
        }))
      }),
      rest.post('/api/projects/:projectId/agents/:agentId/chat/start-session', (req, res, ctx) => {
        return res(ctx.json({ success: true }))
      })
    )

    render(<ChatPanel projectId="prj_001" agent={mockAgent} onClose={jest.fn()} />)

    // Act: 再接続ボタンをクリック
    await userEvent.click(screen.getByRole('button', { name: '再接続' }))

    // Assert: startSession API が呼ばれる
    await waitFor(() => {
      expect(mockStartSession).toHaveBeenCalled()
    })
  })
})
```

---

## 実装ステップ

### Step 1: バックエンド DTO 更新 (RED → GREEN)

1. `AgentSessionPurposeCountsDTO` を更新して `chat.status` を追加
2. `listProjectAgentSessions` で `PendingAgentPurpose` を考慮して status を計算
3. テスト 1.1 〜 1.4 を通過

### Step 2: フロントエンド型定義 (RED → GREEN)

1. `useAgentSessions` の型定義を更新
2. `getChatStatus(agentId)` ヘルパー関数を追加
3. テスト 2.1 を通過

### Step 3: ChatInput コンポーネント更新 (RED → GREEN)

1. `sessionReady` を `chatStatus` に変更
2. 3状態の表示を実装
3. `onReconnect` コールバックを追加
4. テスト 3.1 を通過

### Step 4: ChatPanel 更新 (RED → GREEN)

1. `getChatStatus` を使用
2. 再接続ボタンのハンドラを実装
3. テスト 3.2 を通過

---

## 技術詳細

### API レスポンス形式

**変更前:**
```json
{
  "agentSessions": {
    "agt_xxx": { "chat": 1, "task": 0 }
  }
}
```

**変更後:**
```json
{
  "agentSessions": {
    "agt_xxx": {
      "chat": { "count": 1, "status": "connected" },
      "task": { "count": 0 }
    }
  }
}
```

### chatStatus 判定ロジック

```swift
func getChatStatus(agentId: AgentID, projectId: ProjectID) -> String {
    // 1. アクティブなchatセッションがあるか？
    let chatSessionCount = sessionRepository.countActiveSessionsByPurpose(
        agentId: agentId,
        projectId: projectId
    )[.chat] ?? 0

    if chatSessionCount > 0 {
        return "connected"
    }

    // 2. chat用のPendingAgentPurposeがあるか？
    if let pending = pendingAgentPurposeRepository.find(agentId: agentId, projectId: projectId),
       pending.purpose == .chat {
        return "connecting"
    }

    // 3. どちらもなし
    return "disconnected"
}
```

### 状態遷移図

```
[初期状態] → disconnected
     ↓ (ユーザーがチャットパネルを開く / 再接続クリック)
[startSession API] → connecting
     ↓ (エージェントが authenticate 成功)
[セッション確立] → connected
     ↓ (タイムアウト / エラー / ユーザーが閉じる)
[セッション終了] → disconnected
```

---

## ファイル変更一覧

### バックエンド
- `Sources/RESTServer/DTOs/AgentSessionDTOs.swift` - DTO 構造変更
- `Sources/RESTServer/RESTServer.swift` - API レスポンス更新
- `Tests/RESTServerTests/ChatSessionStatusTests.swift` - 新規テスト

### フロントエンド
- `web-ui/src/types/index.ts` - 型定義更新
- `web-ui/src/hooks/useAgentSessions.ts` - フック更新
- `web-ui/src/hooks/useAgentSessions.test.ts` - テスト追加
- `web-ui/src/components/chat/ChatInput.tsx` - コンポーネント更新
- `web-ui/src/components/chat/ChatInput.test.tsx` - テスト更新
- `web-ui/src/components/chat/ChatPanel.tsx` - 再接続機能追加
- `web-ui/src/components/chat/ChatPanel.test.tsx` - テスト更新

---

## 参考

- [CHAT_FEATURE.md](./CHAT_FEATURE.md) - チャット機能全体設計
- [CHAT_SESSION_MAINTENANCE_MODE.md](./CHAT_SESSION_MAINTENANCE_MODE.md) - セッション維持設計
- [CHAT_LONG_POLLING.md](./CHAT_LONG_POLLING.md) - Long Polling 設計
