# ツール認可拡張設計

MCPツールの認可システムを拡張し、セッションのpurpose（task/chat）に基づくアクセス制御と、コンテキスト対応のhelpツールを追加する。

## 背景

### 現状の課題

1. **purpose による制限がない**: チャットセッション（purpose=chat）でもタスク系ツールを呼び出せてしまう
2. **ツール情報の取得手段がない**: エージェントが利用可能なツールを動的に確認する方法がない
3. **認可の一貫性**: `get_next_action`の指示で誘導しているが、認可レベルでの制限がない

### 解決策

1. `ToolPermission`にpurposeベースの権限を追加
2. コンテキスト対応の`help`ツールを新設

---

## 設計

### 1. Purpose ベース認可

#### ToolPermission 拡張

```swift
enum ToolPermission: String {
    // 既存
    case unauthenticated = "unauthenticated"
    case coordinatorOnly = "coordinator_only"
    case managerOnly = "manager_only"
    case workerOnly = "worker_only"
    case authenticated = "authenticated"

    // 新規
    case chatOnly = "chat_only"      // purpose=chat のセッションのみ
    case taskOnly = "task_only"      // purpose=task のセッションのみ
}
```

#### ツール権限マッピング

| ツール | 現在の権限 | 新しい権限 |
|--------|-----------|-----------|
| `get_pending_messages` | authenticated | **chatOnly** |
| `respond_chat` | authenticated | **chatOnly** |
| `start_conversation` | authenticated | **chatOnly** |
| `end_conversation` | authenticated | **chatOnly** |
| `send_message` | authenticated | **chatOnly** |
| `delegate_to_chat_session` | (新規) | **taskOnly** |
| `get_my_task` | authenticated | authenticated（変更なし） |
| `report_completed` | authenticated | authenticated（変更なし） |

> **設計判断**:
> - **コミュニケーション系ツール**（会話・メッセージ）は `chatOnly` に統一
> - **タスク系ツール**は `taskOnly` にしない（チャットセッションでも参照は許可）
> - タスクセッションからコミュニケーションが必要な場合は `delegate_to_chat_session` を使用
>
> **詳細:** [TASK_CHAT_SESSION_SEPARATION.md](./TASK_CHAT_SESSION_SEPARATION.md)

#### 認可チェックロジック

```swift
static func authorize(tool: String, caller: CallerType) throws {
    // ... 既存のチェック ...

    // chatOnly: purpose=chat のセッションのみ
    case (.chatOnly, .manager(_, let session)), (.chatOnly, .worker(_, let session)):
        guard session.purpose == .chat else {
            throw ToolAuthorizationError.chatSessionRequired(tool)
        }
        return
    case (.chatOnly, _):
        throw ToolAuthorizationError.authenticationRequired(tool)

    // taskOnly: purpose=task のセッションのみ
    case (.taskOnly, .manager(_, let session)), (.taskOnly, .worker(_, let session)):
        guard session.purpose == .task else {
            throw ToolAuthorizationError.taskSessionRequired(tool)
        }
        return
    case (.taskOnly, _):
        throw ToolAuthorizationError.authenticationRequired(tool)
}
```

#### エラーメッセージ

```swift
case chatSessionRequired(String)
case taskSessionRequired(String)

// メッセージ
"Tool 'respond_chat' requires a chat session. Current session purpose is 'task'."
"Tool 'xxx' requires a task session. Current session purpose is 'chat'."
```

---

### 2. Help ツール

#### 目的

- エージェントが**現在のコンテキストで利用可能なツール**を確認できる
- 認証前でも呼び出し可能（認証フローの確認用）
- 個別ツールの詳細（パラメータ、使用例）を取得可能

#### インターフェース

```json
{
  "name": "help",
  "description": "利用可能なMCPツールの一覧と詳細を表示します。呼び出し元の認証状態とセッションのpurposeに応じて、実際に利用可能なツールのみが表示されます。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "tool_name": {
        "type": "string",
        "description": "特定のツール名を指定すると、そのツールの詳細（パラメータ、使用例）を表示します。省略すると利用可能なツール一覧を表示します。"
      }
    },
    "required": []
  }
}
```

#### 権限

```swift
"help": .unauthenticated  // 誰でも呼び出し可能
```

#### レスポンス構造

**一覧表示（tool_name 省略時）:**

```json
{
  "context": {
    "caller_type": "worker",
    "session_purpose": "task",
    "agent_id": "agent-001",
    "project_id": "proj-001"
  },
  "available_tools": [
    {
      "name": "get_my_task",
      "description": "自分に割り当てられた実行中のタスクを取得します",
      "category": "authenticated"
    },
    {
      "name": "get_next_action",
      "description": "次に実行すべきアクションの指示を取得します",
      "category": "authenticated"
    },
    {
      "name": "report_completed",
      "description": "タスク完了を報告します",
      "category": "worker"
    }
  ],
  "unavailable_info": {
    "chat_tools": "チャットツール（get_pending_messages, respond_chat）はpurpose=chatのセッションでのみ利用可能です",
    "manager_tools": "Manager専用ツール（assign_task等）はManager権限が必要です"
  },
  "total_available": 12
}
```

**詳細表示（tool_name 指定時）:**

```json
{
  "name": "report_completed",
  "description": "タスクの完了を報告します。result引数で完了状態を指定します。",
  "category": "worker",
  "available": true,
  "parameters": [
    {
      "name": "session_token",
      "type": "string",
      "required": true,
      "description": "認証セッショントークン"
    },
    {
      "name": "result",
      "type": "string",
      "required": true,
      "enum": ["success", "failed", "blocked"],
      "description": "完了結果: success=成功, failed=失敗, blocked=外部要因でブロック"
    },
    {
      "name": "summary",
      "type": "string",
      "required": false,
      "description": "完了サマリー（任意）"
    }
  ],
  "example": {
    "session_token": "sess_xxx",
    "result": "success",
    "summary": "全てのサブタスクを完了しました"
  }
}
```

**利用不可ツールの詳細表示:**

```json
{
  "name": "respond_chat",
  "description": "チャットメッセージに応答します",
  "category": "chat_only",
  "available": false,
  "reason": "このツールはpurpose=chatのセッションでのみ利用可能です。現在のセッションはpurpose=taskです。"
}
```

#### コンテキスト別の表示内容

| 呼び出し元 | 表示されるツール |
|-----------|-----------------|
| 未認証 | `authenticate`, `help` |
| Coordinator | `health_check`, `list_managed_agents`, `get_agent_action`, 等 |
| Manager (task) | Manager専用 + 認証済み共通（チャット系除く） |
| Manager (chat) | Manager専用 + 認証済み共通 + チャット系 |
| Worker (task) | Worker専用 + 認証済み共通（チャット系除く） |
| Worker (chat) | Worker専用 + 認証済み共通 + チャット系 |

---

## データ構造

### ToolDefinitions 拡張

ツール定義にカテゴリとexampleを追加:

```swift
static let reportCompleted: [String: Any] = [
    "name": "report_completed",
    "description": "タスクの完了を報告します",
    "category": "worker",  // NEW: カテゴリ情報
    "inputSchema": [...],
    "example": [           // NEW: 使用例
        "session_token": "sess_xxx",
        "result": "success"
    ]
]
```

### ToolAuthorization 拡張

カテゴリとpurposeのマッピング:

```swift
struct ToolMetadata {
    let permission: ToolPermission
    let category: String
    let purposeRestriction: AgentPurpose?  // nil = 制限なし
}

static let toolMetadata: [String: ToolMetadata] = [
    "authenticate": ToolMetadata(
        permission: .unauthenticated,
        category: "認証",
        purposeRestriction: nil
    ),
    "respond_chat": ToolMetadata(
        permission: .chatOnly,
        category: "チャット",
        purposeRestriction: .chat
    ),
    // ...
]
```

---

## セキュリティ考慮

1. **情報漏洩防止**: helpは利用不可ツールの存在は示すが、詳細パラメータは隠す（available=falseの場合）
2. **認可の二重チェック**: helpで表示されても、実際の呼び出し時に再度認可チェック
3. **セッション情報の最小露出**: contextにはagent_id, project_idのみ（トークンは含めない）

---

## 参照

- 現行認可システム: `Sources/MCPServer/Authorization/ToolAuthorization.swift`
- ツール定義: `Sources/MCPServer/Tools/ToolDefinitions.swift`
- セッション管理: `Sources/Domain/Entities/AgentSession.swift`
- チャット機能設計: `docs/design/CHAT_FEATURE.md`
