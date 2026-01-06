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

## タスク実行アーキテクチャ

### 概要

タスクの実行は **プル型** で設計されています。

- **アプリの責務**: タスクのステータス管理のみ（CLI実行は行わない）
- **Runner の責務**: MCP経由でタスクを検知し、CLI（Claude/Gemini等）を実行

```
┌─────────────────────┐         ┌─────────────────────┐
│       アプリ         │         │  Runner（外部）      │
│                     │         │   ユーザーが実装     │
│  Task → in_progress │         │                     │
│         ↓           │         │    ┌─────────────┐  │
│    DB に保存         │         │    │ ポーリング   │  │
│                     │         │    │  ループ     │  │
└─────────────────────┘         │    └──────┬──────┘  │
                                │           │         │
┌─────────────────────┐         │           ▼         │
│    MCPサーバー       │◀────────│  get_pending_tasks  │
│                     │         │           │         │
│  認証 + タスク取得   │────────▶│    タスク取得        │
│                     │         │           │         │
└─────────────────────┘         │           ▼         │
                                │    CLI実行          │
                                │    (claude/gemini)  │
                                │           │         │
                                │           ▼         │
                                │  update_task_status │
                                └─────────────────────┘
```

### 設計原則

| 原則 | 説明 |
|------|------|
| 疎結合 | アプリと Runner は完全に分離 |
| 外部化 | CLI実行ロジックはアプリに含まない |
| 1 Runner = 1 Agent | Runner はエージェント単位で起動 |
| MCP経由 | 通信は全て MCP ツール経由 |

---

## Runner アーキテクチャ

### 概要

Runner はユーザーが実装・管理する外部プログラムです。
アプリはサンプル実装を提供しますが、実際の Runner はユーザーに委ねられます。

### Runner の責務

| 責務 | 説明 |
|------|------|
| 認証 | MCP経由で agent_id + passkey を使ってセッション取得 |
| タスク監視 | 定期的に `get_pending_tasks` でポーリング |
| CLI実行 | タスク検知時に Claude/Gemini 等を起動 |
| ステータス更新 | 完了時に `update_task_status` を呼び出し |

### 認証フロー

```
[Runner起動時]
    │
    └─ authenticate(agent_id, passkey)
           │
           ▼
    [MCPサーバー]
           │
           ├─ Passkey検証（ハッシュ比較）
           │
           └─ セッショントークン発行（有効期限付き）
                   │
                   ▼
              session_token（1時間有効）

[タスク取得時]
    │
    └─ get_pending_tasks(session_token)
           │
           ├─ トークン検証
           └─ そのエージェントに割り当てられたタスクのみ返却
```

### セッション管理

```swift
struct AgentSession {
    let token: String              // UUID
    let agentId: AgentID
    let expiresAt: Date            // 1時間後
    let createdAt: Date
}
```

- セッショントークンは1時間で期限切れ
- 期限切れ時は再認証が必要
- Runner は `ensure_authenticated()` で自動再認証

### Runner 設定

```bash
# 環境変数で認証情報を渡す
export AGENT_ID="agt_xxx"
export AGENT_PASSKEY="secret123"
./runner
```

または設定ファイル:

```yaml
# runner_config.yaml
agent_id: agt_xxx
passkey: secret123
polling_interval: 5  # 秒
```

### サンプル Runner（Python）

```python
#!/usr/bin/env python3
# sample_runner.py

import os
import time
import subprocess

class AgentRunner:
    def __init__(self):
        self.agent_id = os.environ["AGENT_ID"]
        self.passkey = os.environ["AGENT_PASSKEY"]
        self.session_token = None
        self.mcp_client = MCPClient()

    def authenticate(self):
        result = self.mcp_client.call("authenticate", {
            "agent_id": self.agent_id,
            "passkey": self.passkey
        })
        if result["success"]:
            self.session_token = result["session_token"]
        else:
            raise Exception("Authentication failed")

    def ensure_authenticated(self):
        if self.session_token is None or self.is_expired():
            self.authenticate()

    def get_pending_tasks(self):
        self.ensure_authenticated()
        result = self.mcp_client.call("get_pending_tasks", {
            "session_token": self.session_token
        })
        return result.get("tasks", [])

    def execute_task(self, task):
        prompt = self.build_prompt(task)
        # Claude CLI を実行
        subprocess.run([
            "claude", "--dangerously-skip-permissions",
            "-p", prompt
        ], cwd=task["workingDirectory"])

    def build_prompt(self, task):
        return f"""# Task: {task["title"]}

## Identification
- Task ID: {task["taskId"]}
- Project ID: {task["projectId"]}
- Agent ID: {self.agent_id}

## Description
{task["description"]}

## Working Directory
Path: {task["workingDirectory"]}

## Instructions
1. Complete the task as described above
2. When done, update the task status using:
   update_task_status(task_id="{task["taskId"]}", status="done")
"""

    def run(self):
        while True:
            try:
                tasks = self.get_pending_tasks()
                for task in tasks:
                    self.execute_task(task)
            except Exception as e:
                print(f"Error: {e}")
            time.sleep(5)

if __name__ == "__main__":
    runner = AgentRunner()
    runner.run()
```

### サンプル Runner（Bash）

```bash
#!/bin/bash
# simple_runner.sh

AGENT_ID="${AGENT_ID}"
PASSKEY="${AGENT_PASSKEY}"
POLL_INTERVAL=5

# MCP認証（簡略版）
authenticate() {
    # 実際の実装では MCP クライアントを使用
    SESSION_TOKEN=$(mcp-client authenticate "$AGENT_ID" "$PASSKEY")
}

# メインループ
authenticate

while true; do
    TASKS=$(mcp-client get_pending_tasks "$SESSION_TOKEN")

    for TASK in $TASKS; do
        TASK_ID=$(echo "$TASK" | jq -r '.taskId')
        PROMPT=$(mcp-client get_task_prompt "$TASK_ID")
        WORKING_DIR=$(echo "$TASK" | jq -r '.workingDirectory')

        cd "$WORKING_DIR"
        echo "$PROMPT" | claude --dangerously-skip-permissions -p -
    done

    sleep $POLL_INTERVAL
done
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

## MCP ツール（Runner 向け）

### 認証

```python
# セッション開始
authenticate(
    agent_id: str,
    passkey: str
) -> {
    "success": True,
    "session_token": "sess_xxxxx",
    "expires_in": 3600  # 秒
}

# 認証失敗時
{
    "success": False,
    "error": "Invalid agent_id or passkey"
}

# セッション終了
logout(
    session_token: str
) -> {
    "success": True
}
```

### タスク取得

```python
# 実行待ちタスクを取得
get_pending_tasks(
    session_token: str
) -> {
    "success": True,
    "tasks": [
        {
            "taskId": "tsk_xxx",
            "projectId": "prj_xxx",
            "title": "機能実装",
            "description": "ログイン画面のUIを実装する",
            "priority": "high",
            "workingDirectory": "/path/to/project"
        }
    ]
}
```

### スコープ制限

各エージェントは自分に関連する操作のみ可能：

```python
permissions = {
    "get_pending_tasks": "own_tasks_only",
    "update_task_status": "assigned_tasks_only",
    "save_context": "own_tasks_only",
    "create_handoff": "from_self_only"
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

## 状態確認
- 上位エージェント自身がMCP経由で下位の状態を確認可能
- 下位からの能動的な報告は必須ではない

---

## エージェント認証

### 目的
エージェントがMCPツールを呼び出す際、正しいエージェントとして識別されることを保証する。

### ステートレス設計における認証

MCPサーバーはステートレスに設計されているため、認証は**ツール呼び出し時の引数**で行う。

```
[キック時]
  PMアプリがプロンプトにID情報を含める
  ↓
[LLM（Claude Code）]
  プロンプトからID情報を読み取る
  ↓
[MCPツール呼び出し時]
  引数としてagent_idを渡す
  - 例: create_handoff(task_id=..., from_agent_id="agt_dev001", ...)
  ↓
[MCPサーバー側で検証]
  - agent_id の存在確認
  - passkey の一致確認（将来、必要に応じて）
  ↓
認証成功 → ツール実行
認証失敗 → エラー返却
```

### 認証レベル

| レベル | 認証方式 | 用途 |
|--------|----------|------|
| Level 0 | agent_id のみ | 開発/テスト環境（初期実装） |
| Level 1 | agent_id + passkey | 本番環境（将来） |
| Level 2 | agent_id + passkey + IP制限 | セキュア環境（将来） |

### エージェント属性（認証関連）

| 属性 | 説明 |
|------|------|
| passkey | 認証用の秘密鍵（ハッシュ保存、将来） |
| auth_level | 認証レベル (0/1/2) |
| allowed_ips | 許可IPリスト（Level 2用、将来） |

### 初期実装

1. **Phase 1**: agent_id のみで認証（開発優先）
   - ツール呼び出し時にagent_idの存在確認のみ
   - LLMがプロンプトから読み取ったIDを信頼
2. **Phase 2**: passkey 対応追加
   - 特定のツールでpasskey検証を追加
3. **Phase 3**: IP制限等のセキュリティ強化

### ツール呼び出し時の認証例

```
# ハンドオフ作成時（from_agent_idを検証）
create_handoff(
  task_id="task_abc123",
  from_agent_id="agt_dev001",  ← 検証対象
  to_agent_id="agt_reviewer",
  summary="認証機能実装完了"
)

# ステータス更新時（task_idの権限を検証）
update_task_status(
  task_id="task_abc123",  ← 操作権限を検証
  status="done"
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
