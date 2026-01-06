# Phase 4: Coordinator + Agent アーキテクチャ

Phase 3のRunner実装を発展させ、責務をより明確に分離したアーキテクチャ。

---

## 概要

### 設計原則

1. **責務の明確な分離**: 各コンポーネントは必要最小限の情報のみを持つ
2. **カプセル化**: 内部ステータス（`in_progress`等）は外部に公開しない
3. **汎用性**: Claude Code以外のMCP対応エージェントも利用可能

### 変更の背景

Phase 3では、Runnerが以下の責務を持っていた：
- ポーリング
- タスク詳細の把握
- CLI実行
- 結果報告

これを以下のように分離する：
- **Coordinator**: 起動判断のみ（タスク詳細は知らない）
- **Agent**: MCPとの全やりとり、タスク実行

```
Phase 3: Runner がすべてを管理
Phase 4: Coordinator（起動判断）+ Agent（実行）に分離
```

---

## アーキテクチャ

### 全体構成

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Coordinator                                  │
│                                                                      │
│  責務:                                                               │
│  - MCPサーバーの起動確認（ヘルスチェック）                             │
│  - 管理対象エージェント一覧の取得                                      │
│  - 各エージェントの起動判断（should_start の呼び出し）                  │
│  - エージェントプロセスの起動                                          │
│                                                                      │
│  知らないこと:                                                        │
│  - タスクの内容、ステータス、プロジェクト                               │
│  - MCPの内部構造                                                      │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               │ 1. health_check()
                               │ 2. list_managed_agents()
                               │ 3. should_start(agent_id) × N
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          MCP Server                                  │
│                                                                      │
│  Coordinator向けAPI:                                                 │
│  - health_check() → { status }                                      │
│  - list_managed_agents() → { agents: [agent_id, ...] }              │
│  - should_start(agent_id) → { should_start: bool }                  │
│                                                                      │
│  Agent向けAPI:                                                       │
│  - authenticate(agent_id, passkey) → {token, instruction}           │
│  - get_my_task(token) → task details                                │
│  - report_completed(token, result)                                  │
└─────────────────────────────────────────────────────────────────────┘
                               ▲
                               │ 認証後、直接やりとり
                               │
┌──────────────────────────────┴──────────────────────────────────────┐
│                            Agent                                     │
│                      (Claude Code等)                                 │
│                                                                      │
│  1. 起動される（agent_id, passkeyを受け取る）                          │
│  2. authenticate() → instruction を受け取る                          │
│  3. instruction に従い get_my_task() を呼ぶ                          │
│  4. タスクを実行                                                      │
│  5. report_completed() で完了報告                                    │
│  6. 終了                                                             │
└─────────────────────────────────────────────────────────────────────┘
```

### 各コンポーネントの知識範囲

| コンポーネント | 知っている | 知らない |
|--------------|-----------|---------|
| **Coordinator** | MCPサーバーの状態、agent_id一覧（動的取得）、passkey、起動コマンド | タスク、ステータス、プロジェクト |
| **Agent** | 自分のagent_id、認証情報、タスク詳細 | 他エージェントの情報、システム全体 |
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

#### list_managed_agents

Coordinatorが管理すべきエージェントの一覧を取得する。詳細情報は返さず、agent_idのみ。

```python
list_managed_agents() → {
    "success": true,
    "agents": [
        { "agent_id": "agt_frontend" },
        { "agent_id": "agt_backend" },
        { "agent_id": "agt_infra" }
    ]
}
```

**実装ロジック（内部）**:
- `active` 状態のエージェントのみ返す
- passkey、role、typeなどの詳細は返さない（Coordinatorは知る必要がない）

**重要**: Coordinatorは設定ファイルでpasskeyと起動コマンドを持つが、「どのエージェントを監視するか」はMCPサーバーから動的に取得する。

#### should_start

エージェントを起動すべきかどうかを返す。内部の詳細（タスクステータス等）は隠蔽。

```python
should_start(
    agent_id: str
) → {
    "should_start": true | false,
    "ai_type": "claude"  # should_start が true の場合のみ
}
```

**実装ロジック（内部）**:
- `in_progress` 状態のタスクがあり、かつ実行中でない → `true` + `ai_type`
- それ以外 → `false`

**重要**:
- タスク情報は含めない（Coordinatorはタスクの存在を知る必要がない）
- `ai_type` はアプリDBから取得し、Coordinatorが適切なCLIを選択するために使用

### Agent向けAPI

#### authenticate（拡張）

認証後、エージェントの役割（system_prompt）と次に何をすべきかの instruction を返す。

```python
authenticate(
    agent_id: str,
    passkey: str
) → {
    "success": true,
    "session_token": "sess_xxxxx",
    "expires_in": 3600,
    "agent_name": "frontend-dev",
    "system_prompt": "あなたはフロントエンド開発者です...",  # DBから取得
    "instruction": "get_my_task を呼び出してタスク詳細を取得してください"
}

# 認証失敗時
{
    "success": false,
    "error": "Invalid agent_id or passkey"
}
```

**ポイント**: `system_prompt` はアプリ側（DB）で管理され、認証時にエージェントに渡される。これにより:
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

# エージェント設定
# 注意: 監視対象の一覧は list_managed_agents で動的取得
# ai_type, system_prompt はアプリ側（DB）で管理
agents:
  agt_developer:
    passkey: ${DEV_PASSKEY}
    working_directory: /projects/myapp

  agt_reviewer:
    passkey: ${REVIEWER_PASSKEY}
    working_directory: /projects/myapp
```

**設定項目**:

| セクション | 項目 | 説明 |
|-----------|------|------|
| `ai_providers` | `cli_command` | AIプロバイダーのCLIコマンド |
| `ai_providers` | `cli_args` | CLI引数 |
| `agents` | `passkey` | 認証用パスキー（必須） |
| `agents` | `working_directory` | 作業ディレクトリ（オプション） |

**ポイント**: `ai_type` と `system_prompt` はアプリ側で管理（Single Source of Truth）

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

            # Step 2: 管理対象エージェント一覧を取得
            try:
                result = await self.mcp_client.list_managed_agents()
                managed_agents = result.agents
            except MCPError as e:
                logger.error(f"Failed to get agent list: {e}")
                await asyncio.sleep(self.polling_interval)
                continue

            # Step 3: 各エージェントの起動判断
            for agent_info in managed_agents:
                agent_id = agent_info.agent_id

                # 設定ファイルに起動設定がないエージェントはスキップ
                if agent_id not in self.agents:
                    logger.debug(f"No config for {agent_id}, skipping")
                    continue

                # 起動すべきか確認
                try:
                    result = await self.mcp_client.should_start(agent_id)
                    if result.should_start:
                        self.spawn_agent(agent_id, result.ai_type)
                except MCPError as e:
                    logger.error(f"Failed to check {agent_id}: {e}")

            await asyncio.sleep(self.polling_interval)

    def spawn_agent(self, agent_id: str, ai_type: str):
        """エージェントプロセスを起動"""
        agent_config = self.agents[agent_id]

        # ai_type から起動方法を取得
        provider = self.ai_providers.get(ai_type, self.ai_providers["claude"])
        cli_command = provider["cli_command"]
        cli_args = provider.get("cli_args", [])
        working_dir = agent_config.get("working_directory")

        # 認証情報 + 手順のみ（system_prompt は authenticate で取得）
        prompt = f"""
Agent ID: {agent_id}
Passkey: {agent_config["passkey"]}

手順:
1. authenticate(agent_id="{agent_id}", passkey="{agent_config["passkey"]}") で認証
2. 返された system_prompt があなたの役割です。その役割に従って行動してください
3. get_my_task() でタスク取得
4. タスク実行
5. report_completed() で完了報告
"""
        subprocess.Popen(
            [cli_command, *cli_args, "-p", prompt],
            cwd=working_dir
        )
        logger.info(f"Spawned agent {agent_id} with {ai_type}")
```

---

## 冪等性と実行状態管理

### 設計原則

Coordinatorの重複起動を防ぐため、**MCPサーバー側で実行状態を管理**する。

```
実行状態の遷移:

  idle ──[authenticate成功]──► running ──[report_completed]──► idle
                                  │
                                  └──[セッション期限切れ/タイムアウト]──► idle
```

### メリット

- **Single Source of Truth**: 状態管理がMCPサーバーに集約
- **Coordinatorがステートレス**: 「起動済み」リストを持つ必要がない
- **複数Coordinator対応**: Coordinatorが複数インスタンスあっても競合しない
- **クラッシュリカバリー**: セッションタイムアウトで自動復旧

### should_start の実装ロジック

```python
def should_start(agent_id: str) -> bool:
    agent = get_agent(agent_id)

    # 1. エージェントが存在しない → false
    if not agent:
        return False

    # 2. 既に実行中（セッションがアクティブ）→ false
    if agent.has_active_session():
        return False

    # 3. in_progress タスクがあるか確認
    has_task = has_in_progress_task_for_agent(agent_id)

    return has_task
```

### authenticate での状態遷移

```python
def authenticate(agent_id: str, passkey: str) -> AuthResult:
    agent = get_agent(agent_id)

    # 認証チェック
    if not agent or agent.passkey != passkey:
        return AuthResult(success=False, error="Invalid credentials")

    # 既に実行中の場合はエラー（二重起動防止）
    if agent.has_active_session():
        return AuthResult(success=False, error="Agent already running")

    # セッション作成 → 実行中状態に遷移
    session = create_session(agent_id, expires_in=3600)
    agent.set_running(session.token)  # ← ここで running フラグを立てる

    return AuthResult(
        success=True,
        session_token=session.token,
        expires_in=session.expires_in,
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
     │  │ Step 2: 一覧取得        │ │
     │  └─────────────────────────┘ │
     │                              │
     │  list_managed_agents()       │
     │─────────────────────────────►│
     │  { agents: [agt_a, agt_b] }  │
     │◄─────────────────────────────│
     │                              │
     │  ┌─────────────────────────┐ │
     │  │ Step 3: 各エージェント  │ │
     │  │         起動判断        │ │
     │  └─────────────────────────┘ │
     │                              │
     │  should_start(agt_a)         │
     │─────────────────────────────►│
     │  { should_start: false }     │  ← 実行中 or タスクなし
     │◄─────────────────────────────│
     │                              │
     │  should_start(agt_b)         │
     │─────────────────────────────►│
     │  { should_start: true }      │  ← タスクあり & 未実行
     │◄─────────────────────────────│
     │                              │
     │  [agt_b を spawn]            │
     │                              │
     │  [polling_interval 待機]     │
     │                              │
     │  [ループ継続...]             │
```

### エージェント実行フロー（正常系）

```
Coordinator                    MCP Server                    Agent (Claude Code)
     │                              │                              │
     │  should_start(agt_xxx)       │                              │
     │─────────────────────────────►│                              │
     │  { should_start: true }      │                              │
     │◄─────────────────────────────│                              │
     │                              │                              │
     │  spawn_agent(agt_xxx)        │                              │
     │──────────────────────────────────────────────────────────────►
     │                              │                              │
     │                              │  authenticate(agt_xxx, key)  │
     │                              │◄─────────────────────────────│
     │                              │                              │
     │                              │  [running フラグ ON]         │
     │                              │                              │
     │                              │  { token, instruction }      │
     │                              │─────────────────────────────►│
     │                              │                              │
     │  should_start(agt_xxx)       │                              │
     │─────────────────────────────►│                              │
     │  { should_start: false }     │  ← 実行中なので false        │
     │◄─────────────────────────────│                              │
     │                              │                              │
     │                              │  get_my_task(token)          │
     │                              │◄─────────────────────────────│
     │                              │                              │
     │                              │  { task details }            │
     │                              │─────────────────────────────►│
     │                              │                              │
     │                              │         [タスク実行]          │
     │                              │                              │
     │                              │  report_completed(token)     │
     │                              │◄─────────────────────────────│
     │                              │                              │
     │                              │  [running フラグ OFF]        │
     │                              │                              │
     │                              │  { success, instruction }    │
     │                              │─────────────────────────────►│
     │                              │                              │
     │                              │         [プロセス終了]        │
     │                              │                              │
     │  should_start(agt_xxx)       │                              │
     │─────────────────────────────►│                              │
     │  { should_start: true/false }│  ← 次のタスクがあれば true   │
     │◄─────────────────────────────│                              │
```

### 冪等性の確保

```
Coordinator A                  MCP Server                  Coordinator B
     │                              │                              │
     │  should_start(agt_xxx)       │                              │
     │─────────────────────────────►│                              │
     │  { should_start: true }      │                              │
     │◄─────────────────────────────│                              │
     │                              │                              │
     │  [spawn準備中...]            │  should_start(agt_xxx)       │
     │                              │◄─────────────────────────────│
     │                              │  { should_start: true }      │  ← まだ認証前
     │                              │─────────────────────────────►│
     │                              │                              │
     │  [Agent起動 → authenticate]  │                              │
     │                              │                              │
     │                              │  [running フラグ ON]         │
     │                              │                              │
     │                              │  [Agent起動 → authenticate]  │
     │                              │◄─────────────────────────────│
     │                              │  { error: "Already running" }│  ← 二重起動防止
     │                              │─────────────────────────────►│
     │                              │                              │
     │                              │         [Agent B 終了]       │
```

---

## 移行計画

### Phase 4-1: MCP API追加（Coordinator向け）

1. `health_check` ツールの追加 - サーバー起動確認
2. `list_managed_agents` ツールの追加 - エージェント一覧取得
3. `should_start` ツールの追加 - 起動判断（実行状態チェック含む）

### Phase 4-2: MCP API追加（Agent向け）

1. `authenticate` の拡張 - instruction フィールド追加、二重起動チェック
2. `get_my_task` ツールの追加 - 単一タスク取得
3. `report_completed` ツールの追加 - タスク完了報告、セッション終了

### Phase 4-3: 実行状態管理

1. エージェントの実行状態フラグ実装
2. セッションタイムアウト機構
3. 期限切れセッションのクリーンアップ

### Phase 4-4: Coordinator実装

1. 設定ファイル読み込み
2. 3ステップポーリングループ（health_check → list → should_start）
3. エージェント起動管理
4. 同時実行数制御

### Phase 4-5: 既存Runnerの非推奨化

1. Runner を Coordinator + Agent パターンに置き換え
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
| `get_pending_tasks` | `get_my_task` | 単一タスクに簡略化 |
| `report_execution_start` | 不要 | `get_my_task` 呼び出し時に自動記録 |
| `report_execution_complete` | `report_completed` | 簡略化 |

### 移行期間

- Phase 4完了後、旧APIは6ヶ月間維持
- 非推奨警告をログ出力
- 新APIへの移行ガイドを提供
