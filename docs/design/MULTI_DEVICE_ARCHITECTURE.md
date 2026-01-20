# マルチデバイス アーキテクチャ設計

## 概要

複数端末でAIエージェントを稼働させるためのアーキテクチャ設計。
1台のMacでアプリ（サーバー）を起動し、複数のPCからWebクライアント・MCPクライアントとして接続する構成。

---

## 全体構成

```
┌─────────────────────────────────────────────────────────────────┐
│                    Mac A (サーバー)                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              AIAgentPM App                               │   │
│  │  - SQLite DB                                            │   │
│  │  - MCPサーバー (HTTP Transport)  ← 新規実装必要          │   │
│  │  - REST API (Web UI用)           ← 実装済み              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Coordinator (--agent human-owner)                       │   │
│  │  → 自身の管轄範囲のAIエージェントを起動                   │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────┬───────────────────────────────────┘
                              │ HTTP (LAN内)
            ┌─────────────────┼─────────────────┐
            ▼                 ▼                 ▼
     ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
     │   PC B      │   │   PC C      │   │   PC D      │
     │             │   │             │   │             │
     │ Coordinator │   │ Coordinator │   │ ブラウザ    │
     │ --agent     │   │ --agent     │   │ (Web UI)    │
     │ human-front │   │ human-back  │   │             │
     │             │   │             │   │             │
     │     ↓       │   │     ↓       │   │             │
     │ Claude Code │   │ Claude Code │   │             │
     └─────────────┘   └─────────────┘   └─────────────┘
```

---

## エージェント管轄ルール

### 基本原則

1. **Coordinatorの起点**: `human` タイプのエージェントのみ
2. **管轄範囲**: 起点から「次のhumanに到達するまでのAI」
3. **humanはhumanを管轄しない**: humanで管轄が区切られる

### Human による管轄の区切り

```
human-owner (human)
├── human-frontend-lead (human) ← ここで区切り
│   ├── worker-ui (ai)
│   └── worker-css (ai)
├── human-backend-lead (human)  ← ここで区切り
│   ├── worker-api (ai)
│   └── worker-db (ai)
└── manager-infra (ai)          ← human-ownerが管轄
    └── worker-deploy (ai)
```

### 管轄範囲の決定

| Coordinator起点 | 管轄範囲 |
|----------------|---------|
| `human-owner` | `manager-infra`, `worker-deploy` |
| `human-frontend-lead` | `worker-ui`, `worker-css` |
| `human-backend-lead` | `worker-api`, `worker-db` |

### 重複起動の防止

- **humanがhumanを管轄しない** → 自然と排他的な区画になる
- 各humanエージェントの「領地」が明確に分かれる
- 同一AIエージェントを複数Coordinatorが管轄することがない

---

## Coordinator 起動モード

### エージェント起点モード

```bash
coordinator --agent <human-agent-id> --passkey <passkey>
```

**動作**:
- 指定した `human` タイプのエージェントを起点とする
- 起点から「次のhumanに到達するまでのAI」を管轄
- 起点自身（human）は起動対象外

### 設定ファイル例

```yaml
# coordinator_config.yaml

# 起点エージェント（humanタイプのみ指定可能）
agent_id: human-frontend-lead
passkey: ${FRONTEND_LEAD_PASSKEY}

# MCPサーバー接続先
mcp:
  url: http://192.168.1.100:8080/mcp
  api_key: ${MCP_API_KEY}

# AIプロバイダー設定
ai_providers:
  claude:
    cli_command: claude
    cli_args: ["--dangerously-skip-permissions"]
```

---

## 管轄範囲取得のロジック

### アルゴリズム

```python
def get_managed_agents(root_agent_id: str) -> List[str]:
    """
    起点humanから、次のhumanに到達するまでのAIを収集

    Args:
        root_agent_id: 起点となるhumanエージェントのID

    Returns:
        管轄対象のAIエージェントIDリスト
    """
    # 起点がhumanでなければエラー
    root_agent = get_agent(root_agent_id)
    if root_agent.type != "human":
        raise Error("Coordinator root must be human type agent")

    result = []

    def traverse(agent_id):
        for child in get_children(agent_id):
            if child.type == "human":
                # humanに到達したら、その先は探索しない（区切り）
                continue
            else:
                # AIなら管轄対象
                result.append(child.id)
                # さらに配下を探索（humanに当たるまで）
                traverse(child.id)

    traverse(root_agent_id)
    return result
```

### 探索の可視化

```
human-owner を起点とした場合:

human-owner
├── human-frontend-lead → STOP（humanなので探索終了）
├── human-backend-lead  → STOP（humanなので探索終了）
└── manager-infra       → 収集 ✓
    └── worker-deploy   → 収集 ✓

結果: [manager-infra, worker-deploy]
```

---

## MCP API 拡張

### list_managed_agents（新規）

Coordinatorが自身の管轄範囲を取得するためのAPI。

```python
list_managed_agents(
    root_agent_id: str,  # 起点となるhumanエージェントのID
    project_id: str      # 対象プロジェクト
) → {
    "success": true,
    "root_agent": {
        "id": "human-frontend-lead",
        "name": "Frontend Lead",
        "type": "human"
    },
    "managed_agents": [
        {
            "id": "worker-ui",
            "name": "UI Worker",
            "type": "ai",
            "ai_type": "claude"
        },
        {
            "id": "worker-css",
            "name": "CSS Worker",
            "type": "ai",
            "ai_type": "claude"
        }
    ]
}
```

### should_start（既存・変更なし）

```python
should_start(
    agent_id: str,
    project_id: str
) → {
    "should_start": true | false,
    "ai_type": "claude"  # should_start が true の場合
}
```

---

## 必要な実装

### 現状の制限

現在の実装では、別端末からのアクセスができない：

| コンポーネント | 現状 | 問題点 |
|--------------|------|--------|
| MCPサーバー | Unix Socket のみ | ローカルマシン限定 |
| REST API | `127.0.0.1` にバインド | ローカルマシン限定 |

```swift
// RESTServer.swift:156 - 現状
configuration: .init(address: .hostname("127.0.0.1", port: port))

// 変更後
configuration: .init(address: .hostname("0.0.0.0", port: port))
```

### 新規実装

| コンポーネント | 説明 | 優先度 |
|--------------|------|--------|
| REST API リモートアクセス対応 | `0.0.0.0` バインド、設定可能化 | 高 |
| MCP HTTP Transport | JSON-RPC over HTTP | 高 |
| AgentWorkingDirectory | 新規エンティティ・リポジトリ | 高 |
| Coordinator設定エクスポート拡張 | root_agent選択UI | 中 |
| Coordinator `root_agent_id` 対応 | 設定読み込み・認証 | 中 |

### 既存実装の活用

| コンポーネント | 状況 |
|--------------|------|
| REST API (Web UI用) | ✅ 実装済み（リモートアクセス対応が必要） |
| Web UI (React) | ✅ 実装済み |
| should_start API | ✅ 実装済み |
| authenticate API | ✅ 実装済み |
| Coordinator基盤 (Python) | ✅ 実装済み（HTTP対応が必要） |

---

## 構成例

### シナリオ: 3チーム体制

```
human-cto (human) ──────────────────── Mac A で管轄
├── human-frontend-lead (human) ────── PC B で管轄
│   ├── worker-ui (ai)
│   ├── worker-css (ai)
│   └── worker-test-front (ai)
├── human-backend-lead (human) ─────── PC C で管轄
│   ├── worker-api (ai)
│   ├── worker-db (ai)
│   └── worker-test-back (ai)
└── manager-devops (ai) ─────────────── Mac A で管轄
    ├── worker-ci (ai)
    └── worker-deploy (ai)
```

### 各端末の設定

**Mac A (human-cto)**:
```yaml
agent_id: human-cto
passkey: ${CTO_PASSKEY}
mcp:
  url: unix:///path/to/mcp.sock  # ローカルならUnix Socketも可
```

**PC B (human-frontend-lead)**:
```yaml
agent_id: human-frontend-lead
passkey: ${FRONTEND_LEAD_PASSKEY}
mcp:
  url: http://192.168.1.100:8080/mcp
  api_key: ${MCP_API_KEY}
```

**PC C (human-backend-lead)**:
```yaml
agent_id: human-backend-lead
passkey: ${BACKEND_LEAD_PASSKEY}
mcp:
  url: http://192.168.1.100:8080/mcp
  api_key: ${MCP_API_KEY}
```

---

## セキュリティ考慮事項

### 認証

| 項目 | 方式 |
|------|------|
| MCP接続 | API Key認証（開発用） |
| Coordinator起点 | passkey認証 |
| Agent Instance | passkey認証（既存） |

### 将来の拡張

- OAuth 2.1 + PKCE（外部公開時）
- HTTPS必須化
- IP制限

---

## Coordinator設定エクスポート機能

### 概要

macOSアプリの既存機能「Export Coordinator Config」を拡張し、root_agentを選択してエクスポートできるようにする。

### UI設計

```
[Export Coordinator Config...]  ← ボタンクリック

┌─────────────────────────────────────────────────┐
│ Export Coordinator Configuration                 │
├─────────────────────────────────────────────────┤
│                                                 │
│ Root Agent:                                     │
│   [None - Export all agents ▼]                  │
│   ├─ human-owner                                │
│   ├─ human-frontend-lead                        │
│   └─ human-backend-lead                         │
│                                                 │
│ Managed Agents:                                 │
│   ┌───────────────────────────────────────┐    │
│   │ • worker-ui (ai)                      │    │
│   │ • worker-css (ai)                     │    │
│   │ • worker-test-front (ai)              │    │
│   └───────────────────────────────────────┘    │
│                                                 │
│             [Cancel]  [Export...]               │
└─────────────────────────────────────────────────┘
```

- Root Agentは **humanタイプのみ** をリスト表示
- 選択に応じて管轄対象AIをプレビュー
- 「None」選択時は全エージェントをエクスポート（従来動作）

### 設定ファイルフォーマット（拡張）

```yaml
# coordinator.yaml

# 新規フィールド: 管轄の起点となるhumanエージェント
root_agent_id: human-frontend-lead

# 既存フィールド（変更なし）
polling_interval: 2
max_concurrent: 3
coordinator_token: xxx
mcp_socket_path: http://192.168.1.100:8080/mcp

ai_providers:
  claude:
    cli_command: claude
    cli_args: ["--dangerously-skip-permissions"]

# agents: root_agent_idが指定された場合、その配下のAIのみを含む
agents:
  worker-ui:
    passkey: xxx
  worker-css:
    passkey: xxx
```

---

## Working Directory の扱い

### 課題

同じプロジェクトでも、端末ごとにワーキングディレクトリが異なる：

```
Mac A (human-owner):     /Users/owner/projects/app
PC B (human-frontend):   /home/frontend/projects/app
PC C (human-backend):    C:\Users\backend\projects\app
```

### 解決策

**設計方針**: Coordinator側の変更を最小限に抑え、サーバー側で解決する

#### データモデル拡張

```
AgentWorkingDirectory (新規エンティティ)
├── agent_id: AgentID      # humanタイプのエージェント
├── project_id: ProjectID
└── working_directory: String
```

#### Web UI（プロジェクト詳細画面）

ログインユーザー（humanエージェント）は前提として、プロジェクト画面で「自分のworking_directory」を管理：

```
┌─────────────────────────────────────────────────┐
│ Project: App Development                         │
├─────────────────────────────────────────────────┤
│ Description: ...                                 │
│ Status: Active                                   │
│                                                 │
│ Working Directory (Server):                      │
│   /Users/owner/projects/app                     │
│                                                 │
│ My Working Directory:                            │
│   /home/frontend/projects/app           [Edit]  │
│                                                 │
└─────────────────────────────────────────────────┘
```

#### REST API

```
GET /projects/{project_id}
→ レスポンスに my_working_directory を含める（ログインユーザー分）

PUT /projects/{project_id}/my-working-directory
Body: { "working_directory": "/home/frontend/projects/app" }
```

#### サーバー側のロジック

Coordinatorは `root_agent_id` + `passkey` で認証するため、サーバーはどのhumanとして接続しているかを識別できる。

**取得ロジック**:
1. `AgentWorkingDirectory` に (human_agent_id, project_id) のエントリがあればそれを使用
2. なければ `Project.workingDirectory` をフォールバック

**既存API `list_active_projects_with_agents` の動作**:
- サーバーが認証済みhumanの `AgentWorkingDirectory` を参照
- そのhumanのworking_directoryを `working_directory` フィールドに返す

#### Coordinator側の変更

**最小限の変更のみ**:
- 設定ファイルに `root_agent_id` フィールドを追加
- 起動時に `root_agent_id` で認証
- API呼び出しのロジックは変更不要（サーバーが適切なworking_directoryを返す）

```
Coordinator (root_agent_id: human-frontend-lead)
    │
    ├─ authenticate(root_agent_id, passkey)
    │   → session_token (サーバーはhumanを識別)
    │
    └─ list_active_projects_with_agents()
        → サーバーがhuman-frontend-leadのworking_directoryを返す
        （Coordinator側は従来どおり受け取るだけ）
```

---

## 未決定事項

### Claude Code の MCP 接続設定

Agent Instance（Claude Code）がリモートMCPサーバーに接続する方法。

```json
{
  "mcpServers": {
    "agent-pm": {
      "transport": "http",
      "url": "http://192.168.1.100:8080/mcp",
      "headers": {
        "Authorization": "Bearer <api-key>"
      }
    }
  }
}
```

→ Coordinatorが動的に設定ファイルを生成する方式を検討

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-20 | 初版作成 |
| 2026-01-20 | Coordinator設定エクスポート機能、Working Directory の扱いを追記 |
| 2026-01-20 | 現状の制限（リモートアクセス不可）を追記 |

## 関連ドキュメント

- [実装プラン](./MULTI_DEVICE_IMPLEMENTATION_PLAN.md)
