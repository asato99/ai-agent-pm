# エージェント (Agent) 仕様

## 定義
アプリ内で権限や役割を割り当てられる存在。
AI（Claude Code, Gemini等）や人間を区別なく扱う抽象概念。

## 属性
| 属性 | 説明 |
|------|------|
| 名前 | エージェントの識別名 |
| 種別 (type) | AI / 人間 |
| 階層タイプ (hierarchyType) | Manager / Worker |
| 紐付け先 | AI種別（Claude, Gemini等）または人間の識別子 |
| 役割タイプ (roleType) | 担当領域（developer, reviewer, tester, architect, manager, writer, designer, analyst） |
| 役割 (role) | 自由記述の役割説明 |
| 権限 | 操作可能な範囲 |
| 並列実行可能数 | 同時に in_progress にできるタスク数 |
| 下位エージェント | Managerのみ: 管理対象のエージェントリスト |

### 属性の区別

| 属性 | 用途 | 値の例 |
|------|------|--------|
| **種別 (type)** | AIか人間かの区別 | `ai`, `human` |
| **階層タイプ (hierarchyType)** | タスク作成・割り当て権限 | `manager`, `worker` |
| **役割タイプ (roleType)** | 担当領域の分類 | `developer`, `manager`※ |

※ `roleType.manager` は「マネジメント担当」という役割分類であり、`hierarchyType.manager`（タスク作成権限）とは異なる

---

## エージェントタイプ

### Manager（マネージャー）

**役割**: タスクの作成・管理と下位エージェントへの割り当て

| 項目 | 内容 |
|------|------|
| タスク作成 | ○ 可能 |
| タスク割り当て | ○ 下位エージェントに割り当て可能 |
| タスク実行 | ✕ 自身では作業しない |
| 下位エージェント | ○ 保持可能 |

```
[Manager]
 ├─ タスク作成
 ├─ 下位エージェントへ割り当て
 └─ 進捗管理・報告受領
```

### Worker（ワーカー）

**役割**: 自身に割り当てられたタスクの実行

| 項目 | 内容 |
|------|------|
| タスク作成 | ✕ 不可（自分のタスクへのサブタスク追加は将来検討） |
| タスク割り当て | ✕ 自分自身のみ |
| タスク実行 | ○ 作業を行う |
| 下位エージェント | ✕ 保持しない |

```
[Worker]
 ├─ 割り当てられたタスクを実行
 └─ 完了/失敗を上位に報告
```

### タイプ比較

| 機能 | Manager | Worker |
|------|---------|--------|
| タスク作成 | ○ | ✕ |
| 他者への割り当て | ○ | ✕ |
| タスク実行 | ✕ | ○ |
| 下位エージェント | ○ | ✕ |

---

## エージェント間の依存関係

### 構造
- **ツリー構造**（上下関係）
- 親エージェント（上位） → 子エージェント（下位）

### 上位エージェントの責務
1. **タスクのアサイン**: 下位エージェントにタスクを割り当てる
2. **活動のキック**: 下位エージェントの作業を開始させる（トリガー）
3. **報告の受領**: 下位エージェントからの完了/失敗報告を受け取る

### 下位エージェントの責務
1. **タスクの実行**: アサインされたタスクを遂行
2. **報告**: タスクの完了または失敗を上位エージェントに報告

```
[上位エージェント]
    │
    ├── タスクアサイン ──→ [下位エージェント]
    │                           │
    ├── 活動キック ────→        │
    │                           │
    ←── 完了/失敗報告 ─────────┘
```

---

## タスク実行アーキテクチャ（Phase 4: Runner + Agent Instance）

### 概要

タスク実行は **Runner + Agent Instance** アーキテクチャで設計されています。

> **Phase 4 での変更**: 既存の Runner に `project_id` 対応を追加。管理単位が `agent_id` から `(agent_id, project_id)` に拡張されました。

- **アプリの責務**: タスクのステータス管理のみ（CLI実行は行わない）
- **Runner の責務**: MCPサーバーに問い合わせ、Agent Instance を起動
- **Agent Instance の責務**: 認証後、タスクを取得・実行し、完了報告

**重要**: Agent Instance の管理単位は `(agent_id, project_id)` の組み合わせ

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            Runner                                        │
│  - MCPサーバー起動確認 (health_check)                                    │
│  - プロジェクト+エージェント一覧取得 (list_active_projects_with_agents)   │
│  - 起動判断 (should_start(agent_id, project_id))                        │
│  - Agent Instance起動 (working_directory指定)                           │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        MCPサーバー (ステートレス)                          │
│                                                                          │
│  Runner向けAPI:                                                          │
│    - health_check() → { status }                                        │
│    - list_active_projects_with_agents() → { projects }                  │
│    - should_start(agent_id, project_id) → { should_start, ai_type }     │
│                                                                          │
│  Agent Instance向けAPI:                                                  │
│    - authenticate(agent_id, passkey, project_id) → { token, ... }       │
│    - get_my_task(token) → { task }                                      │
│    - report_completed(token, result) → { success }                      │
└──────────────────────────────┬──────────────────────────────────────────┘
                               ▲
                               │
┌──────────────────────────────┴──────────────────────────────────────────┐
│                       Agent Instance (Claude Code等)                     │
│                                                                          │
│  1. Runner起動 → 認証情報(agent_id, passkey, project_id)を受取          │
│  2. authenticate() → system_prompt, instruction を取得                  │
│  3. get_my_task() → タスク詳細を取得                                    │
│  4. タスク実行（working_directory内で）                                  │
│  5. report_completed() → 完了報告                                       │
└─────────────────────────────────────────────────────────────────────────┘
```

### 設計原則

| 原則 | 説明 |
|------|------|
| 疎結合 | アプリと Runner/Agent Instance は完全に分離 |
| 外部化 | CLI実行ロジックはアプリに含まない |
| 1 Instance = 1 (Agent, Project) | Agent Instance は (agent_id, project_id) 単位で起動 |
| MCP経由 | 通信は全て MCP ツール経由 |
| プロジェクト明示 | 全ての操作で project_id を明示 |

---

## Runner + Agent Instance アーキテクチャ

### 概要

Runner と Agent Instance はユーザーが実装・管理する外部プログラムです。
アプリはサンプル実装を提供しますが、実際の実装はユーザーに委ねられます。

> **Phase 4 での変更**: 既存の Runner に `project_id` 対応を追加（Coordinator 機能）。

### Runner の責務

| 責務 | 説明 |
|------|------|
| MCPサーバー監視 | `health_check` で死活確認 |
| プロジェクト一覧取得 | `list_active_projects_with_agents` でアクティブな (project, agent) ペア取得 |
| 起動判断 | `should_start(agent_id, project_id)` で起動要否を判断 |
| Agent Instance起動 | working_directory を指定して Agent Instance を起動 |

### Agent Instance の責務

| 責務 | 説明 |
|------|------|
| 認証 | MCP経由で agent_id + passkey + project_id を使ってセッション取得 |
| タスク取得 | `get_my_task(token)` でタスク取得 |
| タスク実行 | Claude/Gemini 等を使ってタスク実行 |
| 完了報告 | `report_completed(token, result)` で完了報告 |

### 認証フロー（Phase 4）

```
[Agent Instance起動時]
    │
    └─ authenticate(agent_id, passkey, project_id)
           │
           ▼
    [MCPサーバー]
           │
           ├─ Passkey検証（ハッシュ比較）
           ├─ project_agents テーブルで割り当て確認
           │
           └─ セッショントークン + system_prompt + instruction 発行
                   │
                   ▼
              {
                session_token: "sess_xxx",
                system_prompt: "あなたは...",
                instruction: "get_my_task を呼び出してください"
              }

[タスク取得時]
    │
    └─ get_my_task(session_token)
           │
           ├─ トークン検証（agent_id + project_id を特定）
           └─ その (agent_id, project_id) に割り当てられたタスクを返却
```

### セッション管理（Phase 4）

```swift
struct AgentSession {
    let token: String              // UUID
    let agentId: AgentID
    let projectId: ProjectID       // Phase 4 追加
    let expiresAt: Date            // 1時間後
    let createdAt: Date
}
```

- セッショントークンは1時間で期限切れ
- セッションは **(agent_id, project_id)** の組み合わせに紐づく
- 同一エージェントでもプロジェクトが異なれば別セッション

### Runner 設定

```yaml
# runner_config.yaml
mcp_db_path: "/path/to/pm.db"
polling_interval: 30  # 秒
```

### Agent Instance 起動パラメータ

```bash
# Runner から Agent Instance を起動する際のパラメータ
claude --dangerously-skip-permissions \
  -p "認証情報: agent_id=agt_xxx, passkey=secret123, project_id=prj_frontend"
  --cwd "/path/to/frontend/project"  # working_directory
```

### サンプル Runner（Python）

```python
#!/usr/bin/env python3
# sample_runner.py
"""
Phase 4 Runner: (agent_id, project_id) ペアごとに Agent Instance を管理
"""

import time
import subprocess
from typing import Dict, Set

class Runner:
    def __init__(self, mcp_client):
        self.mcp_client = mcp_client
        self.running_instances: Set[tuple] = set()  # {(agent_id, project_id), ...}

    def health_check(self) -> bool:
        result = self.mcp_client.call("health_check", {})
        return result.get("status") == "ok"

    def get_active_projects_with_agents(self):
        result = self.mcp_client.call("list_active_projects_with_agents", {})
        return result.get("projects", [])

    def should_start(self, agent_id: str, project_id: str) -> dict:
        result = self.mcp_client.call("should_start", {
            "agent_id": agent_id,
            "project_id": project_id
        })
        return result

    def start_agent_instance(self, agent_id: str, project_id: str,
                             working_directory: str, ai_type: str, passkey: str):
        """Agent Instance を起動"""
        key = (agent_id, project_id)
        if key in self.running_instances:
            return  # 既に起動中

        prompt = f"""# Agent Instance 起動

## 認証情報
- Agent ID: {agent_id}
- Project ID: {project_id}
- Passkey: {passkey}

## 指示
1. authenticate(agent_id, passkey, project_id) を呼び出してセッションを取得
2. 取得した system_prompt と instruction に従ってタスクを実行
3. 完了したら report_completed(token, result) で報告
"""
        # Claude CLI を起動
        subprocess.Popen([
            "claude", "--dangerously-skip-permissions",
            "-p", prompt
        ], cwd=working_directory)

        self.running_instances.add(key)

    def run(self):
        while True:
            if not self.health_check():
                print("MCP server not available, retrying...")
                time.sleep(10)
                continue

            projects = self.get_active_projects_with_agents()
            for project in projects:
                project_id = project["project_id"]
                working_dir = project["working_directory"]

                for agent_id in project["agents"]:
                    check = self.should_start(agent_id, project_id)
                    if check.get("should_start"):
                        passkey = self.get_passkey(agent_id)  # 安全に取得
                        self.start_agent_instance(
                            agent_id, project_id, working_dir,
                            check.get("ai_type", "claude"), passkey
                        )

            time.sleep(30)  # 30秒ごとにチェック
```

### サンプル Agent Instance 処理フロー

```python
#!/usr/bin/env python3
# agent_instance_flow.py
"""
Phase 4 Agent Instance: 認証 → タスク取得 → 実行 → 完了報告
"""

class AgentInstance:
    def __init__(self, agent_id: str, passkey: str, project_id: str, mcp_client):
        self.agent_id = agent_id
        self.passkey = passkey
        self.project_id = project_id
        self.mcp_client = mcp_client
        self.session_token = None
        self.system_prompt = None

    def authenticate(self):
        """Phase 4: project_id も含めて認証"""
        result = self.mcp_client.call("authenticate", {
            "agent_id": self.agent_id,
            "passkey": self.passkey,
            "project_id": self.project_id
        })
        if result["success"]:
            self.session_token = result["session_token"]
            self.system_prompt = result.get("system_prompt")
            return result.get("instruction")
        else:
            raise Exception("Authentication failed")

    def get_my_task(self):
        """Phase 4: get_pending_tasks → get_my_task に変更"""
        result = self.mcp_client.call("get_my_task", {
            "token": self.session_token
        })
        return result.get("task")

    def report_completed(self, result_summary: str):
        """Phase 4: report_execution_complete → report_completed に変更"""
        result = self.mcp_client.call("report_completed", {
            "token": self.session_token,
            "result": result_summary
        })
        return result.get("success")

    def execute(self):
        # 1. 認証
        instruction = self.authenticate()
        print(f"System Prompt: {self.system_prompt}")
        print(f"Instruction: {instruction}")

        # 2. タスク取得
        task = self.get_my_task()
        if not task:
            print("No task assigned")
            return

        # 3. タスク実行（ここで実際の作業を行う）
        print(f"Executing task: {task['title']}")
        # ... タスク実行ロジック ...

        # 4. 完了報告
        self.report_completed("タスク完了")
```

---

## アプリ側の設計

### アプリの責務

| やること | やらないこと |
|---------|-------------|
| エージェント作成・Passkey発行 | Runner の管理 |
| タスクのステータス管理 | CLI の実行 |
| MCP経由でタスク情報を提供 | Runner との直接通信 |

### エージェント設定画面

```
[エージェント設定]
├── 基本情報
│   ├── 名前: [________]
│   ├── 種別: [Human ▼] / [AI ▼]
│   └── 役割: [Developer ▼]
│
├── 認証設定
│   ├── エージェントID: agt_58d5015e-825（自動生成、表示のみ）
│   ├── Passkey: ●●●●●●●● [表示] [再生成]
│   └── ※ Passkey は Runner 設定に使用します
│
└── 詳細設定
    ├── 並列実行可能数: [1]
    └── ステータス: [Active ▼]
```

### データモデル

```swift
struct Agent {
    let id: AgentID
    var name: String
    var type: AgentType           // .human / .ai
    var hierarchyType: HierarchyType
    var roleType: RoleType?
    var role: String?
    var status: AgentStatus
    var maxConcurrentTasks: Int

    // 認証関連
    var passkeyHash: String?      // bcrypt でハッシュ化
}

struct AgentCredential {
    let agentId: AgentID
    let passkeyHash: String        // bcrypt
    let createdAt: Date
    let lastUsedAt: Date?
}
```

---

## MCP ツール（Phase 4: Runner / Agent Instance 向け）

### Runner 向け API

```python
# MCPサーバー死活確認
health_check() -> {
    "status": "ok"
}

# アクティブプロジェクト + 割当エージェント一覧
list_active_projects_with_agents() -> {
    "success": True,
    "projects": [
        {
            "project_id": "prj_frontend",
            "project_name": "Frontend App",
            "working_directory": "/projects/frontend",
            "agents": ["agt_developer", "agt_reviewer"]
        }
    ]
}

# 起動判断
should_start(
    agent_id: str,
    project_id: str
) -> {
    "should_start": True,
    "ai_type": "claude"
}
```

### Agent Instance 向け API

```python
# 認証（Phase 4: project_id 必須）
authenticate(
    agent_id: str,
    passkey: str,
    project_id: str
) -> {
    "success": True,
    "session_token": "sess_xxxxx",
    "expires_in": 3600,
    "agent_name": "frontend-dev",
    "project_name": "Frontend App",
    "system_prompt": "あなたはフロントエンド開発者です...",
    "instruction": "get_my_task を呼び出してタスク詳細を取得してください"
}

# 認証失敗時
{
    "success": False,
    "error": "Invalid credentials or not assigned to project"
}

# タスク取得（Phase 4: get_pending_tasks → get_my_task）
get_my_task(
    token: str
) -> {
    "success": True,
    "task": {
        "taskId": "tsk_xxx",
        "title": "機能実装",
        "description": "ログイン画面のUIを実装する",
        "priority": "high"
    }
}

# 完了報告（Phase 4: report_execution_complete → report_completed）
report_completed(
    token: str,
    result: str
) -> {
    "success": True
}

# セッション終了
logout(
    session_token: str
) -> {
    "success": True
}
```

### スコープ制限

各 Agent Instance は自分に関連する (agent_id, project_id) スコープのみ操作可能：

```python
permissions = {
    "get_my_task": "own_project_tasks_only",
    "update_task_status": "assigned_tasks_only",
    "save_context": "own_tasks_only",
    "create_handoff": "from_self_only",
    "report_completed": "own_session_only"
}
```

---

## セキュリティ

### 認証レベル

| レベル | 認証方式 | 用途 |
|--------|----------|------|
| Level 0 | agent_id のみ | 開発/テスト環境 |
| Level 1 | agent_id + passkey + session | 本番環境（推奨） |
| Level 2 | + IP制限 + 監査ログ | セキュア環境（将来） |

### セキュリティ対策

| 対策 | 説明 | 優先度 |
|------|------|--------|
| Passkey ハッシュ保存 | bcrypt/argon2 で保存 | 必須 |
| セッション有効期限 | 1時間で期限切れ | 必須 |
| レート制限 | 認証失敗5回でロック | 推奨 |
| 監査ログ | 全操作を記録 | 推奨 |
| IP制限 | localhost のみ許可 | オプション |

### 監査ログ

```json
{
  "timestamp": "2025-01-06T10:30:00Z",
  "agent_id": "agt_xxx",
  "session_token": "sess_xxx",
  "action": "get_pending_tasks",
  "ip": "127.0.0.1",
  "success": true
}
```

---

## 実行ログ管理

### 概要

タスク実行のログはアプリで管理します。
Agent Instance が MCP 経由でログファイルのパスを報告し、アプリがファイルを読み込んで表示します。

### 設計方針

| 項目 | 保存先 | 理由 |
|------|--------|------|
| メタデータ | DB | 小さい、検索可能、一覧表示用 |
| ログ内容 | ファイル | 大きい（数KB〜数MB）、DB 肥大化を防ぐ |

```
[DB]
  └─ execution_logs テーブル
      ├─ id, task_id, agent_id, project_id  ← Phase 4: project_id 追加
      ├─ started_at, completed_at
      ├─ exit_code, status
      └─ log_file_path  ← ファイルパスのみ

[ファイルシステム]
  └─ ~/Library/Application Support/AIAgentPM/logs/
      └─ prj_xxx/tsk_xxx/  ← Phase 4: project_id でグループ化
          └─ exec_20250106_103000.log  ← 実際のログ内容
```

### Agent Instance の責務（Phase 4）

```python
import os
import subprocess
from datetime import datetime

# ログディレクトリ
LOG_BASE = os.path.expanduser(
    "~/Library/Application Support/AIAgentPM/logs"
)

def execute_task(task, session_token, project_id):
    task_id = task["taskId"]

    # ログファイルパス（Phase 4: project_id でグループ化）
    log_dir = f"{LOG_BASE}/{project_id}/{task_id}"
    os.makedirs(log_dir, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = f"{log_dir}/exec_{timestamp}.log"

    # タスク実行
    start_time = datetime.now()
    with open(log_file, "w") as log:
        result = subprocess.run(
            ["claude", "--dangerously-skip-permissions", "-p", prompt],
            stdout=log,
            stderr=subprocess.STDOUT,
            cwd=task.get("workingDirectory", ".")
        )
    end_time = datetime.now()

    # 完了報告（Phase 4: report_completed）
    mcp.call("report_completed", {
        "token": session_token,
        "result": f"exit_code={result.returncode}, duration={(end_time - start_time).total_seconds()}s"
    })
```

### データモデル

```swift
struct ExecutionLog {
    let id: ExecutionLogID
    let taskId: TaskID
    let agentId: AgentID
    let projectId: ProjectID        // Phase 4 追加
    let executionId: String         // exec_xxx

    // タイムスタンプ
    var startedAt: Date
    var completedAt: Date?

    // 結果
    var exitCode: Int?
    var durationSeconds: Double?
    var status: ExecutionStatus     // running / completed / failed

    // ログファイル（内容は保存しない、パスのみ）
    var logFilePath: String?
}

enum ExecutionStatus: String, Codable {
    case running = "running"
    case completed = "completed"
    case failed = "failed"
}
```

### MCP ツール（Phase 4）

```python
# 完了報告（Phase 4: シンプル化）
report_completed(
    token: str,
    result: str  # 実行結果サマリー
) -> {
    "success": True
}

# 注: Phase 4 では report_execution_start/report_execution_complete は
# report_completed に統合され、簡略化されています
```

### アプリ UI

```
[タスク詳細画面]
├── 基本情報
├── ステータス: in_progress
│
└── 実行履歴
    ├── #1 [2025-01-06 10:30:00] 完了 (exit: 0, 5分)
    │   └── [ログを表示] ← クリックでログ内容表示
    ├── #2 [2025-01-06 11:00:00] 失敗 (exit: 1, 2分)
    │   └── [ログを表示]
    └── #3 [2025-01-06 11:30:00] 実行中...
```

### ログローテーション（将来）

| ポリシー | 設定 |
|---------|------|
| 保持期間 | 30日で自動削除 |
| 最大サイズ | タスクあたり 50MB |
| 圧縮 | 完了後 7日で gzip |

---

## 状態確認
- 上位エージェント自身がMCP経由で下位の状態を確認可能
- 下位からの能動的な報告は必須ではない

---

## エージェント認証（Phase 4）

### 目的
Agent Instance が MCPツールを呼び出す際、正しい (agent_id, project_id) として識別されることを保証する。

### Phase 4 認証フロー

Phase 4 では、**セッションベース認証**を採用。`authenticate` 時に `project_id` を含めることで、スコープを明確化。

```
[Runner起動]
  Runner が Agent Instance を起動（認証情報を渡す）
  ↓
[Agent Instance 起動]
  認証情報 (agent_id, passkey, project_id) を受け取る
  ↓
[authenticate 呼び出し]
  authenticate(agent_id, passkey, project_id)
  ↓
[MCPサーバー側で検証]
  - agent_id の存在確認
  - passkey のハッシュ比較
  - project_agents テーブルで割り当て確認
  ↓
認証成功 → session_token + system_prompt + instruction 返却
認証失敗 → エラー返却
  ↓
[タスク取得/実行]
  get_my_task(token) → タスク取得
  report_completed(token, result) → 完了報告
```

### 認証レベル

| レベル | 認証方式 | 用途 |
|--------|----------|------|
| Level 0 | agent_id + project_id のみ | 開発/テスト環境 |
| Level 1 | agent_id + passkey + project_id | 本番環境（推奨） |
| Level 2 | + IP制限 + 監査ログ | セキュア環境（将来） |

### エージェント属性（認証関連）

| 属性 | 説明 |
|------|------|
| passkey | 認証用の秘密鍵（ハッシュ保存） |
| auth_level | 認証レベル (0/1/2) |
| allowed_ips | 許可IPリスト（Level 2用、将来） |

### Phase 4 での実装

1. **Phase 4**: セッションベース認証 + project_id
   - `authenticate(agent_id, passkey, project_id)` でセッション取得
   - セッショントークンは (agent_id, project_id) に紐づく
   - `project_agents` テーブルで割り当て確認
2. **将来**: IP制限等のセキュリティ強化

### 認証後のツール呼び出し例（Phase 4）

```python
# 認証（Phase 4: project_id 必須）
result = authenticate(
  agent_id="agt_dev001",
  passkey="secret123",
  project_id="prj_frontend"
)
token = result["session_token"]

# タスク取得（トークンでスコープ制限）
task = get_my_task(token=token)

# 完了報告（トークンでスコープ制限）
report_completed(token=token, result="実装完了")

# ハンドオフ作成時（from_agent_idを検証）
create_handoff(
  task_id="task_abc123",
  from_agent_id="agt_dev001",  # セッションの agent_id と一致確認
  to_agent_id="agt_reviewer",
  summary="認証機能実装完了"
)
```

### 認証失敗時の動作
- エラーをMCPレスポンスとして返却
- エラーログに記録
- 上位エージェント/管理者に通知（オプション）

---

## 依存関係の構造

- **初期実装**: ツリー構造（単一の親）
- **将来検討**: DAG（複数の親）も視野に

---

## プロジェクト参加

- 1エージェントが複数プロジェクトに参加可能

---

## リソース可用性

### 初期実装
- **並列実行可能数**をエージェントごとに設定
- in_progress 状態のタスク数が上限に達したらロック

```
例:
  エージェントA: 並列数 = 1 → 1タスクのみ in_progress 可
  エージェントB: 並列数 = 3 → 3タスクまで同時 in_progress 可
```

### ロックの動作
- in_progress への状態変更時にチェック
- 上限到達時は状態変更をブロック

### 将来検討
- タスクの重さ・種類による制御
- 実際の処理状態（待ち/実行中）の反映
- 稼働時間帯の設定（人間向け）

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2025-01-06 | 1.0.0 | 初版作成 |
| 2026-01-07 | 4.0.0 | Phase 4 Runner + Agent Instance アーキテクチャに整合。Runner に project_id 対応を追加、管理単位を(agent_id, project_id)に変更、API名を更新（get_pending_tasks → get_my_task, report_execution_complete → report_completed）|
