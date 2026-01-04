# MCPサーバー アーキテクチャ設計

Claude Codeと連携するMCPサーバーの内部構成。

---

## 設計原則

### ステートレス設計

MCPサーバーは**ステートレス**に設計されています。

```
従来の設計（問題あり）:
  mcp-server-pm --db xxx --agent-id yyy --project-id zzz
  → サーバー起動時にIDが固定され、設定ファイルとDBの不整合が発生

新設計（ステートレス）:
  mcp-server-pm --db xxx
  → IDは各ツール呼び出し時に引数として渡す
  → キック時にプロンプトでID情報を提供し、LLMが橋渡し
```

### データフロー

```
┌─────────────┐                    ┌──────────────┐                    ┌─────────────┐
│  PMアプリ   │ ─プロンプトに─────▶│ Claude Code  │ ─引数として────────▶│ MCPサーバー │
│             │  ID情報を含める    │   (LLM)      │  IDを渡す          │ (ステートレス)│
└─────────────┘                    └──────────────┘                    └─────────────┘

キック時のプロンプト例:
  # Task: 機能実装
  Task ID: task_abc123
  Project ID: proj_xyz789
  Agent ID: agt_dev001
  Agent Name: frontend-dev
  ...

ツール呼び出し例:
  update_task_status(task_id="task_abc123", status="done")
  create_handoff(task_id="task_abc123", from_agent_id="agt_dev001", ...)
```

---

## 概要

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Claude Code                                     │
│                              │                                           │
│                         stdio (JSON-RPC)                                │
│                              │                                           │
└──────────────────────────────┼───────────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        mcp-server-pm                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                     Transport Layer                                │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  StdioTransport: stdin/stdout JSON-RPC 処理                  │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                               │                                          │
│  ┌───────────────────────────▼───────────────────────────────────────┐  │
│  │                     Protocol Layer                                 │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │  │
│  │  │   Tools     │  │  Resources  │  │   Prompts   │               │  │
│  │  │  Handler    │  │   Handler   │  │   Handler   │               │  │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘               │  │
│  └─────────┼────────────────┼────────────────┼───────────────────────┘  │
│            │                │                │                           │
│  ┌─────────▼────────────────▼────────────────▼───────────────────────┐  │
│  │                    Infrastructure Layer                            │  │
│  │                  (Repository + Database)                           │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 起動フロー

### コマンドライン引数

```bash
# 最小構成（DBパスのみ必須）
mcp-server-pm --db "/path/to/data.db"
```

### 起動処理

```swift
@main
struct MCPServerApp {
    static func main() async throws {
        // 1. 引数パース（DBパスのみ必須）
        let config = try ServerConfig.parse()

        // 2. データベース接続
        let database = try DatabaseQueue(path: config.dbPath)

        // 3. サーバー起動（ステートレス）
        let server = MCPServer(database: database)

        // 4. メインループ
        try await server.run()
    }
}
```

---

## Tools設計（ステートレス版）

### ID引数の原則

**すべてのツールで必要なIDは引数として受け取る**

```swift
// ❌ 旧設計: サーバー内部に保持したagentIdを使用
func getMyProfile() -> Agent {
    return agentRepository.findById(self.agentId)
}

// ✅ 新設計: 引数でIDを受け取る
func getAgentProfile(agentId: String) -> Agent {
    return agentRepository.findById(AgentID(value: agentId))
}
```

### ツール定義

| Tool | 引数 | 説明 |
|------|------|------|
| `get_agent_profile` | `agent_id` | エージェント情報を取得 |
| `list_agents` | - | 全エージェント一覧 |
| `list_tasks` | `project_id`, `status?`, `assignee_id?` | タスク一覧取得 |
| `get_task` | `task_id` | タスク詳細取得 |
| `update_task_status` | `task_id`, `status` | ステータス更新 |
| `create_handoff` | `task_id`, `from_agent_id`, `to_agent_id?`, `summary` | ハンドオフ作成 |
| `get_pending_handoffs` | `agent_id?` | 未処理ハンドオフ取得 |
| `save_context` | `task_id`, `progress?`, `findings?`, ... | コンテキスト保存 |

### ツール実装例

```swift
func callTool(_ params: [String: Any]) throws -> [String: Any] {
    guard let name = params["name"] as? String,
          let arguments = params["arguments"] as? [String: Any] else {
        throw MCPError.invalidParams
    }

    switch name {
    case "get_agent_profile":
        // agent_id は引数で受け取る
        guard let agentId = arguments["agent_id"] as? String else {
            throw MCPError.missingArguments(["agent_id"])
        }
        return try getAgentProfile(agentId: agentId)

    case "create_handoff":
        // from_agent_id も引数で受け取る
        guard let taskId = arguments["task_id"] as? String,
              let fromAgentId = arguments["from_agent_id"] as? String,
              let summary = arguments["summary"] as? String else {
            throw MCPError.missingArguments(["task_id", "from_agent_id", "summary"])
        }
        let toAgentId = arguments["to_agent_id"] as? String
        return try createHandoff(
            taskId: taskId,
            fromAgentId: fromAgentId,
            toAgentId: toAgentId,
            summary: summary
        )

    // ...
    }
}
```

---

## Resources設計

リソースURIにIDを含める:

```swift
let resources = [
    ResourceTemplate(uriTemplate: "agent://{id}", name: "Agent by ID"),
    ResourceTemplate(uriTemplate: "project://{id}", name: "Project by ID"),
    ResourceTemplate(uriTemplate: "task://{id}", name: "Task by ID"),
    ResourceTemplate(uriTemplate: "context://{taskId}", name: "Task Context"),
    ResourceTemplate(uriTemplate: "handoff://{taskId}", name: "Task Handoff")
]
```

※ `agent://me` や `session://current` のような「現在の」リソースは廃止

---

## Prompts設計

プロンプトもタスクIDを引数で受け取る:

```swift
let prompts = [
    PromptDefinition(
        name: "task_start",
        description: "タスク開始時のガイダンス",
        arguments: [
            PromptArgument(name: "task_id", required: true),
            PromptArgument(name: "agent_id", required: true)
        ]
    ),
    PromptDefinition(
        name: "handoff_template",
        description: "ハンドオフ作成テンプレート",
        arguments: [
            PromptArgument(name: "task_id", required: true),
            PromptArgument(name: "from_agent_id", required: true)
        ]
    )
]
```

---

## キック時のプロンプト

PMアプリがエージェントをキックする際、プロンプトに必要な情報を含める:

```swift
// ClaudeCodeKickService.swift
private func buildPrompt(task: Task, agent: Agent, project: Project) -> String {
    """
    # Task: \(task.title)

    ## Identification
    - Task ID: \(task.id.value)
    - Project ID: \(project.id.value)
    - Agent ID: \(agent.id.value)
    - Agent Name: \(agent.name)

    ## Description
    \(task.description)

    ## Instructions
    1. Complete the task as described above
    2. When done, update the task status using:
       update_task_status(task_id="\(task.id.value)", status="done")
    3. If handing off to another agent, use:
       create_handoff(task_id="\(task.id.value)", from_agent_id="\(agent.id.value)", ...)
    """
}
```

LLM（Claude Code）はこのプロンプトからIDを読み取り、ツール呼び出し時に引数として渡す。

---

## エラーハンドリング

```swift
enum MCPError: Error {
    case invalidParams
    case missingArguments([String])
    case agentNotFound(String)
    case taskNotFound(String)
    case projectNotFound(String)
    case handoffNotFound(String)
    case unknownTool(String)
    case unknownMethod(String)
    case internalError(String)
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
        "--db", "/path/to/pm.db"
      ]
    }
  }
}
```

**注意**: `--agent-id` や `--project-id` は不要。IDはツール呼び出し時に引数で渡す。

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | 初版作成 |
| 2025-01-04 | 2.0.0 | ステートレス設計に変更。agent-id/project-idを起動引数から削除し、各ツール呼び出し時に引数で渡す設計に変更 |
