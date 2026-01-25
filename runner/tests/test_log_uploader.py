# runner/tests/test_log_uploader.py
# ログアップロードクラス - テスト
# 参照: docs/design/LOG_TRANSFER_TDD.md - Phase 2.1

import pytest
import asyncio
from pathlib import Path
from unittest.mock import AsyncMock, patch, MagicMock, PropertyMock
from aiagent_runner.log_uploader import LogUploader, LogUploadConfig


class TestLogUploader:
    """LogUploaderクラスのテスト"""

    @pytest.fixture
    def config(self):
        """テスト用設定"""
        return LogUploadConfig(
            enabled=True,
            endpoint="http://localhost:8080/api/v1/execution-logs/upload",
            max_file_size_mb=10,
            retry_count=3,
            retry_delay_seconds=0.01  # テスト高速化
        )

    @pytest.fixture
    def uploader(self, config):
        """テスト用LogUploaderインスタンス"""
        return LogUploader(config, coordinator_token="test-token")

    def _create_mock_session(self, mock_response):
        """モックセッションを作成するヘルパー"""
        # response context manager
        response_cm = MagicMock()
        response_cm.__aenter__ = AsyncMock(return_value=mock_response)
        response_cm.__aexit__ = AsyncMock(return_value=None)

        # session with post method
        mock_session = MagicMock()
        mock_session.post = MagicMock(return_value=response_cm)

        # session context manager
        session_cm = MagicMock()
        session_cm.__aenter__ = AsyncMock(return_value=mock_session)
        session_cm.__aexit__ = AsyncMock(return_value=None)

        return session_cm, mock_session

    # TEST 1: アップロード無効時はNoneを返す
    @pytest.mark.asyncio
    async def test_upload_disabled_returns_none(self):
        """アップロードが無効な場合はNoneを返す"""
        config = LogUploadConfig(enabled=False)
        uploader = LogUploader(config, coordinator_token="token")

        result = await uploader.upload(
            log_file_path="/tmp/test.log",
            execution_log_id="exec_123",
            agent_id="agt_456",
            task_id="task_789",
            project_id="proj_123"
        )

        assert result is None

    # TEST 2: ファイルが存在しない場合はNoneを返す
    @pytest.mark.asyncio
    async def test_upload_file_not_found_returns_none(self, uploader):
        """ファイルが存在しない場合はNoneを返す"""
        result = await uploader.upload(
            log_file_path="/nonexistent/file.log",
            execution_log_id="exec_123",
            agent_id="agt_456",
            task_id="task_789",
            project_id="proj_123"
        )

        assert result is None

    # TEST 3: ファイルサイズ超過時はNoneを返す
    @pytest.mark.asyncio
    async def test_upload_file_too_large_returns_none(self, uploader, tmp_path):
        """ファイルサイズが制限を超えている場合はNoneを返す"""
        # 11MB のファイルを作成
        large_file = tmp_path / "large.log"
        large_file.write_bytes(b"x" * (11 * 1024 * 1024))

        result = await uploader.upload(
            log_file_path=str(large_file),
            execution_log_id="exec_123",
            agent_id="agt_456",
            task_id="task_789",
            project_id="proj_123"
        )

        assert result is None

    # TEST 4: 正常なアップロード
    @pytest.mark.asyncio
    async def test_upload_success(self, uploader, tmp_path):
        """正常なアップロードが成功する"""
        log_file = tmp_path / "test.log"
        log_file.write_text("test log content")

        # レスポンスモック
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.json = AsyncMock(return_value={
            "success": True,
            "log_file_path": "/project/.ai-pm/logs/agt_456/test.log",
            "execution_log_id": "exec_123",
            "file_size": 16
        })

        session_cm, _ = self._create_mock_session(mock_response)

        with patch("aiagent_runner.log_uploader.aiohttp.ClientSession", return_value=session_cm):
            result = await uploader.upload(
                log_file_path=str(log_file),
                execution_log_id="exec_123",
                agent_id="agt_456",
                task_id="task_789",
                project_id="proj_123"
            )

        assert result == "/project/.ai-pm/logs/agt_456/test.log"

    # TEST 5: リトライ動作
    @pytest.mark.asyncio
    async def test_upload_retries_on_failure(self, uploader, tmp_path):
        """失敗時にリトライする"""
        log_file = tmp_path / "test.log"
        log_file.write_text("test log content")

        call_count = 0

        def create_response_cm():
            nonlocal call_count
            call_count += 1

            mock_response = MagicMock()
            if call_count < 3:
                mock_response.status = 500
                mock_response.text = AsyncMock(return_value="Server error")
            else:
                mock_response.status = 200
                mock_response.json = AsyncMock(return_value={
                    "success": True,
                    "log_file_path": "/project/.ai-pm/logs/test.log",
                    "execution_log_id": "exec_123",
                    "file_size": 16
                })

            response_cm = MagicMock()
            response_cm.__aenter__ = AsyncMock(return_value=mock_response)
            response_cm.__aexit__ = AsyncMock(return_value=None)
            return response_cm

        mock_session = MagicMock()
        mock_session.post = MagicMock(side_effect=lambda *args, **kwargs: create_response_cm())

        session_cm = MagicMock()
        session_cm.__aenter__ = AsyncMock(return_value=mock_session)
        session_cm.__aexit__ = AsyncMock(return_value=None)

        with patch("aiagent_runner.log_uploader.aiohttp.ClientSession", return_value=session_cm):
            result = await uploader.upload(
                log_file_path=str(log_file),
                execution_log_id="exec_123",
                agent_id="agt_456",
                task_id="task_789",
                project_id="proj_123"
            )

        assert result == "/project/.ai-pm/logs/test.log"
        assert call_count == 3

    # TEST 6: 全リトライ失敗時はNoneを返す
    @pytest.mark.asyncio
    async def test_upload_all_retries_failed_returns_none(self, uploader, tmp_path):
        """全リトライが失敗した場合はNoneを返す"""
        log_file = tmp_path / "test.log"
        log_file.write_text("test log content")

        # レスポンスモック（常に500エラー）
        mock_response = MagicMock()
        mock_response.status = 500
        mock_response.text = AsyncMock(return_value="Server error")

        session_cm, _ = self._create_mock_session(mock_response)

        with patch("aiagent_runner.log_uploader.aiohttp.ClientSession", return_value=session_cm):
            result = await uploader.upload(
                log_file_path=str(log_file),
                execution_log_id="exec_123",
                agent_id="agt_456",
                task_id="task_789",
                project_id="proj_123"
            )

        assert result is None

    # TEST 7: Authorizationヘッダーが正しく設定される
    @pytest.mark.asyncio
    async def test_upload_sets_authorization_header(self, uploader, tmp_path):
        """Authorizationヘッダーにcoordinator_tokenが設定される"""
        log_file = tmp_path / "test.log"
        log_file.write_text("test log content")

        captured_headers = {}

        def capture_post(*args, **kwargs):
            nonlocal captured_headers
            captured_headers = kwargs.get("headers", {})

            mock_response = MagicMock()
            mock_response.status = 200
            mock_response.json = AsyncMock(return_value={
                "success": True,
                "log_file_path": "/test/path.log",
                "execution_log_id": "exec_123",
                "file_size": 16
            })

            response_cm = MagicMock()
            response_cm.__aenter__ = AsyncMock(return_value=mock_response)
            response_cm.__aexit__ = AsyncMock(return_value=None)
            return response_cm

        mock_session = MagicMock()
        mock_session.post = MagicMock(side_effect=capture_post)

        session_cm = MagicMock()
        session_cm.__aenter__ = AsyncMock(return_value=mock_session)
        session_cm.__aexit__ = AsyncMock(return_value=None)

        with patch("aiagent_runner.log_uploader.aiohttp.ClientSession", return_value=session_cm):
            await uploader.upload(
                log_file_path=str(log_file),
                execution_log_id="exec_123",
                agent_id="agt_456",
                task_id="task_789",
                project_id="proj_123"
            )

        assert "Authorization" in captured_headers
        assert captured_headers["Authorization"] == "Bearer test-token"
