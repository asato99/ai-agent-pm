# src/aiagent_runner/cooldown.py
# Cooldown manager for spawn error protection
# Reference: docs/design/SPAWN_ERROR_PROTECTION.md

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional

from aiagent_runner.models import AgentInstanceKey


@dataclass
class CooldownEntry:
    """クールダウン情報"""
    until: datetime          # クールダウン終了時刻
    reason: str              # クールダウン理由（"error", "quota"）
    error_message: str       # エラーメッセージ（ログ用）
    consecutive_errors: int  # 連続エラー回数

    def is_expired(self) -> bool:
        """クールダウンが期限切れかどうか"""
        return datetime.now() >= self.until


class CooldownManager:
    """クールダウン管理クラス

    エージェント/プロジェクトペアごとにクールダウン状態を管理し、
    連続スポーンを防止する。
    """

    def __init__(
        self,
        default_seconds: int = 60,
        max_seconds: int = 3600
    ):
        """初期化

        Args:
            default_seconds: デフォルトクールダウン時間（秒）
            max_seconds: 最大クールダウン時間（秒）
        """
        self._default_seconds = default_seconds
        self._max_seconds = max_seconds
        self._cooldowns: dict[AgentInstanceKey, CooldownEntry] = {}

    def check(self, key: AgentInstanceKey) -> Optional[CooldownEntry]:
        """クールダウン中かどうかを確認

        Args:
            key: エージェント/プロジェクトキー

        Returns:
            CooldownEntry if in cooldown, None otherwise
        """
        if key not in self._cooldowns:
            return None

        entry = self._cooldowns[key]
        if entry.is_expired():
            # クールダウン終了
            del self._cooldowns[key]
            return None

        return entry

    def set_error(
        self,
        key: AgentInstanceKey,
        error_message: str,
        cooldown_seconds: Optional[int] = None
    ) -> None:
        """エラー時のクールダウンを設定

        Args:
            key: エージェント/プロジェクトキー
            error_message: エラーメッセージ
            cooldown_seconds: クールダウン時間（秒）、Noneでデフォルト値
        """
        seconds = cooldown_seconds if cooldown_seconds is not None else self._default_seconds
        seconds = min(seconds, self._max_seconds)  # 最大値でキャップ

        # 連続エラーカウント
        consecutive = 1
        if key in self._cooldowns:
            consecutive = self._cooldowns[key].consecutive_errors + 1

        self._cooldowns[key] = CooldownEntry(
            until=datetime.now() + timedelta(seconds=seconds),
            reason="error",
            error_message=error_message,
            consecutive_errors=consecutive
        )

    def set_quota(
        self,
        key: AgentInstanceKey,
        cooldown_seconds: int,
        error_message: str
    ) -> None:
        """クォータエラー時のクールダウンを設定

        Args:
            key: エージェント/プロジェクトキー
            cooldown_seconds: クールダウン時間（秒）
            error_message: エラーメッセージ
        """
        seconds = min(cooldown_seconds, self._max_seconds)  # 最大値でキャップ

        # 連続エラーカウント
        consecutive = 1
        if key in self._cooldowns:
            consecutive = self._cooldowns[key].consecutive_errors + 1

        self._cooldowns[key] = CooldownEntry(
            until=datetime.now() + timedelta(seconds=seconds),
            reason="quota",
            error_message=error_message,
            consecutive_errors=consecutive
        )

    def clear(self, key: AgentInstanceKey) -> None:
        """クールダウンをクリア（正常終了時）

        Args:
            key: エージェント/プロジェクトキー
        """
        if key in self._cooldowns:
            del self._cooldowns[key]

    def get_remaining_seconds(self, key: AgentInstanceKey) -> Optional[float]:
        """残りクールダウン時間を取得

        Args:
            key: エージェント/プロジェクトキー

        Returns:
            残り秒数、クールダウン外ではNone
        """
        entry = self.check(key)
        if entry is None:
            return None

        return (entry.until - datetime.now()).total_seconds()

    def get_all(self) -> dict[AgentInstanceKey, CooldownEntry]:
        """全クールダウン情報を取得

        Returns:
            キーとエントリのマッピング
        """
        # 期限切れをクリーンアップ
        expired_keys = [
            key for key, entry in self._cooldowns.items()
            if entry.is_expired()
        ]
        for key in expired_keys:
            del self._cooldowns[key]

        return self._cooldowns.copy()
