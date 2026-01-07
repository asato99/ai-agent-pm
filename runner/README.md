# AI Agent PM オーケストレーションデーモン

特定のエージェントとしてタスク実行を監視・実行する常駐プロセス。

---

## 起動方法

**1エージェント = 1デーモン** で起動する。

```bash
cd runner
pip install -e .
aiagent-runner --agent-id <AGENT_ID> --passkey <PASSKEY> --working-directory <PROJECT_DIR>
```

### 例

```bash
# エージェント agt_backend_dev として起動
aiagent-runner --agent-id agt_backend_dev --passkey secret123 --working-directory /projects/backend
```

### 設定ファイルを使う場合

```yaml
# backend_dev.yaml
agent_id: agt_backend_dev
passkey: secret123
working_directory: /projects/backend
polling_interval: 5
cli_command: claude
cli_args:
  - "--dangerously-skip-permissions"
```

```bash
aiagent-runner -c backend_dev.yaml
```

### バックグラウンド実行

```bash
nohup aiagent-runner -c backend_dev.yaml > backend_dev.log 2>&1 &
```

---

## 前提条件

- MCP Serverが起動していること
- エージェントがアプリで登録済みで、passkeyが設定されていること
- 該当エージェントにタスクが割り当てられていること

---

## 動作

1. 指定された`agent_id`でMCPサーバーに認証
2. そのエージェントに割り当てられたin_progressタスクをポーリング
3. タスク検出時、Claude CLI等を起動して実行
4. 完了報告後、待機して2に戻る

---

## 開発

```bash
pip install -e ".[dev]"
pytest
```
