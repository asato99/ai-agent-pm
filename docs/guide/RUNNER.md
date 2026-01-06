# Runner セットアップガイド

## 概要

Runnerは外部プログラムとしてタスクを実行するPythonアプリケーションです。
MCPサーバーからタスクを取得し、CLIツール（claude、geminiなど）を使用して実行します。

## アーキテクチャ

```
┌─────────────────┐      MCP Protocol      ┌──────────────────┐
│   AI Agent PM   │◄─────────────────────►│     Runner       │
│   (Swift App)   │                        │   (Python)       │
└─────────────────┘                        └────────┬─────────┘
                                                    │
                                                    ▼
                                           ┌──────────────────┐
                                           │   CLI Tool       │
                                           │ (claude/gemini)  │
                                           └──────────────────┘
```

## クイックスタート

### 1. インストール

```bash
cd runner
pip install -e .
```

### 2. 環境変数を設定

```bash
export AGENT_ID="agt_xxx"        # アプリで確認
export AGENT_PASSKEY="secret"    # アプリで発行
```

### 3. Runnerを起動

```bash
# 環境変数を使用
python -m aiagent_runner

# または設定ファイルを使用
python -m aiagent_runner -c runner_config.yaml

# 詳細ログ出力
python -m aiagent_runner -v
```

### 4. アプリでタスクをin_progressに

アプリでタスクのステータスを「in_progress」に変更すると、
Runnerが自動的に検知して実行します。

## 設定

### 環境変数

| 変数名 | 必須 | デフォルト | 説明 |
|--------|------|-----------|------|
| `AGENT_ID` | ✓ | - | エージェントID |
| `AGENT_PASSKEY` | ✓ | - | エージェントのパスキー |
| `POLLING_INTERVAL` | - | 5 | ポーリング間隔（秒） |
| `CLI_COMMAND` | - | claude | 使用するCLIコマンド |
| `CLI_ARGS` | - | --dangerously-skip-permissions | CLI引数（スペース区切り） |
| `WORKING_DIRECTORY` | - | カレントディレクトリ | 作業ディレクトリ |
| `LOG_DIRECTORY` | - | ~/.aiagent-runner/logs | ログ出力先 |
| `MCP_SOCKET_PATH` | - | ~/Library/Application Support/AIAgentPM/mcp.sock | MCPソケットパス |

### 設定ファイル（YAML）

```yaml
# runner_config.yaml
agent_id: agt_xxx
passkey: your_passkey
polling_interval: 5        # ポーリング間隔（秒）
cli_command: claude        # 使用するCLI
cli_args:
  - "--dangerously-skip-permissions"
working_directory: /path/to/project
log_directory: ~/logs
```

### CLIオプション

```bash
aiagent-runner [OPTIONS]

Options:
  -c, --config PATH         設定ファイルのパス
  -v, --verbose            詳細ログを出力
  --agent-id TEXT          エージェントID（設定/環境変数より優先）
  --passkey TEXT           パスキー（設定/環境変数より優先）
  --polling-interval INT   ポーリング間隔（秒）
  --cli-command TEXT       CLIコマンド
  --working-directory PATH 作業ディレクトリ
  --log-directory PATH     ログディレクトリ
```

## 設定の優先順位

設定は以下の優先順位で適用されます（上が優先）：

1. CLIオプション
2. 設定ファイル（YAML）
3. 環境変数

## カスタマイズ

### 別のLLMを使用

#### Gemini

```yaml
cli_command: gemini
cli_args:
  - "--project"
  - "my-project"
```

#### カスタムコマンド

```yaml
cli_command: /path/to/my-llm-cli
cli_args:
  - "--custom-flag"
```

### 独自のRunnerを実装

MCPクライアントライブラリを使用して独自のRunnerを実装できます：

```python
import asyncio
from aiagent_runner.mcp_client import MCPClient
from aiagent_runner.config import RunnerConfig

async def my_custom_runner():
    # 設定を読み込み
    config = RunnerConfig.from_env()

    # MCPクライアントを初期化
    client = MCPClient()

    # 認証
    auth = await client.authenticate(config.agent_id, config.passkey)
    print(f"Authenticated as: {auth.agent_name}")

    # タスクを取得
    tasks = await client.get_pending_tasks(config.agent_id)

    for task in tasks:
        print(f"Task: {task.title}")
        # 独自の処理...

        # コンテキストを保存
        await client.save_context(
            task_id=task.task_id,
            progress="50% complete",
            findings="Found something interesting"
        )

        # ステータスを更新
        await client.update_task_status(
            task_id=task.task_id,
            status="done"
        )

if __name__ == "__main__":
    asyncio.run(my_custom_runner())
```

## プロンプト構造

Runnerが生成するプロンプトは以下の構造を持ちます：

```markdown
# Task: [タスクタイトル]

## Identification
- Task ID: [タスクID]
- Project ID: [プロジェクトID]
- Agent ID: [エージェントID]
- Agent Name: [エージェント名]
- Priority: [優先度]

## Description
[タスクの説明]

## Working Directory
Path: [作業ディレクトリ]

## Previous Context（前回のコンテキストがある場合）
**Progress**: [進捗]
**Findings**: [発見事項]
**Blockers**: [ブロッカー]
**Next Steps**: [次のステップ]

## Handoff Information（引き継ぎ情報がある場合）
**From Agent**: [前のエージェント]
**Summary**: [サマリー]
**Context**: [コンテキスト]
**Recommendations**: [推奨事項]

## Instructions
1. Complete the task as described above
2. Save your progress regularly using:
   save_context(task_id="[タスクID]", progress="...", findings="...", next_steps="...")
3. When done, update the task status using:
   update_task_status(task_id="[タスクID]", status="done")
4. If you need to hand off to another agent, use:
   create_handoff(task_id="[タスクID]", from_agent_id="[エージェントID]", summary="...", recommendations="...")
```

## 実行ログ

実行ログは以下の形式で保存されます：

```
{log_directory}/{task_id}_{timestamp}.log
```

ログ内容：
```
=== PROMPT ===
[CLIに渡されたプロンプト]

=== OUTPUT ===
[CLIの出力]
```

## トラブルシューティング

### 認証エラー

**症状**: `AuthenticationError: Invalid credentials`

**対処法**:
- `AGENT_ID`と`AGENT_PASSKEY`が正しいか確認
- アプリでエージェントの詳細画面を開き、Passkeyを再生成
- 環境変数が正しく設定されているか確認: `echo $AGENT_ID`

### MCPサーバーに接続できない

**症状**: `MCPError: Cannot connect to MCP server`

**対処法**:
- AI Agent PMアプリが起動しているか確認
- MCPソケットファイルが存在するか確認:
  ```bash
  ls -la ~/Library/Application\ Support/AIAgentPM/mcp.sock
  ```
- アプリを再起動してみる

### タスクが検出されない

**症状**: ログに `No pending tasks` が出続ける

**対処法**:
- タスクのステータスが `in_progress` か確認
- タスクの担当者が正しいエージェントか確認
- 担当者のエージェントIDとRunner設定のAGENT_IDが一致しているか確認
- ポーリング間隔を短くしてみる（`--polling-interval 1`）

### CLIコマンドが見つからない

**症状**: `ERROR: Command 'claude' not found`

**対処法**:
- CLIツールがインストールされているか確認: `which claude`
- PATHが正しく設定されているか確認
- フルパスを指定: `--cli-command /path/to/claude`

### 実行ログが見つからない

**症状**: ログディレクトリが空

**対処法**:
- `log_directory`のパーミッションを確認
- ディスク容量を確認
- 別のログディレクトリを指定してみる

### セッション切れ

**症状**: 一定時間後に `SessionExpiredError`

**説明**: セッションは1時間で期限切れになりますが、Runnerは自動的に再認証します。
エラーが継続する場合は、Passkeyを再生成してください。

## 開発

### テスト実行

```bash
cd runner
pip install -e ".[dev]"
pytest -v
```

### カバレッジレポート

```bash
pytest --cov=aiagent_runner --cov-report=html
open htmlcov/index.html
```

### 統合テスト

```bash
pytest tests/integration/ -v
```

## API リファレンス

### MCPClient

```python
class MCPClient:
    async def authenticate(agent_id: str, passkey: str) -> AuthResult
    async def get_pending_tasks(agent_id: str) -> list[TaskInfo]
    async def report_execution_start(task_id: str, agent_id: str) -> ExecutionStartResult
    async def report_execution_complete(execution_id: str, exit_code: int, ...) -> None
    async def update_task_status(task_id: str, status: str, reason: str = None) -> None
    async def save_context(task_id: str, progress: str = None, ...) -> None
```

### RunnerConfig

```python
@dataclass
class RunnerConfig:
    agent_id: str
    passkey: str
    polling_interval: int = 5
    cli_command: str = "claude"
    cli_args: list[str] = ["--dangerously-skip-permissions"]
    working_directory: Optional[str] = None
    log_directory: Optional[str] = None
    mcp_socket_path: Optional[str] = None

    @classmethod
    def from_env() -> RunnerConfig

    @classmethod
    def from_yaml(path: Path) -> RunnerConfig
```

### Runner

```python
class Runner:
    def __init__(config: RunnerConfig)
    async def start() -> None  # メインループを開始
    def stop() -> None         # ループを停止
```
