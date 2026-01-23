# 設計書: タスクセッションからのメッセージ送信機能

## 概要

タスク実行中のエージェントが、同一プロジェクト内の他のエージェントにメッセージを送信できる機能を追加する。

### 背景

現在、チャット関連ツール（`get_pending_messages`, `respond_chat`）は `chatOnly` 権限であり、チャットセッション（`purpose=chat`）でのみ利用可能。タスク実行中のエージェントが他のエージェントと非同期でコミュニケーションを取る手段がない。

### 目的

- タスク実行中のエージェント間コミュニケーションを可能にする
- 既存のチャットインフラ（ファイルベース）を活用する
- 非同期送信（送りっぱなし、応答待ちなし）をサポートする

---

## 設計方針

| 観点 | 決定 | 理由 |
|------|------|------|
| ストレージ | 既存ファイルベース活用 | 実装コスト削減、一貫性維持 |
| 通信方式 | 非同期（送りっぱなし） | タスク実行への影響を最小化 |
| スコープ | 同一プロジェクト内のみ | 権限管理の簡素化、セキュリティ |
| 通知連携 | 将来対応 | 現時点ではポーリングで検知 |

---

## 現状アーキテクチャ

### ストレージ構造

```
{project.workingDirectory}/
└── .ai-pm/
    └── agents/
        └── {agent-id}/
            └── chat.jsonl    # JSONL形式、追記型
```

### 保存方式: 双方向保存（Dual Write）

メッセージ送信時、送信者と受信者の両方のファイルに書き込む。

**送信者のファイル**:
```jsonl
{"id":"msg_01","senderId":"agent-a","receiverId":"agent-b","content":"質問です","createdAt":"..."}
```

**受信者のファイル**:
```jsonl
{"id":"msg_01","senderId":"agent-a","content":"質問です","createdAt":"..."}
```

- `receiverId` は送信者のファイルにのみ存在（誰宛てか記録）
- 受信者のファイルには `receiverId` なし（自分のファイル = 自分宛て）

### 既存実装

- `ChatFileRepository.saveMessageDualWrite()`: 双方向保存メソッド
- `ChatMessage`: メッセージエンティティ（senderId, receiverId, content, etc.）

---

## 新規ツール設計

### ツール名: `send_message`

### 権限

```swift
// ToolAuthorization.swift
"send_message": .authenticated  // タスク・チャット両方で使用可能
```

### 定義

```swift
// ToolDefinitions.swift
static let sendMessage: [String: Any] = [
    "name": "send_message",
    "description": """
        プロジェクト内の他のエージェントにメッセージを送信します（非同期）。
        受信者は get_pending_messages またはチャット画面で確認できます。
        タスクセッション・チャットセッションの両方で使用可能です。
        """,
    "inputSchema": [
        "type": "object",
        "properties": [
            "session_token": [
                "type": "string",
                "description": "authenticateツールで取得したセッショントークン"
            ],
            "target_agent_id": [
                "type": "string",
                "description": "送信先エージェントID（同一プロジェクト内のエージェントのみ指定可能）"
            ],
            "content": [
                "type": "string",
                "description": "メッセージ内容（最大4,000文字）"
            ],
            "related_task_id": [
                "type": "string",
                "description": "関連タスクID（任意）"
            ]
        ],
        "required": ["session_token", "target_agent_id", "content"]
    ]
]
```

---

## データフロー

### 送信フロー

```
┌─────────────────────────────────────────────────────────────────────┐
│ Agent A (タスクセッション)                                            │
│                                                                      │
│  send_message(                                                       │
│    session_token: "...",                                             │
│    target_agent_id: "agent-b",                                       │
│    content: "タスクXについて質問があります"                             │
│  )                                                                   │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│ MCP Server                                                           │
│                                                                      │
│  1. セッション検証                                                     │
│  2. target_agent_id がプロジェクト内か確認                             │
│  3. 自分自身への送信でないか確認                                        │
│  4. ChatMessage 作成                                                  │
│  5. saveMessageDualWrite() で双方向保存                               │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
                    ▼                               ▼
┌───────────────────────────┐      ┌───────────────────────────┐
│ Agent A のファイル         │      │ Agent B のファイル         │
│ .ai-pm/agents/agent-a/    │      │ .ai-pm/agents/agent-b/    │
│ chat.jsonl                │      │ chat.jsonl                │
│                           │      │                           │
│ {"id":"msg_01",           │      │ {"id":"msg_01",           │
│  "senderId":"agent-a",    │      │  "senderId":"agent-a",    │
│  "receiverId":"agent-b",  │      │  "content":"タスクXに...",│
│  "content":"タスクXに...",│      │  "createdAt":"..."}       │
│  "createdAt":"..."}       │      │                           │
└───────────────────────────┘      └───────────────────────────┘
```

### 受信フロー

受信者（Agent B）は以下の方法でメッセージを確認できる：

1. **チャットセッション起動時**: `get_pending_messages()` で取得
2. **Web UI**: REST API `/projects/{id}/agents/{agentId}/chat/messages` でポーリング
3. **ネイティブアプリ**: チャット画面でポーリング表示

```
┌─────────────────────────────────────────────────────────────────────┐
│ Agent B (チャットセッション)                                          │
│                                                                      │
│  get_pending_messages(session_token: "...")                          │
│                                                                      │
│  Response:                                                           │
│  {                                                                   │
│    "pending_messages": [                                             │
│      {                                                               │
│        "id": "msg_01",                                               │
│        "senderId": "agent-a",                                        │
│        "content": "タスクXについて質問があります",                      │
│        "createdAt": "2026-01-23T10:00:00Z"                           │
│      }                                                               │
│    ]                                                                 │
│  }                                                                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 実装詳細

### 権限チェック

```swift
// MCPServer.swift
private func handleSendMessage(
    session: AgentSession,
    targetAgentId: String,
    content: String,
    relatedTaskId: String?
) throws -> [String: Any] {

    // 1. コンテンツ長チェック
    guard content.count <= 4000 else {
        throw MCPError.contentTooLong(maxLength: 4000)
    }

    // 2. 自分自身への送信は禁止
    guard targetAgentId != session.agentId.value else {
        throw MCPError.cannotMessageSelf
    }

    // 3. 送信先エージェントの存在確認
    guard let targetAgent = try agentRepository.findById(AgentID(targetAgentId)) else {
        throw MCPError.agentNotFound(targetAgentId)
    }

    // 4. 同一プロジェクト内のエージェントか確認
    //    (プロジェクトに割り当てられているエージェントのみ送信可能)
    let assignedAgents = try projectRepository.getAssignedAgents(projectId: session.projectId)
    guard assignedAgents.contains(where: { $0.id.value == targetAgentId }) else {
        throw MCPError.targetAgentNotInProject(targetAgentId, projectId: session.projectId.value)
    }

    // 5. メッセージ作成
    let message = ChatMessage(
        id: ChatMessageID(UUID().uuidString),
        senderId: session.agentId,
        receiverId: AgentID(targetAgentId),
        content: content,
        createdAt: Date(),
        relatedTaskId: relatedTaskId.map { TaskID($0) },
        relatedHandoffId: nil
    )

    // 6. 双方向保存
    try chatRepository.saveMessageDualWrite(
        message,
        projectId: session.projectId,
        senderAgentId: session.agentId,
        receiverAgentId: AgentID(targetAgentId)
    )

    return [
        "success": true,
        "message_id": message.id.value,
        "target_agent_id": targetAgentId
    ]
}
```

### エラーケース

| エラー | 条件 | レスポンス |
|--------|------|-----------|
| `content_too_long` | content > 4,000文字 | 400 Bad Request |
| `cannot_message_self` | target = 自分自身 | 400 Bad Request |
| `agent_not_found` | 存在しないエージェント | 404 Not Found |
| `target_agent_not_in_project` | プロジェクト外のエージェント | 403 Forbidden |
| `working_directory_not_set` | プロジェクトにworkingDir未設定 | 500 Internal Error |

---

## 変更ファイル一覧

### 修正

| ファイル | 変更内容 |
|----------|----------|
| `Sources/MCPServer/Authorization/ToolAuthorization.swift` | `"send_message": .authenticated` 追加 |
| `Sources/MCPServer/Tools/ToolDefinitions.swift` | `sendMessage` ツール定義追加、`all()` に追加 |
| `Sources/MCPServer/MCPServer.swift` | `handleSendMessage()` 実装、ツールルーティング追加 |

### 新規作成

なし（既存インフラを活用）

---

## テスト計画

### 単体テスト

1. **正常系**: タスクセッションからメッセージ送信 → 双方のファイルに保存
2. **正常系**: チャットセッションからメッセージ送信 → 双方のファイルに保存
3. **異常系**: 自分自身への送信 → エラー
4. **異常系**: プロジェクト外エージェントへの送信 → エラー
5. **異常系**: 4,000文字超過 → エラー

### 統合テスト

1. Agent A (タスク) → Agent B へ送信 → Agent B (チャット) で受信確認
2. Web UI でメッセージ確認

---

## 将来拡張

### 通知システム連携（UC010実装後）

`send_message` 実行時に受信者への通知を生成する。

```swift
// 将来実装
try notificationRepository.create(
    agentId: targetAgentId,
    projectId: session.projectId,
    type: .newMessage,
    payload: ["message_id": message.id.value, "sender_id": session.agentId.value]
)
```

### 既読管理

受信者が `respond_chat` または明示的な既読APIを呼んだ時点で既読とする。

### グループメッセージ

複数エージェントへの同時送信（ブロードキャスト）。

---

## 関連ドキュメント

- [docs/design/CHAT_FEATURE.md](CHAT_FEATURE.md) - チャット機能全体設計
- [docs/design/NOTIFICATION_SYSTEM.md](NOTIFICATION_SYSTEM.md) - 通知システム設計（将来連携）
- [Sources/Infrastructure/FileStorage/ChatFileRepository.swift](../../Sources/Infrastructure/FileStorage/ChatFileRepository.swift) - ファイルストレージ実装
