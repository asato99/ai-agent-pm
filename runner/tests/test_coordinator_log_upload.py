# runner/tests/test_coordinator_log_upload.py
# Coordinator非同期ログアップロード - テスト
# 参照: docs/design/LOG_TRANSFER_TDD.md - Phase 2.2

import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock, patch
from pathlib import Path
from datetime import datetime

from aiagent_runner.coordinator import Coordinator, AgentInstanceKey, AgentInstanceInfo


class TestCoordinatorAsyncLogUpload:
    """Coordinator非同期ログアップロードのテスト"""

    @pytest.fixture
    def mock_config(self):
        """テスト用の設定モック"""
        config = MagicMock()
        config.mcp_socket_path = "/tmp/test.sock"
        config.coordinator_token = "test-token"
        config.log_directory = None
        config.polling_interval_seconds = 1
        config.ai_providers = {}
        config.agents = {}
        config.log_upload = MagicMock()
        config.log_upload.enabled = True
        config.log_upload.endpoint = "http://localhost:8080/api/v1/execution-logs/upload"
        config.log_upload.max_file_size_mb = 10
        config.log_upload.retry_count = 3
        config.log_upload.retry_delay_seconds = 1
        return config

    @pytest.fixture
    def coordinator(self, mock_config):
        """テスト用のCoordinatorインスタンス"""
        with patch("aiagent_runner.coordinator.MCPClient"):
            coord = Coordinator(mock_config)
            coord.mcp_client = AsyncMock()
            return coord

    # TEST 1: プロセス完了時に非同期アップロードが開始される
    @pytest.mark.asyncio
    async def test_cleanup_finished_starts_async_upload(self, coordinator, tmp_path):
        """プロセス完了時に非同期アップロードが開始される"""
        # ログファイルを作成
        log_file = tmp_path / "test.log"
        log_file.write_text("test content")

        # 終了したプロセスをシミュレート
        mock_process = MagicMock()
        mock_process.poll.return_value = 0

        mock_log_handle = MagicMock()

        key = AgentInstanceKey("agt_123", "proj_456")
        info = AgentInstanceInfo(
            key=key,
            process=mock_process,
            working_directory="/tmp",
            provider="claude",
            model="opus",
            started_at=datetime.now(),
            log_file_handle=mock_log_handle,
            task_id="task_789",
            log_file_path=str(log_file),
            mcp_config_file=None
        )
        # execution_log_idを追加（新フィールド）
        info.execution_log_id = "exec_001"
        coordinator._instances[key] = info

        # cleanup_finished を実行
        finished = coordinator._cleanup_finished()

        # ログファイルハンドルがクローズされた
        mock_log_handle.close.assert_called_once()

        # 非同期タスクが作成された
        assert len(coordinator._pending_uploads) == 1
        assert "exec_001" in coordinator._pending_uploads

        # プロセスがfinishedリストに含まれる
        assert len(finished) == 1
        assert finished[0][0] == key

    # TEST 2: 非同期アップロード成功時、一時ファイルが削除される
    @pytest.mark.asyncio
    async def test_async_upload_success_deletes_temp_file(self, coordinator, tmp_path):
        """非同期アップロード成功時、一時ファイルが削除される"""
        # LogUploaderモックを設定
        coordinator.log_uploader = MagicMock()
        coordinator.log_uploader.upload = AsyncMock(
            return_value="/project/.ai-pm/logs/test.log"
        )

        # ログファイルを作成
        log_file = tmp_path / "test.log"
        log_file.write_text("test content")

        upload_info = MagicMock()
        upload_info.log_file_path = str(log_file)
        upload_info.execution_log_id = "exec_001"
        upload_info.agent_id = "agt_123"
        upload_info.task_id = "task_789"
        upload_info.project_id = "proj_456"

        await coordinator._upload_log_async(upload_info)

        # ファイルが削除された
        assert not log_file.exists()

    # TEST 3: 非同期アップロード失敗時、ローカルパスがDBに登録される
    @pytest.mark.asyncio
    async def test_async_upload_failure_registers_local_path(self, coordinator, tmp_path):
        """非同期アップロード失敗時、ローカルパスがDBに登録される"""
        # LogUploaderモックを設定（失敗を返す）
        coordinator.log_uploader = MagicMock()
        coordinator.log_uploader.upload = AsyncMock(return_value=None)

        # ログファイルを作成
        log_file = tmp_path / "test.log"
        log_file.write_text("test content")

        upload_info = MagicMock()
        upload_info.log_file_path = str(log_file)
        upload_info.execution_log_id = "exec_001"
        upload_info.agent_id = "agt_123"
        upload_info.task_id = "task_789"
        upload_info.project_id = "proj_456"

        await coordinator._upload_log_async(upload_info)

        # ローカルパスがMCP経由で登録された
        coordinator.mcp_client.register_execution_log_file.assert_called_once_with(
            execution_log_id="exec_001",
            log_file_path=str(log_file)
        )

        # ファイルは削除されていない（フォールバック）
        assert log_file.exists()

    # TEST 4: 非同期アップロードが次のタスク割当をブロックしない
    @pytest.mark.asyncio
    async def test_async_upload_does_not_block(self, coordinator, tmp_path):
        """非同期アップロードが次のタスク割当をブロックしない"""
        # 時間のかかるアップロードをシミュレート
        async def slow_upload(*args, **kwargs):
            await asyncio.sleep(5)  # 5秒かかる
            return "/project/.ai-pm/logs/test.log"

        coordinator.log_uploader = MagicMock()
        coordinator.log_uploader.upload = slow_upload

        # ログファイルを作成
        log_file = tmp_path / "test.log"
        log_file.write_text("test content")

        mock_process = MagicMock()
        mock_process.poll.return_value = 0

        key = AgentInstanceKey("agt_123", "proj_456")
        info = AgentInstanceInfo(
            key=key,
            process=mock_process,
            working_directory="/tmp",
            provider="claude",
            model="opus",
            started_at=datetime.now(),
            log_file_handle=MagicMock(),
            task_id="task_789",
            log_file_path=str(log_file),
            mcp_config_file=None
        )
        info.execution_log_id = "exec_001"
        coordinator._instances[key] = info

        # 時間計測
        loop = asyncio.get_event_loop()
        start = loop.time()
        finished = coordinator._cleanup_finished()
        elapsed = loop.time() - start

        # 即座に完了する（5秒待たない）
        assert elapsed < 0.1
        assert len(finished) == 1

        # アップロードはバックグラウンドで進行中
        assert len(coordinator._pending_uploads) == 1

    # TEST 5: LogUploaderがCoordinator初期化時に作成される
    def test_coordinator_creates_log_uploader(self, mock_config):
        """LogUploaderがCoordinator初期化時に作成される"""
        with patch("aiagent_runner.coordinator.MCPClient"):
            with patch("aiagent_runner.coordinator.LogUploader") as mock_uploader_class:
                coord = Coordinator(mock_config)

                # LogUploaderが作成された
                mock_uploader_class.assert_called_once()
                assert coord.log_uploader is not None

    # TEST 6: LogUpload無効時はUploaderが作成されない
    def test_coordinator_no_uploader_when_disabled(self, mock_config):
        """LogUpload無効時はUploaderが作成されない"""
        mock_config.log_upload.enabled = False

        with patch("aiagent_runner.coordinator.MCPClient"):
            coord = Coordinator(mock_config)

            # LogUploaderが作成されていない
            assert coord.log_uploader is None

    # TEST 7: LogUpload設定がない場合もUploaderは作成されない
    def test_coordinator_no_uploader_when_no_config(self, mock_config):
        """LogUpload設定がない場合もUploaderは作成されない"""
        mock_config.log_upload = None

        with patch("aiagent_runner.coordinator.MCPClient"):
            coord = Coordinator(mock_config)

            # LogUploaderが作成されていない
            assert coord.log_uploader is None
