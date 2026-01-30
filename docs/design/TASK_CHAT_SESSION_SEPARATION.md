# タスクセッション・チャットセッション分離設計

## 概要

タスクセッションからチャットセッションへの責務委譲により、AI-to-AI会話の安定性を向上させる設計変更。

### 背景と課題

UC020（タスクベースAI-to-AI会話）テストで以下の問題が発覚：

1. **タスクセッションでの会話制御の不安定性**
   - タスク実行中のAIエージェントが `start_conversation` を呼び出すが、会話の継続（メッセージ交換）が不安定
   - 6往復のしりとりを指示しても、2メッセージで停止するケースが頻発
   - `end_conversation` が呼ばれないまま終了することがある

2. **責務の混在**
   - タスクセッションが「タスク実行」と「会話制御」の両方を担っている
   - AIエージェントの判断に依存するため、非決定的な挙動が発生

### 解決方針

**タスクセッションとチャットセッションの責務を明確に分離する**

- タスクセッション: タスク実行に専念、メッセージ送信・会話は不可
- チャットセッション: コミュニケーション全般を担当、会話方法の判断を含む

---

## 現状のアーキテクチャ

### セッション構造

同一エージェントが複数のセッションを独立して保持可能：

```
Agent (uc020-worker-a)
├── タスクセッション (purpose=task)
│   - タスク実行用
│   - authenticate → get_next_action → 作業 → report_completed
│
└── チャットセッション (purpose=chat)
    - 会話・メッセージ用
    - get_pending_messages → respond_chat
```

### 現状の権限設定

```swift
// ToolAuthorization.swift
"start_conversation": .authenticated,  // タスク・チャット両方から呼べる
"end_conversation": .authenticated,    // タスク・チャット両方から呼べる
"send_message": .authenticated,        // タスク・チャット両方から呼べる

"get_pending_messages": .chatOnly,     // チャットセッション専用
"respond_chat": .chatOnly,             // チャットセッション専用
```

### 現状の問題

```
タスクセッション(Worker-A)
    ↓ start_conversation("worker-b", "りんご")
    ↓ (Worker-Bからの返答を待つ)
    ↓ ... AIが会話継続を判断できず停止 ...
    ↓ get_next_action (タスク完了扱い)
    × end_conversation が呼ばれない
```

---

## 新アーキテクチャ

### 設計原則

1. **タスクセッションはメッセージ送信・会話開始が不可**
2. **チャットセッションへ「意図」を委譲する**
3. **チャットセッションが実行方法を判断する**

### セッション間フロー

```
タスクセッション(Worker-A)
    │
    │ delegate_to_chat_session(
    │   target_agent: "worker-b",
    │   purpose: "6往復しりとりをしてほしい。最初は「りんご」で。"
    │ )
    │
    ↓ (依頼を投げたら即座に戻る)

チャットセッション(Worker-A)  ← 次回スポーン時に処理
    │
    │ 依頼内容を確認
    │ AIが判断: 複数往復 → 会話が必要
    │
    ↓ start_conversation("worker-b", "りんご")
    ↓ send_conversation_message(...) x N回
    ↓ end_conversation()
    ↓ (完了通知をタスクセッションへ)

チャットセッション(Worker-B)
    │
    │ 会話招待を受信
    │ respond_conversation_message(...) x N回
```

### 権限変更

```swift
// 変更後の ToolAuthorization.swift

// タスクセッション用（新規）
"delegate_to_chat_session": .taskOnly,

// チャットセッション専用に変更
"start_conversation": .chatOnly,       // 変更: .authenticated → .chatOnly
"end_conversation": .chatOnly,         // 変更: .authenticated → .chatOnly
"send_message": .chatOnly,             // 変更: .authenticated → .chatOnly
"send_conversation_message": .chatOnly, // チャットセッション専用

// 既存のチャットセッション専用（変更なし）
"get_pending_messages": .chatOnly,
"respond_chat": .chatOnly,
```

---

## 新規MCPツール定義

### delegate_to_chat_session

タスクセッションからチャットセッションへコミュニケーション依頼を行う。

```json
{
  "name": "delegate_to_chat_session",
  "description": "チャットセッションへコミュニケーションを委譲する。タスクセッションから他エージェントへのメッセージ送信や会話は直接行えないため、このツールでチャットセッションに依頼する。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "session_token": {
        "type": "string",
        "description": "タスクセッションのトークン"
      },
      "target_agent_id": {
        "type": "string",
        "description": "コミュニケーション相手のエージェントID"
      },
      "purpose": {
        "type": "string",
        "description": "依頼内容（何を伝えたいか、何をしてほしいか）"
      },
      "context": {
        "type": "string",
        "description": "追加のコンテキスト情報（任意）"
      }
    },
    "required": ["session_token", "target_agent_id", "purpose"]
  }
}
```

**レスポンス例:**

```json
{
  "success": true,
  "delegation_id": "dlg_abc123",
  "message": "依頼をチャットセッションに登録しました。次回チャットセッション起動時に処理されます。"
}
```

---

## データモデル

### chat_delegations テーブル（新規）

```sql
CREATE TABLE chat_delegations (
  id TEXT PRIMARY KEY,
  agent_id TEXT NOT NULL REFERENCES agents(id),
  project_id TEXT NOT NULL REFERENCES projects(id),
  target_agent_id TEXT NOT NULL REFERENCES agents(id),
  purpose TEXT NOT NULL,
  context TEXT,
  status TEXT NOT NULL DEFAULT 'pending',  -- pending, processing, completed, failed
  created_at DATETIME NOT NULL,
  processed_at DATETIME,
  result TEXT  -- JSON: 実行結果
);
```

### status 状態遷移

```
pending → processing → completed
                   ↘ failed
```

---

## チャットセッションの挙動変更

### get_pending_messages の拡張

チャットセッションが起動時に確認するメッセージに、委譲リクエストを含める：

```json
{
  "pending_messages": [...],
  "pending_delegations": [
    {
      "delegation_id": "dlg_abc123",
      "target_agent_id": "worker-b",
      "purpose": "6往復しりとりをしてほしい。最初は「りんご」で。",
      "context": null
    }
  ]
}
```

### チャットセッションの判断ロジック

チャットセッション側のAIが以下を判断：

1. **会話が必要な場合**
   - 複数回のやり取りが予想される
   - 相手の反応を見ながら進める必要がある
   → `start_conversation` で会話を開始し、完了まで管理

2. **単発メッセージで済む場合**
   - 一方的な通知・報告
   - 返答を期待しない
   → `send_message` で送信

---

## 実装計画

### Phase 1: 権限変更

1. `ToolAuthorization.swift` の権限マッピング変更
2. 既存テストの更新（タスクセッションからの会話テストはエラーになる）

### Phase 2: 委譲機能実装

1. `chat_delegations` テーブル追加
2. `delegate_to_chat_session` ツール実装
3. `get_pending_messages` の拡張

### Phase 3: テスト更新

1. UC016/UC016-B/UC020 テストの更新
2. チャットセッション経由の会話フロー検証

---

## 移行の影響

### 影響を受けるユースケース

| ユースケース | 現状 | 変更後 |
|------------|------|--------|
| UC016 (AI-to-AI会話) | タスクセッションから直接会話 | チャットセッション経由 |
| UC016-B (Manager-Worker会話) | タスクセッションから直接会話 | チャットセッション経由 |
| UC020 (タスクベース会話) | タスクセッションから直接会話 | delegate_to_chat_session使用 |
| UC012 (メッセージ送信) | タスクセッションから可能 | delegate_to_chat_session使用 |

### 後方互換性

- タスクセッションから `start_conversation` / `send_message` を呼ぶと `chatSessionRequired` エラーになる
- 既存のCoordinator設定でチャットセッションが生成されるよう調整が必要

---

## 期待される効果

1. **安定性向上**
   - 会話ロジックがチャットセッションに集約され、管理しやすくなる
   - タスクセッションは「依頼を投げる」だけでよい

2. **責務の明確化**
   - タスクセッション: タスク実行に専念
   - チャットセッション: コミュニケーション全般

3. **テストの予測可能性向上**
   - チャットセッションが会話を最後まで管理するため、中途半端な状態になりにくい

---

## 関連ドキュメント

- [AI_TO_AI_CONVERSATION.md](./AI_TO_AI_CONVERSATION.md) - AI-to-AI会話の基本設計
- [CHAT_FEATURE.md](./CHAT_FEATURE.md) - チャット機能設計
- [TOOL_AUTHORIZATION_ENHANCEMENT.md](./TOOL_AUTHORIZATION_ENHANCEMENT.md) - ツール認可設計
