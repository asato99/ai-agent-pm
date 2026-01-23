# チャットセッション維持モード設計書

## 1. 概要

### 1.1 現在の問題

現在のチャット機能では、各メッセージの応答ごとに以下のサイクルが発生します：

```
[User sends message]
  ↓
Web UI: POST /chat (creates PendingAgentPurpose)
  ↓
Coordinator: Detects pending purpose, spawns agent
  ↓
Agent: authenticate → get_next_action → get_pending_messages → respond_chat → get_next_action → logout
  ↓
Agent process terminates
  ↓
[Next message: Repeat from step 1]
```

**問題点**：
- Claude CLIの起動に数十秒〜1分以上かかる
- 認証処理のオーバーヘッド
- 毎回新しいコンテキストで開始（会話の文脈が維持されない）

### 1.2 目標

- チャットパネルを開いた時点でエージェントを起動し、待機状態にする
- ユーザーがメッセージを送信したら即座に応答可能にする
- 非アクティブ時（10分）に適切にクリーンアップする

## 2. 設計

### 2.1 チャットセッション開始フロー

```
1. ユーザーがチャットパネルを開く
      ↓
2. Web UI → POST /chat/start
      ↓
3. REST Server:
   - システムメッセージを chat.jsonl に書き込み（visible: false）
   - PendingAgentPurpose 作成（purpose: chat）
      ↓
4. Coordinator がエージェント起動
      ↓
5. Agent: authenticate
      ↓
6. Agent: get_next_action → "get_pending_messages"
      ↓
7. Agent: get_pending_messages → 空（visible: false は除外）
      ↓
8. Agent: get_next_action → "wait_for_messages"（待機ループ開始）
```

### 2.2 システムメッセージ（visible フラグ）

`ChatMessage` に `visible` フィールドを追加：

```json
{
  "id": "msg_xxx",
  "senderId": "system",
  "receiverId": null,
  "content": "セッション開始",
  "createdAt": "2026-01-23T...",
  "visible": false
}
```

**効果**:
- ファイルに記録される（整合性 ✅）
- `findUnreadMessages` で除外（エージェントのコンテキスト ✅）
- Web UI で非表示（表示 ✅）

### 2.3 新しいアクション: `wait_for_messages`

```swift
// MCPServer.swift - getNextAction内
if session.purpose == .chat {
    let pendingMessages = try chatRepository.findUnreadMessages(
        projectId: session.projectId,
        agentId: session.agentId
    )

    if pendingMessages.isEmpty {
        // 現在: return "logout"
        // 新規: return "wait_for_messages"
        return [
            "action": "wait_for_messages",
            "instruction": """
                現在処理待ちのメッセージがありません。
                5秒後に再度 get_next_action を呼び出して新しいメッセージを確認してください。
                """,
            "state": "chat_waiting",
            "wait_seconds": 5,
            "session_timeout_minutes": 10
        ]
    } else {
        // 既存の処理
        return [
            "action": "get_pending_messages",
            ...
        ]
    }
}
```

### 2.4 Agent側の動作変更

現在：
```
get_next_action → logout指示 → プロセス終了
```

新規：
```
get_next_action → wait_for_messages指示 → 5秒待機 → get_next_action → (ループ)
                                                           ↓
                                                    新メッセージあり
                                                           ↓
                                                 get_pending_messages
                                                           ↓
                                                    respond_chat
                                                           ↓
                                                 get_next_action → (ループに戻る)
```

### 2.5 セッションタイムアウト管理

**タイムアウトの定義**:
- **起点**: 最後のメッセージ応答時刻（`respond_chat` 実行時）
- **終点**: 次のメッセージが来るか、タイムアウトに達するまで

```
[respond_chat] → lastActivityAt更新 → 10分間メッセージなし → タイムアウト
     ↑                                      ↓
     └──────── 新メッセージ到着 ←───────────┘
```

**タイムアウト条件**:
- **10分**: 最後の `respond_chat` から10分間新しいメッセージがなければ `logout` を返す

**更新タイミング**:
- `respond_chat` 実行時に `lastActivityAt` を現在時刻に更新

### 2.6 フロー全体図

```
┌─────────────────────────────────────────────────────────────┐
│                    Chat Session Flow                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐                                            │
│  │  User sends │                                            │
│  │   message   │                                            │
│  └──────┬──────┘                                            │
│         │                                                   │
│         ▼                                                   │
│  ┌─────────────┐   no session    ┌─────────────────┐       │
│  │   Web UI    │  ──────────────▶│ Create Pending  │       │
│  │  POST /chat │                 │ AgentPurpose    │       │
│  └──────┬──────┘                 └────────┬────────┘       │
│         │ session exists                  │                │
│         │                                 ▼                │
│         │                         ┌─────────────────┐      │
│         │                         │  Coordinator    │      │
│         │                         │  spawns agent   │      │
│         │                         └────────┬────────┘      │
│         │                                  │               │
│         │◀─────────────────────────────────┘               │
│         │                                                   │
│         ▼                                                   │
│  ┌─────────────────────────────────────────────────┐       │
│  │              Agent Process Loop                  │       │
│  │  ┌────────────────────────────────────────────┐ │       │
│  │  │                                            │ │       │
│  │  │  get_next_action                           │ │       │
│  │  │      │                                     │ │       │
│  │  │      ├──▶ wait_for_messages ──┐           │ │       │
│  │  │      │       (5s wait)        │           │ │       │
│  │  │      │                        │           │ │       │
│  │  │      ├──▶ get_pending_messages│           │ │       │
│  │  │      │         │              │           │ │       │
│  │  │      │         ▼              │           │ │       │
│  │  │      │    respond_chat        │           │ │       │
│  │  │      │         │              │           │ │       │
│  │  │      │         └──────────────┼───────┐   │ │       │
│  │  │      │                        │       │   │ │       │
│  │  │      ◀────────────────────────┘       │   │ │       │
│  │  │      │                                │   │ │       │
│  │  │      ├──▶ logout (timeout)            │   │ │       │
│  │  │             │                         │   │ │       │
│  │  └─────────────┼─────────────────────────┘   │ │       │
│  │                │                             │ │       │
│  │                ▼                             │ │       │
│  │         Process exits                        │ │       │
│  └──────────────────────────────────────────────┘ │       │
│                                                    │       │
└────────────────────────────────────────────────────┘       │
```

## 3. 実装詳細

### 3.1 ChatMessage の変更

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

    /// UI表示フラグ（false = システムメッセージ、エージェントに渡さない）
    public let visible: Bool  // 追加

    // デフォルト値: true（通常のメッセージは表示）
}
```

### 3.2 findUnreadMessages の変更

```swift
// Sources/Infrastructure/FileStorage/ChatFileRepository.swift
public func findUnreadMessages(projectId: ProjectID, agentId: AgentID) throws -> [ChatMessage] {
    let allMessages = try findMessages(projectId: projectId, agentId: agentId)

    // visible: false のメッセージを除外
    let visibleMessages = allMessages.filter { $0.visible }

    // 以降は既存ロジック（lastSentIndex で未読判定）
    ...
}
```

### 3.3 REST API: POST /chat/start

```swift
// Sources/RESTServer/RESTServer.swift
// チャットセッション開始エンドポイント
router.post("/projects/:projectId/chat/start") { request async throws -> Response in
    let projectId = request.parameters.get("projectId")!
    let targetAgentId = request.query["agentId"]!

    // 1. システムメッセージを書き込み（visible: false）
    let systemMessage = ChatMessage(
        id: .generate(),
        senderId: AgentID("system"),
        content: "セッション開始",
        createdAt: Date(),
        visible: false  // エージェントには渡さない
    )
    try chatRepository.saveMessage(systemMessage, projectId: projectId, agentId: targetAgentId)

    // 2. PendingAgentPurpose 作成
    let purpose = PendingAgentPurpose(
        agentId: targetAgentId,
        projectId: projectId,
        purpose: .chat
    )
    try pendingPurposeRepository.save(purpose)

    return Response(status: .ok)
}
```

### 3.4 getNextAction の変更

```swift
// getNextAction内のChat処理
if session.purpose == .chat {
    // タイムアウトチェック（最後の応答から10分）
    let idleTime = Date().timeIntervalSince(session.lastActivityAt)
    let timeoutSeconds = 10.0 * 60.0  // 10分

    if idleTime > timeoutSeconds {
        return [
            "action": "logout",
            "instruction": "セッションがタイムアウトしました。",
            "state": "chat_timeout"
        ]
    }

    let pendingMessages = try chatRepository.findUnreadMessages(...)

    if pendingMessages.isEmpty {
        return [
            "action": "wait_for_messages",
            "instruction": "5秒後に再度 get_next_action を呼び出してください。",
            "state": "chat_waiting",
            "wait_seconds": 5
        ]
    } else {
        return [
            "action": "get_pending_messages",
            ...
        ]
    }
}
```

### 3.5 respond_chat の変更

```swift
// respond_chat 実行時に lastActivityAt を更新
func respondChat(...) {
    // メッセージ保存処理...

    // セッションの lastActivityAt を更新
    session.lastActivityAt = Date()
    try sessionRepository.update(session)
}
```

### 3.6 既存フィールドの利用

`AgentSession` には既に `lastActivityAt` フィールドが存在するため、DBスキーマ変更は不要。

### 3.7 Web UI の変更

チャットパネルを開いた時に `/chat/start` を呼び出す：

```typescript
// ChatPanel.tsx
useEffect(() => {
    // チャットパネルを開いた時にセッション開始
    api.post(`/projects/${projectId}/chat/start?agentId=${selectedAgent.id}`)
}, [selectedAgent.id])

async function sendMessage(content: string) {
    // メッセージをDBに保存（既存のフロー）
    await api.post('/chat', {
        projectId,
        toAgentId: selectedAgent.id,
        content
    })
    // エージェントが待機中であれば、次のget_next_actionで自動的に取得される
}
```

### 3.8 Coordinator の変更

既存セッションがアクティブな場合、新しいプロセスを起動しない：

```python
# coordinator.py
def should_spawn_agent(agent_id, project_id):
    # アクティブなセッションがあるかチェック
    session = get_active_session(agent_id, project_id)
    if session and session.purpose == 'chat':
        # セッションがまだアクティブなら起動しない
        if is_session_alive(session):
            return False
    return True
```

## 4. シーケンス図

### 4.1 連続メッセージのフロー

```
User          Web UI        MCP Server       Agent
 │               │               │              │
 │──message 1──▶│               │              │
 │               │──POST /chat──▶│              │
 │               │               │◀─get_next_action─│
 │               │               │──pending_msgs──▶│
 │               │               │◀─respond_chat──│
 │               │               │──wait_for_msgs─▶│
 │               │               │              │
 │               │               │     (5s wait)│
 │               │               │              │
 │──message 2──▶│               │              │
 │               │──POST /chat──▶│              │
 │               │               │◀─get_next_action─│
 │               │               │──pending_msgs──▶│
 │               │               │◀─respond_chat──│
 │               │◀──response────│              │
 │◀──display────│               │              │
```

### 4.2 タイムアウトのフロー

```
Agent                    MCP Server
 │                           │
 │──get_next_action────────▶│
 │                           │──check timeout
 │◀──wait_for_messages─────│
 │                           │
 │    (5s wait, loop...)    │
 │                           │
 │──get_next_action────────▶│
 │                           │──check timeout (10min reached)
 │◀──logout────────────────│
 │                           │
 │    (process terminates)   │
```

## 5. 設定パラメータ

| パラメータ | デフォルト値 | 説明 |
|-----------|-------------|------|
| `chat.wait_interval_seconds` | 5 | メッセージ待機のポーリング間隔 |
| `chat.soft_timeout_minutes` | 10 | エージェントが自発的にlogoutするまでの時間 |
| `chat.hard_timeout_minutes` | 15 | Coordinatorが強制終了するまでの時間 |

## 6. セッション終了フロー（UC015）

### 6.1 セッション状態遷移

セッションは以下の3つの状態を持つ：

```
┌──────────┐      ユーザーが閉じる      ┌─────────────┐      exit指示を返却      ┌─────────┐
│  active  │  ─────────────────────▶  │ terminating │  ───────────────────▶  │  ended  │
└──────────┘                          └─────────────┘                         └─────────┘
     │                                       │
     │         タイムアウト（10分）            │
     └───────────────────────────────────────┘
                        ↓
                   ┌─────────┐
                   │  ended  │
                   └─────────┘
```

| 状態 | 説明 |
|------|------|
| `active` | セッションが有効、エージェントが待機中 |
| `terminating` | 終了要求済み、エージェントへのexit指示待ち |
| `ended` | 終了完了、セッションは無効 |

### 6.2 終了フロー（明示的終了）

ユーザーがチャットパネルを閉じた場合：

```
User          Web UI        REST Server      MCP Server         Agent
 │               │               │                │                │
 │ [×クリック]    │               │                │                │
 │               │               │                │                │
 │               ├─POST /chat/end─────────────────▶│                │
 │               │               │                │                │
 │               │               │                │ session.state  │
 │               │               │                │ = terminating  │
 │               │               │                │                │
 │               │◀──────────200 OK───────────────┤                │
 │               │               │                │                │
 │  [パネル閉じる] │               │                │                │
 │               │               │                │                │
 │               │               │                │   (ポーリング)  │
 │               │               │                │◀─get_next_action─┤
 │               │               │                │                │
 │               │               │                │ state ==       │
 │               │               │                │ terminating?   │
 │               │               │                │                │
 │               │               │                ├──{action:exit}─▶│
 │               │               │                │                │
 │               │               │                │ session.state  │
 │               │               │                │ = ended        │
 │               │               │                │                │
 │               │               │                │               [終了]
```

### 6.3 終了フロー（タイムアウト）

10分間メッセージがない場合：

```
Agent                    MCP Server
 │                           │
 │──get_next_action────────▶│
 │                           │──check: lastActivityAt + 10min < now?
 │                           │  → Yes (timeout)
 │                           │
 │                           │  session.state = terminating
 │                           │
 │◀──{action: exit}─────────│
 │                           │
 │                           │  session.state = ended
 │                           │
 │    [プロセス終了]          │
```

### 6.4 状態遷移の保証

**なぜ `terminating` 状態が必要か？**

1. **exit指示の到達保証**: セッションを即座に `ended` にすると、エージェントが終了指示を受け取る前にセッションが消える可能性がある
2. **リソース管理**: `terminating` 状態のセッションは新規起動をブロックしつつ、既存エージェントの終了を待つ
3. **監査**: どの段階でセッションが終了したかを追跡可能

**状態遷移ルール**:

| 現在の状態 | 許可される遷移 | トリガー |
|------------|----------------|----------|
| `active` | `terminating` | ユーザーが閉じる / タイムアウト |
| `active` | `ended` | 不可（必ずterminatingを経由） |
| `terminating` | `ended` | exit指示を返却後 |
| `ended` | - | 最終状態 |

### 6.5 AgentSession の変更

```swift
public struct AgentSession {
    public let id: AgentSessionID
    public let agentId: AgentID
    public let projectId: ProjectID
    public let purpose: SessionPurpose
    public var state: SessionState      // 追加
    public var lastActivityAt: Date
    public let expiresAt: Date
    public let createdAt: Date
}

public enum SessionState: String, Codable {
    case active       // 有効
    case terminating  // 終了要求済み
    case ended        // 終了完了
}
```

### 6.6 getNextAction の変更

```swift
func getNextAction(agentId: String, projectId: String) -> [String: Any] {
    let session = try findActiveSession(agentId, projectId)

    // 終了要求をチェック
    if session.state == .terminating {
        // exit指示を返し、セッションを ended に更新
        session.state = .ended
        try sessionRepository.update(session)

        return [
            "action": "exit",
            "reason": "session_closed",
            "instruction": "チャットセッションが終了しました。"
        ]
    }

    // タイムアウトチェック
    let idleTime = Date().timeIntervalSince(session.lastActivityAt)
    if idleTime > 10 * 60 {  // 10分
        session.state = .terminating
        try sessionRepository.update(session)
        // 次回のget_next_actionでexitを返す
    }

    // ... 通常の処理
}
```

### 6.7 POST /chat/end エンドポイント

```swift
// REST API
router.post("/projects/:projectId/agents/:agentId/chat/end") { request -> Response in
    let projectId = request.parameters.get("projectId")!
    let agentId = request.parameters.get("agentId")!

    // アクティブなセッションを検索
    let sessions = try sessionRepository.findByAgentIdAndProjectId(agentId, projectId)
    let activeSession = sessions.first { $0.state == .active }

    if let session = activeSession {
        // terminating に更新（まだ ended にしない）
        var updated = session
        updated.state = .terminating
        try sessionRepository.update(updated)
    }

    // セッションがなくても 200 OK（べき等性）
    return Response(status: .ok)
}
```

### 6.8 Web UI の変更

```typescript
// ChatPanel.tsx
const handleClose = async () => {
  try {
    await chatApi.endSession(projectId, agent.id)
  } catch (error) {
    // エラーがあってもUIは閉じる
    console.error('Failed to end chat session:', error)
  }
  onClose()
}

// ブラウザ直接閉じ対応
useEffect(() => {
  const handleBeforeUnload = () => {
    navigator.sendBeacon(
      `/api/projects/${projectId}/agents/${agent.id}/chat/end`
    )
  }
  window.addEventListener('beforeunload', handleBeforeUnload)
  return () => window.removeEventListener('beforeunload', handleBeforeUnload)
}, [projectId, agent.id])
```

## 7. 利点と考慮事項

### 7.1 利点

1. **レスポンス速度向上**: 起動・認証のオーバーヘッドがなくなる
2. **コンテキスト維持**: 会話の流れが自然に維持される
3. **リソース効率**: 短い会話でも長時間プロセスを維持しない（タイムアウト）

### 7.2 考慮事項

1. **リソース消費**: 待機中もプロセスがメモリを消費
2. **API課金**: Claude APIの場合、コンテキストが積み重なる
3. **同時接続数**: 複数ユーザーが同時にチャットする場合の制限

### 7.3 将来の拡張

1. **WebSocket対応**: ポーリングの代わりにリアルタイム通知
2. **コンテキスト圧縮**: 長い会話のサマリー化
3. **プライオリティキュー**: 重要なメッセージの優先処理

## 8. 実装フェーズ

### Phase 1: Domain層
- [ ] `ChatMessage` に `visible` フィールド追加（デフォルト: true）

### Phase 2: Infrastructure層
- [ ] `ChatFileRepository.findUnreadMessages` で `visible: false` を除外
- [ ] `AgentSessionRepository.updateLastActivity` 実装（既存フィールド利用）

### Phase 3: REST API
- [ ] `POST /projects/:projectId/chat/start` エンドポイント追加
- [ ] システムメッセージ（visible: false）の書き込み
- [ ] `PendingAgentPurpose` 作成

### Phase 4: MCP Server
- [ ] `getNextAction` で `wait_for_messages` アクション追加
- [ ] タイムアウト判定（lastActivityAt から10分）
- [ ] `respond_chat` で `lastActivityAt` 更新

### Phase 5: Web UI
- [ ] チャットパネル開封時に `/chat/start` 呼び出し
- [ ] `visible: false` メッセージの非表示

### Phase 6: Coordinator
- [ ] アクティブセッション検出
- [ ] 重複起動防止

### Phase 7: テスト
- [ ] 単体テスト
- [ ] 統合テスト（UC014として追加）
