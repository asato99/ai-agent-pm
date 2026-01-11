# 設計書: プロジェクト画面エージェント一覧 & チャット機能

## 概要

プロジェクト表示画面（TaskBoardView）に割り当てられたエージェント一覧を表示し、エージェントをクリックすることでチャット画面を第3カラムに表示する機能を追加する。

---

## 1. UI設計

### 1.1 エージェント一覧（TaskBoardViewヘッダー）

**配置**: TaskBoardViewのProject Info Headerセクション内

```
┌─────────────────────────────────────────────────────────────────┐
│ Working Directory: /path/to/project                             │
│ ─────────────────────────────────────────────────────────────── │
│ 👥 Agents: [🤖 Agent1] [🤖 Agent2] [👤 Human1]                  │
└─────────────────────────────────────────────────────────────────┘
│ Backlog      │ Todo        │ In Progress  │ Done        │
```

**コンポーネント構成**:
```
ProjectInfoHeader (VStack)
├── WorkingDirectoryRow (HStack) - 既存
├── Divider
└── AssignedAgentsRow (HStack)
    ├── Label "👥 Agents:"
    └── AgentAvatarList (HStack, spacing: 4)
        └── AgentAvatarButton × N
            ├── アイコン (🤖 or 👤)
            ├── 名前
            ├── ステータスインジケーター (●)
            └── onTapGesture → router.selectChatWithAgent(agentId)
```

**AgentAvatarButton デザイン**:
- 形状: 角丸ボタン（capsule）
- 背景色: ステータスに応じた色（active=green, busy=orange, inactive=gray）
- サイズ: コンパクト（高さ24pt程度）
- ホバー時: 軽いハイライト
- 表示上限: 最大5件 + 「+N more」表示

### 1.2 チャット画面（第3カラム）

**表示条件**: `router.selectedChatAgent != nil` の場合

**切り替え優先順位**:
1. `selectedTask` → TaskDetailView
2. `selectedChatAgent` → AgentChatView（新規）
3. `selectedAgent` → AgentDetailView
4. それ以外 → ContentUnavailableView

**AgentChatView構成**:
```
AgentChatView (VStack)
├── ChatHeader
│   ├── エージェント名・役割
│   ├── ステータスバッジ
│   └── CloseButton (×)
├── MessageList (ScrollView)
│   └── ChatMessageRow × N
│       ├── 送信者アイコン
│       ├── メッセージ本文
│       └── タイムスタンプ
├── Divider
└── MessageInputArea
    ├── TextEditor
    └── SendButton
```

---

## 2. データ設計

### 2.1 ストレージ方式: ファイルベース

**選定理由**:
- エージェントが直接読み書き可能（MCP連携時）
- プロジェクト単位でのバックアップ・移行が容易
- Git管理との親和性（.gitignoreで除外可能）
- 将来的にDBとのハイブリッド対応が可能

### 2.2 ディレクトリ構成

```
{project.workingDirectory}/
└── .ai-pm/                          # アプリ専用ディレクトリ
    ├── .gitignore                   # "chat.jsonl" 等を除外
    ├── config.json                  # プロジェクト設定（将来用）
    └── agents/
        └── {agent-id}/
            ├── chat.jsonl           # チャット履歴（追記型）
            └── context.md           # 最新コンテキストサマリ（将来用）
```

### 2.3 ファイル形式: JSONL

**chat.jsonl**（1行1メッセージ、追記型）:
```jsonl
{"id":"msg_01HJ...","sender":"user","content":"タスクAの進捗を教えて","createdAt":"2026-01-11T10:00:00Z"}
{"id":"msg_01HK...","sender":"agent","content":"タスクAは現在実装中です。","createdAt":"2026-01-11T10:00:03Z"}
{"id":"msg_01HL...","sender":"user","content":"ブロッカーはある？","createdAt":"2026-01-11T10:01:00Z"}
```

**JSONL採用理由**:
- 追記が高速（ファイル末尾にappend）
- 行単位で読み込み可能（メモリ効率）
- エージェントが直接読み書きしやすい
- パース失敗が行単位で局所化

### 2.4 ChatMessageエンティティ

```swift
// Sources/Domain/Entities/ChatMessage.swift
public struct ChatMessage: Identifiable, Equatable, Sendable, Codable {
    public let id: ChatMessageID
    public let sender: SenderType
    public let content: String
    public let createdAt: Date

    // オプション: 関連エンティティ参照
    public let relatedTaskId: TaskID?
    public let relatedHandoffId: HandoffID?
}

public enum SenderType: String, Codable, Sendable {
    case user   // 人間ユーザー（PMアプリ操作者）
    case agent  // AIエージェント
}

public typealias ChatMessageID = Tagged<ChatMessage, String>
```

---

## 3. アーキテクチャ

### 3.1 レイヤー構成

```
Sources/
├── Domain/
│   ├── Entities/
│   │   └── ChatMessage.swift              # 型定義
│   └── Repositories/
│       └── ChatRepositoryProtocol.swift   # プロトコル定義
├── Infrastructure/
│   └── FileStorage/                       # 新規ディレクトリ
│       ├── ProjectDirectoryManager.swift  # .ai-pm管理
│       └── ChatFileRepository.swift       # ファイルI/O実装
└── App/
    ├── Core/
    │   └── Navigation/Router.swift        # 修正: チャット選択追加
    ├── Features/
    │   ├── Chat/                          # 新規ディレクトリ
    │   │   ├── AgentChatView.swift
    │   │   ├── ChatMessageRow.swift
    │   │   └── MessageInputView.swift
    │   └── TaskBoard/
    │       ├── TaskBoardView.swift        # 修正: ヘッダー拡張
    │       └── Components/
    │           ├── AgentAvatarButton.swift
    │           └── AssignedAgentsRow.swift
    └── ContentView.swift                  # 修正: 第3カラム分岐
```

### 3.2 リポジトリ設計（ハイブリッド対応準備）

```swift
// プロトコル定義
public protocol ChatRepositoryProtocol: Sendable {
    func findMessages(projectId: ProjectID, agentId: AgentID) throws -> [ChatMessage]
    func saveMessage(_ message: ChatMessage, projectId: ProjectID, agentId: AgentID) throws
    func getLastMessages(projectId: ProjectID, agentId: AgentID, limit: Int) throws -> [ChatMessage]
}

// Phase 1: ファイル実装
public final class ChatFileRepository: ChatRepositoryProtocol {
    private let directoryManager: ProjectDirectoryManager
    // ...
}

// 将来: ハイブリッド実装（ファイル + DBインデックス）
// public final class ChatHybridRepository: ChatRepositoryProtocol { ... }
```

### 3.3 ProjectDirectoryManager

```swift
// .ai-pm ディレクトリの管理
public final class ProjectDirectoryManager: Sendable {
    /// .ai-pm ディレクトリのパスを取得（なければ作成）
    func getOrCreateAppDirectory(for project: Project) throws -> URL

    /// エージェント用ディレクトリのパスを取得（なければ作成）
    func getOrCreateAgentDirectory(for project: Project, agentId: AgentID) throws -> URL

    /// チャットファイルのパスを取得
    func getChatFilePath(for project: Project, agentId: AgentID) throws -> URL
}
```

---

## 4. Router拡張

### 4.1 新規プロパティ

```swift
// Sources/App/Core/Navigation/Router.swift
@Observable
public final class Router {
    // 既存
    public var selectedTask: TaskID?
    public var selectedAgent: AgentID?

    // 新規追加
    public var selectedChatAgent: AgentID?      // チャット表示中のエージェント
    public var selectedChatProjectId: ProjectID? // チャットのプロジェクトコンテキスト
}
```

### 4.2 選択メソッド

```swift
/// エージェントとのチャットを開く
public func selectChatWithAgent(_ agentId: AgentID, in projectId: ProjectID) {
    selectedTask = nil
    selectedAgent = nil
    selectedChatAgent = agentId
    selectedChatProjectId = projectId
}

/// チャットを閉じる
public func closeChatView() {
    selectedChatAgent = nil
    selectedChatProjectId = nil
}
```

---

## 5. 実装ファイル一覧

### 5.1 新規作成

| ファイル | 説明 |
|----------|------|
| `Sources/Domain/Entities/ChatMessage.swift` | ChatMessageエンティティ |
| `Sources/Domain/Repositories/ChatRepositoryProtocol.swift` | リポジトリプロトコル |
| `Sources/Infrastructure/FileStorage/ProjectDirectoryManager.swift` | .ai-pm管理 |
| `Sources/Infrastructure/FileStorage/ChatFileRepository.swift` | ファイルI/O実装 |
| `Sources/App/Features/Chat/AgentChatView.swift` | チャット画面 |
| `Sources/App/Features/Chat/ChatMessageRow.swift` | メッセージ行コンポーネント |
| `Sources/App/Features/Chat/MessageInputView.swift` | メッセージ入力コンポーネント |
| `Sources/App/Features/TaskBoard/Components/AgentAvatarButton.swift` | エージェントアバターボタン |
| `Sources/App/Features/TaskBoard/Components/AssignedAgentsRow.swift` | 割り当てエージェント行 |

### 5.2 修正

| ファイル | 変更内容 |
|----------|----------|
| `Sources/App/Core/Navigation/Router.swift` | selectedChatAgent, selectedChatProjectId追加 |
| `Sources/App/ContentView.swift` | 第3カラムにAgentChatView分岐追加 |
| `Sources/App/Features/TaskBoard/TaskBoardView.swift` | ヘッダーにAssignedAgentsRow追加 |
| `Sources/App/Core/DependencyContainer/DependencyContainer.swift` | ChatFileRepository登録 |

---

## 6. 実装フェーズ

### Phase 1: データ層
1. ChatMessageエンティティ作成
2. ChatRepositoryProtocol作成
3. ProjectDirectoryManager作成
4. ChatFileRepository作成
5. DependencyContainerに登録

### Phase 2: ナビゲーション
1. Routerにselected系プロパティ追加
2. selectChatWithAgent/closeChatViewメソッド追加
3. ContentViewの第3カラム分岐追加

### Phase 3: UI - ヘッダー
1. AgentAvatarButtonコンポーネント作成
2. AssignedAgentsRowコンポーネント作成
3. TaskBoardViewヘッダーに統合

### Phase 4: UI - チャット画面
1. AgentChatView作成
2. ChatMessageRowコンポーネント作成
3. MessageInputView作成
4. メッセージ送信/取得ロジック実装
5. モック応答実装

### Phase 5: テスト・検証
1. ビルド確認
2. 手動テスト
3. UIテスト追加（オプション）

---

## 7. 検証方法

### 7.1 機能テスト

1. **エージェント一覧表示**
   - プロジェクトを選択 → TaskBoardヘッダーに割り当て済みエージェントが表示される
   - エージェントが0件の場合 → 「No agents assigned」表示

2. **チャット画面遷移**
   - エージェントアバターをクリック → 第3カラムにチャット画面表示
   - タスクを選択 → チャット画面がTaskDetailViewに切り替わる
   - チャット画面の×ボタン → チャット画面が閉じる

3. **メッセージ送受信**
   - メッセージ入力・送信 → メッセージリストに表示
   - 画面再読み込み → 履歴が保持されている
   - モック応答 → エージェントからの固定メッセージが表示

### 7.2 ファイル確認

```bash
# ディレクトリ確認
ls -la /path/to/project/.ai-pm/agents/

# チャット履歴確認
cat /path/to/project/.ai-pm/agents/{agent-id}/chat.jsonl
```

---

## 8. 初期スコープ（Phase 1リリース）

| 項目 | 実装 | 備考 |
|------|------|------|
| エージェント一覧表示 | ✅ | ヘッダーにアバター列 |
| チャット画面表示 | ✅ | 第3カラム |
| メッセージ送信（ユーザー→） | ✅ | ファイル保存（.ai-pm/） |
| メッセージ履歴表示 | ✅ | 時系列表示、ポーリング更新 |
| 起動理由管理 | ✅ | pending_agent_purposes テーブル |
| MCP: get_pending_messages | ✅ | エージェントが未読取得 |
| MCP: respond_chat | ✅ | エージェントが応答送信 |

---

## 9. MCP連携設計

### 9.1 設計方針

- **タスクとチャットの区別**: エージェント起動理由をMCP側で管理
- **DB**: 制御情報のみ（pending_agent_purposes）
- **ファイル**: メッセージ本文（.ai-pm/agents/{id}/chat.jsonl）

### 9.2 起動理由管理テーブル

```sql
CREATE TABLE pending_agent_purposes (
    agent_id TEXT NOT NULL,
    project_id TEXT NOT NULL,
    purpose TEXT NOT NULL,  -- "task" | "chat"
    created_at DATETIME NOT NULL,
    PRIMARY KEY (agent_id, project_id)
);
```

**役割**:
- `get_agent_action` で起動理由を記録
- `authenticate` で参照してセッションに設定
- 使用後は削除

### 9.3 エージェント起動フロー

```
【PMアプリ側】
1. ユーザーがチャット画面でメッセージ送信
   ↓
2. PMアプリ:
   - ファイルにメッセージ追記（.ai-pm/agents/{id}/chat.jsonl）
   - pending_agent_purposes に purpose="chat" を記録
   ↓
【Runner側】
3. Runner: get_agent_action(agent_id, project_id) をポーリング
   ↓
4. MCP:
   - pending_agent_purposes を確認
   - purpose があれば action: "start" を返す
   - reason: "has_pending_chat" を付与（ログ用）
   ↓
5. Runner: エージェントを起動
   ↓
【エージェント側】
6. エージェント: authenticate(agent_id, passkey, project_id)
   ↓
7. MCP:
   - pending_agent_purposes を参照 → purpose="chat"
   - セッションに purpose を設定
   - pending_agent_purposes を削除
   ↓
8. エージェント: get_next_action()
   ↓
9. MCP: purpose="chat" なので「チャットに応答してください」を返す
   ↓
10. エージェント: get_pending_messages() でメッセージ取得
   ↓
11. エージェント: respond_chat(content) で応答
   ↓
12. MCP: ファイルにエージェント応答を追記
   ↓
【PMアプリ側】
13. PMアプリ: ポーリングで新メッセージ検知 → 画面に表示
```

### 9.4 get_agent_action の拡張

```swift
private func getAgentAction(agentId: String, projectId: String) throws -> [String: Any] {
    // 既存のチェック（割り当て確認、セッション確認等）
    // ...

    // pending_agent_purposes を確認
    if let pending = try pendingAgentPurposeRepository.find(agentId: id, projectId: projId) {
        return [
            "action": "start",
            "reason": pending.purpose == "chat" ? "has_pending_chat" : "has_pending_task"
        ]
    }

    // 既存のタスクチェック
    if hasInProgressTask {
        // purpose を記録（タスク用）
        try pendingAgentPurposeRepository.save(agentId: id, projectId: projId, purpose: "task")
        return [
            "action": "start",
            "reason": "has_in_progress_task"
        ]
    }

    return ["action": "hold", "reason": "no_pending_work"]
}
```

### 9.5 authenticate の拡張

```swift
private func authenticate(agentId: String, passkey: String, projectId: String) throws -> [String: Any] {
    // 既存の認証処理
    // ...

    // 起動理由を取得
    let purpose = try pendingAgentPurposeRepository.find(agentId: id, projectId: projId)?.purpose ?? "task"

    // セッション作成時に purpose を設定
    let session = AgentSession(
        // ...
        purpose: purpose  // 新規フィールド
    )
    try agentSessionRepository.save(session)

    // pending_agent_purposes を削除
    try pendingAgentPurposeRepository.delete(agentId: id, projectId: projId)

    return [
        "success": true,
        "session_token": session.token,
        "purpose": purpose,
        // ...
    ]
}
```

### 9.6 get_next_action の拡張

```swift
private func getNextAction(session: AgentSession) throws -> [String: Any] {
    // セッションの purpose を確認
    if session.purpose == "chat" {
        return [
            "action": "respond_chat",
            "instruction": """
                ユーザーからのチャットメッセージに応答してください。
                1. get_pending_messages でメッセージを取得
                2. 内容を確認して適切に応答
                3. respond_chat で応答を送信
                4. 完了したら終了
                """
        ]
    }

    // 既存のタスク用ロジック
    // ...
}
```

### 9.7 新規MCPツール

#### A. `get_pending_messages` - 未読メッセージ取得

```swift
static let getPendingMessages: [String: Any] = [
    "name": "get_pending_messages",
    "description": "ユーザーからの未読チャットメッセージを取得します",
    "inputSchema": [
        "type": "object",
        "properties": [:],
        "required": []
    ]
]
```

**実装**:
```swift
private func getPendingMessages(session: AgentSession) throws -> [[String: Any]] {
    guard let project = try projectRepository.findById(session.projectId),
          let workingDir = project.workingDirectory else {
        throw MCPError.projectNotFound(session.projectId.value)
    }

    let chatRepo = ChatFileRepository(baseDirectory: URL(fileURLWithPath: workingDir))
    let messages = try chatRepo.findUnreadMessages(agentId: session.agentId)

    return messages.map { msg in
        [
            "id": msg.id.value,
            "content": msg.content,
            "createdAt": ISO8601DateFormatter().string(from: msg.createdAt)
        ]
    }
}
```

#### B. `respond_chat` - チャット応答

```swift
static let respondChat: [String: Any] = [
    "name": "respond_chat",
    "description": "ユーザーへのチャット応答を送信します",
    "inputSchema": [
        "type": "object",
        "properties": [
            "content": [
                "type": "string",
                "description": "応答メッセージ本文"
            ],
            "related_task_id": [
                "type": "string",
                "description": "関連タスクID（オプション）"
            ]
        ],
        "required": ["content"]
    ]
]
```

**実装**:
```swift
private func respondChat(session: AgentSession, content: String, relatedTaskId: String?) throws -> [String: Any] {
    guard let project = try projectRepository.findById(session.projectId),
          let workingDir = project.workingDirectory else {
        throw MCPError.projectNotFound(session.projectId.value)
    }

    let chatRepo = ChatFileRepository(baseDirectory: URL(fileURLWithPath: workingDir))
    let message = ChatMessage(
        id: ChatMessageID(UUID().uuidString),
        sender: .agent,
        content: content,
        createdAt: Date(),
        relatedTaskId: relatedTaskId.map { TaskID($0) }
    )

    try chatRepo.saveMessage(message, agentId: session.agentId)

    return ["success": true, "message_id": message.id.value]
}
```

### 9.8 エッジケース対応

| ケース | 対応 |
|--------|------|
| get_agent_action 複数回呼び出し | pending_agent_purposes を上書き（最新を採用） |
| authenticate が来ない | TTL（5分）で pending_agent_purposes を自動削除 |
| pending がない時に authenticate | デフォルトで purpose="task" |
| タスクとチャット両方ある | チャット優先（PMアプリが pending に "chat" を記録） |

### 9.9 AgentSession の拡張

```swift
public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: AgentSessionID
    public let token: String
    public let agentId: AgentID
    public let projectId: ProjectID
    public let purpose: String  // "task" | "chat" ← 新規追加
    public let expiresAt: Date
    public let createdAt: Date
    // ...
}
```

### 9.10 ファイル形式

**chat.jsonl**（JSONL形式、追記型）:
```jsonl
{"id":"msg_01","sender":"user","content":"タスクAの進捗は？","createdAt":"2026-01-11T10:00:00Z"}
{"id":"msg_02","sender":"agent","content":"現在50%です","createdAt":"2026-01-11T10:00:05Z"}
```

- 未読管理はファイル読み込み時に判定（DBで管理しない）
- エージェント応答後のメッセージは既読扱い

---

## 10. 実装ファイル一覧（MCP関連追加）

### 10.1 新規作成

| ファイル | 説明 |
|----------|------|
| `Sources/Domain/Entities/PendingAgentPurpose.swift` | 起動理由エンティティ |
| `Sources/Infrastructure/Repositories/PendingAgentPurposeRepository.swift` | リポジトリ実装 |
| `Sources/Infrastructure/Database/Migrations/vXX_pending_agent_purposes.swift` | マイグレーション |

### 10.2 修正

| ファイル | 変更内容 |
|----------|----------|
| `Sources/Domain/Entities/AgentSession.swift` | purpose フィールド追加 |
| `Sources/MCPServer/Tools/ToolDefinitions.swift` | get_pending_messages, respond_chat 追加 |
| `Sources/MCPServer/MCPServer.swift` | ツール実行ロジック、authenticate/get_next_action 拡張 |
| `Sources/MCPServer/Authorization/ToolAuthorization.swift` | 権限設定追加 |

---

## 11. 将来拡張（スコープ外）

- ファイル監視によるリアルタイム更新（FSEvents）
- 実行中エージェントへの通知（ツール返却値に通知フィールド追加）
- エージェント間対話
- メッセージ検索・編集・削除
- ファイル添付
- context.md自動生成（会話サマリ）

---

## 12. 決定事項

| 項目 | 決定 | 理由 |
|------|------|------|
| UI配置 | ヘッダーにアバター列 | コンパクト、既存レイアウト影響小 |
| チャット表示 | 第3カラム | 3カラム構成維持、タスク詳細と自然な切り替え |
| メッセージ保存 | ファイルベース（.ai-pm/） | エージェントアクセス容易 |
| 制御情報 | DB（pending_agent_purposes） | MCP側で起動理由を管理 |
| 未読管理 | ファイルから判定 | 専用テーブル不要 |
| ファイル形式 | JSONL | 追記高速、行単位処理 |
| 起動理由 | MCP内部で管理 | Runnerは action: "start" のみ判断 |
| タスク/チャット優先度 | チャット優先 | リアルタイム性重視 |
| MCPツール | 2つ追加 | get_pending_messages, respond_chat |
