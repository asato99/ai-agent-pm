# AI Agent PM Coordinator

全エージェントのタスク実行を統合管理するオーケストレーションデーモン。

---

## クイックスタート

```bash
cd runner
pip install -e .

# デフォルト設定で起動（config/coordinator_default.yaml を使用）
python -m aiagent_runner --coordinator
```

---

## Coordinatorモード（推奨）

単一のCoordinatorが全ての(agent_id, project_id)ペアを管理します。

### 基本起動

```bash
# デフォルト設定で起動
python -m aiagent_runner --coordinator

# 詳細ログ出力
python -m aiagent_runner --coordinator -v
```

### カスタム設定ファイル

```bash
python -m aiagent_runner --coordinator -c /path/to/config.yaml
```

### 設定ファイル例

```yaml
# config/coordinator_default.yaml がデフォルトで読み込まれます
# カスタム設定で上書き可能

polling_interval: 10
max_concurrent: 3

# MCP server configuration (Agent Instance用)
mcp_server_command: /path/to/mcp-server-pm
mcp_database_path: /path/to/database.db

# AI providers
ai_providers:
  claude:
    cli_command: claude
    cli_args:
      - "--dangerously-skip-permissions"
      - "--max-turns"
      - "50"

# Agents (passkeyのみ - ai_type等はMCPから取得)
agents:
  agt_developer:
    passkey: secret123
  agt_reviewer:
    passkey: ${REVIEWER_PASSKEY}  # 環境変数展開対応

log_directory: /tmp/coordinator_logs
```

### バックグラウンド実行

```bash
nohup python -m aiagent_runner --coordinator -v > coordinator.log 2>&1 &
```

---

## 設定の優先順位

1. **コマンドライン引数** (`--polling-interval` 等)
2. **指定した設定ファイル** (`-c /path/to/config.yaml`)
3. **デフォルト設定** (`runner/config/coordinator_default.yaml`)
4. **組み込みデフォルト値**

---

## 動作フロー

1. MCPサーバーに接続（Unixソケット）
2. `list_active_projects_with_agents()` で全プロジェクト・エージェントを取得
3. 各(agent_id, project_id)ペアに対して `should_start()` を呼び出し
4. 作業が必要な場合、Agent Instance（Claude CLI等）をスポーン
5. Agent Instanceが `authenticate` → `get_my_task` → 実行 → `report_completed`
6. 待機して2に戻る

---

## 前提条件

- MCPサーバーが起動していること
- エージェントがアプリで登録済みで、passkeyが設定されていること
- 該当エージェントがプロジェクトに割り当てられていること
- タスクが `in_progress` ステータスであること

---

## Legacy Runnerモード（非推奨）

1エージェント = 1デーモン の旧アーキテクチャ。

```bash
# 非推奨: Coordinatorモードを使用してください
aiagent-runner --agent-id <AGENT_ID> --passkey <PASSKEY> --project-id <PROJECT_ID>
```

---

## 開発

```bash
pip install -e ".[dev]"
pytest
```
