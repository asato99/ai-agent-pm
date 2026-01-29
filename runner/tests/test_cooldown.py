# tests/test_cooldown.py
# Cooldown manager unit tests (TDD - RED phase)
# Reference: docs/design/SPAWN_ERROR_PROTECTION.md

import time
from datetime import datetime, timedelta

import pytest

from aiagent_runner.cooldown import CooldownEntry, CooldownManager
from aiagent_runner.models import AgentInstanceKey


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

        manager.set_error(key, error_message="Test error")

        entry = manager.check(key)
        assert entry is not None
        assert entry.reason == "error"
        assert 58 <= (entry.until - datetime.now()).total_seconds() <= 62

    def test_cooldown_set_with_custom_seconds(self):
        """カスタム秒数でクールダウンを設定"""
        manager = CooldownManager(default_seconds=60)
        key = AgentInstanceKey("agt_001", "prj_001")

        manager.set_error(key, error_message="Test error", cooldown_seconds=120)

        entry = manager.check(key)
        assert entry is not None
        assert 118 <= (entry.until - datetime.now()).total_seconds() <= 122

    def test_cooldown_cleared_on_success(self):
        """正常終了でクールダウンがクリアされる"""
        manager = CooldownManager(default_seconds=60)
        key = AgentInstanceKey("agt_001", "prj_001")

        # エラーでクールダウン設定
        manager.set_error(key, error_message="Test error")
        assert manager.check(key) is not None

        # 正常終了でクリア
        manager.clear(key)
        assert manager.check(key) is None

    def test_cooldown_expires(self):
        """クールダウン期間終了後にNone"""
        manager = CooldownManager(default_seconds=1)  # 1秒
        key = AgentInstanceKey("agt_001", "prj_001")

        manager.set_error(key, error_message="Test error")
        assert manager.check(key) is not None

        time.sleep(1.1)  # 期間終了待ち

        assert manager.check(key) is None

    def test_consecutive_error_count(self):
        """連続エラー回数がカウントされる"""
        manager = CooldownManager(default_seconds=60)
        key = AgentInstanceKey("agt_001", "prj_001")

        manager.set_error(key, error_message="Error 1")
        assert manager.check(key).consecutive_errors == 1

        manager.set_error(key, error_message="Error 2")
        assert manager.check(key).consecutive_errors == 2

        manager.set_error(key, error_message="Error 3")
        assert manager.check(key).consecutive_errors == 3

    def test_consecutive_count_reset_on_clear(self):
        """クリア時に連続エラー回数がリセット"""
        manager = CooldownManager(default_seconds=60)
        key = AgentInstanceKey("agt_001", "prj_001")

        manager.set_error(key, error_message="Error 1")
        manager.set_error(key, error_message="Error 2")
        assert manager.check(key).consecutive_errors == 2

        manager.clear(key)

        manager.set_error(key, error_message="Error 3")
        assert manager.check(key).consecutive_errors == 1

    def test_different_keys_independent(self):
        """異なるキーは独立してクールダウン"""
        manager = CooldownManager(default_seconds=60)
        key1 = AgentInstanceKey("agt_001", "prj_001")
        key2 = AgentInstanceKey("agt_002", "prj_001")

        manager.set_error(key1, error_message="Error 1")

        assert manager.check(key1) is not None
        assert manager.check(key2) is None

    def test_set_quota_cooldown(self):
        """クォータエラー用のクールダウン設定"""
        manager = CooldownManager(default_seconds=60)
        key = AgentInstanceKey("agt_001", "prj_001")

        manager.set_quota(key, cooldown_seconds=1800, error_message="Quota exhausted")

        entry = manager.check(key)
        assert entry is not None
        assert entry.reason == "quota"
        assert 1798 <= (entry.until - datetime.now()).total_seconds() <= 1802

    def test_max_cooldown_cap(self):
        """最大クールダウン時間でキャップ"""
        manager = CooldownManager(default_seconds=60, max_seconds=300)
        key = AgentInstanceKey("agt_001", "prj_001")

        # 最大値を超えるクールダウンを設定
        manager.set_error(key, error_message="Test error", cooldown_seconds=600)

        entry = manager.check(key)
        assert entry is not None
        # 最大300秒でキャップされる
        assert (entry.until - datetime.now()).total_seconds() <= 302

    def test_remaining_seconds(self):
        """残り時間を取得"""
        manager = CooldownManager(default_seconds=60)
        key = AgentInstanceKey("agt_001", "prj_001")

        manager.set_error(key, error_message="Test error")

        remaining = manager.get_remaining_seconds(key)
        assert remaining is not None
        assert 58 <= remaining <= 62

    def test_remaining_seconds_none_when_not_in_cooldown(self):
        """クールダウン外では残り時間はNone"""
        manager = CooldownManager(default_seconds=60)
        key = AgentInstanceKey("agt_001", "prj_001")

        remaining = manager.get_remaining_seconds(key)
        assert remaining is None

    def test_get_all_cooldowns(self):
        """全クールダウン情報を取得"""
        manager = CooldownManager(default_seconds=60)
        key1 = AgentInstanceKey("agt_001", "prj_001")
        key2 = AgentInstanceKey("agt_002", "prj_001")

        manager.set_error(key1, error_message="Error 1")
        manager.set_quota(key2, cooldown_seconds=300, error_message="Quota")

        all_cooldowns = manager.get_all()
        assert len(all_cooldowns) == 2
        assert key1 in all_cooldowns
        assert key2 in all_cooldowns


class TestCooldownEntry:
    """CooldownEntry データクラスのテスト"""

    def test_entry_creation(self):
        """エントリの作成"""
        until = datetime.now() + timedelta(seconds=60)
        entry = CooldownEntry(
            until=until,
            reason="error",
            error_message="Test error",
            consecutive_errors=1
        )

        assert entry.until == until
        assert entry.reason == "error"
        assert entry.error_message == "Test error"
        assert entry.consecutive_errors == 1

    def test_entry_is_expired(self):
        """期限切れ判定"""
        # 過去の時刻
        past_until = datetime.now() - timedelta(seconds=10)
        expired_entry = CooldownEntry(
            until=past_until,
            reason="error",
            error_message="Test error",
            consecutive_errors=1
        )
        assert expired_entry.is_expired()

        # 未来の時刻
        future_until = datetime.now() + timedelta(seconds=60)
        active_entry = CooldownEntry(
            until=future_until,
            reason="error",
            error_message="Test error",
            consecutive_errors=1
        )
        assert not active_entry.is_expired()
