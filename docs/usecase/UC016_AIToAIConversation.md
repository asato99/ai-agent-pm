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
    purpose: "しりとり"
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
    purpose: "しりとり"
}
```

### 4. メッセージ交換（しりとり例）

**重要**: `send_message`はアクティブな会話が存在する場合のみ使用可能。
`start_conversation`を呼ばずに`send_message`を使用するとエラーになる。

```
Worker-A → send_message(to: worker-b, "しりとりをしましょう。りんご")
  ↓
Worker-B → get_pending_messages()
        ← [{senderId: "worker-a", content: "...", conversationId: "conv_xxx"}]
  ↓
Worker-B → respond_chat(to: worker-a, "ごりら")
  ↓
Worker-A → get_pending_messages()
        ← [{senderId: "worker-b", content: "ごりら", conversationId: "conv_xxx"}]
  ↓
[繰り返し: 5往復まで]
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

### E4: 会話開始せずにAI間メッセージ送信

```
Worker-A → send_message(target: worker-b, "質問があります")
        ← Error: conversation_required_for_ai_to_ai
           "AIエージェント間のメッセージ送信にはアクティブな会話が必要です。
            先にstart_conversation(participant_agent_id: \"worker-b\",
            initial_message: \"...\")を呼び出してください。"
```

AI間メッセージは`start_conversation`で会話を開始してから送信する必要がある。
これにより、会話ライフサイクルの使用が強制され、すべてのAI間通信が追跡可能になる。

**注意**: Human-AI間のメッセージ送信はこの制約の対象外。

---

## テストシナリオ

### シナリオ1: 正常な会話フロー（しりとり5ターン）

**目的**: Worker-A → Worker-B の会話が正常に開始・5往復・終了することを検証

**テストデータ**:
- プロジェクト: `prj_uc016` (UC016 AI Conversation Test)
- Worker-A: `agt_uc016_worker_a` (会話開始者)
- Worker-B: `agt_uc016_worker_b` (会話参加者)
- Working Directory: `/tmp/uc016`

**シナリオ**: しりとりを5ターン行い、Worker-Aが終了を宣言

```
Worker-A: 「しりとりをしましょう。りんご」
Worker-B: 「ごりら」
Worker-A: 「らっぱ」
Worker-B: 「ぱんだ」
Worker-A: 「だちょう」
Worker-B: 「うさぎ」
Worker-A: 「ぎんこう」
Worker-B: 「うま」
Worker-A: 「まくら」
Worker-B: 「らいおん」
Worker-A: 「5ターン完了。会話を終了します」
```

**手順**:
1. Worker-Aを起動（chat session）
2. Worker-Aが`start_conversation(target: worker-b, purpose: "しりとり")`を呼び出し
3. Conversation (state: pending) が作成されることを確認
4. Worker-Bが起動することを確認
5. Worker-Bの`get_next_action`が`conversation_request`を返すことを確認
6. Worker-Aが`send_message`で「しりとりをしましょう。りんご」を送信
7. Worker-Bが`get_pending_messages`でメッセージ受信
8. Worker-Bが`respond_chat`で「ごりら」を応答
9. 手順6-8を繰り返し、5往復（10メッセージ）を完了
10. Worker-Aが`end_conversation`を呼び出し
11. Worker-Bの`get_next_action`が`conversation_ended`を返すことを確認

**期待結果**:
- Conversationの状態遷移: pending → active → terminating → ended
- chat.jsonlに10件のメッセージが保存
- 全メッセージに同一の`conversationId`が設定されている
- しりとりのルール（前の単語の最後の文字 = 次の単語の最初の文字）が守られている
- Worker-Bが正常に終了通知を受け取る

### シナリオ2: 参加者からの終了（しりとり中断）

**目的**: Worker-Bから会話を終了できることを検証

**シナリオ**: しりとり中にWorker-Bが「ん」で終わる単語を出して終了

```
Worker-A: 「しりとりをしましょう。りんご」
Worker-B: 「ごりら」
Worker-A: 「らっぱ」
Worker-B: 「ぱんだ」
Worker-A: 「だちょう」
Worker-B: 「うどん」  ← 「ん」で終了
Worker-B: (end_conversation)
```

**手順**:
1. シナリオ1の手順1-5を実行（会話開始）
2. 3往復のしりとりを実行
3. Worker-Bが「ん」で終わる単語で応答
4. Worker-Bが`end_conversation`を呼び出し
5. Worker-Aの`get_next_action`が`conversation_ended`を返すことを確認

**期待結果**:
- chat.jsonlに6件のメッセージが保存
- 全メッセージに同一の`conversationId`が設定されている
- Worker-Aが`ended_by: "worker-b"`で終了通知を受け取る

### シナリオ3: タイムアウト（応答なし）

**目的**: 一定時間やり取りがない場合に自動終了することを検証

**シナリオ**: しりとり開始後、Worker-Bが応答しないままタイムアウト

**前提**: テスト用にタイムアウト時間を短縮（デフォルト10分 → テスト時5秒）

**手順**:
1. 環境変数 `CONVERSATION_TIMEOUT_SECONDS=5` を設定
2. 会話を開始、1往復のやり取りを実行（state: active）
3. 6秒待機
4. Worker-Aが`get_next_action`を呼び出し
5. `conversation_ended (reason: timeout)`が返されることを確認

**期待結果**:
- Conversationの状態が`ended`に遷移
- 両者の次回`get_next_action`で`conversation_ended`が返される
- chat.jsonlの既存メッセージは保持される（`conversationId`付き）

---

## 検証項目（アサーション）

| # | 検証項目 | 説明 |
|---|----------|------|
| 1 | Conversation作成 | start_conversationでConversation (pending) が作成される |
| 2 | PendingPurpose作成 | 参加者用のPendingAgentPurposeが作成される |
| 3 | 状態遷移 pending→active | 参加者がauthenticateするとactiveに遷移 |
| 4 | conversation_request | 参加者のget_next_actionが会話リクエストを返す |
| 5 | メッセージ保存 | send_message/respond_chatでchat.jsonlに保存 |
| 6 | conversationId付与 | 会話中のメッセージにconversationIdが自動設定される |
| 7 | 状態遷移 active→terminating | end_conversationでterminatingに遷移 |
| 8 | conversation_ended | 相手のget_next_actionが終了通知を返す |
| 9 | 状態遷移 terminating→ended | 両者に通知後、endedに遷移 |
| 10 | **AI間メッセージ制約** | **会話開始前のAI間send_messageがエラーになる** |

---

## 関連エンティティ

| エンティティ | 操作 |
|--------------|------|
| Conversation | 作成・状態更新 |
| PendingAgentPurpose | 作成（会話ID付き） |
| AgentSession | 作成（参加者のchatセッション） |
| ChatMessage | 作成（send_message/respond_chat、conversationId付与） |

---

## 関連ドキュメント

- [docs/design/AI_TO_AI_CONVERSATION.md](../design/AI_TO_AI_CONVERSATION.md) - 設計書
- [docs/design/CHAT_SESSION_MAINTENANCE_MODE.md](../design/CHAT_SESSION_MAINTENANCE_MODE.md) - セッション維持モード
- [docs/usecase/UC013_WorkerToWorkerMessageRelay.md](UC013_WorkerToWorkerMessageRelay.md) - Worker間メッセージ連携（非同期）
- [docs/usecase/UC014_ChatSessionImmediateResponse.md](UC014_ChatSessionImmediateResponse.md) - チャット即時応答
- [docs/usecase/UC015_ChatSessionClose.md](UC015_ChatSessionClose.md) - チャットセッション終了
