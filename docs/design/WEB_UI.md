# Web UI 詳細設計

## 概要

AI Agent PM のプロジェクト管理機能をブラウザから利用可能にするWeb UI。
エージェントとしてログインし、プロジェクトとタスクの閲覧・編集を行う。

---

## 機能スコープ

| 機能 | 対応 | 備考 |
|------|------|------|
| ログイン（エージェント認証） | ✅ | agent_id + passkey |
| プロジェクト一覧表示 | ✅ | 参加プロジェクトのみ |
| タスクボード表示 | ✅ | カンバン形式 |
| タスク新規作成 | ✅ | |
| タスクステータス変更 | ✅ | D&D対応 |
| タスク詳細編集 | ✅ | |
| タスク割り当て | ✅ | 自身 + 下位エージェントのみ |
| リアルタイム更新 | ✅ | SSE |
| プロジェクト新規作成 | ❌ | |
| エージェント一覧表示 | ✅ | トップページに部下エージェント表示 |
| エージェント詳細・編集 | ✅ | 自身または部下のみ |
| 監査チーム | ❌ | |
| 履歴 | ❌ | |

---

## 画面一覧

| パス | 画面名 | 説明 |
|------|--------|------|
| `/login` | ログイン | エージェント認証 |
| `/projects` | トップページ | プロジェクト一覧 + 部下エージェント一覧 |
| `/projects/:id` | タスクボード | カンバン形式でタスク管理 |
| `/projects/:id/tasks/new` | タスク作成 | モーダル |
| `/projects/:id/tasks/:taskId` | タスク詳細 | モーダル / サイドパネル |
| `/agents/:id` | エージェント詳細 | 詳細表示・編集 |

---

## 認証

### 認証フロー

```
[ログイン画面]
    ↓ agent_id + passkey 入力
[POST /api/auth/login]
    ↓ 検証成功
[session_token 発行]
    ↓ Cookie または LocalStorage に保存
[プロジェクト選択画面へ]
```

### API

```
POST /api/auth/login
Request:
{
  "agent_id": "agent-001",
  "passkey": "secret-key"
}

Response:
{
  "session_token": "xxx",
  "agent": {
    "id": "agent-001",
    "name": "Manager A",
    "role": "Backend Manager",
    "hierarchy_type": "manager"
  },
  "expires_at": "2024-01-20T12:00:00Z"
}
```

### セッション管理

- session_token を Cookie (HttpOnly) に保存
- 有効期限: 24時間（設定可能）
- 各リクエストで `Authorization: Bearer <token>` ヘッダー送信

---

## 画面詳細

### 1. ログイン画面 (`/login`)

```
┌─────────────────────────────────────────────────┐
│                                                 │
│              AI Agent PM                        │
│              Web Console                        │
│                                                 │
│   ┌─────────────────────────────────────────┐   │
│   │ Agent ID                                │   │
│   │ ┌─────────────────────────────────────┐ │   │
│   │ │                                     │ │   │
│   │ └─────────────────────────────────────┘ │   │
│   │                                         │   │
│   │ Passkey                                 │   │
│   │ ┌─────────────────────────────────────┐ │   │
│   │ │ ••••••••                            │ │   │
│   │ └─────────────────────────────────────┘ │   │
│   │                                         │   │
│   │           [ログイン]                    │   │
│   │                                         │   │
│   │ ⚠️ エラーメッセージ表示エリア           │   │
│   └─────────────────────────────────────────┘   │
│                                                 │
└─────────────────────────────────────────────────┘
```

**コンポーネント:**
- `LoginForm`: ログインフォーム
- `ErrorAlert`: エラー表示

**状態:**
```typescript
interface LoginState {
  agentId: string;
  passkey: string;
  isLoading: boolean;
  error: string | null;
}
```

---

### 2. プロジェクト一覧画面 (`/projects`)

```
┌─────────────────────────────────────────────────────────────────┐
│  AI Agent PM                                                    │
│                                        🤖 Manager A  [ログアウト] │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   参加プロジェクト                                              │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │ 📁 ECサイト開発                              ⚡ Active   │   │
│   │                                                         │   │
│   │    タスク: 12 | 完了: 5 | 進行中: 3 | ブロック: 1       │   │
│   │    あなたの担当: 3件                                    │   │
│   │    更新: 5分前                                          │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │ 📁 モバイルアプリ                            ⚡ Active   │   │
│   │                                                         │   │
│   │    タスク: 8 | 完了: 7 | 進行中: 1 | ブロック: 0        │   │
│   │    あなたの担当: 1件                                    │   │
│   │    更新: 1時間前                                        │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐   │
│   │ 📁 アーカイブ済みプロジェクト (2件)           [展開 ▼]  │   │
│   └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘   │
│                                                                 │
│   ─────────────────────────────────────────────────────────────│
│                                                                 │
│   部下エージェント                                              │
│                                                                 │
│   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │
│   │ 🤖 Worker 1   │ │ 🤖 Worker 2   │ │ 🤖 Worker 3   │           │
│   │              │ │              │ │              │           │
│   │ Backend Dev  │ │ Frontend Dev │ │ QA Engineer  │           │
│   │ 🟢 Active    │ │ 🟢 Active    │ │ 🟡 Inactive  │           │
│   └──────────────┘ └──────────────┘ └──────────────┘           │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  接続: 🟢 | 最終同期: たった今                                  │
└─────────────────────────────────────────────────────────────────┘
```

**コンポーネント:**
- `Header`: ヘッダー（ユーザー情報、ログアウト）
- `ProjectCard`: プロジェクトカード
- `ProjectList`: プロジェクト一覧
- `AgentCard`: エージェントカード（クリックで詳細へ遷移）
- `AgentListSection`: 部下エージェント一覧セクション
- `ConnectionStatus`: 接続状態表示

**データ取得:**
```
GET /api/projects
→ ログイン中エージェントが参加しているプロジェクト一覧

GET /api/agents/subordinates
→ ログイン中エージェントの部下一覧（parentAgentId が自分のエージェント）
```

**備考:**
- Workerでログインした場合は部下がいないため、空のセクションが表示される
- エージェントカードをクリックすると `/agents/:id` へ遷移

---

### 3. タスクボード画面 (`/projects/:id`)

```
┌─────────────────────────────────────────────────────────────────────────┐
│  📁 ECサイト開発                                                        │
│                              [+ タスク作成]  🤖 Manager A  [← プロジェクト] │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  フィルター: [担当 ▼] [優先度 ▼] [🔍 検索...]                           │
│                                                                         │
│  ┌───────────┬───────────┬───────────┬───────────┬───────────┐         │
│  │  Backlog  │   Todo    │ Progress  │   Done    │  Blocked  │         │
│  │    (3)    │    (2)    │    (2)    │    (5)    │    (1)    │         │
│  ├───────────┼───────────┼───────────┼───────────┼───────────┤         │
│  │           │           │           │           │           │         │
│  │ ┌───────┐ │ ┌───────┐ │ ┌───────┐ │ ┌───────┐ │ ┌───────┐ │         │
│  │ │🔵     │ │ │🔵     │ │ │🟠     │ │ │       │ │ │🔴     │ │         │
│  │ │UI設計 │ │ │DB設計 │ │ │API実装│ │ │要件定義│ │ │API統合│ │         │
│  │ │       │ │ │       │ │ │       │ │ │  ✅   │ │ │       │ │         │
│  │ │👻 未  │ │ │🤖 W1  │ │ │🤖 W2  │ │ │       │ │ │⏳ 依存│ │         │
│  │ └───────┘ │ └───────┘ │ └───────┘ │ └───────┘ │ └───────┘ │         │
│  │           │           │           │           │           │         │
│  │ ┌───────┐ │ ┌───────┐ │ ┌───────┐ │ ┌───────┐ │           │         │
│  │ │🔵     │ │ │🔵     │ │ │🔵     │ │ │       │ │           │         │
│  │ │決済   │ │ │認証   │ │ │画面  │ │ │DB設計 │ │           │         │
│  │ │       │ │ │       │ │ │      │ │ │  ✅   │ │           │         │
│  │ │👻 未  │ │ │🤖 W1  │ │ │🤖 W3 │ │ │       │ │           │         │
│  │ └───────┘ │ └───────┘ │ └───────┘ │ └───────┘ │           │         │
│  │           │           │           │           │           │         │
│  └───────────┴───────────┴───────────┴───────────┴───────────┘         │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  タスク: 13件 | 🟢 リアルタイム更新中 | 最終更新: 3秒前                  │
└─────────────────────────────────────────────────────────────────────────┘
```

**コンポーネント:**
- `BoardHeader`: ボードヘッダー（プロジェクト名、アクション）
- `FilterBar`: フィルターバー
- `KanbanBoard`: カンバンボード全体
- `KanbanColumn`: 各ステータスカラム
- `TaskCard`: タスクカード（ドラッグ可能）
- `StatusBar`: ステータスバー

**ドラッグ&ドロップ:**
- dnd-kit 使用
- ステータス変更時に API 呼び出し
- 権限チェック（担当タスクのみ移動可能など）

**リアルタイム更新:**
- SSE で購読
- タスク変更時に自動反映

---

### 4. タスク作成モーダル (`/projects/:id/tasks/new`)

```
┌────────────────────────────────────────────────────────────┐
│  タスク作成                                          [×]   │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  タイトル *                                                │
│  ┌──────────────────────────────────────────────────────┐ │
│  │                                                      │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
│  説明                                                      │
│  ┌──────────────────────────────────────────────────────┐ │
│  │                                                      │ │
│  │                                                      │ │
│  │                                                      │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
│  ステータス              優先度                            │
│  [Backlog ▼]            [Medium ▼]                        │
│                                                            │
│  担当エージェント                                          │
│  ┌──────────────────────────────────────────────────────┐ │
│  │ [未アサイン ▼]                                       │ │
│  │                                                      │ │
│  │ 選択可能:                                            │ │
│  │   🤖 Manager A (自分)                                │ │
│  │   🤖 Worker 1                                        │ │
│  │   🤖 Worker 2                                        │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
│  依存タスク                                                │
│  ┌──────────────────────────────────────────────────────┐ │
│  │ 🔍 タスクを検索...                                   │ │
│  │ ☑ DB設計                                             │ │
│  │ ☐ API設計                                            │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
│                          [キャンセル]  [作成]              │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**割り当て可能エージェント:**
- 自身
- 下位エージェント（list_subordinates API で取得）

```
GET /api/agents/assignable
→ 自身 + 下位エージェントの一覧
```

---

### 5. タスク詳細パネル (`/projects/:id/tasks/:taskId`)

```
┌────────────────────────────────────────────────────────────┐
│  API実装                                       [編集] [×]  │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  ステータス                                                │
│  ┌────────────────────────────────────────────────────┐   │
│  │ ○ Backlog  ○ Todo  ● Progress  ○ Done  ○ Blocked │   │
│  └────────────────────────────────────────────────────┘   │
│                                                            │
│  優先度: 🟠 High                                           │
│  担当:   🤖 Worker 2                     [変更]           │
│  作成者: 🤖 Manager A                                      │
│  作成日: 2024-01-15                                        │
│                                                            │
├────────────────────────────────────────────────────────────┤
│  📝 説明                                                   │
│  ──────────────────────────────────────────────────────── │
│  REST APIエンドポイントの実装                              │
│  - ユーザー認証 API                                        │
│  - 商品 CRUD API                                           │
│                                                            │
├────────────────────────────────────────────────────────────┤
│  🔗 依存関係                                               │
│  ──────────────────────────────────────────────────────── │
│  ← DB設計 ✅                                               │
│  ← 認証設計 ✅                                             │
│  → API統合テスト (blocked)                                 │
│                                                            │
├────────────────────────────────────────────────────────────┤
│  💬 コンテキスト                                           │
│  ──────────────────────────────────────────────────────── │
│  🤖 Worker 2 (01/16 10:30)                                │
│  「JWT認証を採用、有効期限1時間に設定」                    │
│                                                            │
│  🤖 Worker 2 (01/16 14:00)                                │
│  「Rate limit: 100 req/min で実装」                       │
│                                                            │
│  [+ コンテキスト追加]                                      │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**編集可能項目:**
- ステータス
- 優先度
- 担当（自身 + 下位エージェントから選択）
- 説明
- 依存関係
- コンテキスト追加

---

### 6. エージェント詳細画面 (`/agents/:id`)

```
┌────────────────────────────────────────────────────────────┐
│  ← 戻る                            🤖 Manager A  [ログアウト] │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  エージェント詳細                                          │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐ │
│  │                                                      │ │
│  │  🤖 Worker 1                           🟢 Active     │ │
│  │     Backend Developer                               │ │
│  │                                                      │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
│  ────────────────────────────────────────────────────────  │
│                                                            │
│  基本情報                                        [編集]    │
│                                                            │
│  名前                                                      │
│  ┌──────────────────────────────────────────────────────┐ │
│  │ Worker 1                                             │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
│  役割                                                      │
│  ┌──────────────────────────────────────────────────────┐ │
│  │ Backend Developer                                    │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
│  ステータス                                                │
│  ○ Active  ● Inactive                                     │
│                                                            │
│  最大並列タスク数                                          │
│  ┌──────────────────────────────────────────────────────┐ │
│  │ 3                                                    │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
│  ────────────────────────────────────────────────────────  │
│                                                            │
│  システムプロンプト                                        │
│  ┌──────────────────────────────────────────────────────┐ │
│  │ あなたはバックエンド開発を担当するAIエージェントです  │ │
│  │ ...                                                  │ │
│  │                                                      │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
│  ────────────────────────────────────────────────────────  │
│                                                            │
│  詳細情報（読み取り専用）                                  │
│                                                            │
│  タイプ:        AI                                         │
│  階層:          Worker                                     │
│  ロールタイプ:   General                                    │
│  キック方法:     MCP                                        │
│  プロバイダー:   claude                                     │
│  モデルID:       claude-sonnet-4-20250514                  │
│  作成日:        2024-01-15                                 │
│  更新日:        2024-01-20                                 │
│                                                            │
│  ⚠️ このエージェントは現在ロックされています              │
│     （タスク実行中のためロックされている場合に表示）       │
│                                                            │
│                              [キャンセル]  [保存]          │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**コンポーネント:**
- `AgentHeader`: エージェント名・ステータス表示
- `AgentForm`: 編集フォーム
- `AgentReadonlyInfo`: 読み取り専用の詳細情報

**編集可能項目:**
- 名前 (`name`)
- 役割 (`role`)
- ステータス (`status`: active / inactive)
- 最大並列タスク数 (`maxParallelTasks`)
- システムプロンプト (`systemPrompt`)

**読み取り専用項目:**
- タイプ (`agentType`)
- 階層 (`hierarchyType`)
- ロールタイプ (`roleType`)
- キック方法 (`kickMethod`)
- プロバイダー (`provider`)
- モデルID (`modelId`)
- 作成日 (`createdAt`)
- 更新日 (`updatedAt`)

**非表示項目（セキュリティ）:**
- パスキー (`passkey`)
- 認証レベル (`authLevel`)

**アクセス制御:**
- 自分自身のプロフィール: 閲覧・編集可能
- 部下エージェント: 閲覧・編集可能
- それ以外: 403 Forbidden

**ロック時の動作:**
- `isLocked: true` の場合、フォームは読み取り専用
- 警告メッセージを表示
- 保存ボタンを無効化

**データ取得・更新:**
```
GET /api/agents/:agentId
→ エージェント詳細情報（自分または部下のみ）

PATCH /api/agents/:agentId
→ エージェント情報更新（自分または部下のみ）
```

---

## REST API 設計

### 認証

| Method | Path | 説明 |
|--------|------|------|
| POST | `/api/auth/login` | ログイン |
| POST | `/api/auth/logout` | ログアウト |
| GET | `/api/auth/me` | 現在のユーザー情報 |

### プロジェクト

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/projects` | プロジェクト一覧 |
| GET | `/api/projects/:id` | プロジェクト詳細 |

### タスク

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/projects/:id/tasks` | タスク一覧 |
| POST | `/api/projects/:id/tasks` | タスク作成 |
| GET | `/api/projects/:id/tasks/:taskId` | タスク詳細 |
| PATCH | `/api/projects/:id/tasks/:taskId` | タスク更新 |
| DELETE | `/api/projects/:id/tasks/:taskId` | タスク削除 |

### エージェント

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/agents/subordinates` | 部下エージェント一覧 |
| GET | `/api/agents/:agentId` | エージェント詳細（自分または部下のみ） |
| PATCH | `/api/agents/:agentId` | エージェント更新（自分または部下のみ） |
| GET | `/api/agents/assignable` | 割り当て可能エージェント一覧 |

#### GET /api/agents/subordinates

ログイン中エージェントの部下一覧を取得する。

```
Request:
  Authorization: Bearer <session_token>

Response (200):
[
  {
    "id": "worker-001",
    "name": "Worker 1",
    "role": "Backend Developer",
    "agentType": "ai",
    "status": "active",
    "hierarchyType": "worker",
    "parentAgentId": "manager-001"
  },
  ...
]
```

#### GET /api/agents/:agentId

エージェント詳細を取得する。自分自身または部下のみアクセス可能。

```
Request:
  Authorization: Bearer <session_token>

Response (200):
{
  "id": "worker-001",
  "name": "Worker 1",
  "role": "Backend Developer",
  "agentType": "ai",
  "status": "active",
  "hierarchyType": "worker",
  "parentAgentId": "manager-001",
  "roleType": "general",
  "maxParallelTasks": 3,
  "capabilities": ["coding", "testing"],
  "systemPrompt": "あなたはバックエンド開発を担当する...",
  "kickMethod": "mcp",
  "provider": "claude",
  "modelId": "claude-sonnet-4-20250514",
  "isLocked": false,
  "createdAt": "2024-01-15T10:00:00Z",
  "updatedAt": "2024-01-20T15:30:00Z"
}

Error (403): 権限がない場合
Error (404): エージェントが存在しない場合
```

#### PATCH /api/agents/:agentId

エージェント情報を更新する。自分自身または部下のみ更新可能。

```
Request:
  Authorization: Bearer <session_token>
  Content-Type: application/json

{
  "name": "Worker 1 (Updated)",
  "role": "Senior Backend Developer",
  "status": "inactive",
  "maxParallelTasks": 5,
  "systemPrompt": "更新されたプロンプト..."
}

Response (200): 更新後のAgentDetailDTO

Error (403): 権限がない場合
Error (404): エージェントが存在しない場合
Error (423): エージェントがロック中の場合
```

**更新可能フィールド:**
- `name`: エージェント名
- `role`: 役割
- `status`: ステータス（"active" / "inactive"）
- `maxParallelTasks`: 最大並列タスク数
- `capabilities`: 能力リスト
- `systemPrompt`: システムプロンプト

### リアルタイム

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/projects/:id/events` | SSE イベントストリーム |

---

## ディレクトリ構成

### プロジェクト全体

```
ai-agent-pm/
├── Sources/                      # Swift (既存)
│   ├── Domain/
│   ├── UseCase/
│   ├── Infrastructure/
│   ├── App/
│   └── MCPServer/
│       ├── Transport/
│       │   ├── StdioTransport.swift
│       │   ├── UnixSocketTransport.swift
│       │   └── HTTPTransport.swift      ← 新規
│       ├── Routes/                       ← 新規: REST API
│       │   ├── AuthRoutes.swift
│       │   ├── ProjectRoutes.swift
│       │   ├── TaskRoutes.swift
│       │   └── AgentRoutes.swift
│       ├── Public/                       ← React ビルド成果物配置先
│       └── ...
│
├── web-ui/                       # React プロジェクト (新規)
│   ├── src/
│   ├── e2e/
│   ├── tests/
│   └── ...
│
├── docs/
├── Tests/
└── project.yml
```

---

### web-ui/ 詳細構成

```
web-ui/
├── public/
│   ├── favicon.ico
│   └── robots.txt
│
├── src/
│   ├── api/                          # API クライアント
│   │   ├── client.ts                 # fetch ラッパー
│   │   ├── auth.ts                   # 認証 API
│   │   ├── projects.ts               # プロジェクト API
│   │   ├── tasks.ts                  # タスク API
│   │   ├── agents.ts                 # エージェント API
│   │   └── index.ts
│   │
│   ├── components/                   # UIコンポーネント
│   │   ├── common/                   # 共通コンポーネント
│   │   │   ├── Button/
│   │   │   │   ├── Button.tsx
│   │   │   │   ├── Button.test.tsx
│   │   │   │   └── index.ts
│   │   │   ├── Modal/
│   │   │   ├── Select/
│   │   │   ├── Input/
│   │   │   ├── Badge/
│   │   │   ├── Card/
│   │   │   ├── Loading/
│   │   │   └── index.ts
│   │   │
│   │   ├── layout/                   # レイアウト
│   │   │   ├── AppLayout/
│   │   │   │   ├── AppLayout.tsx
│   │   │   │   ├── Header.tsx
│   │   │   │   ├── Sidebar.tsx
│   │   │   │   └── index.ts
│   │   │   └── ConnectionStatus/
│   │   │
│   │   ├── auth/                     # 認証関連
│   │   │   ├── LoginForm/
│   │   │   │   ├── LoginForm.tsx
│   │   │   │   ├── LoginForm.test.tsx
│   │   │   │   └── index.ts
│   │   │   └── ProtectedRoute/
│   │   │
│   │   ├── project/                  # プロジェクト関連
│   │   │   ├── ProjectList/
│   │   │   │   ├── ProjectList.tsx
│   │   │   │   ├── ProjectList.test.tsx
│   │   │   │   └── index.ts
│   │   │   ├── ProjectCard/
│   │   │   └── ProjectSummary/
│   │   │
│   │   ├── agent/                    # エージェント関連
│   │   │   ├── AgentCard/
│   │   │   │   ├── AgentCard.tsx
│   │   │   │   ├── AgentCard.test.tsx
│   │   │   │   └── index.ts
│   │   │   ├── AgentListSection/
│   │   │   │   ├── AgentListSection.tsx
│   │   │   │   └── index.ts
│   │   │   ├── AgentForm/
│   │   │   │   ├── AgentForm.tsx
│   │   │   │   └── index.ts
│   │   │   └── index.ts
│   │   │
│   │   └── task/                     # タスク関連
│   │       ├── KanbanBoard/
│   │       │   ├── KanbanBoard.tsx
│   │       │   ├── KanbanBoard.test.tsx
│   │       │   └── index.ts
│   │       ├── KanbanColumn/
│   │       ├── TaskCard/
│   │       │   ├── TaskCard.tsx
│   │       │   ├── TaskCard.test.tsx
│   │       │   └── index.ts
│   │       ├── TaskDetail/
│   │       ├── TaskForm/
│   │       ├── TaskFilter/
│   │       └── AssigneeSelect/
│   │
│   ├── hooks/                        # カスタムフック
│   │   ├── useAuth.ts
│   │   ├── useAuth.test.ts
│   │   ├── useProjects.ts
│   │   ├── useTasks.ts
│   │   ├── useAssignableAgents.ts
│   │   ├── useSubordinates.ts        # 部下エージェント一覧
│   │   ├── useAgent.ts               # エージェント詳細・更新
│   │   ├── useRealtimeUpdates.ts
│   │   └── index.ts
│   │
│   ├── pages/                        # ページコンポーネント
│   │   ├── LoginPage/
│   │   │   ├── LoginPage.tsx
│   │   │   └── index.ts
│   │   ├── ProjectListPage/
│   │   │   ├── ProjectListPage.tsx
│   │   │   └── index.ts
│   │   ├── TaskBoardPage/
│   │   │   ├── TaskBoardPage.tsx
│   │   │   └── index.ts
│   │   ├── AgentDetailPage/          # エージェント詳細・編集
│   │   │   ├── AgentDetailPage.tsx
│   │   │   └── index.ts
│   │   └── NotFoundPage/
│   │
│   ├── stores/                       # 状態管理 (Zustand)
│   │   ├── authStore.ts
│   │   ├── connectionStore.ts
│   │   └── index.ts
│   │
│   ├── types/                        # 型定義
│   │   ├── auth.ts
│   │   ├── project.ts
│   │   ├── task.ts
│   │   ├── agent.ts
│   │   ├── api.ts                    # API レスポンス型
│   │   └── index.ts
│   │
│   ├── utils/                        # ユーティリティ
│   │   ├── date.ts                   # 日付フォーマット
│   │   ├── validation.ts             # バリデーション
│   │   ├── constants.ts              # 定数
│   │   └── index.ts
│   │
│   ├── styles/                       # グローバルスタイル
│   │   └── globals.css
│   │
│   ├── App.tsx                       # ルートコンポーネント
│   ├── main.tsx                      # エントリーポイント
│   └── router.tsx                    # ルーティング定義
│
├── e2e/                              # E2Eテスト
│   ├── fixtures/
│   │   ├── auth.ts                   # 認証フィクスチャ
│   │   └── test-data.ts              # テストデータ
│   ├── pages/                        # Page Objects
│   │   ├── base.page.ts
│   │   ├── login.page.ts
│   │   ├── project-list.page.ts
│   │   └── task-board.page.ts
│   ├── tests/
│   │   ├── auth.spec.ts
│   │   ├── project-list.spec.ts
│   │   └── task-board.spec.ts
│   └── global-setup.ts
│
├── tests/                            # テストユーティリティ
│   ├── setup.ts                      # Vitest セットアップ
│   ├── test-utils.tsx                # カスタムレンダー
│   └── mocks/
│       ├── handlers.ts               # MSW ハンドラー
│       ├── server.ts                 # MSW サーバー
│       └── data/                     # モックデータ
│           ├── projects.ts
│           ├── tasks.ts
│           └── agents.ts
│
├── .env                              # 環境変数（開発用）
├── .env.example                      # 環境変数サンプル
├── .eslintrc.cjs                     # ESLint 設定
├── .prettierrc                       # Prettier 設定
├── index.html                        # HTML テンプレート
├── package.json
├── playwright.config.ts              # Playwright 設定
├── tailwind.config.js                # Tailwind 設定
├── tsconfig.json                     # TypeScript 設定
├── tsconfig.node.json
└── vite.config.ts                    # Vite 設定
```

---

### コンポーネント設計方針

**1コンポーネント = 1ディレクトリ（コロケーション）**

```
TaskCard/
├── TaskCard.tsx          # メインコンポーネント
├── TaskCard.test.tsx     # テスト
├── TaskCard.stories.tsx  # Storybook (オプション)
└── index.ts              # エクスポート
```

**index.ts の例:**
```typescript
export { TaskCard } from './TaskCard';
export type { TaskCardProps } from './TaskCard';
```

---

### 型定義例

```typescript
// types/task.ts
export type TaskStatus =
  | 'backlog'
  | 'todo'
  | 'in_progress'
  | 'done'
  | 'blocked';

export type TaskPriority = 'low' | 'medium' | 'high' | 'urgent';

export interface Task {
  id: string;
  projectId: string;
  title: string;
  description: string;
  status: TaskStatus;
  priority: TaskPriority;
  assigneeId: string | null;
  assignee: Agent | null;
  creatorId: string;
  dependencies: string[];
  contexts: TaskContext[];
  createdAt: string;
  updatedAt: string;
}

export interface TaskContext {
  id: string;
  agentId: string;
  content: string;
  createdAt: string;
}
```

```typescript
// types/agent.ts
export type AgentType = 'ai' | 'human';
export type AgentStatus = 'active' | 'inactive' | 'busy';
export type HierarchyType = 'owner' | 'manager' | 'worker';
export type RoleType = 'owner' | 'manager' | 'general';
export type KickMethod = 'mcp' | 'stdio' | 'cli';

// 一覧表示用（簡易）
export interface Agent {
  id: string;
  name: string;
  role: string;
  agentType: AgentType;
  status: AgentStatus;
  hierarchyType: HierarchyType;
  parentAgentId: string | null;
}

// 詳細表示用（フル情報）
export interface AgentDetail extends Agent {
  roleType: RoleType;
  maxParallelTasks: number;
  capabilities: string[];
  systemPrompt: string | null;
  kickMethod: KickMethod;
  provider: string | null;
  modelId: string | null;
  isLocked: boolean;
  createdAt: string;
  updatedAt: string;
}

// 更新リクエスト用
export interface UpdateAgentRequest {
  name?: string;
  role?: string;
  status?: AgentStatus;
  maxParallelTasks?: number;
  capabilities?: string[];
  systemPrompt?: string;
}
```

```typescript
// types/project.ts
export type ProjectStatus = 'active' | 'archived';

export interface Project {
  id: string;
  name: string;
  description: string;
  status: ProjectStatus;
  createdAt: string;
  updatedAt: string;
}

export interface ProjectSummary extends Project {
  taskCount: number;
  completedCount: number;
  inProgressCount: number;
  blockedCount: number;
  myTaskCount: number;
}
```

---

## 状態管理

### グローバル状態 (Context / Zustand)

```typescript
interface AppState {
  // 認証
  auth: {
    isAuthenticated: boolean;
    agent: Agent | null;
    sessionToken: string | null;
  };

  // 接続状態
  connection: {
    status: 'connected' | 'disconnected' | 'reconnecting';
    lastSync: Date | null;
  };
}
```

### サーバー状態 (TanStack Query)

- プロジェクト一覧
- タスク一覧
- 割り当て可能エージェント

---

## リアルタイム更新 (SSE)

### イベント種別

```typescript
type TaskEvent =
  | { type: 'task_created'; task: Task }
  | { type: 'task_updated'; task: Task }
  | { type: 'task_deleted'; taskId: string }
  | { type: 'task_status_changed'; taskId: string; oldStatus: string; newStatus: string };
```

### クライアント側処理

```typescript
// useRealtimeUpdates.ts
const useRealtimeUpdates = (projectId: string) => {
  useEffect(() => {
    const eventSource = new EventSource(`/api/projects/${projectId}/events`);

    eventSource.onmessage = (event) => {
      const data = JSON.parse(event.data);
      // TanStack Query のキャッシュを更新
      queryClient.invalidateQueries(['tasks', projectId]);
    };

    return () => eventSource.close();
  }, [projectId]);
};
```

---

## 技術スタック

| カテゴリ | 技術 |
|----------|------|
| フレームワーク | React 18 |
| ビルドツール | Vite |
| ルーティング | React Router v6 |
| 状態管理 | TanStack Query + Zustand |
| スタイリング | Tailwind CSS |
| D&D | dnd-kit |
| HTTP クライアント | fetch (native) |
| 型定義 | TypeScript |

---

## テスト構成

### 概要

| テスト種別 | ツール | 対象 |
|-----------|--------|------|
| ユニットテスト | Vitest + React Testing Library | コンポーネント、hooks、ユーティリティ |
| E2Eテスト | Playwright | 画面遷移、ユーザーフロー全体 |

---

### ユニットテスト

**ツール:**
- **Vitest**: Vite ネイティブのテストランナー（Jest互換）
- **React Testing Library**: コンポーネントテスト
- **MSW (Mock Service Worker)**: API モック

**ディレクトリ構成:**
```
web-ui/
├── src/
│   ├── components/
│   │   ├── task/
│   │   │   ├── TaskCard.tsx
│   │   │   └── TaskCard.test.tsx    ← コロケーション
│   │   └── ...
│   ├── hooks/
│   │   ├── useAuth.ts
│   │   └── useAuth.test.ts
│   └── ...
├── tests/
│   ├── setup.ts                      ← テストセットアップ
│   └── mocks/
│       ├── handlers.ts               ← MSW ハンドラー
│       └── server.ts
└── vitest.config.ts
```

**テスト例:**

```typescript
// TaskCard.test.tsx
import { render, screen } from '@testing-library/react';
import { TaskCard } from './TaskCard';

describe('TaskCard', () => {
  const task = {
    id: 'task-1',
    title: 'API実装',
    status: 'in_progress',
    priority: 'high',
    assignee: { id: 'agent-1', name: 'Worker 1' }
  };

  it('タスクタイトルを表示する', () => {
    render(<TaskCard task={task} />);
    expect(screen.getByText('API実装')).toBeInTheDocument();
  });

  it('優先度に応じたバッジを表示する', () => {
    render(<TaskCard task={task} />);
    expect(screen.getByTestId('priority-badge')).toHaveClass('bg-orange-500');
  });

  it('担当エージェント名を表示する', () => {
    render(<TaskCard task={task} />);
    expect(screen.getByText('Worker 1')).toBeInTheDocument();
  });
});
```

```typescript
// useAuth.test.ts
import { renderHook, act } from '@testing-library/react';
import { useAuth } from './useAuth';

describe('useAuth', () => {
  it('ログイン成功時にセッションを保存する', async () => {
    const { result } = renderHook(() => useAuth());

    await act(async () => {
      await result.current.login('agent-1', 'passkey');
    });

    expect(result.current.isAuthenticated).toBe(true);
    expect(result.current.agent?.id).toBe('agent-1');
  });

  it('ログイン失敗時にエラーを返す', async () => {
    const { result } = renderHook(() => useAuth());

    await act(async () => {
      await result.current.login('invalid', 'wrong');
    });

    expect(result.current.isAuthenticated).toBe(false);
    expect(result.current.error).toBe('認証に失敗しました');
  });
});
```

**カバレッジ対象:**

| 対象 | テスト内容 |
|------|-----------|
| コンポーネント | レンダリング、イベント処理、条件分岐 |
| hooks | 状態変更、API呼び出し、エラーハンドリング |
| ユーティリティ | 変換関数、バリデーション |

---

### E2Eテスト

**ツール:**
- **Playwright**: クロスブラウザE2Eテスト

**ディレクトリ構成:**
```
web-ui/
├── e2e/
│   ├── fixtures/
│   │   └── auth.ts                   ← 認証フィクスチャ
│   ├── pages/
│   │   ├── login.page.ts             ← Page Object
│   │   ├── project-list.page.ts
│   │   └── task-board.page.ts
│   ├── tests/
│   │   ├── auth.spec.ts
│   │   ├── project-list.spec.ts
│   │   └── task-board.spec.ts
│   └── global-setup.ts
└── playwright.config.ts
```

**テストシナリオ:**

```typescript
// e2e/tests/auth.spec.ts
import { test, expect } from '@playwright/test';
import { LoginPage } from '../pages/login.page';

test.describe('認証', () => {
  test('正しい認証情報でログインできる', async ({ page }) => {
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login('manager-1', 'test-passkey');

    await expect(page).toHaveURL('/projects');
    await expect(page.getByText('参加プロジェクト')).toBeVisible();
  });

  test('不正な認証情報でエラーが表示される', async ({ page }) => {
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login('invalid', 'wrong');

    await expect(page.getByText('認証に失敗しました')).toBeVisible();
    await expect(page).toHaveURL('/login');
  });

  test('ログアウトするとログイン画面に戻る', async ({ page }) => {
    // 事前にログイン状態にする
    await page.goto('/projects');
    await page.getByRole('button', { name: 'ログアウト' }).click();

    await expect(page).toHaveURL('/login');
  });
});
```

```typescript
// e2e/tests/task-board.spec.ts
import { test, expect } from '@playwright/test';
import { TaskBoardPage } from '../pages/task-board.page';

test.describe('タスクボード', () => {
  test.beforeEach(async ({ page }) => {
    // 認証済み状態でセットアップ
    await page.goto('/projects/project-1');
  });

  test('タスクをドラッグ&ドロップでステータス変更できる', async ({ page }) => {
    const board = new TaskBoardPage(page);

    // TodoカラムからProgressカラムへドラッグ
    await board.dragTask('task-1', 'Todo', 'Progress');

    // ステータスが変更されたことを確認
    await expect(board.getColumn('Progress').getByText('API実装')).toBeVisible();
    await expect(board.getColumn('Todo').getByText('API実装')).not.toBeVisible();
  });

  test('タスクを新規作成できる', async ({ page }) => {
    const board = new TaskBoardPage(page);

    await board.openCreateTaskModal();
    await board.fillTaskForm({
      title: '新しいタスク',
      description: 'タスクの説明',
      priority: 'high',
      assignee: 'Worker 1'
    });
    await board.submitTaskForm();

    await expect(page.getByText('新しいタスク')).toBeVisible();
  });

  test('割り当て可能なエージェントは自身と下位のみ表示される', async ({ page }) => {
    const board = new TaskBoardPage(page);
    await board.openCreateTaskModal();

    const assigneeSelect = page.getByLabel('担当エージェント');
    await assigneeSelect.click();

    // 自身と下位エージェントが表示される
    await expect(page.getByRole('option', { name: 'Manager A (自分)' })).toBeVisible();
    await expect(page.getByRole('option', { name: 'Worker 1' })).toBeVisible();
    await expect(page.getByRole('option', { name: 'Worker 2' })).toBeVisible();

    // 兄弟や他のマネージャーは表示されない
    await expect(page.getByRole('option', { name: 'Manager B' })).not.toBeVisible();
  });

  test('リアルタイムで他のユーザーの変更が反映される', async ({ page, context }) => {
    // 2つ目のページを開く（別セッション想定）
    const page2 = await context.newPage();
    await page2.goto('/projects/project-1');

    // page2でタスクを更新
    await page2.getByText('API実装').click();
    await page2.getByLabel('ステータス').selectOption('done');
    await page2.getByRole('button', { name: '保存' }).click();

    // page1でリアルタイム反映を確認
    await expect(page.locator('[data-column="Done"]').getByText('API実装')).toBeVisible();
  });
});
```

**Page Object:**

```typescript
// e2e/pages/task-board.page.ts
import { Page, Locator } from '@playwright/test';

export class TaskBoardPage {
  readonly page: Page;

  constructor(page: Page) {
    this.page = page;
  }

  getColumn(status: string): Locator {
    return this.page.locator(`[data-column="${status}"]`);
  }

  async dragTask(taskId: string, from: string, to: string) {
    const task = this.page.locator(`[data-task-id="${taskId}"]`);
    const targetColumn = this.getColumn(to);
    await task.dragTo(targetColumn);
  }

  async openCreateTaskModal() {
    await this.page.getByRole('button', { name: 'タスク作成' }).click();
  }

  async fillTaskForm(data: {
    title: string;
    description?: string;
    priority?: string;
    assignee?: string;
  }) {
    await this.page.getByLabel('タイトル').fill(data.title);
    if (data.description) {
      await this.page.getByLabel('説明').fill(data.description);
    }
    if (data.priority) {
      await this.page.getByLabel('優先度').selectOption(data.priority);
    }
    if (data.assignee) {
      await this.page.getByLabel('担当エージェント').selectOption(data.assignee);
    }
  }

  async submitTaskForm() {
    await this.page.getByRole('button', { name: '作成' }).click();
  }
}
```

---

### テスト環境

**ユニットテスト:**
- MSWでAPIをモック
- インメモリ状態

**E2Eテスト:**
- テスト用Vaporサーバー起動
- テスト用SQLiteデータベース（シード済み）

```typescript
// playwright.config.ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e/tests',
  webServer: {
    command: 'npm run dev',
    port: 5173,
    reuseExistingServer: !process.env.CI,
  },
  use: {
    baseURL: 'http://localhost:5173',
  },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
    { name: 'firefox', use: { browserName: 'firefox' } },
    { name: 'webkit', use: { browserName: 'webkit' } },
  ],
});
```

---

### テスト実行

**コマンド:**
```bash
# ユニットテスト
npm run test              # 実行
npm run test:watch        # ウォッチモード
npm run test:coverage     # カバレッジ

# E2Eテスト
npm run e2e               # ヘッドレス実行
npm run e2e:ui            # UIモード（デバッグ用）
npm run e2e:headed        # ブラウザ表示
```

**CI設定 (GitHub Actions):**
```yaml
# .github/workflows/web-ui-test.yml
name: Web UI Tests

on:
  push:
    paths:
      - 'web-ui/**'
  pull_request:
    paths:
      - 'web-ui/**'

jobs:
  unit-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: cd web-ui && npm ci
      - run: cd web-ui && npm run test:coverage

  e2e-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: cd web-ui && npm ci
      - run: cd web-ui && npx playwright install --with-deps
      - run: cd web-ui && npm run e2e
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report
          path: web-ui/playwright-report/
```

---

### テスト方針まとめ

| 項目 | ユニットテスト | E2Eテスト |
|------|--------------|-----------|
| ツール | Vitest + RTL + MSW | Playwright |
| 対象 | コンポーネント、hooks | ユーザーフロー全体 |
| 実行速度 | 速い | 遅い |
| API | モック | 実サーバー or テストサーバー |
| CI | 常時実行 | PR時 / デプロイ前 |
| カバレッジ目標 | 80%以上 | 主要フロー100% |

---

## 開発方針

### TDD (テスト駆動開発)

本プロジェクトは **TDD (Test-Driven Development)** で進めます。

**基本サイクル:**
```
RED → GREEN → REFACTOR
```

1. **RED**: 失敗するテストを先に書く
2. **GREEN**: テストを通す最小限のコードを実装
3. **REFACTOR**: コードを整理（テストは通ったまま）

**適用範囲:**

| レイヤー | テスト種別 | TDD適用 |
|---------|-----------|---------|
| コンポーネント | ユニットテスト (Vitest + RTL) | ✅ |
| hooks | ユニットテスト (Vitest) | ✅ |
| API クライアント | ユニットテスト (Vitest + MSW) | ✅ |
| ユーザーフロー | E2Eテスト (Playwright) | ✅ |
| REST API (Vapor) | 統合テスト | ✅ |

**実装順序:**

各機能について以下の順序で進める:

1. **E2Eテスト (RED)**: ユーザーフローのテストを書く
2. **コンポーネントテスト (RED)**: 必要なコンポーネントのテストを書く
3. **実装 (GREEN)**: テストが通るようにコードを実装
4. **リファクタリング**: コード品質を改善

**例: ログイン機能**
```
1. e2e/tests/auth.spec.ts を書く (RED)
2. LoginForm.test.tsx を書く (RED)
3. useAuth.test.ts を書く (RED)
4. LoginForm.tsx を実装 (GREEN)
5. useAuth.ts を実装 (GREEN)
6. リファクタリング
7. E2Eテストが通ることを確認
```

---

## 次のアクション

1. [ ] React プロジェクト初期化 (`web-ui/`)
2. [ ] テスト環境構築 (Vitest, Playwright, MSW)
3. [ ] 認証機能（TDD: E2E → ユニット → 実装）
4. [ ] プロジェクト一覧画面（TDD）
5. [ ] タスクボード画面（TDD）
6. [ ] リアルタイム更新 (SSE)（TDD）
7. [ ] Vapor REST API エンドポイント実装（TDD）
