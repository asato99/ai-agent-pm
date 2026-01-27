# スポーンエラー保護機能 設計書

## 概要

Coordinatorがエージェントをスポーンする際、エラーが発生した場合に連続スポーンを防止する保護機能を実装する。

### 背景

- 現状: エラー終了後、次のポーリング（2秒後）で再スポーンされる
- 問題: クォータ制限エラー等の場合、連続スポーンによりリソースを急速に消費
- 事例: Gemini APIのクォータ制限（23分待機必要）に対して、2秒ごとに再スポーンが発生

## テスト計画（テストファースト）

### Phase 1: ユニットテスト（RED → GREEN）

実装前に以下のテストを作成し、失敗することを確認する。

#### 1.1 クールダウン基本機能

```python
# tests/test_cooldown.py

class TestCooldownManager:
    """クールダウン管理のテスト"""

    def test_no_cooldown_initially(self):
        """初期状態ではクールダウンなし"""
        manager = CooldownManager(default_seconds=60)
        key = AgentInstanceKey("agt_001", "prj_001")

        assert manager.check(key) is None

    def test_cooldown_set_on_error(self):
        """エラー終了時にクールダウンが設定される"""
        manager = CooldownManager(default_seconds=60)
        key = AgentInstanceKey("agt_001", "prj_001")

        manager.set(key, exit_code=1, reason="error")

        entry = manager.check(key)
        assert entry is not None
        assert entry.reason == "error"
        assert 59 <= (entry.until - datetime.now()).total_seconds() <= 61

    def test_cooldown_not_set_on_success(self):
        """正常終了時はクールダウンなし"""
        manager = CooldownManager(default_seconds=60)
        key = AgentInstanceKey("agt_001", "prj_001")

        manager.set(key, exit_code=0, reason="success")

        assert manager.check(key) is None

    def test_cooldown_cleared_on_success(self):
        """既存クールダウンが正常終了でクリアされる"""
        manager = CooldownManager(default_seconds=60)
        key = AgentInstanceKey("agt_001", "prj_001")

        # エラーでクールダウン設定
        manager.set(key, exit_code=1, reason="error")
        assert manager.check(key) is not None

        # 正常終了でクリア
        manager.set(key, exit_code=0, reason="success")
        assert manager.check(key) is None

    def test_cooldown_expires(self):
        """クールダウン期間終了後にNone"""
        manager = CooldownManager(default_seconds=1)  # 1秒
        key = AgentInstanceKey("agt_001", "prj_001")

        manager.set(key, exit_code=1, reason="error")
        assert manager.check(key) is not None

        time.sleep(1.1)  # 期間終了待ち

        assert manager.check(key) is None

    def test_consecutive_error_count(self):
        """連続エラー回数がカウントされる"""
        manager = CooldownManager(default_seconds=60)
        key = AgentInstanceKey("agt_001", "prj_001")

        manager.set(key, exit_code=1, reason="error")
        assert manager.check(key).consecutive_errors == 1

        manager.set(key, exit_code=1, reason="error")
        assert manager.check(key).consecutive_errors == 2

        manager.set(key, exit_code=1, reason="error")
        assert manager.check(key).consecutive_errors == 3
```

#### 1.2 クォータエラー検出

```python
class TestQuotaDetection:
    """クォータエラー検出のテスト"""

    def test_detect_gemini_quota_with_time(self):
        """Geminiクォータエラーから待機時間を抽出"""
        log_content = """
        Error when talking to Gemini API
        TerminalQuotaError: You have exhausted your capacity on this model.
        Your quota will reset after 22m55s.
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        # 22分55秒 = 1375秒、+10%マージン = 約1512秒
        assert seconds is not None
        assert 1500 <= seconds <= 1520

    def test_detect_gemini_quota_without_time(self):
        """Geminiクォータエラー（時間なし）でデフォルト値"""
        log_content = """
        TerminalQuotaError: Quota exhausted
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        assert seconds == 1800  # デフォルト30分

    def test_detect_claude_rate_limit(self):
        """Claudeレートリミットエラーを検出"""
        log_content = """
        RateLimitError: Too many requests. Please retry after 120 seconds.
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        assert seconds is not None
        assert 130 <= seconds <= 140  # 120秒 + 10%マージン

    def test_detect_generic_quota(self):
        """汎用クォータエラーを検出"""
        log_content = """
        Error: API quota exhausted. Please wait.
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        assert seconds == 1800  # デフォルト30分

    def test_no_quota_error(self):
        """クォータ以外のエラーはNone"""
        log_content = """
        Error: Connection timeout
        Network error occurred
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        assert seconds is None

    def test_max_cooldown_cap(self):
        """最大クールダウン時間でキャップされる"""
        log_content = """
        Your quota will reset after 120m0s.
        """

        detector = QuotaErrorDetector(max_seconds=3600)
        seconds = detector.detect(log_content)

        assert seconds == 3600  # 最大1時間でキャップ
```

#### 1.3 Coordinator統合

```python
class TestCoordinatorCooldown:
    """Coordinatorへの統合テスト"""

    @pytest.fixture
    def coordinator(self, mock_mcp_client):
        config = CoordinatorConfig(
            error_protection=ErrorProtectionConfig(
                enabled=True,
                default_cooldown_seconds=60,
                quota_detection_enabled=True
            )
        )
        return Coordinator(config)

    async def test_spawn_skipped_during_cooldown(self, coordinator):
        """クールダウン中はスポーンがスキップされる"""
        key = AgentInstanceKey("agt_001", "prj_001")

        # クールダウンを設定
        coordinator._cooldown_manager.set(key, exit_code=1, reason="error")

        # スポーン判定
        should_spawn = coordinator._should_spawn(key)

        assert should_spawn is False

    async def test_spawn_allowed_after_cooldown(self, coordinator):
        """クールダウン終了後はスポーン可能"""
        coordinator.config.error_protection.default_cooldown_seconds = 1
        key = AgentInstanceKey("agt_001", "prj_001")

        # クールダウンを設定
        coordinator._cooldown_manager.set(key, exit_code=1, reason="error")
        assert coordinator._should_spawn(key) is False

        # 期間終了待ち
        await asyncio.sleep(1.1)

        assert coordinator._should_spawn(key) is True

    async def test_cooldown_set_on_process_error(self, coordinator, tmp_path):
        """プロセスエラー終了時にクールダウンが自動設定される"""
        key = AgentInstanceKey("agt_001", "prj_001")
        log_file = tmp_path / "test.log"
        log_file.write_text("Error: Something went wrong")

        # エラー終了をシミュレート
        coordinator._handle_process_exit(key, exit_code=1, log_file=str(log_file))

        entry = coordinator._cooldown_manager.check(key)
        assert entry is not None
        assert entry.reason == "error"

    async def test_quota_cooldown_from_log(self, coordinator, tmp_path):
        """ログからクォータエラーを検出してクールダウン設定"""
        key = AgentInstanceKey("agt_001", "prj_001")
        log_file = tmp_path / "test.log"
        log_file.write_text("TerminalQuotaError: quota will reset after 10m0s")

        coordinator._handle_process_exit(key, exit_code=1, log_file=str(log_file))

        entry = coordinator._cooldown_manager.check(key)
        assert entry is not None
        assert entry.reason == "quota"
        assert 650 <= (entry.until - datetime.now()).total_seconds() <= 670  # 10分 + 10%
```

### Phase 2: 統合テスト

```python
# tests/integration/test_spawn_protection.py

class TestSpawnProtectionIntegration:
    """スポーン保護の統合テスト"""

    async def test_no_rapid_respawn_on_error(self, coordinator, mock_mcp):
        """エラー後に即時再スポーンされない"""
        # タスクを設定
        mock_mcp.get_agent_action.return_value = ActionResult(action="start")

        # 1回目のスポーン
        await coordinator._run_once()
        assert coordinator._spawn_count == 1

        # プロセスをエラー終了させる
        coordinator._simulate_process_exit(exit_code=1)

        # 2回目のポーリング - クールダウン中なのでスポーンされない
        await coordinator._run_once()
        assert coordinator._spawn_count == 1  # 変わらない

    async def test_quota_error_respected(self, coordinator, mock_mcp, tmp_path):
        """クォータエラー時に指定時間スキップ"""
        # クォータエラーのログを準備
        log_file = tmp_path / "quota_error.log"
        log_file.write_text("quota will reset after 5m0s")

        # エラー終了
        coordinator._handle_process_exit(
            key=AgentInstanceKey("agt_001", "prj_001"),
            exit_code=1,
            log_file=str(log_file)
        )

        # 5分間はスポーンがスキップされることを確認
        entry = coordinator._cooldown_manager.check(
            AgentInstanceKey("agt_001", "prj_001")
        )
        assert entry.reason == "quota"
        assert (entry.until - datetime.now()).total_seconds() > 300
```

## 対策仕様

### 1. 通常エラー時のクールダウン

エラー終了したエージェント/プロジェクトの組み合わせに対して、一定時間スポーンをスキップする。

| 項目 | 値 |
|------|-----|
| デフォルトクールダウン時間 | 60秒 |
| 設定可能 | Yes（coordinator_config.yaml） |
| 適用単位 | (agent_id, project_id) ペア |

### 2. クォータエラー検出と動的待機

クォータ制限エラーを検出し、指定された待機時間を設定する。

#### 検出パターン

| パターン | 抽出方法 | デフォルト値 |
|---------|---------|------------|
| `quota will reset after (\d+)m(\d+)s` | 時間抽出 | - |
| `TerminalQuotaError` | - | 1800秒（30分） |
| `retry after (\d+)` | 秒数抽出 | - |
| `RateLimitError` | - | 300秒（5分） |
| `quota.*exhausted` | - | 1800秒（30分） |
| `rate limit` | - | 300秒（5分） |

## 実装詳細

### 変更対象ファイル

| ファイル | 変更内容 |
|---------|---------|
| `runner/src/aiagent_runner/cooldown.py` | **新規** クールダウン管理クラス |
| `runner/src/aiagent_runner/quota_detector.py` | **新規** クォータエラー検出クラス |
| `runner/src/aiagent_runner/coordinator.py` | クールダウン統合 |
| `runner/src/aiagent_runner/coordinator_config.py` | 設定項目追加 |
| `runner/config/coordinator_default.yaml` | デフォルト設定追加 |
| `runner/tests/test_cooldown.py` | **新規** ユニットテスト |
| `runner/tests/test_quota_detector.py` | **新規** ユニットテスト |
| `runner/tests/test_coordinator_cooldown.py` | **新規** 統合テスト |

### 設定項目

```yaml
# coordinator_config.yaml
error_protection:
  enabled: true
  default_cooldown_seconds: 60      # 通常エラー時のクールダウン
  max_cooldown_seconds: 3600        # 最大クールダウン時間（1時間）
  quota_detection_enabled: true     # クォータエラー検出
```

### データ構造

```python
@dataclass
class CooldownEntry:
    """クールダウン情報"""
    until: datetime          # クールダウン終了時刻
    reason: str              # クールダウン理由（"error", "quota"）
    error_message: str       # エラーメッセージ（ログ用）
    consecutive_errors: int  # 連続エラー回数
```

## 実装順序

1. **テスト作成（RED）**
   - `tests/test_cooldown.py` 作成
   - `tests/test_quota_detector.py` 作成
   - 全テストが失敗することを確認

2. **クールダウン管理クラス実装（GREEN）**
   - `cooldown.py` 作成
   - `test_cooldown.py` が全てパス

3. **クォータ検出クラス実装（GREEN）**
   - `quota_detector.py` 作成
   - `test_quota_detector.py` が全てパス

4. **Coordinator統合**
   - `coordinator.py` 修正
   - `coordinator_config.py` 修正
   - 統合テストがパス

5. **リファクタリング**
   - コードの整理
   - ドキュメント更新

## ログ出力

```
# クールダウン設定時
[WARNING] coordinator: Cooldown set for agt_xxx/prj_yyy: 1380s (reason: quota, consecutive: 1)

# クールダウン中のスキップ
[DEBUG] coordinator: Skipping agt_xxx/prj_yyy: in cooldown (quota, 1378s remaining)

# クールダウン終了
[INFO] coordinator: Cooldown ended for agt_xxx/prj_yyy, spawn allowed
```

## 将来の拡張

### Phase 2: エクスポネンシャルバックオフ

連続エラー時にクールダウン時間を倍増させる。

### Phase 3: エラー上限での停止

連続N回エラー後、手動介入まで停止。

### Phase 4: 通知機能

クールダウン設定時にユーザーに通知（Web UI、メール等）。

## 参照

- [Gemini CLI Rate Limits](https://ai.google.dev/pricing)
- [Claude API Rate Limits](https://docs.anthropic.com/en/docs/rate-limits)
