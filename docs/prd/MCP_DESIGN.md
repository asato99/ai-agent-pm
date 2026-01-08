# MCP連携設計

MCPサーバーが提供するTools、Resources、Promptsの詳細設計。

---

## 設計原則

### ステートレスMCPサーバー

MCPサーバーは**ステートレス**に設計されています。

- 起動時に`--db`（データベースパス）のみ必要
- `--agent-id` や `--project-id` は**不要**
- 必要なIDは**各ツール呼び出し時に引数として渡す**
- キック時にプロンプトでID情報を提供し、LLM（Claude Code）が橋渡し

```
┌─────────────┐                    ┌──────────────┐                    ┌─────────────┐
│  PMアプリ   │ ─プロンプトに─────▶│ Claude Code  │ ─引数として────────▶│ MCPサーバー │
│             │  ID情報を含める    │   (LLM)      │  IDを渡す          │ (ステートレス)│
└─────────────┘                    └──────────────┘                    └─────────────┘
```

---

## MCPサーバーが提供するTools

### Runner 向けAPI（Phase 4）

> **Phase 4 での変更**: 既存の Runner に `project_id` 対応を追加。管理単位が `(agent_id, project_id)` に拡張されました。

Runner は以下の3ステップでポーリングを行う：
1. `health_check` - サーバー起動確認
2. `list_active_projects_with_agents` - アクティブプロジェクト+割り当てエージェント一覧取得
3. `should_start` - 各(agent_id, project_id)の起動判断

| Tool | 引数 | 説明 |
|------|------|------|
| `health_check` | なし | MCPサーバーの起動確認 |
| `list_active_projects_with_agents` | なし | アクティブプロジェクトと割り当てエージェント一覧を取得 |
| `should_start` | `agent_id`, `project_id` | (agent, project)の組み合わせで起動すべきかどうかを返す |

#### health_check

MCPサーバーの起動状態を確認する。

```python
health_check() -> {
    "status": "ok",
    "version": "1.0.0",
    "timestamp": "2025-01-06T10:00:00Z"
}
```

**用途**:
- サーバー起動確認
- 接続テスト
- バージョン確認（将来の互換性チェック用）

#### list_active_projects_with_agents

アクティブなプロジェクト一覧と、各プロジェクトに割り当てられたエージェントを取得する。

```python
list_active_projects_with_agents() -> {
    "success": True,
    "projects": [
        {
            "project_id": "prj_frontend",
            "project_name": "Frontend App",
            "working_directory": "/projects/frontend",
            "agents": ["agt_developer", "agt_reviewer"]
        },
        {
            "project_id": "prj_backend",
            "project_name": "Backend API",
            "working_directory": "/projects/backend",
            "agents": ["agt_developer", "agt_infra"]
        }
    ]
}
```

**実装ロジック（内部）**:
- `active` 状態のプロジェクトのみ返す
- 各プロジェクトに割り当てられた `active` 状態のエージェントIDを返す
- working_directoryはプロジェクトから取得

**重要**:
- 同一エージェントが複数プロジェクトに登場可能
- Runner は各 (agent_id, project_id) の組み合わせを個別に管理

#### should_start

特定の(agent_id, project_id)の組み合わせでAgent Instanceを起動すべきかを返す。

```python
should_start(
    agent_id: str,      # エージェントID
    project_id: str     # プロジェクトID
) -> {
    "should_start": True,     # or False
    "ai_type": "claude"       # should_start が true の場合のみ
}
```

**実装ロジック（内部）**:
1. エージェントまたはプロジェクトが存在しない → `False`
2. 該当 (agent_id, project_id) で既に実行中（アクティブセッションあり）→ `False`
3. 該当プロジェクトで該当エージェントにアサインされた `in_progress` タスクがある → `True` + `ai_type`
4. それ以外 → `False`

**重要**:
- タスク情報は含めない（Runner はタスクの存在を知る必要がない）
- `ai_type` はエージェント定義から取得し、Runner が適切なCLIを選択するために使用
- 実行状態は (agent_id, project_id) 単位で管理

---

### Agent Instance向けAPI（Phase 4）

| Tool | 引数 | 説明 |
|------|------|------|
| `authenticate` | `agent_id`, `passkey`, `project_id` | セッショントークン、system_prompt、instructionを取得 |
| `logout` | `session_token` | セッションを終了 |
| `get_my_task` | `session_token` | 現在のタスク詳細を取得 |
| `report_completed` | `session_token`, `result`, `summary?`, `next_steps?` | タスク完了を報告 |

#### authenticate

認証後、エージェントの役割（system_prompt）と次に何をすべきかの instruction を返す。
project_idを含めることで、セッションが特定の(agent_id, project_id)に紐づく。

```python
authenticate(
    agent_id: str,      # エージェントID
    passkey: str,       # パスキー
    project_id: str     # プロジェクトID
) -> {
    "success": True,
    "session_token": "sess_xxxxx",
    "expires_in": 3600,  # 秒（1時間）
    "agent_name": "frontend-dev",
    "project_name": "Frontend App",
    "system_prompt": "あなたはフロントエンド開発者です...",  # DBから取得
    "instruction": "get_my_task を呼び出してタスク詳細を取得してください"
}

# 認証失敗時
{
    "success": False,
    "error": "Invalid agent_id or passkey"
}

# 既に実行中の場合（二重起動防止）
{
    "success": False,
    "error": "Agent instance already running for this project"
}
```

**ポイント**:
- `system_prompt` はアプリ側（DB）で管理され、認証時にエージェントに渡される
- `project_id` によりセッションがプロジェクトに紐づく
- 同一 (agent_id, project_id) の二重起動を防止
- 同一エージェントでも異なるプロジェクトは別セッションとして許可

**実行状態の遷移**:
- 認証成功 → (agent_id, project_id) の `running` フラグ ON
- `report_completed` 呼び出し → `running` フラグ OFF
- セッションタイムアウト → `running` フラグ OFF（自動リカバリー）

#### get_my_task

認証済みエージェントの現在のタスクを取得。

```python
get_my_task(
    session_token: str  # 認証で取得したトークン
) -> {
    "success": True,
    "has_task": True,
    "task": {
        "task_id": "tsk_xxx",
        "title": "機能実装",
        "description": "ログイン画面のUIを実装する",
        "working_directory": "/path/to/project",
        "context": { ... },      # 前回の進捗等
        "handoff": { ... }       # 引き継ぎ情報（あれば）
    },
    "instruction": "タスクを完了したら report_completed を呼び出してください"
}

# タスクがない場合
{
    "success": True,
    "has_task": False,
    "instruction": "現在割り当てられたタスクはありません"
}
```

#### report_completed

タスク完了を報告。

```python
report_completed(
    session_token: str,     # 認証で取得したトークン
    result: str,            # "success" | "failed" | "blocked"
    summary: str = None,    # 作業サマリー（オプション）
    next_steps: str = None  # 次のステップ（オプション）
) -> {
    "success": True,
    "instruction": "タスクが完了しました。セッションを終了します。"
}
```

---

### 旧API（非推奨・Phase 3）

以下のAPIは非推奨です。Phase 4の新APIを使用してください。

| 旧Tool | 新Tool | 備考 |
|--------|--------|------|
| `get_pending_tasks` | `get_my_task` | 単一タスクに簡略化 |
| `report_execution_start` | 不要 | `get_my_task` 呼び出し時に自動記録 |
| `report_execution_complete` | `report_completed` | 簡略化 |

#### get_pending_tasks（非推奨）

```python
get_pending_tasks(
    session_token: str  # 認証で取得したトークン
) -> {
    "success": True,
    "tasks": [
        {
            "taskId": "tsk_xxx",
            "projectId": "prj_xxx",
            "title": "機能実装",
            "description": "ログイン画面のUIを実装する",
            "priority": "high",
            "workingDirectory": "/path/to/project",
            "assignedAt": "2025-01-06T10:00:00Z"
        }
    ]
}

# トークン無効時
{
    "success": False,
    "error": "Invalid or expired session_token"
}
```

### 実行ログ管理（Runner向け）

| Tool | 引数 | 説明 |
|------|------|------|
| `report_execution_start` | `session_token`, `task_id` | 実行開始を報告、execution_idを取得 |
| `report_execution_complete` | `session_token`, `execution_id`, `exit_code`, `duration_seconds`, `log_file_path` | 実行完了を報告 |
| `list_execution_logs` | `task_id?`, `agent_id?`, `limit?` | 実行ログ一覧取得 |
| `get_execution_log` | `execution_id` | 実行ログ詳細取得 |

#### report_execution_start

```python
report_execution_start(
    session_token: str,  # 認証で取得したトークン
    task_id: str         # 実行対象のタスクID
) -> {
    "success": True,
    "execution_id": "exec_abc123",
    "started_at": "2025-01-06T10:00:00Z"
}

# 失敗時
{
    "success": False,
    "error": "Invalid session_token or task_id"
}
```

#### report_execution_complete

```python
report_execution_complete(
    session_token: str,      # 認証で取得したトークン
    execution_id: str,       # report_execution_startで取得したID
    exit_code: int,          # CLIの終了コード（0=成功）
    duration_seconds: float, # 実行時間（秒）
    log_file_path: str       # ログファイルのパス
) -> {
    "success": True,
    "execution_id": "exec_abc123",
    "completed_at": "2025-01-06T10:15:30Z",
    "status": "completed"  # completed / failed / error
}

# 失敗時
{
    "success": False,
    "error": "Invalid execution_id or session_token"
}
```

#### list_execution_logs

```python
list_execution_logs(
    task_id: str = None,    # タスクでフィルタ（オプション）
    agent_id: str = None,   # エージェントでフィルタ（オプション）
    limit: int = 20         # 取得件数（デフォルト20）
) -> {
    "success": True,
    "logs": [
        {
            "executionId": "exec_abc123",
            "taskId": "tsk_xxx",
            "agentId": "agt_xxx",
            "status": "completed",
            "exitCode": 0,
            "durationSeconds": 930.5,
            "startedAt": "2025-01-06T10:00:00Z",
            "completedAt": "2025-01-06T10:15:30Z"
        }
    ]
}
```

#### get_execution_log

```python
get_execution_log(
    execution_id: str  # 実行ログID
) -> {
    "success": True,
    "log": {
        "executionId": "exec_abc123",
        "taskId": "tsk_xxx",
        "agentId": "agt_xxx",
        "status": "completed",
        "exitCode": 0,
        "durationSeconds": 930.5,
        "startedAt": "2025-01-06T10:00:00Z",
        "completedAt": "2025-01-06T10:15:30Z",
        "logFilePath": "~/Library/Application Support/AIAgentPM/logs/exec_abc123.log"
    }
}
```

### エージェント管理

| Tool | 引数 | 説明 |
|------|------|------|
| `get_agent_profile` | `agent_id` | 指定エージェントの情報を取得 |
| `list_agents` | - | 全エージェント一覧 |

### プロジェクト・タスク管理

| Tool | 引数 | 説明 |
|------|------|------|
| `list_projects` | - | プロジェクト一覧取得 |
| `get_project` | `project_id` | プロジェクト詳細取得 |
| `list_tasks` | `project_id`, `status?`, `assignee_id?` | タスク一覧取得（フィルタ可） |
| `get_task` | `task_id` | タスク詳細取得 |
| `update_task_status` | `task_id`, `status` | ステータス更新 |
| `assign_task` | `task_id`, `assignee_id` | タスクをエージェントに割当 |

### コンテキスト・ハンドオフ

| Tool | 引数 | 説明 |
|------|------|------|
| `save_context` | `task_id`, `progress?`, `findings?`, `blockers?`, `next_steps?` | コンテキスト情報保存 |
| `get_task_context` | `task_id`, `include_history?` | タスクのコンテキスト取得 |
| `create_handoff` | `task_id`, `from_agent_id`, `to_agent_id?`, `summary`, `context?`, `recommendations?` | ハンドオフ作成 |
| `accept_handoff` | `handoff_id`, `agent_id` | ハンドオフ受領確認 |
| `get_pending_handoffs` | `agent_id?` | 未処理ハンドオフ一覧 |

### 旧ツール（廃止）

以下のツールは廃止されました:

| 旧ツール | 代替 |
|---------|------|
| `get_my_profile` | `get_agent_profile(agent_id)` |
| `get_my_tasks` | `list_tasks(assignee_id=agent_id)` または `get_pending_tasks(session_token)` |
| `start_session` | `authenticate(agent_id, passkey)` |
| `end_session` | `logout(session_token)` |
| `get_my_sessions` | 廃止 |

---

## MCPサーバーが提供するResources

| Resource | 説明 |
|----------|------|
| `agent://{id}` | 指定エージェント情報 |
| `project://{id}` | プロジェクト情報 |
| `task://{id}` | タスク情報 |
| `context://{taskId}` | タスクのコンテキスト |
| `handoff://{taskId}` | 最新のハンドオフ情報 |
| `execution://{id}` | 実行ログ情報 |
| `executions://{taskId}` | タスクの実行履歴一覧 |

**廃止されたリソース:**
- `agent://me` → `agent://{id}` を使用
- `session://current` → 廃止

---

## MCPサーバーが提供するPrompts

| Prompt | 引数 | 説明 |
|--------|------|------|
| `task_start` | `task_id`, `agent_id` | タスク開始時のガイダンス（コンテキスト、過去の作業履歴） |
| `handoff_template` | `task_id`, `from_agent_id` | ハンドオフ作成テンプレート |
| `context_summary` | `task_id` | タスクのコンテキストサマリ |

**廃止されたプロンプト:**
- `session_start` → 廃止
- `session_end` → 廃止

---

## タスク実行アーキテクチャ

### Phase 4: Runner + Agent Instance アーキテクチャ

> **Phase 4 での変更**: 既存の Runner に `project_id` 対応を追加。管理単位が `(agent_id, project_id)` に拡張されました。

責務を明確に分離した設計：

- **Runner**: 起動判断のみ（タスク詳細は知らない）
- **Agent Instance**: MCPとの全やりとり、タスク実行（Claude Code等）
- **MCPサーバー**: 状態管理、認証、APIゲートウェイ

**重要**: Agent Instanceの管理単位は `(agent_id, project_id)` の組み合わせ

```
同一エージェント × 複数プロジェクト → 別々のAgent Instance

Project A (working_dir: /proj_a)
└── Agent X のタスク
    → Agent Instance 1 (agent=X, project=A, cwd=/proj_a)

Project B (working_dir: /proj_b)
└── Agent X のタスク
    → Agent Instance 2 (agent=X, project=B, cwd=/proj_b)
```

```
┌─────────────────────────────────────────────────────────────────────┐
│                            Runner                                    │
│                                                                      │
│  責務:                                                               │
│  - MCPサーバーの起動確認（ヘルスチェック）                             │
│  - アクティブプロジェクトと割り当てエージェントの取得                    │
│  - 各(agent_id, project_id)の起動判断                                │
│  - Agent Instanceプロセスの起動（working_directory指定）              │
│                                                                      │
│  知らないこと:                                                        │
│  - タスクの内容、ステータス                                           │
│  - MCPの内部構造                                                      │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               │ 1. health_check()
                               │ 2. list_active_projects_with_agents()
                               │ 3. should_start(agent_id, project_id) × N
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          MCP Server                                  │
│                                                                      │
│  Runner向けAPI:                                                      │
│  - health_check() → { status }                                      │
│  - list_active_projects_with_agents()                               │
│      → { projects: [{project_id, working_directory, agents}, ...] } │
│  - should_start(agent_id, project_id) → { should_start, ai_type }   │
│                                                                      │
│  Agent Instance向けAPI:                                              │
│  - authenticate(agent_id, passkey, project_id)                      │
│      → {token, system_prompt, instruction}                          │
│  - get_my_task(token) → task details                                │
│  - report_completed(token, result)                                  │
└─────────────────────────────────────────────────────────────────────┘
                               ▲
                               │ 認証後、直接やりとり
                               │
┌──────────────────────────────┴──────────────────────────────────────┐
│                       Agent Instance                                 │
│                      (Claude Code等)                                 │
│                                                                      │
│  1. 起動される（agent_id, passkey, project_id, working_dir）          │
│  2. authenticate(project_id含む) → system_prompt, instruction        │
│  3. instruction に従い get_my_task() を呼ぶ                          │
│  4. タスクを実行（working_directory内で）                             │
│  5. report_completed() で完了報告                                    │
│  6. 終了                                                             │
└─────────────────────────────────────────────────────────────────────┘
```

### 各コンポーネントの知識範囲

| コンポーネント | 知っている | 知らない |
|--------------|-----------|---------|
| **Runner** | MCPサーバーの状態、project一覧、各projectの割り当てagent、passkey | タスクの内容・ステータス |
| **Agent Instance** | 自分のagent_id、project_id、認証情報、タスク詳細、working_directory | 他インスタンスの情報 |
| **MCP Server** | すべて | - |

### 設計原則

1. **責務の明確な分離**: 各コンポーネントは必要最小限の情報のみを持つ
2. **カプセル化**: 内部ステータス（`in_progress`等）は外部に公開しない
3. **汎用性**: Claude Code以外のMCP対応エージェントも利用可能
4. **プロジェクト単位の実行分離**: 同一エージェントでもプロジェクトが異なれば別インスタンス

---

## 典型的なワークフロー

### タスク実行フロー（Phase 4）

```
Runner                         MCP Server                    Agent Instance
     │                              │                              │
     │  health_check()              │                              │
     │─────────────────────────────►│                              │
     │  { status: "ok" }            │                              │
     │◄─────────────────────────────│                              │
     │                              │                              │
     │  list_active_projects_with_agents()                         │
     │─────────────────────────────►│                              │
     │  { projects: [               │                              │
     │      {prj_a, [agt_x, agt_y]},│                              │
     │      {prj_b, [agt_x]}        │                              │
     │  ]}                          │                              │
     │◄─────────────────────────────│                              │
     │                              │                              │
     │  should_start(agt_x, prj_a)  │                              │
     │─────────────────────────────►│                              │
     │  { should_start: true,       │                              │
     │    ai_type: "claude" }       │                              │
     │◄─────────────────────────────│                              │
     │                              │                              │
     │  spawn(agt_x, prj_a, /proj_a)│                              │
     │──────────────────────────────────────────────────────────────►
     │                              │                              │
     │                              │ authenticate(agt_x,key,prj_a)│
     │                              │◄─────────────────────────────│
     │                              │                              │
     │                              │ [session(agt_x,prj_a) ON]    │
     │                              │                              │
     │                              │ {token, system_prompt,       │
     │                              │  instruction}                │
     │                              │─────────────────────────────►│
     │                              │                              │
     │  should_start(agt_x, prj_a)  │                              │
     │─────────────────────────────►│                              │
     │  { should_start: false }     │  ← (agt_x,prj_a)実行中       │
     │◄─────────────────────────────│                              │
     │                              │                              │
     │  should_start(agt_x, prj_b)  │                              │
     │─────────────────────────────►│                              │
     │  { should_start: true }      │  ← (agt_x,prj_b)は別なのでOK │
     │◄─────────────────────────────│                              │
     │                              │                              │
     │                              │  get_my_task(token)          │
     │                              │◄─────────────────────────────│
     │                              │                              │
     │                              │  { task details }            │
     │                              │─────────────────────────────►│
     │                              │                              │
     │                              │    [タスク実行 at /proj_a]    │
     │                              │                              │
     │                              │  report_completed(token)     │
     │                              │◄─────────────────────────────│
     │                              │                              │
     │                              │ [session(agt_x,prj_a) OFF]   │
     │                              │                              │
     │                              │  { success, instruction }    │
     │                              │─────────────────────────────►│
     │                              │                              │
     │                              │         [プロセス終了]        │
```

### ハンドオフフロー

```
┌─────────────────────────────────────────────────────────────┐
│  Agent A の Runner: 作業完了、引き継ぎが必要                 │
│      ↓                                                      │
│  LLM が create_handoff(                                     │
│      task_id="task_123",                                    │
│      from_agent_id="agt_A",                                 │
│      to_agent_id="agt_B",                                   │
│      summary="認証機能実装完了。UIテストが必要"              │
│  ) を呼び出し                                                │
│      ↓                                                      │
│  Agent B の Runner: 次回ポーリング時にタスクを検知           │
│      ↓                                                      │
│  LLM が get_pending_handoffs(agent_id="agt_B") で確認       │
│      ↓                                                      │
│  accept_handoff(handoff_id="...", agent_id="agt_B")         │
│      ↓                                                      │
│  作業継続...                                                │
└─────────────────────────────────────────────────────────────┘
```

---

## エージェントが知るべき情報

キック時のプロンプトで提供される情報:

| 情報 | 提供方法 | 用途 |
|------|----------|------|
| 自分のAgent ID | プロンプト内 | ツール呼び出し時に使用 |
| 自分のAgent Name | プロンプト内 | 自己識別 |
| Task ID | プロンプト内 | ツール呼び出し時に使用 |
| Project ID | プロンプト内 | ツール呼び出し時に使用 |
| タスク詳細 | プロンプト内 | 作業内容の理解 |

MCPツールで追加取得可能な情報:

| 情報 | 取得方法 | 用途 |
|------|----------|------|
| 自分のプロフィール詳細 | `get_agent_profile(agent_id)` | 役割・専門分野を確認 |
| 他のエージェント一覧 | `list_agents()` | 誰に引き継げるか把握 |
| 自分へのハンドオフ | `get_pending_handoffs(agent_id)` | 引き継ぎ事項を確認 |
| タスクのコンテキスト | `get_task_context(task_id)` | 過去の作業履歴を確認 |

---

## コンテキスト共有

```swift
Context {
    progress: String?       // 現在の進捗状況
    findings: String?       // 発見事項
    blockers: String?       // 障害・ブロッカー
    nextSteps: String?      // 次のステップ
}
```

---

## ハンドオフ（引き継ぎ）

```swift
Handoff {
    taskId: TaskID
    fromAgentId: AgentID      // 引数で渡す（旧: サーバー内部で保持）
    toAgentId: AgentID?       // nil = 次の担当者未定
    summary: String           // 作業サマリ
    context: String?          // コンテキスト情報
    recommendations: String?  // 推奨事項
    acceptedAt: Date?         // 受領日時
}
```

---

## Claude Code設定

### claude_desktop_config.json

```json
{
  "mcpServers": {
    "agent-pm": {
      "command": "/usr/local/bin/mcp-server-pm",
      "args": [
        "--db", "$HOME/Library/Application Support/AIAgentPM/pm.db"
      ]
    }
  }
}
```

**重要**: `--agent-id` や `--project-id` は不要。これらはキック時のプロンプトで提供され、ツール呼び出し時に引数として渡される。

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | PRD.mdから分離して初版作成 |
| 2025-01-04 | 2.0.0 | ステートレス設計に変更。agent-id/project-idを起動引数から削除し、各ツール呼び出し時に引数で渡す設計に変更 |
| 2025-01-06 | 3.0.0 | プル型アーキテクチャに変更。認証ツール（authenticate, logout, get_pending_tasks）を追加。アプリからのキック処理を廃止し、外部Runner経由でのタスク実行に変更 |
| 2025-01-06 | 3.1.0 | 実行ログ管理ツールを追加（report_execution_start, report_execution_complete, list_execution_logs, get_execution_log）。execution://リソースを追加 |
| 2025-01-06 | 4.0.0 | Runner + Agent Instance アーキテクチャに変更。Runner に project_id 対応追加。should_start、get_my_task、report_completed APIを追加。authenticateにinstruction追加。旧API（get_pending_tasks, report_execution_start, report_execution_complete）を非推奨化。責務の明確な分離と内部ステータスのカプセル化を実現 |
| 2026-01-07 | 4.1.0 | Phase 4完全対応。(agent_id, project_id)単位の管理に変更。`list_managed_agents`→`list_active_projects_with_agents`、`should_start(agent_id)`→`should_start(agent_id, project_id)`、`authenticate`にproject_id追加。プロジェクトへのエージェント割り当て前提の設計に統一 |
