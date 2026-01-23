# 設計書: AIエージェント間会話機能

## 概要

AIエージェント同士がチャットセッションを通じて対話できる機能を追加する。

### 背景

現在のチャット機能は以下のパターンをサポートしている：

| パターン | 開始者 | 応答者 | セッション | 状態 |
|----------|--------|--------|------------|------|
| Human → AI | Human (Web UI) | AI Worker (chat) | Human が制御 | UC014/UC015で実装済み |
| AI (task) → AI (chat) | AI Worker (task) | AI Worker (chat) | 非同期送信 | UC012/UC013で実装済み |
| **AI ⇄ AI** | AI Worker (chat) | AI Worker (chat) | **双方が対話** | **本設計で追加** |

### 目的

- AIエージェント同士がリアルタイムで対話できるようにする
- 明示的な会話開始・終了のライフサイクル管理を提供する
- 複数エージェント間の協調作業を可能にする

---

## 設計方針

| 観点 | 決定 | 理由 |
|------|------|------|
| 開始方式 | 明示的ツール呼び出し | 意図が明確、リソース管理が容易 |
| 対話モデル | ターンベース + 非同期 | 柔軟性を確保しつつ制御可能 |
| ストレージ | 既存ファイルベース活用 | 実装コスト削減、一貫性維持 |
| 状態管理 | DBで会話状態を管理 | セッション終了の同期が必要 |

---

## 現状アーキテクチャ

### Human ⇄ AI チャット（既存）

```
Human(Web UI)                MCP Server                 AI Worker
     │                           │                          │
     │ POST /chat/start ────────▶│                          │
     │                           │── PendingPurpose ───────▶│
     │                           │                          │
     │                           │         ┌── authenticate │
     │                           │◀────────┤   (chat)       │
     │                           │         └────────────────│
     │                           │                          │
     │                           │── get_next_action ──────▶│
     │                           │◀── wait_for_messages ────│
     │                           │                          │
     │ POST /chat (message) ────▶│                          │
     │                           │── get_next_action ──────▶│
     │                           │◀── get_pending_messages ─│
     │                           │── respond_chat ─────────▶│
     │◀── response ──────────────│                          │
     │                           │                          │
     │ POST /chat/end ──────────▶│                          │
     │                           │── get_next_action ──────▶│
     │                           │◀── exit ─────────────────│
```

**特徴**:
- Human側がセッションのライフサイクルを制御
- AI Workerは受動的（メッセージを待つ）

---

## 新規アーキテクチャ

### AI ⇄ AI チャット

```
AI Worker-A (chat)           MCP Server              AI Worker-B
     │                           │                       │
     │── start_conversation ────▶│                       │
     │   (target: B, purpose)    │                       │
     │                           │── Conversation作成    │
     │                           │   (state: pending)    │
     │                           │                       │
     │                           │── PendingPurpose ────▶│
     │                           │   (conv_id付き)       │
     │                           │                       │
     │◀── {conv_id, pending} ────│                       │
     │                           │                       │
     │── send_message(B) ───────▶│                       │
     │                           │── chat.jsonl書込 ────▶│
     │                           │                       │
     │                           │      ┌── authenticate │
     │                           │◀─────┤   (chat)       │
     │                           │      └────────────────│
     │                           │                       │
     │                           │── Conversation更新    │
     │                           │   (state: active)     │
     │                           │                       │
     │                           │◀── get_next_action ──│
     │                           │── conversation_request│
     │                           │   + pending_msgs ────▶│
     │                           │                       │
     │                           │◀── respond_chat(A) ──│
     │◀── message ──────────────│                       │
     │                           │                       │
     │── send_message(B) ───────▶│                       │
     │                           │── message ──────────▶│
     │                           │                       │
     │                           │◀── respond_chat(A) ──│
     │◀── message ──────────────│                       │
     │                           │                       │
     │── end_conversation ──────▶│                       │
     │                           │── Conversation更新    │
     │                           │   (state: terminating)│
     │                           │                       │
     │                           │◀── get_next_action ──│
     │                           │── conversation_ended ▶│
     │                           │                       │
     │                           │◀── logout ───────────│
```

**特徴**:
- どちらのエージェントも能動的に対話を開始できる
- 会話（Conversation）エンティティで状態を管理
- 明示的な開始・終了により、リソースを適切に管理

---

## 新規エンティティ

### Conversation

```swift
// Sources/Domain/Entities/Conversation.swift

public typealias ConversationID = EntityID<Conversation>

public struct Conversation: Identifiable, Codable, Sendable {
    public let id: ConversationID
    public let projectId: ProjectID
    public let initiatorAgentId: AgentID    // 会話を開始したエージェント
    public let participantAgentId: AgentID  // 招待されたエージェント
    public var state: ConversationState
    public let purpose: String?             // 会話の目的（オプション）
    public let createdAt: Date
    public var endedAt: Date?

    public init(
        id: ConversationID = .generate(),
        projectId: ProjectID,
        initiatorAgentId: AgentID,
        participantAgentId: AgentID,
        state: ConversationState = .pending,
        purpose: String? = nil,
        createdAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.initiatorAgentId = initiatorAgentId
        self.participantAgentId = participantAgentId
        self.state = state
        self.purpose = purpose
        self.createdAt = createdAt
        self.endedAt = endedAt
    }
}

public enum ConversationState: String, Codable, Sendable {
    case pending      // 開始要求済み、相手未参加
    case active       // 両者参加中
    case terminating  // 終了要求済み、終了通知待ち
    case ended        // 終了完了
}
```

### ConversationRepository

```swift
// Sources/Domain/Repositories/RepositoryProtocols.swift

public protocol ConversationRepository: Sendable {
    func save(_ conversation: Conversation) throws
    func findById(_ id: ConversationID) throws -> Conversation?
    func findActiveByAgentId(_ agentId: AgentID, projectId: ProjectID) throws -> [Conversation]
    func findPendingForParticipant(_ agentId: AgentID, projectId: ProjectID) throws -> [Conversation]
    func updateState(_ id: ConversationID, state: ConversationState) throws
}
```

---

## 状態遷移

```
┌─────────────┐
│   (none)    │
└──────┬──────┘
       │ start_conversation
       ▼
┌─────────────┐
│   pending   │ ── 参加者がauthenticate ──┐
└──────┬──────┘                          │
       │ timeout (5分)                    │
       ▼                                 ▼
┌─────────────┐                   ┌─────────────┐
│   expired   │                   │   active    │◀───────┐
└─────────────┘                   └──────┬──────┘        │
                                         │               │
                          ┌──────────────┼───────────────┘
                          │              │    (messages exchanged)
                          │              │
           end_conversation              │ timeout (10分)
                          │              │
                          ▼              ▼
                   ┌─────────────────────────────┐
                   │        terminating          │
                   └──────────────┬──────────────┘
                                  │
                       通知が両者に到達
                                  │
                                  ▼
                           ┌─────────────┐
                           │    ended    │
                           └─────────────┘
```

### 状態遷移ルール

| 現在の状態 | 許可される遷移 | トリガー |
|------------|----------------|----------|
| (none) | pending | `start_conversation` |
| pending | active | 参加者が `authenticate` |
| pending | expired | 5分間参加者が応答しない |
| active | terminating | `end_conversation` / 10分タイムアウト |
| terminating | ended | 両者に終了通知が到達 |
| ended | - | 最終状態 |

---

## 新規ツール

### start_conversation

```swift
// ToolDefinitions.swift
static let startConversation: [String: Any] = [
    "name": "start_conversation",
    "description": """
        他のAIエージェントとの会話を開始します。
        相手エージェントにチャットセッションが開始され、会話が可能になります。
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
                "description": "会話相手のエージェントID（同一プロジェクト内のAIエージェントのみ）"
            ],
            "purpose": [
                "type": "string",
                "description": "会話の目的（任意、相手に通知される）"
            ]
        ],
        "required": ["session_token", "target_agent_id"]
    ]
]
```

**レスポンス**:
```json
{
    "success": true,
    "conversation_id": "conv_xxx",
    "status": "pending",
    "target_agent_id": "worker-b",
    "instruction": "会話リクエストを送信しました。send_messageでメッセージを送信できます。"
}
```

### end_conversation

```swift
// ToolDefinitions.swift
static let endConversation: [String: Any] = [
    "name": "end_conversation",
    "description": """
        会話を終了します。相手エージェントにも終了が通知されます。
        """,
    "inputSchema": [
        "type": "object",
        "properties": [
            "session_token": [
                "type": "string",
                "description": "authenticateツールで取得したセッショントークン"
            ],
            "conversation_id": [
                "type": "string",
                "description": "終了する会話ID（省略時は現在アクティブな会話）"
            ]
        ],
        "required": ["session_token"]
    ]
]
```

**レスポンス**:
```json
{
    "success": true,
    "conversation_id": "conv_xxx",
    "status": "terminating",
    "instruction": "会話終了をリクエストしました。相手に通知されます。"
}
```

---

## get_next_action の拡張

### conversation_request（参加者側）

会話リクエストを受けた側が `get_next_action` を呼び出した時：

```json
{
    "action": "conversation_request",
    "conversation_id": "conv_xxx",
    "from_agent_id": "worker-a",
    "from_agent_name": "Analysis Worker",
    "purpose": "実装方針についての相談",
    "instruction": "worker-aから会話リクエストがあります。get_pending_messagesでメッセージを確認し、respond_chatで応答してください。",
    "state": "conversation_active"
}
```

### conversation_ended（両者）

会話が終了した時：

```json
{
    "action": "conversation_ended",
    "conversation_id": "conv_xxx",
    "ended_by": "worker-a",
    "reason": "initiator_ended",
    "instruction": "会話が終了しました。get_next_actionで次の指示を確認してください。"
}
```

### 終了理由

| reason | 説明 |
|--------|------|
| `initiator_ended` | 開始者が終了 |
| `participant_ended` | 参加者が終了 |
| `timeout` | 10分間やり取りなし |
| `session_expired` | セッション有効期限切れ |

---

## DBスキーマ

### マイグレーション v38

```sql
-- conversations テーブル
CREATE TABLE conversations (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(id),
    initiator_agent_id TEXT NOT NULL REFERENCES agents(id),
    participant_agent_id TEXT NOT NULL REFERENCES agents(id),
    state TEXT NOT NULL DEFAULT 'pending',
    purpose TEXT,
    created_at TEXT NOT NULL,
    ended_at TEXT,

    -- 同じペアで同時に複数のactiveな会話は不可
    CONSTRAINT unique_active_conversation
        CHECK (state != 'active' OR
               id = (SELECT MIN(c2.id) FROM conversations c2
                     WHERE c2.project_id = project_id
                     AND c2.initiator_agent_id = initiator_agent_id
                     AND c2.participant_agent_id = participant_agent_id
                     AND c2.state = 'active'))
);

CREATE INDEX idx_conversations_project ON conversations(project_id);
CREATE INDEX idx_conversations_initiator ON conversations(initiator_agent_id, state);
CREATE INDEX idx_conversations_participant ON conversations(participant_agent_id, state);
CREATE INDEX idx_conversations_state ON conversations(state) WHERE state IN ('pending', 'active', 'terminating');
```

---

## 実装詳細

### start_conversation

```swift
// MCPServer.swift
private func startConversation(
    session: AgentSession,
    targetAgentId: String,
    purpose: String?
) throws -> [String: Any] {
    Self.log("[MCP] startConversation: from='\(session.agentId.value)' to='\(targetAgentId)'")

    // 1. 自分自身との会話は禁止
    guard targetAgentId != session.agentId.value else {
        throw MCPError.cannotConversationWithSelf
    }

    // 2. 対象エージェントの存在確認
    guard let targetAgent = try agentRepository.findById(AgentID(targetAgentId)) else {
        throw MCPError.agentNotFound(targetAgentId)
    }

    // 3. AIエージェントであることを確認（Humanとの会話は別フロー）
    guard targetAgent.type == .ai else {
        throw MCPError.cannotStartConversationWithHuman
    }

    // 4. 同一プロジェクト内のエージェントか確認
    let assignedAgents = try projectRepository.getAssignedAgents(projectId: session.projectId)
    guard assignedAgents.contains(where: { $0.id.value == targetAgentId }) else {
        throw MCPError.targetAgentNotInProject(targetAgentId, projectId: session.projectId.value)
    }

    // 5. 既にアクティブな会話がないか確認
    let existingConversations = try conversationRepository.findActiveByAgentId(
        session.agentId,
        projectId: session.projectId
    )
    if existingConversations.contains(where: {
        $0.participantAgentId.value == targetAgentId ||
        $0.initiatorAgentId.value == targetAgentId
    }) {
        throw MCPError.conversationAlreadyActive(targetAgentId)
    }

    // 6. Conversation作成
    let conversation = Conversation(
        projectId: session.projectId,
        initiatorAgentId: session.agentId,
        participantAgentId: AgentID(targetAgentId),
        state: .pending,
        purpose: purpose
    )
    try conversationRepository.save(conversation)

    // 7. PendingAgentPurpose作成（参加者のエージェント起動トリガー）
    let pendingPurpose = PendingAgentPurpose(
        id: .generate(),
        agentId: AgentID(targetAgentId),
        projectId: session.projectId,
        purpose: .chat,
        conversationId: conversation.id,  // 会話IDを紐付け
        createdAt: Date()
    )
    try pendingPurposeRepository.save(pendingPurpose)

    return [
        "success": true,
        "conversation_id": conversation.id.value,
        "status": "pending",
        "target_agent_id": targetAgentId,
        "instruction": "会話リクエストを送信しました。send_messageでメッセージを送信できます。相手がオンラインになると会話が開始されます。"
    ]
}
```

### end_conversation

```swift
// MCPServer.swift
private func endConversation(
    session: AgentSession,
    conversationId: String?
) throws -> [String: Any] {

    // 1. 会話を特定
    let conversation: Conversation
    if let convId = conversationId {
        guard let conv = try conversationRepository.findById(ConversationID(convId)) else {
            throw MCPError.conversationNotFound(convId)
        }
        conversation = conv
    } else {
        // アクティブな会話を検索
        let activeConversations = try conversationRepository.findActiveByAgentId(
            session.agentId,
            projectId: session.projectId
        )
        guard let conv = activeConversations.first else {
            throw MCPError.noActiveConversation
        }
        conversation = conv
    }

    // 2. 参加者であることを確認
    guard conversation.initiatorAgentId == session.agentId ||
          conversation.participantAgentId == session.agentId else {
        throw MCPError.notConversationParticipant
    }

    // 3. 状態を terminating に更新
    try conversationRepository.updateState(conversation.id, state: .terminating)

    return [
        "success": true,
        "conversation_id": conversation.id.value,
        "status": "terminating",
        "instruction": "会話終了をリクエストしました。相手に通知されます。"
    ]
}
```

### getNextAction の拡張（会話関連）

```swift
// MCPServer.swift - getNextAction内
private func getNextAction(session: AgentSession) throws -> [String: Any] {

    // 1. 終了中の会話があるかチェック
    let terminatingConversations = try conversationRepository.findActiveByAgentId(
        session.agentId,
        projectId: session.projectId
    ).filter { $0.state == .terminating }

    if let conv = terminatingConversations.first {
        // 終了通知を返し、ended に更新
        try conversationRepository.updateState(conv.id, state: .ended)

        let endedBy = conv.initiatorAgentId == session.agentId ? "self" : "partner"
        return [
            "action": "conversation_ended",
            "conversation_id": conv.id.value,
            "ended_by": endedBy == "self" ? conv.initiatorAgentId.value : conv.participantAgentId.value,
            "reason": "partner_ended",
            "instruction": "会話が終了しました。get_next_actionで次の指示を確認してください。"
        ]
    }

    // 2. 新しい会話リクエストがあるかチェック（参加者側）
    let pendingConversations = try conversationRepository.findPendingForParticipant(
        session.agentId,
        projectId: session.projectId
    )

    if let conv = pendingConversations.first {
        // 会話を active に更新
        try conversationRepository.updateState(conv.id, state: .active)

        let initiator = try agentRepository.findById(conv.initiatorAgentId)
        return [
            "action": "conversation_request",
            "conversation_id": conv.id.value,
            "from_agent_id": conv.initiatorAgentId.value,
            "from_agent_name": initiator?.name ?? conv.initiatorAgentId.value,
            "purpose": conv.purpose as Any,
            "instruction": "\(initiator?.name ?? conv.initiatorAgentId.value)から会話リクエストがあります。get_pending_messagesでメッセージを確認し、respond_chatで応答してください。",
            "state": "conversation_active"
        ]
    }

    // 3. 既存のチャット処理...
    // (wait_for_messages, get_pending_messages, etc.)
}
```

---

## ユースケース例

### UC016: AIエージェント間の明示的会話

#### シナリオ: Worker-AがWorker-Bに実装方針を相談

```
1. Worker-A (タスク実行中)
   └── start_conversation(target: worker-b, purpose: "認証実装の相談")

2. System
   └── Conversation作成 (state: pending)
   └── PendingAgentPurpose作成 (worker-b, chat, conv_id)

3. Coordinator
   └── Worker-B起動 (purpose: chat)

4. Worker-B
   └── authenticate(chat)
   └── get_next_action → conversation_request from worker-a

5. Worker-A
   └── send_message(to: worker-b, "JWT と Session、どちらが推奨？")

6. Worker-B
   └── get_pending_messages → Worker-Aからのメッセージ
   └── respond_chat(to: worker-a, "このプロジェクトではJWTを使用しています。理由は...")

7. Worker-A
   └── (メッセージ受信)
   └── send_message(to: worker-b, "了解、JWTで実装します")

8. Worker-A
   └── end_conversation

9. Worker-B
   └── get_next_action → conversation_ended
   └── get_next_action → (次の指示、またはwait_for_messages)
```

---

## エラーケース

| エラー | 条件 | レスポンス |
|--------|------|-----------|
| `cannot_conversation_with_self` | target = 自分自身 | 400 Bad Request |
| `cannot_start_conversation_with_human` | targetがHumanタイプ | 400 Bad Request |
| `agent_not_found` | 存在しないエージェント | 404 Not Found |
| `target_agent_not_in_project` | プロジェクト外のエージェント | 403 Forbidden |
| `conversation_already_active` | 同じ相手と既にアクティブな会話あり | 409 Conflict |
| `conversation_not_found` | 指定された会話IDが存在しない | 404 Not Found |
| `no_active_conversation` | アクティブな会話がない（end時） | 400 Bad Request |
| `not_conversation_participant` | 会話の参加者ではない | 403 Forbidden |

---

## 変更ファイル一覧

### 新規作成

| ファイル | 内容 |
|----------|------|
| `Sources/Domain/Entities/Conversation.swift` | Conversationエンティティ |
| `Sources/Infrastructure/Repositories/ConversationRepository.swift` | リポジトリ実装 |
| `Tests/MCPServerTests/AIConversationTests.swift` | 単体テスト |
| `docs/usecase/UC016_AIToAIConversation.md` | ユースケース定義 |

### 修正

| ファイル | 変更内容 |
|----------|----------|
| `Sources/Domain/Repositories/RepositoryProtocols.swift` | `ConversationRepository`プロトコル追加 |
| `Sources/Domain/Entities/PendingAgentPurpose.swift` | `conversationId`フィールド追加 |
| `Sources/Infrastructure/Database/DatabaseSetup.swift` | マイグレーション v38 追加 |
| `Sources/MCPServer/Authorization/ToolAuthorization.swift` | 新ツールの権限定義 |
| `Sources/MCPServer/Tools/ToolDefinitions.swift` | `startConversation`, `endConversation` 追加 |
| `Sources/MCPServer/MCPServer.swift` | ツール実装、getNextAction拡張 |

---

## 実装フェーズ

### Phase 1: Domain層
- [ ] `Conversation` エンティティ作成
- [ ] `ConversationRepository` プロトコル定義
- [ ] `PendingAgentPurpose` に `conversationId` 追加

### Phase 2: Infrastructure層
- [ ] DBマイグレーション v38 作成
- [ ] `ConversationRepository` 実装

### Phase 3: MCP Tools
- [ ] `start_conversation` ツール実装
- [ ] `end_conversation` ツール実装
- [ ] ツール定義・権限設定

### Phase 4: getNextAction拡張
- [ ] `conversation_request` アクション追加
- [ ] `conversation_ended` アクション追加
- [ ] 会話タイムアウト処理

### Phase 5: テスト
- [ ] 単体テスト作成
- [ ] 統合テスト作成

---

## 将来拡張

### 自動会話開始（send_message契機）

`send_message` 送信時に、受信者がオフラインの場合は自動で会話を開始するオプション。

```swift
send_message(
    target_agent_id: "worker-b",
    content: "質問があります",
    auto_start_conversation: true  // 追加オプション
)
```

### グループ会話

3人以上のエージェントが参加できるグループ会話。

### 会話履歴の永続化

会話のコンテキストを次回以降の会話でも参照できるようにする。

---

## 関連ドキュメント

- [docs/design/CHAT_SESSION_MAINTENANCE_MODE.md](CHAT_SESSION_MAINTENANCE_MODE.md) - チャットセッション維持モード
- [docs/design/SEND_MESSAGE_FROM_TASK_SESSION.md](SEND_MESSAGE_FROM_TASK_SESSION.md) - タスクセッションからのメッセージ送信
- [docs/design/CHAT_FEATURE.md](CHAT_FEATURE.md) - チャット機能全体設計
- [docs/usecase/UC013_WorkerToWorkerMessageRelay.md](../usecase/UC013_WorkerToWorkerMessageRelay.md) - Worker間メッセージ連携
