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
| `get_my_tasks` | `list_tasks(assignee_id=agent_id)` |
| `start_session` | 廃止（セッション管理はオプション） |
| `end_session` | 廃止 |
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

## キック時の情報共有

### プロンプトに含める情報

PMアプリがエージェントをキックする際、プロンプトに必要なIDを含める:

```markdown
# Task: 機能実装

## Identification
- Task ID: task_abc123
- Project ID: proj_xyz789
- Agent ID: agt_dev001
- Agent Name: frontend-dev

## Description
ログイン画面のUIを実装する

## Instructions
1. Complete the task as described above
2. When done, update the task status using:
   update_task_status(task_id="task_abc123", status="done")
3. If handing off to another agent, use:
   create_handoff(task_id="task_abc123", from_agent_id="agt_dev001", ...)
```

### LLMの役割

Claude Code（LLM）は:
1. プロンプトからID情報を読み取る
2. MCPツール呼び出し時に引数としてIDを渡す
3. 作業完了時に適切なツールを呼び出す

---

## 典型的なワークフロー

### タスク実行フロー

```
┌─────────────────────────────────────────────────────────────┐
│  PMアプリでタスクをin_progressに変更                         │
│      ↓                                                      │
│  エージェントをキック（プロンプトにID情報を含める）           │
│      ↓                                                      │
│  Claude Code起動                                            │
│  - プロンプトからID情報を読み取る                           │
│      ↓                                                      │
│  作業中...                                                  │
│  - save_context(task_id, ...) で進捗を記録                  │
│      ↓                                                      │
│  作業完了時                                                 │
│  - update_task_status(task_id, "done")                     │
│  - または create_handoff(task_id, from_agent_id, ...)      │
└─────────────────────────────────────────────────────────────┘
```

### ハンドオフフロー

```
┌─────────────────────────────────────────────────────────────┐
│  Agent A: 作業完了、引き継ぎが必要                           │
│      ↓                                                      │
│  create_handoff(                                            │
│      task_id="task_123",                                    │
│      from_agent_id="agt_A",                                 │
│      to_agent_id="agt_B",  // または省略                    │
│      summary="認証機能実装完了。UIテストが必要"              │
│  )                                                          │
│      ↓                                                      │
│  Agent B: キックされる                                      │
│  - プロンプトにタスク情報が含まれる                         │
│      ↓                                                      │
│  get_pending_handoffs(agent_id="agt_B")                    │
│  - 引き継ぎ情報を確認                                       │
│      ↓                                                      │
│  accept_handoff(handoff_id="...", agent_id="agt_B")        │
│  - 引き継ぎを受領                                           │
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
