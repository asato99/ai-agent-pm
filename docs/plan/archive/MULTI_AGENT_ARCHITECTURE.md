# マルチエージェント アーキテクチャ設計

> ユースケースは docs/usecase/UC002_MultiAgentCollaboration.md を参照

## 前提

- 各エージェントは**独立したClaude Codeプロセス**
- 知識・記憶の共有は**されない**
- エージェントの特性は**アプリ側で管理**し、認証時に渡す

---

## なぜ複数エージェントが必要か

**異なるシステムプロンプト = 異なる専門家**

| エージェント | システムプロンプト（抜粋） | 期待される振る舞い |
|-------------|--------------------------|-------------------|
| `agt_developer` | 「あなたは開発者です。コードを実装してください」 | 実装重視 |
| `agt_reviewer` | 「あなたはレビュアーです。問題点を指摘してください」 | 批判的視点 |
| `agt_tester` | 「あなたはQAです。テストケースを作成してください」 | テスト重視 |

同じタスクでも、異なるプロンプトで異なる成果物を得られる。

---

## アーキテクチャ

### 役割分担

| コンポーネント | 管理する情報 |
|--------------|-------------|
| **アプリ（DB）** | エージェントの全属性（名前、aiType、system_prompt） |
| **Coordinator** | passkey + AIプロバイダーごとの起動方法 |
| **MCP Server** | should_start で aiType、authenticate で system_prompt を返す |

### Single Source of Truth

```
[アプリ UI]
    │
    │ エージェント作成・編集
    ▼
[DB: agents テーブル]
    ├── id: agt_developer
    ├── name: "Developer Agent"
    ├── ai_type: "claude"           ← どのAIを使うか
    └── system_prompt: "あなたは開発者です..."
```

---

## Coordinator設定

Coordinatorは **passkey** と **AIプロバイダーの起動方法** を保持。

```yaml
# coordinator_config.yaml

polling_interval: 10
mcp_socket_path: ~/Library/Application Support/AIAgentPM/mcp.sock

# AIプロバイダーごとの起動方法
ai_providers:
  claude:
    cli_command: claude
    cli_args: ["--dangerously-skip-permissions"]
  gemini:
    cli_command: gemini-cli
    cli_args: ["--project", "my-project"]
  openai:
    cli_command: openai-cli
    cli_args: []

# エージェントごとの認証情報（aiType はアプリ側で管理）
agents:
  agt_developer:
    passkey: ${DEV_PASSKEY}
    working_directory: /projects/myapp

  agt_reviewer:
    passkey: ${REVIEWER_PASSKEY}
    working_directory: /projects/myapp
```

**ポイント**:
- `ai_type` はアプリ側で管理、`should_start` で返される
- Coordinatorは `ai_providers` で各AIの起動方法を定義
- `system_prompt` もアプリ側で管理

---

## 認証フロー

### authenticate レスポンス（拡張）

```python
authenticate(agent_id, passkey) → {
    "success": true,
    "session_token": "sess_xxx",
    "agent_name": "Developer Agent",
    "system_prompt": "あなたは開発者です。タスクの要件に従い...",  # DBから取得
    "instruction": "get_my_task() でタスクを取得してください"
}
```

### 起動プロンプト（Coordinator → Agent）

```
Agent ID: {agent_id}
Passkey: {passkey}

手順:
1. authenticate(agent_id, passkey) で認証
2. 返された system_prompt があなたの役割です
3. get_my_task() でタスク取得
4. タスク実行
5. report_completed() で完了報告
```

### 完全なフロー

```
[Coordinator]
    │
    │ should_start(agt_developer)
    ▼
[MCP Server]
    │
    │ { should_start: true, ai_type: "claude" }
    ▼
[Coordinator]
    │
    │ ai_providers["claude"] → cli_command: "claude"
    │ spawn(claude ... -p "agent_id + passkey")
    ▼
[Agent (Claude Code)]
    │
    │ authenticate(agt_developer, passkey)
    ▼
[MCP Server]
    │
    │ { token, system_prompt: "あなたは開発者です..." }
    ▼
[Agent]
    │
    │ system_prompt に従って振る舞う
    │ get_my_task() → タスク実行 → report_completed()
    ▼
[完了]
```

---

## 情報の受け渡し（アプリ側の役割）

### エージェント間の記憶共有

Claude Code自体は記憶を共有しないが、**アプリが記憶の保存・引き継ぎを担当**:

| MCP ツール | 用途 |
|-----------|------|
| `save_context()` | タスクに紐づく進捗・成果を保存 |
| `create_handoff()` | 次のエージェントへの引き継ぎ情報を作成 |
| `get_my_task()` | 保存された context / handoff を含むタスク情報を取得 |

### フロー

```
[agt_developer]
    │
    │ save_context() で成果を記録
    ▼
[MCP Server / DB]
    │
    │ get_my_task() で context を付与
    ▼
[agt_reviewer]
    │
    └ 前のエージェントの成果を取得
```

---

## アプリ側の実装要件

### Agent エンティティの拡張

```swift
struct Agent {
    let id: AgentID
    var name: String
    var type: AgentType           // .ai / .human
    var aiType: AIType?           // NEW: .claude, .gemini, .openai（AIの場合）
    var role: String?             // 役割説明
    var systemPrompt: String?     // NEW: LLM向けシステムプロンプト
    var status: AgentStatus
    // ...
}

enum AIType: String, Codable {
    case claude = "claude"
    case gemini = "gemini"
    case openai = "openai"
}
```

### should_start の拡張

```swift
func shouldStart(agentId: String) -> [String: Any] {
    // ... 既存の判定ロジック ...

    return [
        "should_start": shouldStart,
        "ai_type": agent.aiType?.rawValue ?? "claude"  // NEW
    ]
}
```

### authenticate の拡張

```swift
func authenticate(agentId: String, passkey: String) -> AuthResult {
    // 既存の認証処理...

    return [
        "success": true,
        "session_token": session.token,
        "agent_name": agent.name,
        "system_prompt": agent.systemPrompt ?? "",  // NEW
        "instruction": "get_my_task() でタスクを取得してください"
    ]
}
```

---

## まとめ

| 項目 | 管理場所 |
|------|---------|
| エージェントの存在・認証 | アプリ（DB） |
| AIタイプ（claude, gemini...） | アプリ（DB） |
| エージェントの役割（system_prompt） | アプリ（DB） |
| AIプロバイダーの起動方法 | Coordinator設定 |
| 認証用 passkey | Coordinator設定 |
| タスクの記憶（context, handoff） | アプリ（DB） |
| 起動判断 | Coordinator + MCP Server |
