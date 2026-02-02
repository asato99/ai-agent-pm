# Multi-CLI Provider Support Design

## 概要

現在のCoordinatorはClaude CLI専用の設計になっているため、Gemini CLIなど他のAI CLIツールとの互換性がない。本設計書では、複数のCLIプロバイダーをサポートするための拡張案を提案する。

## 現状の問題

### Claude CLI vs Gemini CLI の違い

| 項目 | Claude CLI | Gemini CLI |
|------|-----------|------------|
| MCP設定 | `--mcp-config JSON` (インライン) | `.gemini/settings.json` (ファイル) または `gemini mcp add` |
| モデル指定 | `--model <model-id>` | `-m <model-id>` |
| 自動承認 | `--dangerously-skip-permissions` | `-y` または `--yolo` |
| プロンプト | `-p <prompt>` | `-p <prompt>` または positional |
| MCP信頼設定 | MCP config内で指定 | `--trust` フラグ |

### 現在のCoordinator実装の問題点

```python
# coordinator.py - 現在の実装（Claude固有）
cmd = [
    cli_command,
    *cli_args,
    "--mcp-config", mcp_config,  # ← Claude固有
]
if model:
    cmd.extend(["--model", model])  # ← Claude固有
```

## 設計案

### 案A: ファイルベースMCP設定（推奨）

Gemini CLIが `.gemini/settings.json` を読み込む仕様を利用し、作業ディレクトリにMCP設定ファイルを自動生成する。

```
working_directory/
├── .gemini/
│   └── settings.json  ← Coordinator が自動生成
└── (作業ファイル)
```

**実装:**

```python
def _prepare_mcp_config(self, working_dir: str, provider: str, socket_path: str) -> None:
    """プロバイダーに応じたMCP設定を準備"""
    if provider == "gemini":
        gemini_dir = Path(working_dir) / ".gemini"
        gemini_dir.mkdir(parents=True, exist_ok=True)

        config = {
            "mcpServers": {
                "agent-pm": {
                    "command": "nc",
                    "args": ["-U", socket_path],
                    "trust": True
                }
            }
        }

        with open(gemini_dir / "settings.json", "w") as f:
            json.dump(config, f, indent=2)
```

**メリット:**
- シンプルな実装
- Gemini CLIの標準機能を活用
- 作業ディレクトリ単位で分離

**デメリット:**
- ファイルが残る（クリーンアップが必要）

### 案B: プロバイダー固有CLIビルダー

各プロバイダー用のCLIコマンドビルダークラスを作成。

```python
class CLIBuilder(ABC):
    @abstractmethod
    def build_command(self, config: ProviderConfig, context: SpawnContext) -> list[str]:
        pass

class ClaudeCLIBuilder(CLIBuilder):
    def build_command(self, config, context):
        cmd = [config.cli_command, *config.cli_args]
        cmd.extend(["--mcp-config", context.mcp_config_json])
        if context.model:
            cmd.extend(["--model", context.model])
        cmd.extend(["-p", context.prompt])
        return cmd

class GeminiCLIBuilder(CLIBuilder):
    def build_command(self, config, context):
        # 事前にMCP設定ファイルを作成
        self._prepare_mcp_config(context.working_dir, context.socket_path)

        cmd = [config.cli_command, *config.cli_args]
        if context.model:
            cmd.extend(["-m", context.model])
        cmd.extend(["-p", context.prompt])
        return cmd
```

**メリット:**
- 拡張性が高い（OpenAI CLI等も追加可能）
- プロバイダー固有のロジックを分離
- テストしやすい

**デメリット:**
- コード量が増える
- 新プロバイダー追加時にコード変更が必要

### 案C: 設定駆動型（YAML拡張）

```yaml
ai_providers:
  claude:
    cli_command: claude
    cli_args:
      - "--dangerously-skip-permissions"
      - "--max-turns"
      - "50"
    mcp_method: inline_json          # inline_json | file_based
    model_flag: "--model"
    prompt_flag: "-p"

  gemini:
    cli_command: gemini
    cli_args:
      - "-y"
    mcp_method: file_based           # .gemini/settings.json を生成
    mcp_config_path: ".gemini/settings.json"
    model_flag: "-m"
    prompt_flag: "-p"
```

**メリット:**
- 設定ファイルで新プロバイダー追加可能
- コード変更なしで拡張
- 運用者が調整可能

**デメリット:**
- 設定が複雑になる
- バリデーションが必要

## 推奨案: 案A + 案Bのハイブリッド

1. **短期（今回）**: 案Aのファイルベース方式でGemini対応
2. **中期**: 案Bのビルダーパターンでリファクタリング
3. **長期**: 案Cの設定駆動型への移行を検討

## 実装計画

### Phase 1: Gemini基本対応（案A）

**変更ファイル:**
- `runner/src/aiagent_runner/coordinator.py`
  - `_spawn_instance()` にプロバイダー分岐追加
  - `_prepare_gemini_mcp_config()` メソッド追加

**作業量:** 約30行の追加

```python
def _spawn_instance(self, ...):
    # Gemini用MCP設定ファイル生成
    if provider == "gemini":
        self._prepare_gemini_mcp_config(working_dir, socket_path)

    # コマンド構築
    cmd = [cli_command, *cli_args]

    # MCP設定（プロバイダーによって異なる）
    if provider != "gemini":  # Claude, OpenAI等
        cmd.extend(["--mcp-config", mcp_config])

    # モデル指定（フラグが異なる）
    if model:
        model_flag = "-m" if provider == "gemini" else "--model"
        cmd.extend([model_flag, model])

    cmd.extend(["-p", prompt])
```

### Phase 2: リファクタリング（案B）

将来的にプロバイダーが増えた場合、ビルダーパターンへ移行。

## 検証項目

1. **MCP接続**: Gemini CLI が agent-pm MCP サーバーに接続できること
2. **ツール実行**: `authenticate`, `get_my_task`, `report_completed` が動作すること
3. **モデル検証**: `report_model` で正しいモデル名が報告されること
4. **並行動作**: Claude/Gemini エージェントが同時に動作できること

## リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| Gemini CLIバージョン依存 | MCP設定方法が変わる可能性 | バージョンチェック、設定方法の抽象化 |
| ファイル残存 | 作業ディレクトリが汚れる | タスク完了後のクリーンアップ |
| 認証の違い | API キー管理が異なる | 環境変数で統一 |

## 結論

**推奨**: Phase 1（案A）を実装し、Gemini CLIの基本対応を行う。

- 実装コスト: 低（約30行）
- リスク: 低（ファイルベースは安定）
- 拡張性: 中（将来的にリファクタリング可能）
