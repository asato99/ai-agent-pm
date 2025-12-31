# エージェント概念設計

AIエージェントをプロジェクト管理の「一級市民」として扱うための概念定義。

---

## 概念の階層

```
┌─────────────────────────────────────────────────────────────────┐
│                        アプリケーション                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   Agent A    │    │   Agent B    │    │   Agent C    │      │
│  │  (Frontend)  │    │  (Backend)   │    │   (Human)    │      │
│  │              │    │              │    │              │      │
│  │  Session 1 ──┼────┼─→ Handoff ──┼────┼─→ Review     │      │
│  │  Session 2   │    │  Session 1   │    │              │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│         │                   │                                   │
│         └─────────┬─────────┘                                   │
│                   ▼                                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    AIツール層                            │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │   │
│  │  │ Claude Code │  │   Gemini    │  │   (将来)    │     │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3つの概念の区別

### 1. Agent（エージェント）

**定義**: プロジェクトに参加する論理的なアイデンティティ

| 属性 | 説明 |
|------|------|
| 永続性 | アプリ内で永続的に存在 |
| 役割 | 明確な責務を持つ（Frontend担当、レビュアーなど） |
| 人格 | 一貫した行動指針（システムプロンプト） |
| 権限 | 実行可能な操作の範囲（Owner/Manager/Worker/Viewer） |
| 記憶 | コンテキストとハンドオフの履歴 |

```swift
struct Agent {
    let id: AgentID              // agt_xxx (不変)
    var name: String             // "frontend-dev"
    var role: String             // "フロントエンド開発担当"
    var type: AgentType          // .ai | .human
    var roleType: AgentRole      // .owner | .manager | .worker | .viewer
    var capabilities: [String]   // ["React", "TypeScript", "CSS"]
    var systemPrompt: String?    // AI向け行動指針
    var status: AgentStatus      // .active | .inactive | .archived
    let createdAt: Date
}
```

**重要**: エージェントは「誰であるか」を定義する。どのツールを使うかは関係ない。

### 2. Session（セッション）

**定義**: エージェントがシステムに接続している一時的な期間

| 属性 | 説明 |
|------|------|
| 一時性 | 開始と終了がある |
| 紐付け | 1つのエージェントに属する |
| 活動 | その間に行われた作業の記録 |
| ツール | 使用しているAIツール |

```swift
struct Session {
    let id: SessionID            // ses_xxx
    let agentId: AgentID         // 所属エージェント
    var toolType: AIToolType     // .claudeCode | .gemini | .human | .other
    var status: SessionStatus    // .active | .ended
    let startedAt: Date
    var endedAt: Date?
    var summary: String?         // セッション終了時のサマリ
}
```

**重要**: セッションは「いつ、何のツールで作業したか」を記録する。

### 3. AI Tool（AIツール）

**定義**: エージェントが使用する具体的なAI実行環境

| ツール | 説明 |
|--------|------|
| Claude Code | Anthropic社のCLIツール |
| Gemini | Google社のAIアシスタント（将来対応） |
| Human | 人間による直接操作 |
| Other | その他のAIツール |

```swift
enum AIToolType: String, Codable {
    case claudeCode = "claude_code"
    case gemini = "gemini"
    case human = "human"
    case other = "other"
}
```

**重要**: AIツールは「どうやって作業するか」の手段。同じエージェントが異なるツールを使うことも可能。

---

## 概念の関係性

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│    Agent (1) ───────< Session (多)                              │
│      │                    │                                     │
│      │                    └──── uses ──── AITool                │
│      │                                                          │
│      ├──── has ──── Role (役割)                                 │
│      ├──── has ──── RoleType (権限)                             │
│      ├──── has ──── Capabilities (専門)                         │
│      └──── has ──── SystemPrompt (人格)                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 具体例

```
Agent: "frontend-dev"
├── Role: フロントエンド開発担当
├── RoleType: Worker
├── Capabilities: [React, TypeScript, CSS]
├── SystemPrompt: "UIの実装を担当。アクセシビリティを重視..."
│
├── Session #1 (2024-12-28 10:00-12:00)
│   └── Tool: Claude Code
│   └── 作業: ログイン画面の実装
│
├── Session #2 (2024-12-28 14:00-16:00)
│   └── Tool: Claude Code
│   └── 作業: API統合
│
└── Session #3 (2024-12-29 09:00-11:00)
    └── Tool: Gemini (将来)
    └── 作業: テスト作成
```

---

## エージェントのタイプ

### AIエージェント (type: .ai)

- AIツールを通じてシステムにアクセス
- MCPサーバー経由でタスク情報を取得・更新
- システムプロンプトに従って行動
- 自律的にタスクを実行

```
┌─────────────────────────────────────────────────────────┐
│ AIエージェントのワークフロー                            │
│                                                          │
│  Claude Code起動                                         │
│       │                                                  │
│       ▼                                                  │
│  MCPサーバーに接続 (agent-id指定)                       │
│       │                                                  │
│       ▼                                                  │
│  セッション開始 (自動記録)                              │
│       │                                                  │
│       ▼                                                  │
│  タスク取得 → 実行 → コンテキスト追加 → ハンドオフ     │
│       │                                                  │
│       ▼                                                  │
│  セッション終了 (サマリ記録)                            │
└─────────────────────────────────────────────────────────┘
```

### 人間エージェント (type: .human)

- GUIアプリを通じてシステムにアクセス
- プロジェクトオーナー、レビュアー、マネージャーなど
- AIエージェントへの指示、承認、レビューを担当

```
┌─────────────────────────────────────────────────────────┐
│ 人間エージェントのワークフロー                          │
│                                                          │
│  アプリにログイン                                        │
│       │                                                  │
│       ▼                                                  │
│  タスクボードを確認                                      │
│       │                                                  │
│       ▼                                                  │
│  タスク作成 / アサイン / レビュー / 承認                │
│       │                                                  │
│       ▼                                                  │
│  ハンドオフの確認・応答                                 │
└─────────────────────────────────────────────────────────┘
```

---

## エージェントの識別

### Agent ID

```
形式: agt_[ランダム12文字]
例:   agt_a1b2c3d4e5f6

特徴:
- 作成時に一度だけ生成
- 変更不可（immutable）
- MCP設定でエージェントを特定するために使用
```

### MCPサーバーでの識別フロー

```
1. Claude Code起動時
   $ claude --mcp-config ~/.claude/config.json

2. MCP設定にagent-idが含まれる
   {
     "mcpServers": {
       "agent-pm-frontend-dev": {
         "args": ["--agent-id", "agt_a1b2c3d4e5f6"]
       }
     }
   }

3. MCPサーバーがagent-idでエージェントを特定
   → 対応するエージェントの権限・役割を適用
   → セッションを自動開始
```

---

## エージェントの状態

```
┌─────────────────────────────────────────────────────────┐
│                                                          │
│    [作成] ──→ Active ←──→ Inactive ──→ Archived         │
│                  │            │                          │
│                  └── Session ─┘                          │
│                     (接続中)                             │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

| 状態 | 説明 | 表示 |
|------|------|------|
| Active | 有効なエージェント | 🟢（セッション中）/ 🟡（アイドル） |
| Inactive | 一時的に無効化 | ⚫ |
| Archived | 削除済み（履歴保持） | 表示なし |

---

## エージェントの記憶

エージェントは以下の情報を「記憶」として保持：

### 1. コンテキスト (Context)

タスクに関連する情報の蓄積

```swift
struct Context {
    let id: ContextID
    let taskId: TaskID
    let agentId: AgentID         // 誰が追加したか
    let sessionId: SessionID?    // どのセッションで
    var content: String          // 内容
    var type: ContextType        // .note | .decision | .code | .reference
    let createdAt: Date
}
```

### 2. ハンドオフ (Handoff)

エージェント間の引き継ぎ

```swift
struct Handoff {
    let id: HandoffID
    let taskId: TaskID
    let fromAgentId: AgentID     // 送信元
    let toAgentId: AgentID       // 送信先
    var message: String          // 引き継ぎ内容
    var status: HandoffStatus    // .pending | .acknowledged | .completed
    let createdAt: Date
    var acknowledgedAt: Date?
}
```

### 3. セッション履歴 (Session History)

過去の作業記録

```swift
// セッションサマリから参照可能
let sessions = agent.sessions.sorted(by: { $0.startedAt > $1.startedAt })
for session in sessions {
    print("\(session.startedAt): \(session.summary ?? "No summary")")
}
```

---

## エージェント管理の原則

### 1. アプリ側集中管理

```
✅ 正しいアプローチ:
   アプリがエージェントを作成 → MCP設定を生成 → Claude Codeに適用

❌ 避けるべきアプローチ:
   Claude Codeが自己登録 → アプリが追認
```

**理由**:
- 一貫した権限管理が可能
- エージェントの重複を防止
- 監査証跡の確保

### 2. 1エージェント = 1役割

```
✅ 推奨:
   frontend-dev (フロントエンド担当)
   backend-dev (バックエンド担当)
   reviewer (レビュー担当)

❌ 非推奨:
   all-purpose-agent (何でもやるエージェント)
```

**理由**:
- 責任の所在が明確
- 権限の最小化が可能
- コンテキストの汚染を防止

### 3. セッションの明示的管理

```
✅ 推奨:
   session_start → 作業 → session_end (サマリ記録)

❌ 非推奨:
   接続したまま放置 (状態が不明確)
```

**理由**:
- 作業履歴の追跡が可能
- リソース管理が容易
- ハンドオフのタイミングが明確

---

## 典型的なエージェント構成

### 小規模プロジェクト (2-3人)

```
owner (Human)        - プロジェクトオーナー、全体管理
fullstack-dev (AI)   - 開発全般
```

### 中規模プロジェクト (4-6人)

```
owner (Human)        - プロジェクトオーナー
pm (Human/AI)        - プロジェクトマネージャー
frontend-dev (AI)    - フロントエンド開発
backend-dev (AI)     - バックエンド開発
reviewer (Human)     - コードレビュー
```

### 大規模プロジェクト (7人以上)

```
owner (Human)           - プロジェクトオーナー
pm (Human)              - プロジェクトマネージャー
tech-lead (Human/AI)    - 技術リード
frontend-lead (AI)      - フロントエンドリード
frontend-dev-1 (AI)     - フロントエンド開発
frontend-dev-2 (AI)     - フロントエンド開発
backend-lead (AI)       - バックエンドリード
backend-dev-1 (AI)      - バックエンド開発
backend-dev-2 (AI)      - バックエンド開発
qa (AI)                 - QAエンジニア
reviewer (Human)        - コードレビュー
```

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | 初版作成 |
