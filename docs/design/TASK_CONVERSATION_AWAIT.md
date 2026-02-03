# タスクセッションからの会話待機設計

## 概要

タスクセッションがチャットセッションに会話を移譲した後、その会話の完了を待機・確認するための設計。

## 背景

### 問題

UC020で発覚した課題：
- タスクセッションがチャットセッションに「しりとり6往復」を移譲
- チャットセッションは正常に会話を完了（`ended`状態）
- しかしタスクセッションは会話完了を確認せずに退出
- 結果、メインタスクが`done`にならなかった

### 根本原因

タスクセッションが移譲した会話の完了を待機・確認する仕組みがなかった。

## 待機の分類

| 種類 | 責務 | 解決手段 |
|------|------|----------|
| 複数エージェント間の協調 | マネージャー | マネージャーによる監視・調整 |
| 同一エージェントのセッション間協調 | エージェント自身 | **本設計で対応** |

## 移譲後の関係パターン

タスクセッションからチャットセッションへの移譲には複数のパターンがある：

| パターン | タスクセッションの責任 | 待機の必要性 |
|----------|------------------------|--------------|
| Fire-and-forget | メッセージ送信で完了 | 不要 |
| 結果待ち | 会話完了の確認が必要 | **必要** |

どちらのパターンかの判断はタスクセッション（エージェント）が行う。

## 設計方針: タスクIDによる自動紐付け

### 基本アイデア

1. **認証時にタスクIDをセッションに含める**
   - タスクセッションのスポーン時、どのタスクを処理するかは既に確定している
   - AgentSession に taskId フィールドを追加

2. **移譲時に自動的にタスクIDを紐付け**
   - `delegate_to_chat_session` 呼び出し時、セッションからタスクIDを自動取得
   - ChatDelegation に taskId を含める

3. **会話開始時にタスクIDで紐付け**
   - `start_conversation` 時、Conversation に taskId を紐付け

4. **タスクIDで会話を取得**
   - `get_task_conversations(task_id)` で紐づく全会話を取得
   - タスクセッションが内容を見て判断

### フロー概要

```
認証時
├─ WorkDetectionService.hasTaskWork で対象タスクを特定
├─ AgentSession に taskId を設定
└─ セッション作成

タスクセッション                          チャットセッション
      │                                         │
      ├─ delegate_to_chat_session               │
      │   └─ セッションから taskId を自動取得     │
      │   └─ ChatDelegation に taskId を含める   │
      │                                         │
      │   （チャットセッションがスポーン）          │
      │                                         │
      │                                         ├─ get_pending_delegations
      │                                         │   └─ delegation 情報を取得
      │                                         │
      │                                         ├─ start_conversation
      │                                         │   └─ Conversation に taskId を紐付け
      │                                         │
      │                                         ├─ 会話実行...
      │                                         │
      │                                         ├─ end_conversation
      │                                         │
      ├─ get_task_conversations(task_id)        │
      │   └─ 紐づく全会話を取得                   │
      │   └─ タスクセッションが内容を確認・判断    │
      │                                         │
      ├─ (完了確認後) report_completed          │
      │                                         │
      └─ 完了                                   └─ 完了
```

## 設計詳細

### 1. AgentSession の拡張

```swift
public struct AgentSession {
    // ...既存フィールド
    public let taskId: TaskID?  // タスクセッションの場合のみ設定
}
```

### 2. セッション作成時のタスクID設定

認証時（`AuthenticateUseCaseV3`）に以下を追加:

```swift
// hasTaskWork で対象タスクを特定
let inProgressTasks = taskRepository.findByProject(projectId, status: .inProgress)
    .filter { $0.assigneeId == agentId }
let targetTaskId = inProgressTasks.first?.id  // 複数ある場合は最初の一つ

// セッション作成時に taskId を設定
let session = AgentSession(
    agentId: agentId,
    projectId: projectId,
    purpose: .task,
    taskId: targetTaskId  // 追加
)
```

### 3. ChatDelegation の拡張

```swift
public struct ChatDelegation {
    // ...既存フィールド
    public let taskId: TaskID?  // 追加: 移譲元タスクID
}
```

### 4. Conversation の拡張

```swift
public struct Conversation {
    // ...既存フィールド
    public let taskId: TaskID?  // 追加: 紐付くタスクID
}
```

### 5. 既存ツールの修正

#### `delegate_to_chat_session` の修正

```typescript
// リクエスト（変更なし）
{
  "session_token": "xxx",
  "target_agent_id": "worker-b",
  "purpose": "6往復しりとりを行う"
}

// レスポンス（追加）
{
  "success": true,
  "instruction": "会話を Worker-B（AI）に移譲しました。確認方法：get_task_conversations()

【確認頻度】
タスク内に他の作業があれば、作業を進めつつ区切りで確認してください。
他の作業がなければ、確認の頻度を上げてください。
相手はAIのため、人間より応答が速い傾向があります。

【中断判断】
相手のタイプ、会話の進捗状況、応答の見込みを考慮して判断してください。
見込みがないと判断したら、タスクを blocked に変更し理由を記録して退出。"
}

// 内部処理（修正）
// セッションから taskId を自動取得
// ChatDelegation に taskId を含めて保存
// 相手エージェントの type に応じた instruction を生成
```

**instruction の動的生成:**
- 相手が AI の場合: 「応答が速い傾向」と記載
- 相手が人間の場合: 「応答に時間がかかる可能性」と記載

#### `start_conversation` の修正

```typescript
// リクエスト（変更なし）
{
  "session_token": "xxx",
  "target_agent_id": "worker-b",
  "initial_message": "しりとりを始めましょう"
}

// 内部処理（修正）
// pending delegation から taskId を取得
// Conversation に taskId を紐付けて保存
```

### 6. 新規MCPツール

#### `get_task_conversations` - タスクに紐づく会話を取得（タスクセッション用）

```typescript
// リクエスト
{
  "session_token": "xxx",
  "task_id": "tsk_xxx"  // 省略時はセッションの taskId を使用
}

// レスポンス
{
  "task_id": "tsk_xxx",
  "conversations": [
    {
      "conversation_id": "cnv_xxx",
      "status": "active",         // pending | active | ended
      "target_agent_id": "worker-b",
      "message_count": 6,
      "messages": [               // ステータスに関わらず内容を返す
        {
          "id": "msg_xxx",
          "sender_id": "worker-a",
          "content": "りんご",
          "created_at": "2026-02-02T12:00:00Z"
        },
        // ...
      ],
      "started_at": "2026-02-02T12:00:00Z",
      "ended_at": null            // active の場合は null
    }
  ],
  "total_conversations": 1
}
```

**注意**: ステータス（pending / active / ended）に関わらず、会話の内容（messages）を返す。これにより、タスクセッションは進行中の会話の進捗も確認できる。

タスクセッションが内容を見て、完了したか判断する。

### エージェント判断による待機

待機判断はエージェントに委ねる。判断基準は `delegate_to_chat_session` の戻り値 instruction で提供される。

**判断基準:**
- 相手エージェントのタイプ（AI / 人間）
- タスク内に他の作業があるか
- 会話の進捗状況（ステータス、メッセージ数、最終更新時刻）
- 応答の見込み

**ステータスごとの意味:**
- `pending`: 会話がまだ開始されていない
- `active`: 会話が進行中
- `ended`: 会話が完了

### 中断判断

中断（blocked）の判断もエージェントに委ねる。

エージェントは相手のタイプ、進捗状況、応答の見込みを考慮し、見込みがないと判断したら：
1. タスクを `blocked` に変更
2. 理由をタスクの説明に記録
3. タスクセッションは退出

### フロー例

```
認証時
├─ WorkDetectionService で in_progress タスクを特定
├─ AgentSession に taskId: "tsk_xxx" を設定
└─ タスクセッション開始

タスクセッション (Worker-A)              チャットセッション (Worker-A)
│                                              │
├─ タスク「Worker-Bと6往復しりとり」を受け取る    │
│   (セッションに taskId: "tsk_xxx" が設定済み)  │
│                                              │
├─ delegate_to_chat_session(                   │
│     target_agent_id: "worker-b",             │
│     purpose: "6往復しりとり"                  │
│   )                                          │
│   └─ 戻り値: success + instruction           │
│                                              │
│   （チャットセッションがスポーン）               │
│                                              ├─ get_pending_delegations
│                                              │   └─ delegation を取得（taskId 含む）
│                                              │
│                                              ├─ start_conversation(
│                                              │     target_agent_id: "worker-b"
│                                              │   )
│                                              │   └─ Conversation に taskId を紐付け
│                                              │
│                                              ├─ 会話実行（しりとり6往復）
│                                              │
│                                              ├─ end_conversation
│                                              │
├─ 【エージェント判断】他に作業があるか？         │
│   ├─ ある → 他の作業を進める                  │
│   └─ ない → 待機                             │
│                                              │
├─ get_task_conversations()                    │
│   └─ taskId はセッションから自動取得          │
│   ├─ 会話なし → 待機                          │
│   ├─ active の会話あり → 進捗確認、待機継続   │
│   └─ ended の会話あり → 内容確認、完了判断    │
│                                              │
├─ （必要に応じて繰り返し確認）                  │
│                                              │
├─ 完了確認後                                   │
│   └─ 会話内容を確認、report_completed         │
│                                              │
└─ 完了                                        └─ 完了
```

## 実装計画

### Phase 1: エンティティ拡張

1. **AgentSession に taskId 追加**
   - `Sources/Domain/Entities/AgentSession.swift`
   - DBスキーマ: `agent_sessions.task_id` カラム追加

2. **ChatDelegation に taskId 追加**
   - `Sources/Domain/Entities/ChatDelegation.swift`
   - DBスキーマ: `chat_delegations.task_id` カラム追加

3. **Conversation に taskId 追加**
   - `Sources/Domain/Entities/Conversation.swift`
   - DBスキーマ: `conversations.task_id` カラム追加

### Phase 2: 認証時のタスクID設定

1. **WorkDetectionService の拡張**
   - `hasTaskWork` → `getTaskWork` に変更 or 追加
   - タスクの有無だけでなく、対象タスクIDも返す

2. **AuthenticateUseCaseV3 の修正**
   - タスクセッション作成時に taskId を設定

3. **AgentSessionRepository の修正**
   - taskId の保存・取得に対応

### Phase 3: 既存ツールの修正

1. **delegate_to_chat_session の修正**
   - セッションから taskId を自動取得
   - ChatDelegation に taskId を含めて保存
   - 相手エージェントの type に応じた instruction を戻り値に含める

2. **start_conversation の修正**
   - pending delegation から taskId を取得
   - Conversation に taskId を紐付け

3. **ConversationRepository の拡張**
   - `findByTaskId(taskId:)` メソッド追加

### Phase 4: 新規MCPツール追加

1. **get_task_conversations**
   - タスクに紐づく全会話を取得
   - taskId 省略時はセッションから自動取得

### Phase 5: エージェント指示更新

`delegate_to_chat_session` の戻り値に instruction を含めるため、静的な指示定義は不要。
エージェントは戻り値の instruction に従って判断する。

**チャットセッションの指示:**

```
（変更なし - 既存の get_pending_delegations / start_conversation を使用）
```

### Phase 6: テスト

- UC020の再テスト
- タスクID紐付けの単体テスト
- タイムアウトケースのテスト

## 考慮事項

### 相手による違い

| 相手 | 特性 | instruction での伝達内容 |
|------|------|--------------------------|
| AI | 比較的すぐ返答 | 「応答が速い傾向」 |
| 人間 | 返信が遅い/ない可能性 | 「応答に時間がかかる可能性」 |

エージェントはこの情報を基に、確認頻度と中断判断を自ら決定する。

### 将来の拡張

- イベント駆動への移行（WebSocket等）
- 会話以外の外部処理待機への汎用化
