# チャットセッションからのタスク操作設計

**日付**: 2026-02-06
**ステータス**: Draft
**関連**: docs/design/TASK_REQUEST_APPROVAL.md, docs/design/TASK_CHAT_SESSION_SEPARATION.md

---

## 背景と問題

### 発生した問題（パイロットテスト）

1. マネージャーが `delegate_to_chat_session` でワーカーに追加作業を依頼
2. しかしこれは**コミュニケーション**であり、正式な**タスク**ではない
3. ワーカーは指示を受けたが、タスクとして追跡されない
4. システムは既存タスクの完了のみを追跡し、「全完了」と誤認

### 根本原因

| セッション種別 | 目的 | 現状の機能 |
|--------------|------|-----------|
| タスクセッション | 正式な作業実行 | `get_next_action`, `report_completed` |
| チャットセッション | コミュニケーション | `send_message`, `request_task`（自分へのタスク作成のみ） |

**断絶**: チャットで作業依頼しても、既存タスクの実行開始・修正ができない。

---

## 設計方針

### 核心原則: 上位者からの依頼のみ許可

**チャットからのタスク操作は、上位者（祖先エージェント）からの依頼がある場合のみ実行可能。**

```
Owner → Manager: ✓ 許可（Owner は Manager の上位）
Manager → Worker: ✓ 許可（Manager は Worker の上位）
Worker → Worker: ✗ 拒否（同階層）
Worker → Manager: ✗ 拒否（下位から上位）
```

### 責務分離

| 操作 | 使用するツール | セッション | 上位者依頼 |
|------|---------------|-----------|-----------|
| タスク作成 | `create_tasks_batch` (既存) | タスクセッション | - |
| タスク実行開始 | `start_task_from_chat` (新規) | チャットセッション | **必須** |
| タスク修正 | `update_task_from_chat` (新規) | チャットセッション | **必須** |

**タスク作成は既存ツール**を使用し、チャットからは**上位者の依頼に基づく実行開始と修正のみ**を行う。

---

## 提案: チャットからのタスク操作ツール

### 1. `start_task_from_chat` - タスク実行開始

既存タスクのIDと依頼者IDを指定して、チャットセッションから実行を開始する。

**⚠️ 上位者からの依頼が必須** - `requester_id` が実行者の上位者でない場合はエラー。

```swift
/// start_task_from_chat - 既存タスクの実行を開始
///
/// 前提条件:
/// - チャットセッションからのみ呼び出し可能
/// - 指定タスクが自分に割り当てられていること
/// - ⚠️ 依頼者が自分の上位者であること（必須）
///
/// 動作:
/// 1. タスクの存在・割り当て確認
/// 2. 依頼者の階層バリデーション（requesterId が上位者か）
///    → 上位者でなければエラーで拒否
/// 3. タスクステータスを in_progress に変更
/// 4. チャットセッション→タスクセッションへの切り替え準備

func startTaskFromChat(
    session: AgentSession,
    taskId: String,              // 実行するタスクのID
    requesterId: String          // 依頼者のエージェントID（上位者であること）
) throws -> [String: Any]
```

**パラメータ**:
| 名前 | 型 | 必須 | 説明 |
|------|-----|------|------|
| `task_id` | String | ✓ | 実行するタスクのID |
| `requester_id` | String | ✓ | 依頼者のエージェントID（**上位者のみ**） |

**エラーケース**:
- `requester_id` が上位者でない → `unauthorized` エラー
- `requester_id` がプロジェクトに未所属 → `agent_not_assigned_to_project` エラー
- `task_id` が自分に割り当てられていない → `unauthorized` エラー

### 2. `update_task_from_chat` - タスク修正

チャットセッションから既存タスクを修正する。

**⚠️ 上位者からの依頼が必須** - `requester_id` が実行者の上位者でない場合はエラー。

```swift
/// update_task_from_chat - チャットからタスクを修正
///
/// 前提条件:
/// - チャットセッションからのみ呼び出し可能
/// - ⚠️ 依頼者が自分の上位者であること（必須）
///
/// 修正可能な項目:
/// - title, description, priority, status, blocked_reason

func updateTaskFromChat(
    session: AgentSession,
    taskId: String,
    requesterId: String,         // 依頼者のエージェントID（上位者であること）
    updates: [String: Any]       // 修正内容
) throws -> [String: Any]
```

**パラメータ**:
| 名前 | 型 | 必須 | 説明 |
|------|-----|------|------|
| `task_id` | String | ✓ | 修正するタスクのID |
| `requester_id` | String | ✓ | 依頼者のエージェントID（**上位者のみ**） |
| `title` | String | - | 新しいタイトル |
| `description` | String | - | 新しい説明 |
| `status` | String | - | 新しいステータス |
| `priority` | String | - | 新しい優先度 |
| `blocked_reason` | String | - | ブロック理由（status=blocked時） |

**エラーケース**:
- `requester_id` が上位者でない → `unauthorized` エラー
- `requester_id` がプロジェクトに未所属 → `agent_not_assigned_to_project` エラー

---

## バリデーション設計

### 1. 依頼者の検証

`requesterId` はエージェントが明示的に指定する。アプリ側で以下を検証する。

```swift
/// 依頼者の存在確認
func validateRequesterExists(requesterId: String) throws -> Agent {
    let id = AgentID(value: requesterId)
    guard let agent = try agentRepository.findById(id) else {
        throw MCPError.agentNotFound(requesterId)
    }
    return agent
}

/// 依頼者がプロジェクトに所属しているか確認
func validateRequesterInProject(
    requesterId: AgentID,
    projectId: ProjectID
) throws {
    let isAssigned = try projectAgentAssignmentRepository
        .isAgentAssignedToProject(agentId: requesterId, projectId: projectId)
    guard isAssigned else {
        throw MCPError.agentNotAssignedToProject(
            agentId: requesterId.value,
            projectId: projectId.value
        )
    }
}
```

### 2. 階層バリデーション（必須）

**⚠️ この検証は必須であり、失敗した場合はツール全体がエラーとなる。**

```swift
/// 依頼者が上位者かを検証（必須）
/// 上位者でない場合は即座にエラーを投げる
func validateRequesterIsAncestor(
    requesterId: AgentID,    // 依頼者
    executorId: AgentID,     // 実行者（自分）
    agents: [AgentID: Agent]
) throws {
    // 上位者（祖先）チェック
    let isAncestor = AgentHierarchy.isAncestorOf(
        ancestor: requesterId,
        descendant: executorId,
        agents: agents
    )

    guard isAncestor else {
        throw MCPError.unauthorized(
            "この操作には上位者からの依頼が必要です。" +
            "依頼者 '\(requesterId.value)' は '\(executorId.value)' の上位者ではありません。"
        )
    }
}
```

**階層判定の例**:
```
Owner
  └─ Manager
       ├─ Worker-Frontend-01
       └─ Worker-Frontend-02

Worker-Frontend-01 が start_task_from_chat を呼ぶ場合:
  requester_id = "owner"          → ✓ 許可（Owner は上位）
  requester_id = "manager-dev"    → ✓ 許可（Manager は上位）
  requester_id = "worker-frontend-02" → ✗ 拒否（同階層）
  requester_id = "worker-qa-01"   → ✗ 拒否（別系統）
```

### 3. タスク権限バリデーション

```swift
/// タスク操作の権限チェック
/// 注: 階層チェック（validateRequesterIsAncestor）は事前に実行済みの前提
func validateTaskPermission(
    task: Task,
    operatorId: AgentID,     // 操作する人（実行者）
    operation: TaskOperation
) throws {
    switch operation {
    case .start:
        // 実行開始: 自分に割り当てられたタスクのみ
        guard task.assigneeId == operatorId else {
            throw MCPError.unauthorized(
                "自分に割り当てられたタスクのみ開始できます。" +
                "タスク担当者: \(task.assigneeId?.value ?? "未割当")"
            )
        }

    case .update:
        // 修正: タスクの担当者、または関連するタスクであること
        // （階層チェックは事前に通過済み）
        let isAssignee = task.assigneeId == operatorId
        let isCreator = task.createdByAgentId == operatorId
        guard isAssignee || isCreator else {
            throw MCPError.unauthorized("このタスクの修正権限がありません")
        }
    }
}

enum TaskOperation {
    case start   // タスク実行開始
    case update  // タスク修正
}
```

**バリデーション実行順序**:
```
1. validateRequesterExists()        - 依頼者が存在するか
2. validateRequesterInProject()     - 依頼者がプロジェクトに所属しているか
3. validateRequesterIsAncestor()    - 依頼者が上位者か（⚠️ 必須）
4. validateTaskPermission()         - タスク操作の権限があるか
```

---

## 利用フロー

### 基本フロー: マネージャー → ワーカー

```
1. [タスクセッション] Manager: create_tasks_batch でサブタスク作成
   → tsk_dashboard (assignee: worker-frontend-01)
   → tsk_orders (assignee: worker-frontend-02)

2. [タスクセッション] Manager: assign_task + update_task_status
   → タスクを todo に変更

3. [タスクセッション] Manager: delegate_to_chat_session
   → Worker に詳細説明・コンテキスト共有

4. [チャットセッション] Worker: チャットで質問・確認

5. [チャットセッション] Worker: start_task_from_chat(
       task_id: "tsk_dashboard",
       requester_id: "manager-dev"    ← 明示的に指定
   )
   → 依頼者(manager-dev)の存在確認 ✓
   → 依頼者がプロジェクトに所属 ✓
   → 依頼者が上位者か階層チェック ✓
   → タスクステータスを in_progress に変更
   → 応答: "タスクセッションでlogoutし、タスク実行を開始してください"

6. [タスクセッション] Worker: logout → タスクセッションで再ログイン
   → get_next_action で作業開始
```

### 修正フロー: チャットでのタスク修正

```
1. [チャットセッション] Manager → Worker: 「要件が変わりました、説明を更新します」

2. [チャットセッション] Manager: update_task_from_chat(
       task_id: "tsk_dashboard",
       requester_id: "manager-dev",   ← 自分自身を指定
       description: "新しい要件..."
   )
   → 依頼者(manager-dev)の権限チェック ✓
   → タスクの description を更新

3. [チャットセッション] Worker: タスク更新を確認
```

---

## 応答形式

### start_task_from_chat の応答

```json
{
  "success": true,
  "task_id": "tsk_dashboard",
  "previous_status": "todo",
  "new_status": "in_progress",
  "requester_id": "manager-dev",
  "instruction": "タスクを開始しました。チャットセッションを終了し、タスクセッションで作業を開始してください。"
}
```

### update_task_from_chat の応答

```json
{
  "success": true,
  "task_id": "tsk_dashboard",
  "updated_fields": ["description", "priority"],
  "requester_id": "manager-dev",
  "instruction": "タスクを更新しました。"
}
```

### エラー応答

```json
{
  "success": false,
  "error": "unauthorized",
  "message": "この操作には上位者からの依頼が必要です。依頼者: worker-qa-01 は上位者ではありません。"
}
```

---

## 実装方針

### Phase 1: MCPツール実装

1. `start_task_from_chat` ツールの追加
   - ToolDefinitions.swift にスキーマ追加
   - ToolAuthorization.swift に権限設定（チャットセッション専用）
   - MCPServer.swift に実装

2. `update_task_from_chat` ツールの追加
   - 同様の構成

### Phase 2: バリデーション強化

1. `identifyRequester` - チャット相手の特定ロジック
2. `validateRequesterHierarchy` - 階層チェック
3. `validateTaskPermission` - タスク操作権限チェック

### Phase 3: Task エンティティ拡張（オプション）

```swift
// チャット経由での操作を追跡する場合
public struct Task {
    // 既存フィールド...

    /// チャットから開始された場合の会話ID
    public var startedFromConversationId: ConversationID?

    /// チャットからの修正履歴（監査用）
    public var chatModifications: [ChatModificationLog]?
}

struct ChatModificationLog: Codable {
    let conversationId: ConversationID
    let requesterId: AgentID
    let modifiedAt: Date
    let modifiedFields: [String]
}
```

---

## 既存機能との関係

| 機能 | 目的 | 新機能との関係 |
|------|------|---------------|
| `create_tasks_batch` | タスク作成 | そのまま維持（作成はここで行う） |
| `assign_task` | タスク割り当て | そのまま維持 |
| `update_task_status` | ステータス変更 | タスクセッション用、そのまま維持 |
| `delegate_to_chat_session` | 会話委譲 | そのまま維持（コミュニケーション用） |
| `request_task` | 自分用タスク作成 | そのまま維持 |
| `start_task_from_chat` (新) | 既存タスクの実行開始 | チャット→タスク実行の橋渡し |
| `update_task_from_chat` (新) | チャットからタスク修正 | チャット経由の修正 |

---

## 想定ユースケース

### UC1: マネージャーがワーカーにタスク詳細を説明して開始させる

```
Manager: create_tasks_batch → タスク作成 (tsk_xxx)
Manager: delegate_to_chat_session → Worker にチャット
Manager: (チャットで詳細説明)「このタスクを開始してください」
Worker: start_task_from_chat(
    task_id: "tsk_xxx",
    requester_id: "manager-dev"  ← Manager からの依頼
)
Worker: (タスクセッションで作業)
```

### UC2: マネージャーが要件変更を指示

マネージャー自身がチャットからタスクを修正する場合。

```
Manager: delegate_to_chat_session → Worker にチャット
Manager: "要件が変わりました"
Manager: update_task_from_chat(
    task_id: "tsk_xxx",
    requester_id: "owner"        ← Owner からの指示に基づく
    description: "新しい要件..."
)
Worker: (変更を確認して作業継続)
```

**注**: Manager が `requester_id` に自分自身を指定することはできない（自分は自分の上位者ではない）。
Owner など、Manager の上位者からの指示があった場合のみ修正可能。

### UC3: ワーカーがブロック報告（タスクセッション経由）

**注**: ワーカーがチャットからタスクを修正するには上位者の `requester_id` が必要。
単独でのブロック報告は**タスクセッション**の `update_task_status` を使用する。

```
[チャットセッション]
Worker → Manager: 「問題が発生しました。ブロックします。」

[タスクセッション]
Worker: update_task_status(  ← 既存ツール
    task_id: "tsk_xxx",
    status: "blocked",
    blocked_reason: "依存タスクが未完了"
)

[通知]
Manager: (blocked 通知を受けて対処)
```

---

## セキュリティ考慮事項

### 1. 上位者制約による権限昇格防止

**核心**: `requester_id` が上位者でなければツールは動作しない。

| シナリオ | 結果 |
|---------|------|
| Worker が `requester_id=manager-dev` で呼び出し | ✓ 許可（実際に Manager からの依頼なら正当） |
| Worker が `requester_id=worker-qa-01` で呼び出し | ✗ 拒否（同階層は上位者ではない） |
| Worker が虚偽の `requester_id` を指定 | ✗ 後続の監査で発覚、不正使用として扱う |

### 2. 虚偽申告への対策

`requester_id` はエージェントが自己申告するため、虚偽の可能性がある。

**対策**:
- チャット履歴との照合（実際にそのエージェントからメッセージを受信したか）
- 監査ログで `requester_id` と実際のチャット送信者を記録
- 不一致があれば警告フラグを立てる（将来拡張）

```swift
// オプション: チャット履歴との整合性チェック
func validateRequesterInChatHistory(
    requesterId: AgentID,
    session: AgentSession
) throws {
    let messages = try chatRepository.findMessages(
        projectId: session.projectId,
        agentId: session.agentId
    )
    let hasMessageFromRequester = messages.contains { $0.senderId == requesterId }

    if !hasMessageFromRequester {
        // 警告ログを記録（ブロックはしない）
        Self.log("[WARNING] requester_id '\(requesterId.value)' has no chat history with '\(session.agentId.value)'")
    }
}
```

### 3. 監査証跡

- チャット経由の操作は `requesterId` と共に記録
- タスクの `statusChangedByAgentId` に実行者を記録
- 依頼者情報もイベントログに保持

---

## チャットセッション → タスクセッションへの通知

### 背景

同一エージェントが複数のセッション（チャットセッション、タスクセッション）を持つ場合、
チャットセッションからタスクセッションに「チャットを確認してほしい」と通知したいケースがある。

**重要**: タスクセッションは、通知を受けた際に「これは自分自身（同一エージェント）の
チャットセッションからの通知である」と認識する必要がある。

### 既存の通知機能

```swift
// AgentNotificationType
enum AgentNotificationType {
    case statusChange  // ステータス変更通知
    case interrupt     // 割り込み通知（強制的に対応必須）
    case message       // メッセージ通知
}
```

通知はミドルウェアで検出され、`interrupt` タイプの場合はツール応答が差し替えられる。

### 新規: `notify_task_session` ツール

チャットセッションからタスクセッションへ「チャットを確認するように」通知を送信する。

**核心**: このツールの主目的は**チャット内容の確認を促す**こと。メッセージは補足情報。

```swift
/// notify_task_session - 自分のタスクセッションにチャット確認を促す通知を送信
///
/// 前提条件:
/// - チャットセッションからのみ呼び出し可能
/// - 通知先は自分自身（同一エージェント）のタスクセッション
///
/// 目的:
/// - 主目的: タスクセッションにチャット内容を確認するよう促す
/// - 補足: メッセージで概要を添えることができる
///
/// タスクセッションでのチャット確認方法:
/// - get_conversation_messages(conversation_id): 会話IDを指定してメッセージを取得

func notifyTaskSession(
    session: AgentSession,
    conversationId: String,   // 確認してほしい会話のID（必須）
    message: String?,         // 補足メッセージ（オプション）
    relatedTaskId: String?,   // 関連タスクID（オプション）
    priority: String?         // 優先度: "normal" | "high"（interruptにするか）
) throws -> [String: Any]
```

**パラメータ**:
| 名前 | 型 | 必須 | 説明 |
|------|-----|------|------|
| `conversation_id` | String | ✓ | 確認してほしい会話のID |
| `message` | String | - | 補足メッセージ（概要を添える場合） |
| `related_task_id` | String | - | 関連タスクID |
| `priority` | String | - | `normal`(default) / `high` |

### 新規: `get_conversation_messages` ツール

タスクセッションから会話IDを指定してチャットメッセージを取得する。

**目的**: `notify_task_session` で通知された会話の内容をタスクセッションで確認する。

```swift
/// get_conversation_messages - 会話IDを指定してチャットメッセージを取得
///
/// 前提条件:
/// - タスクセッションからのみ呼び出し可能
/// - 自分が参加している会話のみ取得可能
///
/// 動作:
/// 1. 会話IDで ChatMessage を検索
/// 2. 自分が参加者であることを確認
/// 3. メッセージ一覧を返す

func getConversationMessages(
    session: AgentSession,
    conversationId: String,   // 取得する会話のID
    limit: Int?               // 取得件数上限（デフォルト: 50）
) throws -> [String: Any]
```

**パラメータ**:
| 名前 | 型 | 必須 | 説明 |
|------|-----|------|------|
| `conversation_id` | String | ✓ | 取得する会話のID |
| `limit` | Int | - | 取得件数上限（デフォルト: 50） |

**応答**:
```json
{
  "success": true,
  "conversation_id": "conv_xxx",
  "messages": [
    {
      "id": "msg_001",
      "sender_id": "manager-dev",
      "content": "タスクの優先度を上げてください",
      "created_at": "2026-02-06T10:30:00Z"
    },
    {
      "id": "msg_002",
      "sender_id": "worker-frontend-01",
      "content": "承知しました",
      "created_at": "2026-02-06T10:31:00Z"
    }
  ],
  "total_count": 2,
  "instruction": "上記のメッセージを確認し、必要に応じて対応してください。"
}

### 通知タイプの拡張

```swift
public enum AgentNotificationType: String, Codable, Sendable, CaseIterable {
    case statusChange = "status_change"
    case interrupt = "interrupt"
    case message = "message"
    case chatSessionNotification = "chat_session_notification"  // 新規追加
}
```

### 通知の構造

```swift
let notification = AgentNotification(
    id: NotificationID.generate(),
    targetAgentId: session.agentId,      // 自分自身
    targetProjectId: session.projectId,
    type: priority == "high" ? .interrupt : .chatSessionNotification,
    action: "check_chat",
    taskId: relatedTaskId,
    conversationId: conversationId,      // 会話IDを含める
    message: message,
    instruction: """
        あなたのチャットセッションからの通知です。

        【重要】この通知は、あなた自身が別のセッション（チャットセッション）から
        送信したものです。チャットの内容を確認してください。

        確認方法:
        get_conversation_messages(conversation_id: "\(conversationId)") を呼び出してください。
        """,
    createdAt: Date()
)
```

### タスクセッションでの受信

タスクセッションがツールを呼び出した際、ミドルウェアで通知をチェック:

```swift
// MCPServer.swift - callToolAsync ミドルウェア
if let chatNotification = unreadNotifications.first(where: {
    $0.type == .chatSessionNotification
}) {
    // 通知メッセージを応答に追加（応答は差し替えない）
    responseContent["_chat_notification"] = [
        "message": chatNotification.message,
        "instruction": chatNotification.instruction,
        "from": "self_chat_session"  // 自分自身からの通知であることを明示
    ]
}

// priority == "high" (interrupt) の場合は既存の挙動で応答差し替え
```

### 利用フロー

```
1. [チャットセッション] Worker: 上位者から重要な指示を受ける
   Manager → Worker: 「今すぐタスクXの仕様を変更してください」
   （この会話は conversation_id: "conv_abc" で行われている）

2. [チャットセッション] Worker: タスクセッションに通知
   notify_task_session(
       conversation_id: "conv_abc",    ← 会話IDを渡す
       message: "Manager から緊急の仕様変更指示があります",
       related_task_id: "tsk_xxx",
       priority: "high"
   )

3. [タスクセッション] Worker: 次のツール呼び出し時に通知を受信
   ツール応答に通知が含まれる（または差し替え）
   → conversation_id も通知に含まれる

4. [タスクセッション] Worker: 会話内容を確認
   get_conversation_messages(conversation_id: "conv_abc")
   → チャットメッセージの内容を取得して対応
```

### 同一エージェント認識のポイント

通知の `instruction` に以下を明記:

```
【重要】この通知は、あなた自身が別のセッション（チャットセッション）から
送信したものです。
```

また、`conversation_id` を明示的に渡すことで:
- タスクセッションは `get_conversation_messages(conversation_id)` でチャット内容を直接取得可能
- チャットセッションに移行せずに内容を確認できる
- セッション間の連携がスムーズになる

これにより、タスクセッションのエージェントは:
- 通知が外部からではなく、自分自身のチャットセッションからであることを理解
- 会話IDを使って即座にチャット内容を確認できる
- セッション間の連携として適切に対応できる

### 応答形式

**notify_task_session の応答**:
```json
{
  "success": true,
  "notification_id": "ntf_xxx",
  "target_agent_id": "worker-frontend-01",
  "conversation_id": "conv_abc",
  "type": "chat_session_notification",
  "instruction": "タスクセッションに通知を送信しました。次回のツール呼び出し時に通知が届きます。"
}
```

**タスクセッションでの通知受信**:
```json
{
  "content": [{"type": "text", "text": "... 元のツール応答 ..."}],
  "_chat_notification": {
    "conversation_id": "conv_abc",
    "message": "Manager から緊急の仕様変更指示があります",
    "instruction": "あなたのチャットセッションからの通知です。get_conversation_messages(conversation_id: 'conv_abc') で内容を確認してください。",
    "from": "self_chat_session",
    "related_task_id": "tsk_xxx"
  }
}
```

**get_conversation_messages の応答**:
```json
{
  "success": true,
  "conversation_id": "conv_abc",
  "messages": [
    {
      "id": "msg_001",
      "sender_id": "manager-dev",
      "sender_name": "Manager",
      "content": "今すぐタスクXの仕様を変更してください",
      "created_at": "2026-02-06T10:30:00Z"
    },
    {
      "id": "msg_002",
      "sender_id": "worker-frontend-01",
      "sender_name": "Worker Frontend 01",
      "content": "承知しました。詳細を確認します。",
      "created_at": "2026-02-06T10:31:00Z"
    }
  ],
  "total_count": 2,
  "instruction": "上記のメッセージを確認し、必要に応じて対応してください。"
}
```

---

---

## 自己状況確認ツール

チャットセッション・タスクセッション両方から、自分のタスク状況や実行履歴を確認するためのツール。

### 新規: `get_my_tasks` ツール

ID指定なしで自分に割り当てられたタスク一覧を取得する。

```swift
/// get_my_tasks - 自分のタスク一覧を取得
///
/// 前提条件:
/// - 認証済みセッション（タスク・チャット両方で使用可能）
///
/// 動作:
/// 1. セッションから自分のagent_idを取得
/// 2. assignee_id = 自分 のタスクを検索
/// 3. オプションでステータスフィルタ

func getMyTasks(
    session: AgentSession,
    status: String?,          // フィルタ: "backlog" | "todo" | "in_progress" | "done" | "blocked"
    limit: Int?               // 取得件数上限（デフォルト: 20）
) throws -> [String: Any]
```

**パラメータ**:
| 名前 | 型 | 必須 | 説明 |
|------|-----|------|------|
| `status` | String | - | ステータスでフィルタ |
| `limit` | Int | - | 取得件数上限（デフォルト: 20） |

**応答**:
```json
{
  "success": true,
  "agent_id": "worker-frontend-01",
  "tasks": [
    {
      "task_id": "tsk_001",
      "title": "ダッシュボード実装",
      "status": "in_progress",
      "priority": "high",
      "created_at": "2026-02-05T09:00:00Z"
    },
    {
      "task_id": "tsk_002",
      "title": "ログイン画面修正",
      "status": "todo",
      "priority": "medium",
      "created_at": "2026-02-06T10:00:00Z"
    }
  ],
  "total_count": 2,
  "instruction": "上記があなたに割り当てられたタスクです。"
}
```

### 新規: `get_my_execution_history` ツール

自分のタスクセッション実行履歴の一覧を取得する。

**データソース**: `ExecutionLog` エンティティ

```swift
/// get_my_execution_history - 自分の実行履歴一覧を取得
///
/// 前提条件:
/// - 認証済みセッション（タスク・チャット両方で使用可能）
///
/// 動作:
/// 1. セッションから自分のagent_idを取得
/// 2. ExecutionLog から自分の実行履歴を検索
/// 3. 概要レベルの情報を返す（ログ内容は含まない）

func getMyExecutionHistory(
    session: AgentSession,
    taskId: String?,          // 特定タスクに絞り込み（オプション）
    status: String?,          // ステータスフィルタ: "running" | "completed" | "failed"
    limit: Int?               // 取得件数上限（デフォルト: 10）
) throws -> [String: Any]
```

**パラメータ**:
| 名前 | 型 | 必須 | 説明 |
|------|-----|------|------|
| `task_id` | String | - | 特定タスクに絞り込み |
| `status` | String | - | ステータスでフィルタ |
| `limit` | Int | - | 取得件数上限（デフォルト: 10） |

**応答**:
```json
{
  "success": true,
  "agent_id": "worker-frontend-01",
  "executions": [
    {
      "execution_id": "exec_001",
      "task_id": "tsk_001",
      "task_title": "ダッシュボード実装",
      "status": "completed",
      "started_at": "2026-02-06T09:00:00Z",
      "completed_at": "2026-02-06T11:30:00Z",
      "duration_seconds": 9000,
      "exit_code": 0,
      "has_log": true
    },
    {
      "execution_id": "exec_002",
      "task_id": "tsk_001",
      "task_title": "ダッシュボード実装",
      "status": "running",
      "started_at": "2026-02-06T14:00:00Z",
      "completed_at": null,
      "duration_seconds": null,
      "exit_code": null,
      "has_log": true
    }
  ],
  "total_count": 2,
  "instruction": "ログ内容を確認するには get_execution_log(execution_id) を呼び出してください。"
}
```

### 新規: `get_execution_log` ツール

特定の実行履歴のログ内容を取得する。

**データソース**: `ExecutionLog.logFilePath` が指すログファイル

```swift
/// get_execution_log - 実行ログの内容を取得
///
/// 前提条件:
/// - 認証済みセッション（タスク・チャット両方で使用可能）
/// - 自分の実行履歴のみ取得可能
///
/// 動作:
/// 1. execution_id で ExecutionLog を検索
/// 2. 自分の履歴であることを確認
/// 3. logFilePath からログファイルを読み取り
/// 4. 指定された範囲のログを返す

func getExecutionLog(
    session: AgentSession,
    executionId: String,      // 実行履歴ID
    tail: Int?,               // 末尾から何行取得するか（デフォルト: 100）
    offset: Int?              // 先頭からのオフセット（tail と排他）
) throws -> [String: Any]
```

**パラメータ**:
| 名前 | 型 | 必須 | 説明 |
|------|-----|------|------|
| `execution_id` | String | ✓ | 実行履歴ID |
| `tail` | Int | - | 末尾から取得する行数（デフォルト: 100） |
| `offset` | Int | - | 先頭からのオフセット（tail と排他） |

**応答**:
```json
{
  "success": true,
  "execution_id": "exec_001",
  "task_id": "tsk_001",
  "status": "completed",
  "log_file_path": "/logs/exec_001.log",
  "log_content": [
    "[2026-02-06T09:00:05Z] Starting task execution...",
    "[2026-02-06T09:00:10Z] Calling tool: read_file",
    "[2026-02-06T09:00:15Z] Tool result: success",
    "[2026-02-06T09:01:00Z] Calling tool: edit_file",
    "..."
  ],
  "total_lines": 250,
  "returned_lines": 100,
  "truncated": true,
  "instruction": "ログが切り詰められています。offset を指定して続きを取得できます。"
}
```

### ツール権限まとめ

| ツール | 権限 | タスク | チャット | 用途 |
|--------|------|:------:|:--------:|------|
| `get_my_tasks` | authenticated | ✓ | ✓ | 自分のタスク一覧 |
| `get_my_execution_history` | authenticated | ✓ | ✓ | 実行履歴一覧（概要） |
| `get_execution_log` | authenticated | ✓ | ✓ | 実行ログ内容取得 |

---

## 実装計画（テストファースト）

### Phase 1: 基盤準備

#### 1-1. エンティティ拡張

**テスト（RED）**:
```swift
// Tests/DomainTests/AgentNotificationTests.swift
func testChatSessionNotificationType() {
    let notification = AgentNotification.chatSessionNotification(
        targetAgentId: AgentID("worker-01"),
        targetProjectId: ProjectID("proj-01"),
        conversationId: ConversationID("conv-01"),
        message: "確認してください",
        relatedTaskId: TaskID("tsk-01")
    )
    XCTAssertEqual(notification.type, .chatSessionNotification)
    XCTAssertEqual(notification.conversationId?.value, "conv-01")
}
```

**実装（GREEN）**:
- `Sources/Domain/Entities/AgentNotification.swift`
  - `AgentNotificationType` に `.chatSessionNotification` 追加
  - `conversationId: ConversationID?` フィールド追加
  - ファクトリメソッド追加

**変更ファイル**:
| ファイル | 変更内容 |
|----------|----------|
| `AgentNotification.swift` | type追加、フィールド追加 |
| `AgentNotificationTests.swift` | 新規テスト |

---

#### 1-2. Repository拡張

**テスト（RED）**:
```swift
// Tests/InfrastructureTests/ExecutionLogRepositoryTests.swift
func testFindByAgentId() async throws {
    let log = ExecutionLog(taskId: taskId, agentId: agentId)
    try await repository.save(log)

    let results = try await repository.findByAgentId(agentId, limit: 10)
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results[0].agentId, agentId)
}

// Tests/InfrastructureTests/ChatMessageRepositoryTests.swift
func testFindByConversationId() async throws {
    let message = ChatMessage(
        senderId: agentId,
        content: "test",
        conversationId: conversationId
    )
    try await repository.save(message)

    let results = try await repository.findByConversationId(conversationId, limit: 50)
    XCTAssertEqual(results.count, 1)
}
```

**実装（GREEN）**:
- `Sources/Domain/Repositories/ExecutionLogRepository.swift`
  - `findByAgentId(agentId:limit:)` 追加
  - `findByAgentIdAndTaskId(agentId:taskId:limit:)` 追加
- `Sources/Infrastructure/SQLite/SQLiteExecutionLogRepository.swift`
  - 上記メソッドの実装
- `Sources/Domain/Repositories/ChatMessageRepository.swift`
  - `findByConversationId(conversationId:limit:)` 追加

**変更ファイル**:
| ファイル | 変更内容 |
|----------|----------|
| `ExecutionLogRepository.swift` | プロトコル拡張 |
| `SQLiteExecutionLogRepository.swift` | 実装追加 |
| `ChatMessageRepository.swift` | プロトコル拡張 |
| `SQLiteChatMessageRepository.swift` | 実装追加 |

---

### Phase 2: 自己状況確認ツール

#### 2-1. get_my_tasks

**テスト（RED）**:
```swift
// Tests/MCPServerTests/GetMyTasksTests.swift
func testGetMyTasks_ReturnsAssignedTasks() async throws {
    // Setup: タスクを作成し、自分に割り当て
    let task = try await createTask(assigneeId: agentId)

    // Execute
    let result = try await mcpServer.callTool(
        name: "get_my_tasks",
        arguments: [:],
        caller: .worker(agentId, session)
    )

    // Verify
    let tasks = result["tasks"] as! [[String: Any]]
    XCTAssertEqual(tasks.count, 1)
    XCTAssertEqual(tasks[0]["task_id"] as? String, task.id.value)
}

func testGetMyTasks_FilterByStatus() async throws {
    // Setup: 複数ステータスのタスクを作成

    // Execute with filter
    let result = try await mcpServer.callTool(
        name: "get_my_tasks",
        arguments: ["status": "in_progress"],
        caller: .worker(agentId, session)
    )

    // Verify: in_progress のみ
}
```

**実装（GREEN）**:
- `Sources/MCPServer/Tools/ToolDefinitions.swift` - スキーマ追加
- `Sources/MCPServer/Authorization/ToolAuthorization.swift` - 権限設定
- `Sources/MCPServer/MCPServer.swift` - `getMyTasks()` 実装

---

#### 2-2. get_my_execution_history

**テスト（RED）**:
```swift
// Tests/MCPServerTests/GetMyExecutionHistoryTests.swift
func testGetMyExecutionHistory_ReturnsOwnExecutions() async throws {
    // Setup: 実行ログを作成
    let log = ExecutionLog(taskId: taskId, agentId: agentId)
    try await executionLogRepository.save(log)

    // Execute
    let result = try await mcpServer.callTool(
        name: "get_my_execution_history",
        arguments: [:],
        caller: .worker(agentId, session)
    )

    // Verify
    let executions = result["executions"] as! [[String: Any]]
    XCTAssertEqual(executions.count, 1)
    XCTAssertTrue(executions[0]["has_log"] as! Bool)
}

func testGetMyExecutionHistory_FilterByTaskId() async throws {
    // タスク絞り込みテスト
}
```

**実装（GREEN）**:
- `ToolDefinitions.swift` - スキーマ追加
- `ToolAuthorization.swift` - 権限設定（authenticated）
- `MCPServer.swift` - `getMyExecutionHistory()` 実装

---

#### 2-3. get_execution_log

**テスト（RED）**:
```swift
// Tests/MCPServerTests/GetExecutionLogTests.swift
func testGetExecutionLog_ReturnsLogContent() async throws {
    // Setup: ログファイルを作成
    let logPath = "/tmp/test_exec.log"
    try "Line 1\nLine 2\nLine 3".write(toFile: logPath, atomically: true, encoding: .utf8)

    var log = ExecutionLog(taskId: taskId, agentId: agentId)
    log.setLogFilePath(logPath)
    try await executionLogRepository.save(log)

    // Execute
    let result = try await mcpServer.callTool(
        name: "get_execution_log",
        arguments: ["execution_id": log.id.value],
        caller: .worker(agentId, session)
    )

    // Verify
    let content = result["log_content"] as! [String]
    XCTAssertEqual(content.count, 3)
}

func testGetExecutionLog_TailOption() async throws {
    // tail オプションのテスト
}

func testGetExecutionLog_RejectsOthersLog() async throws {
    // 他人のログは取得不可
    let otherAgentId = AgentID("other-agent")
    let log = ExecutionLog(taskId: taskId, agentId: otherAgentId)

    do {
        _ = try await mcpServer.callTool(
            name: "get_execution_log",
            arguments: ["execution_id": log.id.value],
            caller: .worker(agentId, session)  // 別のエージェント
        )
        XCTFail("Should throw unauthorized")
    } catch {
        // Expected
    }
}
```

**実装（GREEN）**:
- `ToolDefinitions.swift` - スキーマ追加
- `ToolAuthorization.swift` - 権限設定（authenticated）
- `MCPServer.swift` - `getExecutionLog()` 実装

---

### Phase 3: チャット→タスク操作ツール

#### 3-1. start_task_from_chat

**テスト（RED）**:
```swift
// Tests/MCPServerTests/StartTaskFromChatTests.swift
func testStartTaskFromChat_Success() async throws {
    // Setup: タスク作成、上位者設定
    let manager = try await createAgent(role: .manager)
    let worker = try await createAgent(role: .worker, parentId: manager.id)
    let task = try await createTask(assigneeId: worker.id, status: .todo)

    // Execute: チャットセッションから
    let chatSession = AgentSession(agentId: worker.id, projectId: projectId, purpose: .chat)
    let result = try await mcpServer.callTool(
        name: "start_task_from_chat",
        arguments: [
            "task_id": task.id.value,
            "requester_id": manager.id.value
        ],
        caller: .worker(worker.id, chatSession)
    )

    // Verify
    XCTAssertTrue(result["success"] as! Bool)
    XCTAssertEqual(result["new_status"] as? String, "in_progress")
}

func testStartTaskFromChat_RejectsNonSuperior() async throws {
    // Setup: 同階層のエージェント
    let worker1 = try await createAgent(role: .worker)
    let worker2 = try await createAgent(role: .worker)
    let task = try await createTask(assigneeId: worker1.id)

    // Execute: worker2 を requester_id に指定
    let chatSession = AgentSession(agentId: worker1.id, projectId: projectId, purpose: .chat)

    do {
        _ = try await mcpServer.callTool(
            name: "start_task_from_chat",
            arguments: [
                "task_id": task.id.value,
                "requester_id": worker2.id.value  // 同階層 = 上位者ではない
            ],
            caller: .worker(worker1.id, chatSession)
        )
        XCTFail("Should throw unauthorized")
    } catch let error as MCPError {
        XCTAssertTrue(error.message.contains("上位者"))
    }
}

func testStartTaskFromChat_RejectsFromTaskSession() async throws {
    // タスクセッションからは呼び出し不可
}
```

**実装（GREEN）**:
- `ToolDefinitions.swift` - スキーマ追加
- `ToolAuthorization.swift` - 権限設定（chatOnly）
- `MCPServer.swift` - `startTaskFromChat()` 実装
- 階層バリデーション実装

---

#### 3-2. update_task_from_chat

**テスト（RED）**:
```swift
// Tests/MCPServerTests/UpdateTaskFromChatTests.swift
func testUpdateTaskFromChat_Success() async throws {
    // Setup
    let manager = try await createAgent(role: .manager)
    let worker = try await createAgent(role: .worker, parentId: manager.id)
    let task = try await createTask(assigneeId: worker.id)

    // Execute
    let chatSession = AgentSession(agentId: worker.id, projectId: projectId, purpose: .chat)
    let result = try await mcpServer.callTool(
        name: "update_task_from_chat",
        arguments: [
            "task_id": task.id.value,
            "requester_id": manager.id.value,
            "description": "更新された説明"
        ],
        caller: .worker(worker.id, chatSession)
    )

    // Verify
    XCTAssertTrue(result["success"] as! Bool)
    let updatedTask = try await taskRepository.findById(task.id)
    XCTAssertEqual(updatedTask?.description, "更新された説明")
}

func testUpdateTaskFromChat_RejectsNonSuperior() async throws {
    // 上位者以外は拒否
}
```

**実装（GREEN）**:
- `ToolDefinitions.swift` - スキーマ追加
- `ToolAuthorization.swift` - 権限設定（chatOnly）
- `MCPServer.swift` - `updateTaskFromChat()` 実装

---

### Phase 4: セッション間通知

#### 4-1. notify_task_session

**テスト（RED）**:
```swift
// Tests/MCPServerTests/NotifyTaskSessionTests.swift
func testNotifyTaskSession_CreatesNotification() async throws {
    // Setup
    let chatSession = AgentSession(agentId: agentId, projectId: projectId, purpose: .chat)

    // Execute
    let result = try await mcpServer.callTool(
        name: "notify_task_session",
        arguments: [
            "conversation_id": "conv_abc",
            "message": "確認してください",
            "related_task_id": "tsk_001"
        ],
        caller: .worker(agentId, chatSession)
    )

    // Verify: 通知が作成されている
    XCTAssertTrue(result["success"] as! Bool)

    let notifications = try await notificationRepository.findUnreadByAgentAndProject(
        agentId: agentId, projectId: projectId
    )
    XCTAssertEqual(notifications.count, 1)
    XCTAssertEqual(notifications[0].type, .chatSessionNotification)
    XCTAssertEqual(notifications[0].conversationId?.value, "conv_abc")
}

func testNotifyTaskSession_HighPriorityCreatesInterrupt() async throws {
    // priority: "high" の場合は interrupt タイプ
}

func testNotifyTaskSession_RejectsFromTaskSession() async throws {
    // タスクセッションからは呼び出し不可
}
```

**実装（GREEN）**:
- `ToolDefinitions.swift` - スキーマ追加
- `ToolAuthorization.swift` - 権限設定（chatOnly）
- `MCPServer.swift` - `notifyTaskSession()` 実装

---

#### 4-2. get_conversation_messages

**テスト（RED）**:
```swift
// Tests/MCPServerTests/GetConversationMessagesTests.swift
func testGetConversationMessages_ReturnsMessages() async throws {
    // Setup: 会話メッセージを作成
    let conversationId = ConversationID("conv_abc")
    let msg1 = ChatMessage(
        senderId: AgentID("manager"),
        content: "指示です",
        conversationId: conversationId
    )
    let msg2 = ChatMessage(
        senderId: agentId,
        content: "承知しました",
        conversationId: conversationId
    )
    try await chatMessageRepository.save(msg1)
    try await chatMessageRepository.save(msg2)

    // Execute: タスクセッションから
    let taskSession = AgentSession(agentId: agentId, projectId: projectId, purpose: .task)
    let result = try await mcpServer.callTool(
        name: "get_conversation_messages",
        arguments: ["conversation_id": conversationId.value],
        caller: .worker(agentId, taskSession)
    )

    // Verify
    let messages = result["messages"] as! [[String: Any]]
    XCTAssertEqual(messages.count, 2)
}

func testGetConversationMessages_RejectsFromChatSession() async throws {
    // チャットセッションからは呼び出し不可
}
```

**実装（GREEN）**:
- `ToolDefinitions.swift` - スキーマ追加
- `ToolAuthorization.swift` - 権限設定（taskOnly）
- `MCPServer.swift` - `getConversationMessages()` 実装

---

#### 4-3. 通知ミドルウェア拡張

**テスト（RED）**:
```swift
// Tests/MCPServerTests/NotificationMiddlewareTests.swift
func testMiddleware_IncludesConversationIdInNotification() async throws {
    // Setup: chatSessionNotification を作成
    let notification = AgentNotification.chatSessionNotification(
        targetAgentId: agentId,
        targetProjectId: projectId,
        conversationId: ConversationID("conv_abc"),
        message: "確認してください"
    )
    try await notificationRepository.save(notification)

    // Execute: タスクセッションで任意のツールを呼び出し
    let taskSession = AgentSession(agentId: agentId, projectId: projectId, purpose: .task)
    let result = try await mcpServer.callTool(
        name: "get_my_tasks",
        arguments: [:],
        caller: .worker(agentId, taskSession)
    )

    // Verify: 応答に通知情報が含まれる
    let chatNotification = result["_chat_notification"] as? [String: Any]
    XCTAssertNotNil(chatNotification)
    XCTAssertEqual(chatNotification?["conversation_id"] as? String, "conv_abc")
    XCTAssertEqual(chatNotification?["message"] as? String, "確認してください")
}
```

**実装（GREEN）**:
- `MCPServer.swift` - `callToolAsync` ミドルウェア拡張

---

### Phase 5: 統合テスト

#### 5-1. E2Eシナリオテスト

**テスト（RED）**:
```swift
// Tests/IntegrationTests/ChatTaskExecutionE2ETests.swift
func testE2E_ManagerRequestsWorkerToStartTask() async throws {
    // 1. Manager がタスクを作成
    // 2. Manager → Worker チャット開始
    // 3. Worker が start_task_from_chat 呼び出し
    // 4. タスクが in_progress になる
    // 5. Worker がタスクセッションで作業開始
}

func testE2E_ChatNotificationToTaskSession() async throws {
    // 1. Worker がチャットで指示を受ける
    // 2. Worker が notify_task_session 呼び出し
    // 3. Worker のタスクセッションで通知を受信
    // 4. get_conversation_messages でチャット内容確認
}
```

---

### 実装順序サマリー

| Phase | 内容 | 依存 |
|-------|------|------|
| 1-1 | エンティティ拡張 | なし |
| 1-2 | Repository拡張 | 1-1 |
| 2-1 | get_my_tasks | 1-2 |
| 2-2 | get_my_execution_history | 1-2 |
| 2-3 | get_execution_log | 2-2 |
| 3-1 | start_task_from_chat | 1-1 |
| 3-2 | update_task_from_chat | 3-1 |
| 4-1 | notify_task_session | 1-1 |
| 4-2 | get_conversation_messages | 1-2 |
| 4-3 | 通知ミドルウェア拡張 | 4-1 |
| 5-1 | E2E統合テスト | 全Phase |

---

### 変更ファイル一覧

| ファイル | Phase | 変更内容 |
|----------|-------|----------|
| `AgentNotification.swift` | 1-1 | type追加、conversationId追加 |
| `ExecutionLogRepository.swift` | 1-2 | findByAgentId追加 |
| `SQLiteExecutionLogRepository.swift` | 1-2 | 実装 |
| `ChatMessageRepository.swift` | 1-2 | findByConversationId追加 |
| `SQLiteChatMessageRepository.swift` | 1-2 | 実装 |
| `ToolDefinitions.swift` | 2-4 | 7ツール追加 |
| `ToolAuthorization.swift` | 2-4 | 権限設定追加 |
| `MCPServer.swift` | 2-4 | 7メソッド実装、ミドルウェア拡張 |

---

## 次のステップ（実装開始）

1. [x] Phase 1-1: エンティティ拡張（テスト→実装）✅ 2026-02-06
   - AgentNotificationType に chatSessionNotification 追加
   - AgentNotification に conversationId フィールド追加
   - ファクトリメソッド createChatSessionNotification 追加
   - NotificationRepository の Record 更新
   - DBマイグレーション v50 追加
2. [x] Phase 1-2: Repository拡張（テスト→実装）✅ 2026-02-06
   - ChatRepositoryProtocol に findByConversationId 追加
   - ChatFileRepository に実装追加
   - テスト4件追加・全パス
   - MockリポジトリをProtocol準拠に更新
3. [x] Phase 2: 自己状況確認ツール（テスト→実装）✅ 2026-02-06
   - [x] ツール定義追加（ToolDefinitions.swift）✅ 2026-02-06
   - [x] 権限設定追加（ToolAuthorization.swift）✅ 2026-02-06
   - [x] 定義・権限テスト10件パス ✅ 2026-02-06
   - [x] MCPServer.swift ハンドラー実装 ✅ 2026-02-06
   - [x] MCPError.executionLogNotFound ケース追加 ✅ 2026-02-06
4. [x] Phase 3: チャット→タスク操作ツール（テスト→実装）✅ 2026-02-06
   - [x] ツール定義追加（start_task_from_chat, update_task_from_chat）✅ 2026-02-06
   - [x] 権限設定追加（chatOnly）✅ 2026-02-06
   - [x] 定義・権限テスト10件パス ✅ 2026-02-06
   - [x] MCPServer.swift ハンドラー実装 ✅ 2026-02-06
   - [x] isAncestorAgent 上位者確認ヘルパー追加 ✅ 2026-02-06
5. [x] Phase 4: セッション間通知（テスト→実装）✅ 2026-02-06
   - [x] ツール定義追加（notify_task_session, get_conversation_messages）✅ 2026-02-06
   - [x] 権限設定追加（chatOnly, taskOnly）✅ 2026-02-06
   - [x] 定義・権限テスト10件パス ✅ 2026-02-06
   - [x] MCPServer.swift ハンドラー実装 ✅ 2026-02-06
   - [x] notifyTaskSession: AgentNotification.createChatSessionNotification 使用
   - [x] getConversationMessages: chatRepository.findByConversationId 使用
6. [x] Phase 5: 統合テスト ✅ 2026-02-06
   - [x] ChatTaskExecutionE2ETests.swift 作成
   - [x] E2Eシナリオテスト6件パス
   - [x] 全ツール定義・認可統合確認
7. [ ] パイロットテストでの検証
