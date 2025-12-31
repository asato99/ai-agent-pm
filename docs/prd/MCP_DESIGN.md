# MCP連携設計

MCPサーバーが提供するTools、Resources、Promptsの詳細設計。

---

## MCPサーバーが提供するTools

### エージェント・セッション管理

| Tool | 説明 | 用途 |
|------|------|------|
| `get_my_profile` | 自分のエージェント情報を取得 | 自分の役割・専門分野を確認 |
| `list_agents` | プロジェクトのエージェント一覧 | 誰に引き継げるか把握 |
| `get_agent` | 特定エージェントの詳細 | 他エージェントの専門分野を確認 |
| `start_session` | セッション開始を記録 | 接続時に自動呼び出し |
| `end_session` | セッション終了を記録 | 作業サマリを保存 |
| `get_my_sessions` | 自分の過去セッション一覧 | 過去のコンテキスト復元 |

### プロジェクト・タスク管理

| Tool | 説明 | 用途 |
|------|------|------|
| `list_projects` | プロジェクト一覧取得 | プロジェクト選択 |
| `get_project` | プロジェクト詳細取得 | プロジェクト情報確認 |
| `list_tasks` | タスク一覧取得（フィルタ可） | 作業可能タスク確認 |
| `get_task` | タスク詳細取得 | タスク内容確認 |
| `get_my_tasks` | 自分に割り当てられたタスク | 自分の担当タスク確認 |
| `update_task_status` | ステータス更新 | 進捗報告 |
| `assign_task` | タスクを自分または他エージェントに割当 | タスク分担 |

### コンテキスト・ハンドオフ

| Tool | 説明 | 用途 |
|------|------|------|
| `add_context` | コンテキスト情報追加 | 決定事項・成果物記録 |
| `get_context` | タスクのコンテキスト取得 | 過去の決定事項確認 |
| `create_handoff` | ハンドオフ作成 | 他エージェントへの引き継ぎ |
| `get_pending_handoffs` | 自分宛のハンドオフ一覧 | 引き継ぎ事項確認 |
| `acknowledge_handoff` | ハンドオフ受領確認 | 引き継ぎ完了報告 |

---

## MCPサーバーが提供するResources

| Resource | 説明 |
|----------|------|
| `agent://me` | 自分のエージェント情報 |
| `agent://{id}` | 特定エージェント情報 |
| `project://{id}` | プロジェクト情報 |
| `task://{id}` | タスク情報 |
| `context://{taskId}` | タスクのコンテキスト |
| `handoff://{taskId}` | 最新のハンドオフ情報 |
| `session://current` | 現在のセッション情報 |

---

## MCPサーバーが提供するPrompts

| Prompt | 説明 |
|--------|------|
| `session_start` | セッション開始時のガイダンス（自分の役割、担当タスク、ハンドオフ確認） |
| `task_start` | タスク開始時のガイダンス（コンテキスト、過去の作業履歴） |
| `handoff_template` | ハンドオフ作成テンプレート |
| `session_end` | セッション終了時のサマリ作成ガイド |

---

## セッションライフサイクル

```
┌─────────────────────────────────────────────────────────────┐
│  Claude Code起動                                            │
│      ↓                                                      │
│  MCPサーバー接続（--agent-id で認証）                       │
│      ↓                                                      │
│  start_session() 自動呼び出し                               │
│      ↓                                                      │
│  session_start プロンプト実行                               │
│  - 「あなたは frontend-dev です」                           │
│  - 「担当タスク: Task A, Task B」                           │
│  - 「backend-dev からのハンドオフがあります」               │
│      ↓                                                      │
│  作業中...                                                  │
│  - add_context() で決定事項を記録                           │
│  - update_task_status() で進捗報告                          │
│      ↓                                                      │
│  セッション終了時                                           │
│  - session_end プロンプトでサマリ作成                       │
│  - create_handoff() で引き継ぎ作成（必要なら）              │
│  - end_session() で終了記録                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## エージェントが知るべき情報

MCPを通じてエージェントが取得できる情報：

| 情報 | 取得方法 | 用途 |
|------|----------|------|
| 自分のプロフィール | `get_my_profile` | 自分の役割・専門分野を確認 |
| 他のエージェント一覧 | `list_agents` | 誰に引き継げるか把握 |
| 自分の過去の作業 | `get_my_sessions` | 過去のコンテキストを復元 |
| 自分へのハンドオフ | `get_pending_handoffs` | 引き継ぎ事項を確認 |

---

## コンテキスト共有

```swift
TaskContext {
    decisions: [Decision]       // 決定事項
    assumptions: [Assumption]   // 前提条件
    blockers: [Blocker]         // 障害
    artifacts: [Artifact]       // 成果物（ファイルパス等）
    notes: [Note]               // 自由メモ
}
```

---

## ハンドオフ（引き継ぎ）

```swift
HandoffInfo {
    fromAgent: AgentID
    toAgent: AgentID?           // nil = 次の担当者未定
    summary: String             // 作業サマリ
    nextSteps: [String]         // 次にやるべきこと
    warnings: [String]          // 注意点
    timestamp: Date
}
```

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | PRD.mdから分離して初版作成 |
