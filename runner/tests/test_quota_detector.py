# tests/test_quota_detector.py
# Quota error detector unit tests (TDD - RED phase)
# Reference: docs/design/SPAWN_ERROR_PROTECTION.md

import pytest

from aiagent_runner.quota_detector import QuotaErrorDetector


class TestQuotaErrorDetector:
    """クォータエラー検出のテスト"""

    def test_detect_gemini_quota_with_time(self):
        """Geminiクォータエラーから待機時間を抽出"""
        log_content = """
        Flushing log events to Clearcut.
        Error flushing log events: HTTP 400: Bad Request
        Error when talking to Gemini API
        TerminalQuotaError: You have exhausted your capacity on this model.
        Your quota will reset after 22m55s.
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        # 22分55秒 = 1375秒、+10%マージン = 約1512秒
        assert seconds is not None
        assert 1500 <= seconds <= 1520

    def test_detect_gemini_quota_minutes_only(self):
        """Geminiクォータエラー（分のみ）"""
        log_content = """
        Your quota will reset after 15m0s.
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        # 15分 = 900秒、+10%マージン = 990秒
        assert seconds is not None
        assert 985 <= seconds <= 995

    def test_detect_gemini_quota_seconds_only(self):
        """Geminiクォータエラー（秒のみ）"""
        log_content = """
        Your quota will reset after 0m45s.
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        # 45秒、+10%マージン = 49.5秒
        assert seconds is not None
        assert 48 <= seconds <= 52

    def test_detect_gemini_terminal_quota_error_without_time(self):
        """Geminiクォータエラー（時間なし）でデフォルト値"""
        log_content = """
        TerminalQuotaError: Quota exhausted
        Some other error info
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        # デフォルト30分 = 1800秒 + 10%マージン = 1980秒
        assert seconds == 1980

    def test_detect_claude_rate_limit_with_seconds(self):
        """Claudeレートリミットエラー（秒数あり）"""
        log_content = """
        RateLimitError: Too many requests. Please retry after 120 seconds.
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        # 120秒 + 10%マージン = 132秒
        assert seconds is not None
        assert 130 <= seconds <= 135

    def test_detect_claude_rate_limit_error_without_time(self):
        """Claudeレートリミットエラー（時間なし）でデフォルト値"""
        log_content = """
        RateLimitError: Too many requests.
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        # デフォルト5分 = 300秒 + 10%マージン = 330秒
        assert seconds == 330

    def test_detect_generic_quota_exhausted(self):
        """汎用クォータエラー（quota exhausted）"""
        log_content = """
        Error: API quota exhausted. Please wait and try again later.
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        # デフォルト30分 = 1800秒 + 10%マージン = 1980秒
        assert seconds == 1980

    def test_detect_generic_rate_limit(self):
        """汎用レートリミットエラー"""
        log_content = """
        Error: Rate limit exceeded. Please slow down your requests.
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        # デフォルト5分 = 300秒 + 10%マージン = 330秒
        assert seconds == 330

    def test_no_quota_error_returns_none(self):
        """クォータ以外のエラーはNone"""
        log_content = """
        Error: Connection timeout
        Network error occurred
        File not found: config.yaml
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        assert seconds is None

    def test_empty_log_returns_none(self):
        """空のログはNone"""
        detector = QuotaErrorDetector()
        seconds = detector.detect("")

        assert seconds is None

    def test_max_cooldown_cap(self):
        """最大クールダウン時間でキャップされる"""
        log_content = """
        Your quota will reset after 120m0s.
        """

        detector = QuotaErrorDetector(max_seconds=3600)
        seconds = detector.detect(log_content)

        # 120分 = 7200秒だが、最大3600秒でキャップ
        assert seconds == 3600

    def test_margin_calculation(self):
        """マージン計算が正しい"""
        log_content = """
        Your quota will reset after 10m0s.
        """

        # デフォルトマージン10%
        detector = QuotaErrorDetector(margin_percent=10)
        seconds = detector.detect(log_content)

        # 10分 = 600秒、+10% = 660秒
        assert seconds == 660

        # マージン20%
        detector_20 = QuotaErrorDetector(margin_percent=20)
        seconds_20 = detector_20.detect(log_content)

        # 10分 = 600秒、+20% = 720秒
        assert seconds_20 == 720

    def test_case_insensitive_detection(self):
        """大文字小文字を区別しない検出"""
        log_content = """
        TERMINALQUOTAERROR: QUOTA EXHAUSTED
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        # デフォルト30分 = 1800秒 + 10%マージン = 1980秒
        assert seconds == 1980

    def test_detect_from_file(self, tmp_path):
        """ファイルからクォータエラーを検出"""
        log_file = tmp_path / "test.log"
        log_file.write_text("""
        Error when talking to Gemini API
        Your quota will reset after 5m30s.
        """)

        detector = QuotaErrorDetector()
        seconds = detector.detect_from_file(str(log_file))

        # 5分30秒 = 330秒、+10%マージン = 363秒
        assert seconds is not None
        assert 360 <= seconds <= 370

    def test_detect_from_file_not_found(self):
        """存在しないファイルはNone"""
        detector = QuotaErrorDetector()
        seconds = detector.detect_from_file("/nonexistent/path/file.log")

        assert seconds is None

    def test_multiple_patterns_first_match_wins(self):
        """複数パターンがある場合、最初のマッチが優先"""
        log_content = """
        RateLimitError: Too many requests.
        Your quota will reset after 10m0s.
        """

        detector = QuotaErrorDetector()
        seconds = detector.detect(log_content)

        # 時間付きパターンが優先される
        # 10分 = 600秒、+10% = 660秒
        assert seconds == 660


class TestQuotaPatterns:
    """クォータパターンの個別テスト"""

    @pytest.fixture
    def detector(self):
        return QuotaErrorDetector()

    def test_pattern_gemini_reset_time(self, detector):
        """Gemini: quota will reset after Xm Ys"""
        # 様々な時間形式をテスト
        test_cases = [
            ("quota will reset after 1m0s", 66),      # 60秒 + 10%
            ("quota will reset after 0m30s", 33),     # 30秒 + 10%
            ("quota will reset after 59m59s", 3959),  # 3599秒 + 10%
        ]

        for log_content, expected_approx in test_cases:
            seconds = detector.detect(log_content)
            assert seconds is not None, f"Failed for: {log_content}"
            assert abs(seconds - expected_approx) <= 2, f"Expected ~{expected_approx}, got {seconds}"

    def test_pattern_retry_after_seconds(self, detector):
        """retry after X seconds"""
        test_cases = [
            ("Please retry after 60 seconds", 66),    # 60秒 + 10%
            ("retry after 300 seconds", 330),         # 300秒 + 10%
            ("Retry after 10 seconds.", 11),          # 10秒 + 10%
        ]

        for log_content, expected_approx in test_cases:
            seconds = detector.detect(log_content)
            assert seconds is not None, f"Failed for: {log_content}"
            assert abs(seconds - expected_approx) <= 2, f"Expected ~{expected_approx}, got {seconds}"
