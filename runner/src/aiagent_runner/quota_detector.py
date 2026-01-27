# src/aiagent_runner/quota_detector.py
# Quota error detector for spawn error protection
# Reference: docs/design/SPAWN_ERROR_PROTECTION.md

import logging
import re
from typing import Callable, Optional

logger = logging.getLogger(__name__)


# クォータエラー検出パターン
# (pattern, extractor_function, default_seconds)
# extractor_function: マッチオブジェクトから秒数を抽出、Noneならデフォルト値を使用
QUOTA_PATTERNS: list[tuple[str, Optional[Callable[[re.Match], int]], int]] = [
    # Gemini: quota will reset after XmYs (時間付き - 最優先)
    (
        r"quota will reset after (\d+)m(\d+)s",
        lambda m: int(m.group(1)) * 60 + int(m.group(2)),
        0  # デフォルト不使用（時間抽出）
    ),
    # 汎用: retry after X seconds (時間付き)
    (
        r"retry after (\d+)\s*(?:seconds?)?",
        lambda m: int(m.group(1)),
        0  # デフォルト不使用（時間抽出）
    ),
    # Gemini: TerminalQuotaError (時間なし)
    (
        r"TerminalQuotaError",
        None,
        1800  # デフォルト30分
    ),
    # Claude: RateLimitError (時間なし)
    (
        r"RateLimitError",
        None,
        300  # デフォルト5分
    ),
    # 汎用: quota exhausted
    (
        r"quota.*exhausted",
        None,
        1800  # デフォルト30分
    ),
    # 汎用: rate limit
    (
        r"rate\s*limit",
        None,
        300  # デフォルト5分
    ),
]


class QuotaErrorDetector:
    """クォータエラー検出クラス

    ログ内容からクォータ/レートリミットエラーを検出し、
    適切な待機時間を返す。
    """

    def __init__(
        self,
        max_seconds: int = 7200,
        margin_percent: int = 10
    ):
        """初期化

        Args:
            max_seconds: 最大待機時間（秒）
            margin_percent: 安全マージン（パーセント）
        """
        self._max_seconds = max_seconds
        self._margin_percent = margin_percent

    def detect(self, log_content: str) -> Optional[int]:
        """ログ内容からクォータエラーを検出

        Args:
            log_content: ログの内容

        Returns:
            待機秒数（クォータエラーの場合）、None（通常エラーの場合）
        """
        if not log_content:
            return None

        for pattern, extractor, default_seconds in QUOTA_PATTERNS:
            match = re.search(pattern, log_content, re.IGNORECASE)
            if match:
                # 時間を抽出または固定値を使用
                if extractor is not None:
                    try:
                        seconds = extractor(match)
                    except (ValueError, IndexError) as e:
                        logger.warning(f"Failed to extract time from pattern: {e}")
                        seconds = default_seconds
                else:
                    seconds = default_seconds

                # 安全マージンを追加
                seconds = self._apply_margin(seconds)

                # 最大値でキャップ
                seconds = min(seconds, self._max_seconds)

                logger.info(
                    f"Quota error detected: pattern='{pattern}', "
                    f"cooldown={seconds}s"
                )
                return seconds

        return None

    def detect_from_file(self, log_file_path: str) -> Optional[int]:
        """ファイルからクォータエラーを検出

        Args:
            log_file_path: ログファイルのパス

        Returns:
            待機秒数（クォータエラーの場合）、None（通常エラーの場合）
        """
        try:
            with open(log_file_path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            return self.detect(content)
        except FileNotFoundError:
            logger.warning(f"Log file not found: {log_file_path}")
            return None
        except Exception as e:
            logger.warning(f"Failed to read log file {log_file_path}: {e}")
            return None

    def _apply_margin(self, seconds: int) -> int:
        """安全マージンを適用

        Args:
            seconds: 元の秒数

        Returns:
            マージン適用後の秒数
        """
        return int(seconds * (1 + self._margin_percent / 100))
