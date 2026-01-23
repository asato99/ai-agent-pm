# UC016: AIエージェント間会話

## 概要

AIエージェント同士が明示的に会話を開始・終了し、対話を行うユースケース。

---

## 前提条件

- プロジェクトが存在し、workingDirectoryが設定済み
- Worker-A、Worker-BがAIエージェントとしてプロジェクトにアサイン済み
- Worker-Aがタスクまたはチャットセッションで稼働中
- MCPサーバー、Coordinatorが設定済み

---

## アクター

| アクター | 種別 | セッション | 役割 |
|----------|------|------------|------|
| Worker-A | AI | task / chat | 会話を開始（initiator） |
| Worker-B | AI | chat | 会話に参加（participant） |
| Coordinator | System | - | エージェント起動制御 |

---

## 基本フロー

### 1. 会話開始（Worker-A）

```
Worker-A → start_conversation(
    target_agent_id: "worker-b",
    purpose: "実装方針の相談"
)
  ↓
MCP → Conversation作成（state: pending）
    → PendingAgentPurpose作成（worker-b, chat, conversation_id）
  ↓
Worker-A ← {conversation_id, status: "pending"}
```

### 2. Worker-B起動（Coordinator）

```
Coordinator → PendingAgentPurpose検知
           → Worker-Bプロセス起動（purpose: chat）
  ↓
Worker-B → authenticate(purpose: chat)
```

### 3. 会話参加確認（Worker-B）

```
Worker-B → get_next_action()
  ↓
MCP → Conversation状態を active に更新
    → conversation_request を返却
  ↓
Worker-B ← {
    action: "conversation_request",
    from_agent_id: "worker-a",
    from_agent_name: "Analysis Worker",
    purpose: "実装方針の相談"
}
```

### 4. メッセージ交換

```
Worker-A → send_message(to: worker-b, "JWTとSession、どちらが推奨？")
  ↓
Worker-B → get_pending_messages()
        ← [{senderId: "worker-a", content: "JWTとSession、どちらが推奨？"}]
  ↓
Worker-B → respond_chat(to: worker-a, "このプロジェクトではJWTを推奨します...")
  ↓
Worker-A → (メッセージ受信、get_pending_messagesで取得可能)
```

### 5. 会話終了（Worker-A）

```
Worker-A → end_conversation()
  ↓
MCP → Conversation状態を terminating に更新
  ↓
Worker-B → get_next_action()
        ← {action: "conversation_ended", ended_by: "worker-a"}
  ↓
Worker-B → get_next_action() → (次の指示 or wait_for_messages)
```

---

## シーケンス図

```
Worker-A        MCP Server       Coordinator      Worker-B
   │                │                │               │
   │──start_conv───▶│                │               │
   │  (to: B)       │                │               │
   │                │                │               │
   │                │─Conv作成──────▶│               │
   │                │ PendingPurpose │               │
   │                │                │               │
   │◀──{pending}────│                │               │
   │                │                │               │
   │──send_msg─────▶│                │               │
   │  (質問)        │─chat.jsonl────▶│               │
   │                │                │               │
   │                │                │──起動(chat)──▶│
   │                │                │               │
   │                │◀───────────────┼──authenticate─│
   │                │                │               │
   │                │◀───────────────┼─get_next_action│
   │                │─Conv→active────│               │
   │                │──conv_request─▶│               │
   │                │                │               │
   │                │◀───────────────┼─get_pending──│
   │                │──Worker-Aの質問▶               │
   │                │                │               │
   │                │◀───────────────┼─respond_chat─│
   │◀──回答────────│                │               │
   │                │                │               │
   │──send_msg─────▶│                │               │
   │  (お礼)        │──────────────────────────────▶│
   │                │                │               │
   │──end_conv─────▶│                │               │
   │                │─Conv→terminating              │
   │                │                │               │
   │                │◀───────────────┼─get_next_action│
   │                │──conv_ended───▶│               │
   │                │                │               │
```

---

## 代替フロー

### A1: Worker-Bが既に稼働中の場合

```
Worker-A → start_conversation(target: worker-b)
  ↓
MCP → Conversation作成（state: pending）
    → PendingAgentPurpose作成
  ↓
Worker-B (既に稼働中) → get_next_action()
                     ← conversation_request
```

PendingAgentPurposeは作成されるが、Coordinatorはセッションが既にアクティブな場合は新規起動をスキップ。Worker-Bは次回の`get_next_action`で会話リクエストを検出する。

### A2: Worker-Bから会話を終了する場合

```
Worker-B → end_conversation()
  ↓
MCP → Conversation状態を terminating に更新
  ↓
Worker-A → get_next_action()
        ← {action: "conversation_ended", ended_by: "worker-b"}
```

どちらの参加者からでも会話を終了できる。

### A3: タイムアウトによる自動終了

```
[10分間メッセージ交換なし]
  ↓
MCP → Conversation状態を terminating に更新
  ↓
両者 → get_next_action()
     ← {action: "conversation_ended", reason: "timeout"}
```

---

## 例外フロー

### E1: Worker-Bが応答しない（5分タイムアウト）

```
Worker-A → start_conversation(target: worker-b)
  ↓
[5分経過、Worker-Bがauthenticateしない]
  ↓
MCP → Conversation状態を expired に更新
  ↓
Worker-A → get_next_action()
        ← {action: "conversation_expired", target: "worker-b"}
```

### E2: 同じ相手と既に会話中

```
Worker-A → start_conversation(target: worker-b)
        ← Error: conversation_already_active
```

### E3: Humanエージェントとの会話試行

```
Worker-A → start_conversation(target: human-agent)
        ← Error: cannot_start_conversation_with_human
```

Humanとの会話は別のフロー（Web UIからの`/chat/start`）を使用する。

---

## テストシナリオ

### シナリオ1: 正常な会話フロー

**目的**: Worker-A → Worker-B の会話が正常に開始・終了することを検証

**テストデータ**:
- プロジェクト: `prj_uc016` (UC016 AI Conversation Test)
- Worker-A: `agt_uc016_worker_a` (会話開始者)
- Worker-B: `agt_uc016_worker_b` (会話参加者)
- Working Directory: `/tmp/uc016`

**手順**:
1. Worker-Aを起動（task session）
2. Worker-Aが`start_conversation(target: worker-b)`を呼び出し
3. Conversation (state: pending) が作成されることを確認
4. Worker-Bが起動することを確認
5. Worker-Bの`get_next_action`が`conversation_request`を返すことを確認
6. Worker-Aが`send_message`でメッセージ送信
7. Worker-Bが`get_pending_messages`でメッセージ受信
8. Worker-Bが`respond_chat`で応答
9. Worker-Aが`end_conversation`を呼び出し
10. Worker-Bの`get_next_action`が`conversation_ended`を返すことを確認

**期待結果**:
- Conversationの状態遷移: pending → active → terminating → ended
- 両者のchat.jsonlにメッセージが保存
- Worker-Bが正常に終了通知を受け取る

### シナリオ2: 参加者からの終了

**目的**: Worker-Bから会話を終了できることを検証

**手順**:
1. シナリオ1の手順1-7を実行
2. Worker-Bが`end_conversation`を呼び出し
3. Worker-Aの`get_next_action`が`conversation_ended`を返すことを確認

### シナリオ3: タイムアウト

**目的**: 10分間やり取りがない場合に自動終了することを検証

**手順**:
1. 会話を開始（state: active）
2. `lastActivityAt`を10分以上前に設定（テスト用）
3. どちらかのエージェントが`get_next_action`を呼び出し
4. `conversation_ended (reason: timeout)`が返されることを確認

---

## 検証項目（アサーション）

| # | 検証項目 | 説明 |
|---|----------|------|
| 1 | Conversation作成 | start_conversationでConversation (pending) が作成される |
| 2 | PendingPurpose作成 | 参加者用のPendingAgentPurposeが作成される |
| 3 | 状態遷移 pending→active | 参加者がauthenticateするとactiveに遷移 |
| 4 | conversation_request | 参加者のget_next_actionが会話リクエストを返す |
| 5 | メッセージ保存 | send_message/respond_chatでchat.jsonlに保存 |
| 6 | 状態遷移 active→terminating | end_conversationでterminatingに遷移 |
| 7 | conversation_ended | 相手のget_next_actionが終了通知を返す |
| 8 | 状態遷移 terminating→ended | 両者に通知後、endedに遷移 |

---

## 関連エンティティ

| エンティティ | 操作 |
|--------------|------|
| Conversation | 作成・状態更新 |
| PendingAgentPurpose | 作成（会話ID付き） |
| AgentSession | 作成（参加者のchatセッション） |
| ChatMessage | 作成（send_message/respond_chat） |

---

## 関連ドキュメント

- [docs/design/AI_TO_AI_CONVERSATION.md](../design/AI_TO_AI_CONVERSATION.md) - 設計書
- [docs/design/CHAT_SESSION_MAINTENANCE_MODE.md](../design/CHAT_SESSION_MAINTENANCE_MODE.md) - セッション維持モード
- [docs/usecase/UC013_WorkerToWorkerMessageRelay.md](UC013_WorkerToWorkerMessageRelay.md) - Worker間メッセージ連携（非同期）
- [docs/usecase/UC014_ChatSessionImmediateResponse.md](UC014_ChatSessionImmediateResponse.md) - チャット即時応答
- [docs/usecase/UC015_ChatSessionClose.md](UC015_ChatSessionClose.md) - チャットセッション終了
