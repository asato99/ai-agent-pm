# エージェント固有コンテキストディレクトリ機能 実装計画書

**設計書:** [docs/design/AGENT_CONTEXT_DIRECTORY.md](../design/AGENT_CONTEXT_DIRECTORY.md)

**開始日:** 2026-01-28
**ステータス:** 未着手

---

## 進捗サマリー

| Phase | 名称 | ステータス | 完了日 |
|-------|------|-----------|--------|
| 1 | MCPClient 拡張 | ⬜ 未着手 | - |
| 2 | coordinator.py 変更（Claude対応） | ⬜ 未着手 | - |
| 3 | .gitignore 更新 | ⬜ 未着手 | - |
| 4 | Gemini 対応 | ⬜ 未着手 | - |
| 5 | 統合テスト | ⬜ 未着手 | - |

**凡例:** ⬜ 未着手 / 🔄 進行中 / ✅ 完了 / ⏸️ 保留

---

## Phase 1: MCPClient 拡張

**目的:** Coordinator から `get_subordinate_profile` を呼び出せるようにする

### 1.1 テスト作成（RED）

**ファイル:** `runner/tests/test_mcp_client.py`

- [ ] `test_get_subordinate_profile_success`: 正常系テスト
  - モックで MCP レスポンスを返す
  - `system_prompt` が正しく取得できることを確認
- [ ] `test_get_subordinate_profile_not_found`: エージェント未存在時のエラー
- [ ] `test_get_subordinate_profile_empty_system_prompt`: system_prompt が空の場合

**テストコード例:**
```python
async def test_get_subordinate_profile_success(mock_transport):
    """get_subordinate_profile が system_prompt を正しく返すこと"""
    mock_transport.set_response({
        "success": True,
        "agent": {
            "id": "worker-01",
            "name": "Worker 01",
            "system_prompt": "You are a helpful assistant."
        }
    })

    client = MCPClient(socket_path="/tmp/test.sock")
    profile = await client.get_subordinate_profile("worker-01")

    assert profile.agent_id == "worker-01"
    assert profile.system_prompt == "You are a helpful assistant."
```

### 1.2 実装（GREEN）

**ファイル:** `runner/src/aiagent_runner/mcp_client.py`

- [ ] `SubordinateProfile` データクラス追加
  ```python
  @dataclass
  class SubordinateProfile:
      agent_id: str
      name: str
      system_prompt: str
  ```
- [ ] `get_subordinate_profile` メソッド追加

### 1.3 リファクタリング

- [ ] 型アノテーション確認
- [ ] ドキュメントコメント追加

### 1.4 進捗ログ

| 日時 | 作業内容 | 担当 |
|------|---------|------|
| - | - | - |

---

## Phase 2: coordinator.py 変更（Claude対応）

**目的:** Claude CLI をコンテキストディレクトリから起動する

### 2.1 テスト作成（RED）

**ファイル:** `runner/tests/test_coordinator.py`

#### 2.1.1 ディレクトリ作成テスト

- [ ] `test_prepare_agent_context_creates_directory`: ディレクトリ構造が正しく作成されること
  ```
  {working_dir}/.aiagent/agents/{agent_id}/.claude/
  ```
- [ ] `test_prepare_agent_context_creates_claude_md`: CLAUDE.md が作成されること
- [ ] `test_prepare_agent_context_creates_settings_json`: settings.json が作成されること

#### 2.1.2 CLAUDE.md 内容テスト

- [ ] `test_claude_md_contains_system_prompt`: system_prompt が含まれること
- [ ] `test_claude_md_contains_restrictions`: 制限指示が含まれること
- [ ] `test_claude_md_empty_system_prompt`: system_prompt が空でも動作すること

#### 2.1.3 settings.json 内容テスト

- [ ] `test_settings_json_has_additional_directories`: additionalDirectories が正しいこと

#### 2.1.4 spawn テスト

- [ ] `test_spawn_instance_uses_context_directory_as_cwd`: cwd がコンテキストディレクトリになること

**テストコード例:**
```python
def test_prepare_agent_context_creates_directory(tmp_path, coordinator):
    """コンテキストディレクトリが正しく作成されること"""
    working_dir = str(tmp_path / "project")
    os.makedirs(working_dir)

    context_dir = coordinator._prepare_agent_context(
        agent_id="worker-01",
        working_dir=working_dir,
        provider="claude"
    )

    expected = Path(working_dir) / ".aiagent" / "agents" / "worker-01"
    assert context_dir == str(expected)
    assert (expected / ".claude" / "CLAUDE.md").exists()
    assert (expected / ".claude" / "settings.json").exists()

def test_claude_md_contains_system_prompt(tmp_path, coordinator):
    """CLAUDE.md に system_prompt が含まれること"""
    working_dir = str(tmp_path / "project")
    os.makedirs(working_dir)

    # Mock get_subordinate_profile to return system_prompt
    coordinator.mcp_client.get_subordinate_profile = AsyncMock(
        return_value=SubordinateProfile(
            agent_id="worker-01",
            name="Worker 01",
            system_prompt="You are a coding assistant."
        )
    )

    coordinator._prepare_agent_context("worker-01", working_dir, "claude")

    claude_md = Path(working_dir) / ".aiagent" / "agents" / "worker-01" / ".claude" / "CLAUDE.md"
    content = claude_md.read_text()

    assert "You are a coding assistant." in content
    assert "DO NOT modify any files within `.aiagent/`" in content
```

### 2.2 実装（GREEN）

**ファイル:** `runner/src/aiagent_runner/coordinator.py`

- [ ] `_prepare_agent_context` メソッド追加
- [ ] `_write_claude_md` ヘルパー追加
- [ ] `_write_claude_settings` ヘルパー追加
- [ ] `_spawn_instance` の cwd 変更ロジック追加

**実装詳細:**
```python
async def _prepare_agent_context(
    self,
    agent_id: str,
    working_dir: str,
    provider: str
) -> str:
    """エージェント用コンテキストディレクトリを準備する"""
    context_dir = Path(working_dir) / ".aiagent" / "agents" / agent_id

    if provider == "claude":
        config_dir = context_dir / ".claude"
        config_dir.mkdir(parents=True, exist_ok=True)

        # system_prompt 取得
        try:
            profile = await self.mcp_client.get_subordinate_profile(agent_id)
            system_prompt = profile.system_prompt
        except Exception as e:
            logger.warning(f"Failed to get subordinate profile: {e}")
            system_prompt = ""

        self._write_claude_md(config_dir, system_prompt)
        self._write_claude_settings(config_dir, working_dir)

        return str(context_dir)

    # 他のプロバイダーは従来通り
    return working_dir
```

### 2.3 リファクタリング

- [ ] エラーハンドリング見直し
- [ ] ログ出力追加

### 2.4 進捗ログ

| 日時 | 作業内容 | 担当 |
|------|---------|------|
| - | - | - |

---

## Phase 3: .gitignore 更新

**目的:** `.aiagent/agents/` を git 管理対象外にする

### 3.1 テスト作成（RED）

**ファイル:** `runner/tests/test_coordinator.py`

- [ ] `test_gitignore_includes_agents_directory`: .gitignore に `agents/` が含まれること

**テストコード例:**
```python
def test_gitignore_includes_agents_directory(tmp_path, coordinator):
    """生成される .gitignore に agents/ が含まれること"""
    working_dir = str(tmp_path / "project")
    os.makedirs(working_dir)

    coordinator._prepare_agent_context("worker-01", working_dir, "claude")

    gitignore = Path(working_dir) / ".aiagent" / ".gitignore"
    content = gitignore.read_text()

    assert "agents/" in content
```

### 3.2 実装（GREEN）

**ファイル:** `runner/src/aiagent_runner/coordinator.py`

- [ ] `.aiagent/.gitignore` 生成ロジック追加（または既存があれば更新）

### 3.3 進捗ログ

| 日時 | 作業内容 | 担当 |
|------|---------|------|
| - | - | - |

---

## Phase 4: Gemini 対応

**目的:** Gemini CLI も同様にコンテキストディレクトリから起動する

### 4.1 事前調査

- [ ] Gemini CLI で `additionalDirectories` 相当の機能があるか調査
- [ ] Gemini CLI で system_prompt を設定ファイルから渡せるか調査
- [ ] 調査結果をドキュメント化

**調査結果:**
```
（調査後に記入）
```

### 4.2 テスト作成（RED）

**ファイル:** `runner/tests/test_coordinator.py`

- [ ] `test_prepare_agent_context_gemini_creates_directory`: Gemini 用ディレクトリ作成
- [ ] `test_prepare_agent_context_gemini_settings_json`: settings.json の内容

### 4.3 実装（GREEN）

**ファイル:** `runner/src/aiagent_runner/coordinator.py`

- [ ] `_prepare_agent_context` に Gemini 対応追加
- [ ] `_write_gemini_settings` ヘルパー追加

### 4.4 進捗ログ

| 日時 | 作業内容 | 担当 |
|------|---------|------|
| - | - | - |

---

## Phase 5: 統合テスト

**目的:** 実際のエージェント起動フローで動作確認

### 5.1 テストシナリオ

#### 5.1.1 基本動作確認

- [ ] エージェントを起動する
- [ ] `.aiagent/agents/{agent_id}/.claude/` が作成されることを確認
- [ ] CLAUDE.md に system_prompt が含まれることを確認
- [ ] settings.json に additionalDirectories が含まれることを確認

#### 5.1.2 実作業ディレクトリアクセス確認

- [ ] エージェントが `{manager_working_dir}` のファイルを読み取れることを確認
- [ ] エージェントが `{manager_working_dir}` のファイルを編集できることを確認

#### 5.1.3 制限確認

- [ ] エージェントに `.aiagent/` 編集を指示し、拒否されることを確認（指示ベース）

### 5.2 パイロットテスト更新

**ファイル:** `web-ui/e2e/pilot/`

- [ ] 既存パイロットテストが動作することを確認
- [ ] 必要に応じてテスト更新

### 5.3 進捗ログ

| 日時 | 作業内容 | 担当 |
|------|---------|------|
| - | - | - |

---

## リスクと対策

| リスク | 影響 | 対策 |
|-------|------|------|
| `get_subordinate_profile` が失敗する | system_prompt が空になる | 空文字でフォールバック、ログ出力 |
| ディレクトリ作成権限がない | エージェント起動失敗 | フォールバックで従来 cwd を使用 |
| Gemini が additionalDirectories 未対応 | Gemini は従来動作 | Claude のみコンテキストディレクトリ起動 |

---

## ロールバック計画

問題発生時は以下でロールバック可能：

1. `_spawn_instance` の cwd 変更を元に戻す
2. `_prepare_agent_context` 呼び出しをコメントアウト

**ロールバックコミット:** （実装後に記入）

---

## 完了条件

- [ ] Phase 1〜3 の全テストが GREEN
- [ ] Phase 5 の統合テストが成功
- [ ] 設計書のレビュー完了
- [ ] CHANGELOG への追記

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-28 | 初版作成 |
