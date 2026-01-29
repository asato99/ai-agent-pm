# エージェント固有コンテキストディレクトリ機能 設計書

## 1. 概要

各エージェントを専用のコンテキストディレクトリから起動し、実作業ディレクトリにアクセスさせる機能。

## 2. 背景と目的

### 2.1 現状の問題

現在、Claude Code / Gemini CLI は **プロジェクトのワーキングディレクトリ** から直接起動されている。

```
{manager_working_dir}/   ← Claude の cwd（現状）
├── src/
└── .aiagent/
    └── logs/{agent_id}/
```

**問題点:**
1. エージェント固有の設定（CLAUDE.md, settings.json）を配置できない
2. 複数エージェントが同じディレクトリで動作し、設定が競合する可能性
3. system_prompt を MCP ツール経由で渡す必要があり、プロンプトが肥大化

### 2.2 目的

各エージェントを **専用コンテキストディレクトリ** から起動し、実作業ディレクトリにアクセスさせる。

**メリット:**
- エージェントごとに異なる CLAUDE.md / system_prompt を適用可能
- プロンプトがシンプルになる（system_prompt を CLAUDE.md に分離）
- 将来的にエージェント固有の設定拡張が容易

---

## 3. PoC 検証結果

### 3.1 検証概要

コンテキストディレクトリ（`.aiagent/agents/{agent_id}/`）から CLI を起動し、親ディレクトリのファイルを編集できるか検証。

**検証日:** 2026-01-28
**検証場所:** `poc/context-dir-test/`

### 3.2 Claude Code

| 項目 | 結果 |
|------|------|
| 親ディレクトリ読み取り | ✅ 成功 |
| 親ディレクトリ書き込み | ✅ 成功 |
| 設定方法 | `.claude/settings.json` の `additionalDirectories` |

**設定ファイル:**
```json
{
  "permissions": {
    "additionalDirectories": ["{manager_working_dir}"]
  }
}
```

### 3.3 Gemini CLI

| 項目 | 結果 |
|------|------|
| 親ディレクトリ読み取り | ✅ 成功（フラグ使用時） |
| 親ディレクトリ書き込み | ✅ 成功（フラグ使用時） |
| 設定方法 | `--include-directories` **コマンドラインフラグ** |

**⚠️ 重要な制約:**

`settings.json` の `includeDirectories` 設定は **既知のバグにより無視される**。

- [Issue #5512](https://github.com/google-gemini/gemini-cli/issues/5512)
- [Issue #7365](https://github.com/google-gemini/gemini-cli/issues/7365)

**ワークアラウンド:**
```bash
gemini --include-directories {manager_working_dir}
```

### 3.4 プロバイダー比較

| 項目 | Claude | Gemini |
|------|--------|--------|
| 追加ディレクトリ設定 | `additionalDirectories` | `--include-directories` フラグ |
| 設定ファイルからの読み込み | ✅ 動作 | ❌ バグで無視 |
| システムプロンプトファイル | `CLAUDE.md` | `GEMINI.md` |
| コマンドラインでの指定 | 不要 | **必須** |

---

## 4. ディレクトリ構造

### 4.1 最終構造

```
{manager_working_dir}/                 ← 実作業ディレクトリ（マネージャーのワーキングディレクトリ）
├── src/
├── ...
│
├── .ai-pm/                            ← プロジェクト管理データ（変更なし）
│   └── agents/{agent_id}/
│       └── chat.jsonl
│
└── .aiagent/                          ← エージェント実行環境
    ├── .gitignore
    ├── logs/{agent_id}/               ← 既存: 実行ログ
    │   └── 20260128_143022.log
    │
    └── agents/{agent_id}/             ← 新規: コンテキストディレクトリ
        ├── .claude/                   ← Claude CLI 用
        │   ├── CLAUDE.md
        │   ├── settings.json
        │   └── skills/                ← スキル配置（AGENT_SKILLS.md 参照）
        │       └── {skill_name}/
        │           └── SKILL.md
        │
        └── .gemini/                   ← Gemini CLI 用
            ├── GEMINI.md
            ├── settings.json
            └── skills/                ← スキル配置（AGENT_SKILLS.md 参照）
                └── {skill_name}/
                    └── SKILL.md
```

### 4.2 概念の分離

| ディレクトリ | 目的 | 管理主体 |
|-------------|------|---------|
| `.ai-pm/` | プロジェクト管理データ（タスク、チャット履歴） | AI Agent PM アプリ |
| `.aiagent/logs/` | 実行ログ | Coordinator |
| `.aiagent/agents/` | エージェント起動コンテキスト | Coordinator |

---

## 5. ファイル生成仕様

### 5.1 CLAUDE.md

**配置場所:** `.aiagent/agents/{agent_id}/.claude/CLAUDE.md`

**テンプレート:**
```markdown
# Agent Context

{system_prompt}

---

## Working Directory

Your working directory is: `{manager_working_dir}`

All file operations should be performed in this directory, NOT in the current context directory.

## Restrictions

**DO NOT** modify any files within `.aiagent/`. This directory is managed by AI Agent PM.
```

**生成タイミング:** `_spawn_instance` 呼び出し時（毎回上書き）

**system_prompt 取得方法:**
- `get_subordinate_profile(agent_id)` MCP ツールを呼び出し
- レスポンスの `system_prompt` フィールドを使用

### 5.2 settings.json (Claude)

**配置場所:** `.aiagent/agents/{agent_id}/.claude/settings.json`

**内容:**
```json
{
  "permissions": {
    "additionalDirectories": [
      "{manager_working_dir}"
    ]
  }
}
```

### 5.3 GEMINI.md

**配置場所:** `.aiagent/agents/{agent_id}/.gemini/GEMINI.md`

**テンプレート:**
```markdown
# Agent Context

{system_prompt}

---

## Working Directory

Your working directory is: `{manager_working_dir}`

All file operations should be performed in this directory, NOT in the current context directory.

## Restrictions

**DO NOT** modify any files within `.aiagent/`. This directory is managed by AI Agent PM.
```

### 5.4 settings.json (Gemini)

**配置場所:** `.aiagent/agents/{agent_id}/.gemini/settings.json`

**内容:**
```json
{
  "mcpServers": {
    "agent-pm": {
      "command": "nc",
      "args": ["-U", "{socket_path}"],
      "trust": true
    }
  }
}
```

**注:** `includeDirectories` は設定ファイルからは機能しないため、コマンドラインフラグで指定。

---

## 6. 起動パラメータ

### 6.1 共通

| 項目 | 値 |
|------|-----|
| cwd | `{manager_working_dir}/.aiagent/agents/{agent_id}/` |
| 実作業ディレクトリ | `{manager_working_dir}` |

### 6.2 Claude CLI

| 項目 | 設定 |
|-----|------|
| cwd | `.aiagent/agents/{agent_id}/` |
| CLAUDE.md | 自動生成（system_prompt + 制限指示） |
| settings.json | `additionalDirectories` で実作業ディレクトリを許可 |
| MCP設定 | `--mcp-config` フラグで一時ファイル指定（既存） |
| 追加フラグ | なし |

### 6.3 Gemini CLI

| 項目 | 設定 |
|-----|------|
| cwd | `.aiagent/agents/{agent_id}/` |
| GEMINI.md | 自動生成（system_prompt + 制限指示） |
| settings.json | MCP 設定のみ（`includeDirectories` は機能しない） |
| **追加フラグ** | `--include-directories {manager_working_dir}` **必須** |

---

## 7. coordinator.py 変更仕様

### 7.1 新規メソッド: `_prepare_agent_context`

```python
async def _prepare_agent_context(
    self,
    agent_id: str,
    working_dir: str,
    provider: str
) -> str:
    """
    エージェント用コンテキストディレクトリを準備する。

    Args:
        agent_id: エージェントID
        working_dir: マネージャーのワーキングディレクトリ
        provider: プロバイダー名 ("claude", "gemini", etc.)

    Returns:
        コンテキストディレクトリのパス（cwd として使用）
    """
```

**処理フロー:**
1. ディレクトリ作成: `{working_dir}/.aiagent/agents/{agent_id}/`
2. プロバイダー別設定ディレクトリ作成: `.claude/` or `.gemini/`
3. system_prompt 取得: `get_subordinate_profile(agent_id)`
4. CLAUDE.md / GEMINI.md 生成
5. settings.json 生成
6. コンテキストディレクトリパスを返す

### 7.2 `_spawn_instance` の変更

```python
def _spawn_instance(self, ...):
    # 変更前
    # cwd=working_dir

    # 変更後
    if provider in ("claude", "gemini"):
        cwd = await self._prepare_agent_context(agent_id, working_dir, provider)
    else:
        cwd = working_dir

    # Gemini の場合は --include-directories フラグを追加
    if provider == "gemini":
        cmd.extend(["--include-directories", working_dir])
```

### 7.3 MCPClient への追加

```python
async def get_subordinate_profile(self, agent_id: str) -> SubordinateProfile:
    """get_subordinate_profile ツールを呼び出す"""
```

---

## 8. .gitignore 更新

`.aiagent/.gitignore` の内容（既存 + 新規）:

```gitignore
# AI Agent PM - auto-generated
logs/
agents/
```

---

## 9. 考慮事項

### 9.1 ディレクトリのライフサイクル

| タイミング | 動作 |
|-----------|------|
| spawn 時 | ディレクトリ作成、CLAUDE.md / GEMINI.md / settings.json 上書き |
| セッション終了後 | ディレクトリ保持（次回起動時に再利用） |
| 明示的クリーンアップ | 将来機能として検討 |

### 9.2 エラーハンドリング

| エラー | 対応 |
|-------|------|
| `get_subordinate_profile` 失敗 | system_prompt を空にして続行 |
| ディレクトリ作成失敗 | 従来の working_dir から起動（フォールバック） |
| settings.json 書き込み失敗 | ログ出力して続行 |

### 9.3 セキュリティ

- CLAUDE.md / GEMINI.md で `.aiagent/` 編集禁止を指示
- ただし、これは指示であり強制ではない（AI が従わない可能性あり）
- より強制的な制限が必要な場合は `allowedDirectories` の検討が必要

---

## 10. 解決済み事項

| 項目 | 結果 | 対応 |
|-----|------|-----|
| Gemini の additionalDirectories 相当 | `includeDirectories` あり（設定ファイルはバグ） | `--include-directories` フラグ使用 |
| Gemini の system_prompt 設定方法 | `GEMINI.md` が使用可能 | ファイル生成で対応 |

## 11. 未解決事項

| 項目 | 状態 | 対応方針 |
|-----|------|---------|
| chat.jsonl との連携（--resume 相当） | スコープ外 | 別フェーズで検討 |
| Gemini settings.json バグの修正待ち | 外部依存 | フラグで回避、将来的に設定ファイル移行 |

---

## 12. 実装計画

### Phase 1: MCPClient 拡張

**対象ファイル:** `runner/src/aiagent_runner/mcp_client.py`

**タスク:**
1. `get_subordinate_profile` メソッド追加
2. レスポンス型定義

**見積もり:** 小

---

### Phase 2: coordinator.py 変更（Claude対応）

**対象ファイル:** `runner/src/aiagent_runner/coordinator.py`

**タスク:**
1. `_prepare_agent_context` メソッド追加
2. `_write_claude_md` ヘルパー追加
3. `_write_claude_settings` ヘルパー追加
4. `_spawn_instance` の cwd 変更

**見積もり:** 中

---

### Phase 3: coordinator.py 変更（Gemini対応）

**対象ファイル:** `runner/src/aiagent_runner/coordinator.py`

**タスク:**
1. `_write_gemini_md` ヘルパー追加
2. `_spawn_instance` に `--include-directories` フラグ追加

**見積もり:** 小

---

### Phase 4: .gitignore 更新

**対象:** coordinator.py 内の `.aiagent/.gitignore` 生成ロジック

**タスク:**
1. `agents/` を .gitignore に追加

**見積もり:** 小

---

### Phase 5: 統合テスト

**タスク:**
1. パイロットテストでエージェント起動を確認
2. `.aiagent/agents/{agent_id}/.claude/` が作成されることを検証
3. CLAUDE.md / GEMINI.md に system_prompt が含まれることを検証
4. 実作業ディレクトリのファイル編集が可能なことを検証

**見積もり:** 中

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-28 | 初版作成 |
| 2026-01-28 | PoC 検証結果を反映: Claude は設定ファイル、Gemini はフラグで対応 |
| 2026-01-29 | skills/ ディレクトリ追加（AGENT_SKILLS.md との整合性） |
