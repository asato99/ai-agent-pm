# 設計書: AIエージェント間会話機能

> **📝 権限に関する注記**
>
> 本設計の会話関連ツール（`start_conversation`, `end_conversation`）は **チャットセッション専用** (`.chatOnly`) です。
> タスクセッションから会話を開始する場合は、`delegate_to_chat_session` ツールでチャットセッションに委譲してください。
>
> **詳細:** [TASK_CHAT_SESSION_SEPARATION.md](./TASK_CHAT_SESSION_SEPARATION.md)

## 概要

AIエージェント同士がチャットセッションを通じて対話できる機能を追加する。

### 背景

現在のチャット機能は以下のパターンをサポートしている：

| パターン | 開始者 | 応答者 | セッション | 状態 |
|----------|--------|--------|------------|------|
| Human → AI | Human (Web UI) | AI Worker (chat) | Human が制御 | UC014/UC015で実装済み |
| AI (task) → AI (chat) | AI Worker (task) | AI Worker (chat) | 非同期送信 | ~~UC012/UC013で実装済み~~ **廃止予定** |
| **AI ⇄ AI** | AI Worker (chat) | AI Worker (chat) | **双方が対話** | **本設計で追加** |

> **注:** 「AI (task) → AI (chat)」パターンは廃止予定。タスクセッションからは `delegate_to_chat_session` を使用。

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
| メッセージ紐付け | conversationIdをメッセージに付与 | 会話履歴の追跡・参照を可能に |
| **AI間メッセージ制約** | **アクティブ会話必須** | **ライフサイクル強制、追跡可能性確保** |

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

### ChatMessage の拡張

既存の `ChatMessage` に `conversationId` フィールドを追加し、AI間会話のメッセージを会話単位で追跡可能にする。

```swift
// Sources/Domain/Entities/ChatMessage.swift（既存エンティティの拡張）

public struct ChatMessage: Codable, Sendable {
    public let id: String
    public let senderId: AgentID
    public let recipientId: AgentID
    public let content: String
    public let timestamp: Date
    public let conversationId: ConversationID?  // 追加: AI⇄AI会話時に設定

    // ... 既存のイニシャライザを拡張
}
```

**conversationId の設定ルール**:

| フロー | conversationId | 理由 |
|--------|----------------|------|
| Human → AI | `nil` | Humanは会話エンティティを使用しない |
| AI (task) → AI (非同期) | `nil` | 明示的な会話なし |
| AI ⇄ AI (会話中) | 自動設定 | 会話履歴の追跡に必要 |

**chat.jsonl の形式**:

```json
{
    "id": "msg_xxx",
    "senderId": "worker-a",
    "recipientId": "worker-b",
    "content": "しりとりをしましょう。りんご",
    "timestamp": "2026-01-23T10:00:00Z",
    "conversationId": "conv_xxx"
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
       │ pendingタイムアウト               │
       ▼                                 ▼
┌─────────────┐                   ┌─────────────┐
│   expired   │                   │   active    │◀───────┐
└─────────────┘                   └──────┬──────┘        │
                                         │               │
                          ┌──────────────┼───────────────┘
                          │              │    (messages exchanged)
                          │              │
           end_conversation              │ activeタイムアウト
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
| pending | expired | pendingタイムアウト（デフォルト5分） |
| active | terminating | `end_conversation` / activeタイムアウト（デフォルト10分） |
| terminating | ended | 両者に終了通知が到達 |
| ended | - | 最終状態 |

### タイムアウト設定

テスト時に長時間待機を避けるため、タイムアウト値は環境変数で設定可能とする。

| 環境変数 | デフォルト | 説明 |
|----------|------------|------|
| `CONVERSATION_PENDING_TIMEOUT_SECONDS` | 300 (5分) | pending状態のタイムアウト |
| `CONVERSATION_ACTIVE_TIMEOUT_SECONDS` | 600 (10分) | active状態のタイムアウト |

**テスト時の例**:
```bash
CONVERSATION_PENDING_TIMEOUT_SECONDS=5 \
CONVERSATION_ACTIVE_TIMEOUT_SECONDS=5 \
swift test --filter AIConversationTests
```

---

## send_message 制約: AI間メッセージにはアクティブ会話必須

### 概要

AIエージェント間のメッセージ送信（`send_message`）は、**アクティブな会話が存在する場合のみ許可**される。
これにより、会話ライフサイクル（`start_conversation` → メッセージ交換 → `end_conversation`）の使用が強制される。

### 制約ルール

| 送信者 | 受信者 | アクティブ会話 | 結果 |
|--------|--------|----------------|------|
| Human | AI | 不要 | ✅ 送信可能 |
| AI | Human | 不要 | ✅ 送信可能 |
| AI | AI | **必須** | ⚠️ なければエラー |
| AI | AI | あり | ✅ 送信可能 |

### 実装ロジック

```swift
// sendMessage内での検証
let senderAgent = try agentRepository.findById(session.agentId)
let targetAgent = try agentRepository.findById(AgentID(value: targetAgentId))

// 両方がAIエージェントの場合、アクティブ会話必須
if senderAgent?.type == .ai && targetAgent?.type == .ai {
    guard resolvedConversationId != nil else {
        throw MCPError.conversationRequiredForAIToAI(
            fromAgentId: session.agentId.value,
            toAgentId: targetAgentId
        )
    }
}
```

### エラーレスポンス

```json
{
    "error": "conversation_required_for_ai_to_ai",
    "message": "AIエージェント間のメッセージ送信にはアクティブな会話が必要です。先にstart_conversation(participant_agent_id: \"target-agent\", initial_message: \"...\")を呼び出してください。",
    "from_agent_id": "worker-a",
    "to_agent_id": "worker-b"
}
```

### 設計根拠

1. **ライフサイクル強制**: システムプロンプトに依存せず、ツールの仕様として会話開始を強制
2. **追跡可能性**: すべてのAI間通信に `conversationId` が付与され、監査・デバッグが容易
3. **リソース管理**: 明示的な開始・終了により、未終了の会話を検出・クリーンアップ可能
4. **Human-AI互換性**: 既存のHuman-AIチャット（Web UI経由）には影響なし

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
    "purpose": "しりとり",
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

### send_message の拡張（conversationId 自動付与 + AI間制約）

```swift
// MCPServer.swift - sendMessage内
private func sendMessage(
    session: AgentSession,
    targetAgentId: String,
    content: String
) throws -> [String: Any] {

    // 1. 送信者・受信者のエージェントタイプを取得
    let senderAgent = try agentRepository.findById(session.agentId)
    let targetAgent = try agentRepository.findById(AgentID(value: targetAgentId))

    // 2. 対象エージェントとのアクティブな会話があるか確認
    let activeConversations = try conversationRepository.findActiveByAgentId(
        session.agentId,
        projectId: session.projectId
    )

    let conversationId = activeConversations.first { conv in
        conv.participantAgentId.value == targetAgentId ||
        conv.initiatorAgentId.value == targetAgentId
    }?.id

    // 3. AI間メッセージの場合、アクティブ会話必須
    if senderAgent?.type == .ai && targetAgent?.type == .ai {
        guard conversationId != nil else {
            throw MCPError.conversationRequiredForAIToAI(
                fromAgentId: session.agentId.value,
                toAgentId: targetAgentId
            )
        }
    }

    // 4. ChatMessage作成（conversationIdを付与）
    let message = ChatMessage(
        id: UUID().uuidString,
        senderId: session.agentId,
        recipientId: AgentID(targetAgentId),
        content: content,
        timestamp: Date(),
        conversationId: conversationId  // アクティブな会話があれば自動設定
    )

    // 5. chat.jsonlに書き込み（既存処理）
    try chatRepository.save(message, projectId: session.projectId)

    return [
        "success": true,
        "message_id": message.id,
        "conversation_id": conversationId?.value as Any
    ]
}
```

---

## ユースケース例

### UC016: AIエージェント間の明示的会話

#### シナリオ: Worker-AとWorker-Bでしりとり（検証用）

```
1. Worker-A
   └── start_conversation(target: worker-b, purpose: "しりとり")

2. System
   └── Conversation作成 (state: pending, id: conv_xxx)
   └── PendingAgentPurpose作成 (worker-b, chat, conv_id)

3. Coordinator
   └── Worker-B起動 (purpose: chat)

4. Worker-B
   └── authenticate(chat)
   └── get_next_action → conversation_request from worker-a

5. Worker-A
   └── send_message(to: worker-b, "しりとりをしましょう。りんご")
       → ChatMessage保存 (conversationId: conv_xxx)

6. Worker-B
   └── get_pending_messages → [{content: "しりとりをしましょう。りんご", conversationId: conv_xxx}]
   └── respond_chat(to: worker-a, "ごりら")
       → ChatMessage保存 (conversationId: conv_xxx)

7. [5-6を繰り返し、5往復を完了]
   └── 全メッセージに同一のconversationId: conv_xxxが付与される

8. Worker-A
   └── send_message(to: worker-b, "5ターン完了。終了します")
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
| **`conversation_required_for_ai_to_ai`** | **AI間でアクティブ会話なしに送信** | **400 Bad Request** |

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
| `Sources/Domain/Entities/ChatMessage.swift` | `conversationId`フィールド追加 |
| `Sources/Domain/Repositories/RepositoryProtocols.swift` | `ConversationRepository`プロトコル追加 |
| `Sources/Domain/Entities/PendingAgentPurpose.swift` | `conversationId`フィールド追加 |
| `Sources/Infrastructure/Database/DatabaseSetup.swift` | マイグレーション v38 追加 |
| `Sources/MCPServer/Authorization/ToolAuthorization.swift` | 新ツールの権限定義 |
| `Sources/MCPServer/Tools/ToolDefinitions.swift` | `startConversation`, `endConversation` 追加 |
| `Sources/MCPServer/MCPServer.swift` | ツール実装、getNextAction拡張、sendMessage拡張 |

---

## 実装フェーズ

### Phase 1: Domain層
- [ ] `Conversation` エンティティ作成
- [ ] `ConversationRepository` プロトコル定義
- [ ] `PendingAgentPurpose` に `conversationId` 追加
- [ ] `ChatMessage` に `conversationId` 追加

### Phase 2: Infrastructure層
- [ ] DBマイグレーション v38 作成
- [ ] `ConversationRepository` 実装

### Phase 3: MCP Tools
- [ ] `start_conversation` ツール実装
- [ ] `end_conversation` ツール実装
- [ ] `send_message` 拡張（conversationId自動付与）
- [ ] `send_message` 拡張（AI間メッセージにアクティブ会話必須）
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

### 会話履歴の参照機能

`conversationId` によりメッセージと会話の紐付けは可能になったため、
特定の会話のメッセージのみを取得するツール（`get_conversation_history`）を追加し、
過去の会話コンテキストを参照できるようにする。

---

## 関連ドキュメント

- [docs/design/CHAT_SESSION_MAINTENANCE_MODE.md](CHAT_SESSION_MAINTENANCE_MODE.md) - チャットセッション維持モード
- [docs/design/SEND_MESSAGE_FROM_TASK_SESSION.md](SEND_MESSAGE_FROM_TASK_SESSION.md) - タスクセッションからのメッセージ送信
- [docs/design/CHAT_FEATURE.md](CHAT_FEATURE.md) - チャット機能全体設計
- [docs/usecase/UC013_WorkerToWorkerMessageRelay.md](../usecase/UC013_WorkerToWorkerMessageRelay.md) - Worker間メッセージ連携
