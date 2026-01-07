# Phase 4: Coordinator + Agent アーキテクチャ

Phase 3のRunner実装を発展させ、責務をより明確に分離したアーキテクチャ。

---

> **⚠️ 重要: このドキュメントについて**
>
> このドキュメントは**将来のリファクタリング計画**です。
>
> | 項目 | 説明 |
> |-----|------|
> | **現在の実装** | `runner/` ディレクトリのRunnerがオーケストレーター（Coordinator）として動作中 |
> | **Phase 4の目的** | Runnerの責務を分離し、よりクリーンなアーキテクチャへリファクタリング |
> | **Coordinatorとは** | 新しいコンポーネントではなく、Runnerの役割の一部を指す呼称 |
>
> **現在のアーキテクチャ（Phase 3）**を理解するには `PHASE3_PULL_ARCHITECTURE.md` を参照してください。

---

## 概要

### 設計原則

1. **責務の明確な分離**: 各コンポーネントは必要最小限の情報のみを持つ
2. **カプセル化**: 内部ステータス（`in_progress`等）は外部に公開しない
3. **汎用性**: Claude Code以外のMCP対応エージェントも利用可能
4. **プロジェクト単位の実行分離**: 同一エージェントでもプロジェクトが異なれば別インスタンス

### 変更の背景

Phase 3では、Runnerが以下の責務を持っていた：
- ポーリング
- タスク詳細の把握
- CLI実行
- 結果報告

これを以下のように分離する：
- **Coordinator**: 起動判断のみ（タスク詳細は知らない）
- **Agent Instance**: MCPとの全やりとり、タスク実行

```
Phase 3: Runner がすべてを管理
Phase 4: Coordinator（起動判断）+ Agent Instance（実行）に分離
```

### 用語定義

| 用語 | 説明 |
|------|------|
| **Coordinator** | Agent Instanceを管理するオーケストレーター（デーモン） |
| **Agent Instance** | 特定の(agent_id, project_id)に紐づく実行プロセス |
| **Agent** | アプリ側で定義されるエージェント定義（system_prompt, ai_type等） |
| **Project** | 作業対象のプロジェクト（working_directory を持つ） |

### 管理単位

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

これにより：
- プロジェクト間の作業が干渉しない
- 各インスタンスは適切なworking_directoryで動作
- 並列実行が可能

---

## アーキテクチャ

### 全体構成

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Coordinator                                  │
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
│  Coordinator向けAPI:                                                 │
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
| **Coordinator** | MCPサーバーの状態、project一覧、各projectの割り当てagent、passkey | タスクの内容・ステータス |
| **Agent Instance** | 自分のagent_id、project_id、認証情報、タスク詳細、working_directory | 他インスタンスの情報 |
| **MCP Server** | すべて | - |

---

## MCP API設計

### Coordinator向けAPI

#### health_check

MCPサーバーの起動状態を確認する。Coordinatorはまずこれを呼び出してサーバーが利用可能か確認する。

```python
health_check() → {
    "status": "ok",
    "version": "1.0.0",
    "timestamp": "2025-01-06T10:00:00Z"
}

# サーバー異常時（接続エラー等）
# → 接続自体が失敗するため、Coordinatorはリトライまたはスキップ
```

**用途**:
- サーバー起動確認
- 接続テスト
- バージョン確認（将来の互換性チェック用）

#### list_active_projects_with_agents

アクティブなプロジェクト一覧と、各プロジェクトに割り当てられたエージェントを取得する。

```python
list_active_projects_with_agents() → {
    "success": true,
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
- Coordinatorは各 (agent_id, project_id) の組み合わせを個別に管理

#### should_start

特定の(agent_id, project_id)の組み合わせでAgent Instanceを起動すべきかを返す。

```python
should_start(
    agent_id: str,
    project_id: str
) → {
    "should_start": true | false,
    "ai_type": "claude"  # should_start が true の場合のみ
}
```

**実装ロジック（内部）**:
- 該当プロジェクトで該当エージェントにアサインされた `in_progress` タスクがある
- かつ、該当 (agent_id, project_id) のAgent Instanceが実行中でない
- → `true` + `ai_type`
- それ以外 → `false`

**重要**:
- タスク情報は含めない（Coordinatorはタスクの存在を知る必要がない）
- `ai_type` はエージェント定義から取得し、Coordinatorが適切なCLIを選択するために使用
- 実行状態は (agent_id, project_id) 単位で管理

### Agent Instance向けAPI

#### authenticate（拡張）

認証後、エージェントの役割（system_prompt）と次に何をすべきかの instruction を返す。
project_idを含めることで、セッションが特定の(agent_id, project_id)に紐づく。

```python
authenticate(
    agent_id: str,
    passkey: str,
    project_id: str
) → {
    "success": true,
    "session_token": "sess_xxxxx",
    "expires_in": 3600,
    "agent_name": "frontend-dev",
    "project_name": "Frontend App",
    "system_prompt": "あなたはフロントエンド開発者です...",  # DBから取得
    "instruction": "get_my_task を呼び出してタスク詳細を取得してください"
}

# 認証失敗時
{
    "success": false,
    "error": "Invalid agent_id or passkey"
}

# 既に実行中の場合
{
    "success": false,
    "error": "Agent instance already running for this project"
}
```

**ポイント**:
- `system_prompt` はアプリ側（DB）で管理され、認証時にエージェントに渡される
- `project_id` によりセッションがプロジェクトに紐づく
- 同一 (agent_id, project_id) の二重起動を防止
- Coordinatorは認証情報のみ保持（シンプル化）
- エージェントの役割変更がアプリUIで完結
- Single Source of Truth

#### get_my_task

認証済みエージェントの現在のタスクを取得。

```python
get_my_task(
    session_token: str
) → {
    "success": true,
    "has_task": true,
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
    "success": true,
    "has_task": false,
    "instruction": "現在割り当てられたタスクはありません"
}
```

#### report_completed

タスク完了を報告。

```python
report_completed(
    session_token: str,
    result: str,           # "success" | "failed" | "blocked"
    summary: str = None,   # 作業サマリー（オプション）
    next_steps: str = None # 次のステップ（オプション）
) → {
    "success": true,
    "instruction": "タスクが完了しました。セッションを終了します。"
}
```

---

## Coordinator実装

### 設定ファイル

```yaml
# coordinator_config.yaml

polling_interval: 10  # 秒
max_concurrent: 3     # 同時実行数
mcp_socket_path: ~/Library/Application Support/AIAgentPM/mcp.sock

# AIプロバイダーごとの起動方法
ai_providers:
  claude:
    cli_command: claude
    cli_args: ["--dangerously-skip-permissions"]
  gemini:
    cli_command: gemini-cli
    cli_args: ["--project", "my-project"]
  codex:
    cli_command: codex
    cli_args: []

# エージェント認証情報
# 注意:
# - 監視対象のプロジェクト・エージェントは list_active_projects_with_agents で動的取得
# - ai_type, system_prompt はアプリ側（DB）で管理
# - working_directory はプロジェクトから取得（ここでは指定しない）
agents:
  agt_developer:
    passkey: ${DEV_PASSKEY}

  agt_reviewer:
    passkey: ${REVIEWER_PASSKEY}

  agt_infra:
    passkey: ${INFRA_PASSKEY}
```

**設定項目**:

| セクション | 項目 | 説明 |
|-----------|------|------|
| `ai_providers` | `cli_command` | AIプロバイダーのCLIコマンド |
| `ai_providers` | `cli_args` | CLI引数 |
| `agents` | `passkey` | 認証用パスキー（必須） |

**ポイント**:
- `ai_type` と `system_prompt` はアプリ側で管理（Single Source of Truth）
- `working_directory` はプロジェクトから取得（Coordinator設定には含めない）
- 同一エージェントが複数プロジェクトで使われても、passkey設定は1つでOK

### ポーリングループ

```python
class Coordinator:
    async def run(self):
        while self.running:
            # Step 1: MCPサーバー起動確認
            try:
                health = await self.mcp_client.health_check()
                if health.status != "ok":
                    logger.warning("MCP server unhealthy, skipping cycle")
                    await asyncio.sleep(self.polling_interval)
                    continue
            except ConnectionError:
                logger.error("MCP server not available, retrying...")
                await asyncio.sleep(self.polling_interval)
                continue

            # Step 2: アクティブプロジェクトと割り当てエージェント一覧を取得
            try:
                result = await self.mcp_client.list_active_projects_with_agents()
                projects = result.projects
            except MCPError as e:
                logger.error(f"Failed to get project list: {e}")
                await asyncio.sleep(self.polling_interval)
                continue

            # Step 3: 各 (project, agent) の組み合わせで起動判断
            for project in projects:
                project_id = project.project_id
                working_dir = project.working_directory

                for agent_id in project.agents:
                    # 設定ファイルにpasskey設定がないエージェントはスキップ
                    if agent_id not in self.agents:
                        logger.debug(f"No passkey config for {agent_id}, skipping")
                        continue

                    # 起動すべきか確認
                    try:
                        result = await self.mcp_client.should_start(agent_id, project_id)
                        if result.should_start:
                            self.spawn_agent_instance(
                                agent_id=agent_id,
                                project_id=project_id,
                                working_dir=working_dir,
                                ai_type=result.ai_type
                            )
                    except MCPError as e:
                        logger.error(f"Failed to check {agent_id}/{project_id}: {e}")

            await asyncio.sleep(self.polling_interval)

    def spawn_agent_instance(
        self,
        agent_id: str,
        project_id: str,
        working_dir: str,
        ai_type: str
    ):
        """Agent Instanceプロセスを起動

        起動時に渡す情報:
        - agent_id: エージェント識別子
        - project_id: プロジェクト識別子
        - passkey: 認証用パスキー
        - working_directory: 作業ディレクトリ（cwd として設定）
        """
        agent_config = self.agents[agent_id]
        passkey = agent_config["passkey"]

        # ai_type から起動方法を取得
        provider = self.ai_providers.get(ai_type, self.ai_providers["claude"])
        cli_command = provider["cli_command"]
        cli_args = provider.get("cli_args", [])

        # 起動時に渡す情報（環境変数として設定）
        env = os.environ.copy()
        env["AGENT_ID"] = agent_id
        env["PROJECT_ID"] = project_id
        env["AGENT_PASSKEY"] = passkey
        env["WORKING_DIRECTORY"] = working_dir

        # 認証情報 + 手順（system_prompt は authenticate で取得）
        prompt = f"""
Agent ID: {agent_id}
Project ID: {project_id}
Passkey: {passkey}

手順:
1. authenticate(agent_id="{agent_id}", passkey="{passkey}", project_id="{project_id}") で認証
2. 返された system_prompt があなたの役割です。その役割に従って行動してください
3. get_my_task() でタスク取得
4. タスク実行（カレントディレクトリ: {working_dir}）
5. report_completed() で完了報告
"""
        subprocess.Popen(
            [cli_command, *cli_args, "-p", prompt],
            cwd=working_dir,  # プロジェクトのworking_directoryで起動
            env=env           # 環境変数でも情報を渡す
        )
        logger.info(f"Spawned agent instance {agent_id}/{project_id} with {ai_type} at {working_dir}")
```

---

## 冪等性と実行状態管理

### 設計原則

Coordinatorの重複起動を防ぐため、**MCPサーバー側で実行状態を管理**する。
実行状態は **(agent_id, project_id) 単位**で管理される。

```
実行状態の遷移（agent_id, project_id 単位）:

  idle ──[authenticate成功]──► running ──[report_completed]──► idle
                                  │
                                  └──[セッション期限切れ/タイムアウト]──► idle
```

### メリット

- **Single Source of Truth**: 状態管理がMCPサーバーに集約
- **Coordinatorがステートレス**: 「起動済み」リストを持つ必要がない
- **複数Coordinator対応**: Coordinatorが複数インスタンスあっても競合しない
- **クラッシュリカバリー**: セッションタイムアウトで自動復旧
- **プロジェクト分離**: 同一エージェントでも異なるプロジェクトは独立して実行可能

### should_start の実装ロジック

```python
def should_start(agent_id: str, project_id: str) -> ShouldStartResult:
    agent = get_agent(agent_id)
    project = get_project(project_id)

    # 1. エージェントまたはプロジェクトが存在しない → false
    if not agent or not project:
        return ShouldStartResult(should_start=False)

    # 2. 該当 (agent_id, project_id) で既に実行中 → false
    if has_active_session(agent_id, project_id):
        return ShouldStartResult(should_start=False)

    # 3. 該当プロジェクトで該当エージェントにアサインされた in_progress タスクがあるか
    has_task = has_in_progress_task(agent_id, project_id)

    if has_task:
        return ShouldStartResult(should_start=True, ai_type=agent.ai_type)
    else:
        return ShouldStartResult(should_start=False)
```

### authenticate での状態遷移

```python
def authenticate(agent_id: str, passkey: str, project_id: str) -> AuthResult:
    agent = get_agent(agent_id)
    project = get_project(project_id)

    # 認証チェック
    if not agent or agent.passkey != passkey:
        return AuthResult(success=False, error="Invalid credentials")

    if not project:
        return AuthResult(success=False, error="Project not found")

    # 該当 (agent_id, project_id) で既に実行中の場合はエラー（二重起動防止）
    if has_active_session(agent_id, project_id):
        return AuthResult(success=False, error="Agent instance already running for this project")

    # セッション作成 → 実行中状態に遷移
    session = create_session(agent_id, project_id, expires_in=3600)

    return AuthResult(
        success=True,
        session_token=session.token,
        expires_in=session.expires_in,
        agent_name=agent.name,
        project_name=project.name,
        system_prompt=agent.system_prompt,
        instruction="get_my_task を呼び出してタスク詳細を取得してください"
    )
```

### リカバリーメカニズム

| シナリオ | リカバリー方法 |
|---------|--------------|
| 正常終了 | `report_completed()` で明示的にセッション終了 |
| エージェントクラッシュ | セッションタイムアウト（デフォルト: 1時間）で自動クリア |
| ネットワーク断 | セッションタイムアウトで自動クリア |
| 手動介入 | 管理者がUIからセッションを強制終了 |

### タイムアウト設定

```yaml
session:
  default_timeout: 3600      # 1時間
  max_timeout: 86400         # 24時間（長時間タスク用）
  cleanup_interval: 300      # 5分ごとに期限切れセッションをクリーンアップ
```

---

## フロー図

### Coordinatorポーリングフロー

```
Coordinator                    MCP Server
     │                              │
     │  ┌─────────────────────────┐ │
     │  │ Step 1: 起動確認        │ │
     │  └─────────────────────────┘ │
     │                              │
     │  health_check()              │
     │─────────────────────────────►│
     │  { status: "ok" }            │
     │◄─────────────────────────────│
     │                              │
     │  ┌─────────────────────────┐ │
     │  │ Step 2: プロジェクト    │ │
     │  │         +エージェント   │ │
     │  │         一覧取得        │ │
     │  └─────────────────────────┘ │
     │                              │
     │  list_active_projects_with_agents()
     │─────────────────────────────►│
     │  { projects: [               │
     │      {prj_a, [agt_x, agt_y]},│
     │      {prj_b, [agt_x]}        │
     │  ]}                          │
     │◄─────────────────────────────│
     │                              │
     │  ┌─────────────────────────┐ │
     │  │ Step 3: 各(agent,proj)  │ │
     │  │         起動判断        │ │
     │  └─────────────────────────┘ │
     │                              │
     │  should_start(agt_x, prj_a)  │
     │─────────────────────────────►│
     │  { should_start: false }     │  ← 実行中 or タスクなし
     │◄─────────────────────────────│
     │                              │
     │  should_start(agt_y, prj_a)  │
     │─────────────────────────────►│
     │  { should_start: true }      │  ← タスクあり & 未実行
     │◄─────────────────────────────│
     │                              │
     │  [agt_y/prj_a を spawn]      │
     │  [working_dir=/proj_a]       │
     │                              │
     │  should_start(agt_x, prj_b)  │
     │─────────────────────────────►│
     │  { should_start: true }      │  ← 別プロジェクトなので独立判定
     │◄─────────────────────────────│
     │                              │
     │  [agt_x/prj_b を spawn]      │
     │  [working_dir=/proj_b]       │
     │                              │
     │  [polling_interval 待機]     │
     │                              │
     │  [ループ継続...]             │
```

### Agent Instance実行フロー（正常系）

```
Coordinator                    MCP Server                    Agent Instance
     │                              │                              │
     │  should_start(agt_x, prj_a)  │                              │
     │─────────────────────────────►│                              │
     │  { should_start: true }      │                              │
     │◄─────────────────────────────│                              │
     │                              │                              │
     │  spawn(agt_x, prj_a, /proj_a)│                              │
     │──────────────────────────────────────────────────────────────►
     │                              │                              │
     │                              │  authenticate(agt_x,key,prj_a)
     │                              │◄─────────────────────────────│
     │                              │                              │
     │                              │  [session(agt_x,prj_a) ON]   │
     │                              │                              │
     │                              │  { token, system_prompt }    │
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
     │                              │  [session(agt_x,prj_a) OFF]  │
     │                              │                              │
     │                              │  { success, instruction }    │
     │                              │─────────────────────────────►│
     │                              │                              │
     │                              │         [プロセス終了]        │
     │                              │                              │
     │  should_start(agt_x, prj_a)  │                              │
     │─────────────────────────────►│                              │
     │  { should_start: true/false }│  ← 次のタスクがあれば true   │
     │◄─────────────────────────────│                              │
```

### 冪等性の確保

```
Coordinator A                  MCP Server                  Coordinator B
     │                              │                              │
     │  should_start(agt_x, prj_a)  │                              │
     │─────────────────────────────►│                              │
     │  { should_start: true }      │                              │
     │◄─────────────────────────────│                              │
     │                              │                              │
     │  [spawn準備中...]            │  should_start(agt_x, prj_a)  │
     │                              │◄─────────────────────────────│
     │                              │  { should_start: true }      │  ← まだ認証前
     │                              │─────────────────────────────►│
     │                              │                              │
     │  [Instance起動→authenticate] │                              │
     │                              │                              │
     │                              │  [session(agt_x,prj_a) ON]   │
     │                              │                              │
     │                              │  [Instance起動→authenticate] │
     │                              │◄─────────────────────────────│
     │                              │  { error: "Already running   │  ← 二重起動防止
     │                              │    for this project" }       │
     │                              │─────────────────────────────►│
     │                              │                              │
     │                              │     [Instance B 終了]        │
```

**ポイント**: 冪等性は (agent_id, project_id) 単位で保証される。
同一エージェントでも異なるプロジェクトの起動は許可される。

---

## 移行計画

### Phase 4-0: アプリ側の前提実装

1. プロジェクトへのエージェント割り当て機能（UI + DB）
2. Project.workingDirectory の設定UI
3. プロジェクト×エージェントの関連テーブル（必要に応じて）

### Phase 4-1: MCP API追加（Coordinator向け）

1. `health_check` ツールの追加 - サーバー起動確認
2. `list_active_projects_with_agents` ツールの追加 - プロジェクト+エージェント一覧取得
3. `should_start(agent_id, project_id)` ツールの追加 - 起動判断

### Phase 4-2: MCP API追加（Agent Instance向け）

1. `authenticate(agent_id, passkey, project_id)` の拡張 - project_id追加、二重起動チェック
2. `get_my_task` ツールの追加 - 該当プロジェクトの単一タスク取得
3. `report_completed` ツールの追加 - タスク完了報告、セッション終了

### Phase 4-3: 実行状態管理

1. (agent_id, project_id) 単位の実行状態フラグ実装
2. セッションタイムアウト機構
3. 期限切れセッションのクリーンアップ

### Phase 4-4: Coordinator実装

1. 設定ファイル読み込み（passkey管理）
2. 3ステップポーリングループ（health_check → list_projects → should_start）
3. Agent Instance起動管理（working_directory指定）
4. 同時実行数制御

### Phase 4-5: 既存Runnerの非推奨化

1. Runner を Coordinator + Agent Instance パターンに置き換え
2. 旧APIの非推奨マーク
3. マイグレーションガイド作成

---

## メリット

### 責務の明確化

- **Coordinator**: 「誰を起動するか」だけに専念
- **Agent**: 「何をするか」だけに専念
- **MCP**: 状態管理、認証、APIゲートウェイ

### カスタムRunner不要

Claude Code（や他のMCP対応エージェント）がそのまま動作：
- 特別なクライアント実装が不要
- LLMが自然にMCPツールを呼び出す
- instruction で次のアクションを誘導

### カプセル化

- 内部ステータス（`in_progress`等）を外部に公開しない
- タスク管理のドメインロジックを隠蔽
- API変更の影響範囲を限定

### 拡張性

- `instruction` フィールドで動的に振る舞いを変更可能
- 新しいワークフローを追加しやすい
- エージェント種別ごとに異なる instruction を返せる

---

## 後方互換性

### 非推奨となるAPI

| 旧API | 新API | 備考 |
|-------|-------|------|
| `list_managed_agents` | `list_active_projects_with_agents` | プロジェクト単位に変更 |
| `should_start(agent_id)` | `should_start(agent_id, project_id)` | project_id追加 |
| `authenticate(agent_id, passkey)` | `authenticate(agent_id, passkey, project_id)` | project_id追加 |
| `get_pending_tasks` | `get_my_task` | 単一タスクに簡略化 |
| `report_execution_start` | 不要 | `get_my_task` 呼び出し時に自動記録 |
| `report_execution_complete` | `report_completed` | 簡略化 |

### 移行期間

- Phase 4完了後、旧APIは6ヶ月間維持
- 非推奨警告をログ出力
- 新APIへの移行ガイドを提供

### アプリ側の前提条件

新アーキテクチャを利用するには、以下のアプリ側実装が必要：

1. **プロジェクトへのエージェント割り当て**: どのエージェントがどのプロジェクトで作業可能かを設定
2. **Project.workingDirectory**: 各プロジェクトの作業ディレクトリを設定
3. **タスクのプロジェクト所属**: タスクは必ずプロジェクトに紐づく（既存）
