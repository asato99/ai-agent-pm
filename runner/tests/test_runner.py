# tests/test_runner.py
# Tests for Runner

import pytest
from datetime import datetime
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

from aiagent_runner.config import RunnerConfig
from aiagent_runner.executor import ExecutionResult
from aiagent_runner.mcp_client import (
    AuthenticationError,
    AuthResult,
    ExecutionStartResult,
    MCPError,
    SessionExpiredError,
    TaskInfo,
)
from aiagent_runner.runner import Runner


class TestRunnerInit:
    """Tests for Runner initialization."""

    def test_init(self, sample_config):
        """Should initialize runner."""
        runner = Runner(sample_config)

        assert runner.config == sample_config
        assert runner.mcp_client is not None
        assert runner.executor is not None
        assert runner._running is False
        assert runner._authenticated is False

    def test_log_directory_from_config(self, sample_config):
        """Should use log directory from config."""
        runner = Runner(sample_config)
        assert runner.log_directory == Path(sample_config.log_directory)

    def test_log_directory_default(self):
        """Should use default log directory."""
        config = RunnerConfig(
            agent_id="agent",
            passkey="passkey"
        )
        runner = Runner(config)
        assert ".aiagent-runner/logs" in str(runner.log_directory)

    def test_working_directory_from_config(self, sample_config):
        """Should use working directory from config."""
        runner = Runner(sample_config)
        assert runner.working_directory == sample_config.working_directory

    def test_working_directory_default(self):
        """Should use cwd as default working directory."""
        config = RunnerConfig(
            agent_id="agent",
            passkey="passkey"
        )
        runner = Runner(config)
        assert runner.working_directory is not None


class TestRunnerAuthentication:
    """Tests for Runner authentication."""

    @pytest.mark.asyncio
    async def test_ensure_authenticated_first_time(self, sample_config):
        """Should authenticate on first call."""
        runner = Runner(sample_config)

        auth_result = AuthResult(
            session_token="token",
            expires_in=3600,
            agent_name="Test Agent"
        )

        with patch.object(
            runner.mcp_client, "authenticate",
            new_callable=AsyncMock
        ) as mock_auth:
            mock_auth.return_value = auth_result

            await runner._ensure_authenticated()

            assert runner._authenticated is True
            assert runner._agent_name == "Test Agent"
            assert runner.prompt_builder is not None
            mock_auth.assert_called_once()

    @pytest.mark.asyncio
    async def test_ensure_authenticated_already_auth(self, sample_config):
        """Should not re-authenticate if already authenticated."""
        runner = Runner(sample_config)
        runner._authenticated = True

        with patch.object(
            runner.mcp_client, "authenticate",
            new_callable=AsyncMock
        ) as mock_auth:
            await runner._ensure_authenticated()

            mock_auth.assert_not_called()


class TestRunnerRunOnce:
    """Tests for Runner._run_once()."""

    @pytest.mark.asyncio
    async def test_run_once_no_tasks(self, sample_config):
        """Should handle no pending tasks."""
        runner = Runner(sample_config)
        runner._authenticated = True
        runner.prompt_builder = MagicMock()

        with patch.object(
            runner.mcp_client, "get_pending_tasks",
            new_callable=AsyncMock
        ) as mock_tasks:
            mock_tasks.return_value = []

            await runner._run_once()

            mock_tasks.assert_called_once()

    @pytest.mark.asyncio
    async def test_run_once_with_task(self, sample_config, sample_task):
        """Should process a pending task."""
        runner = Runner(sample_config)
        runner._authenticated = True
        runner.prompt_builder = MagicMock()
        runner.prompt_builder.build.return_value = "test prompt"

        with patch.object(
            runner.mcp_client, "get_pending_tasks",
            new_callable=AsyncMock
        ) as mock_tasks, patch.object(
            runner, "_process_task",
            new_callable=AsyncMock
        ) as mock_process:
            mock_tasks.return_value = [sample_task]

            await runner._run_once()

            mock_process.assert_called_once_with(sample_task)

    @pytest.mark.asyncio
    async def test_run_once_session_expired(self, sample_config, sample_task):
        """Should re-authenticate on session expiry."""
        runner = Runner(sample_config)
        runner._authenticated = True
        runner.prompt_builder = MagicMock()
        runner.prompt_builder.build.return_value = "test prompt"

        call_count = 0

        async def mock_get_tasks():
            # No agent_id argument - derived from session token internally
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                raise SessionExpiredError("Session expired")
            return []

        auth_result = AuthResult(
            session_token="new-token",
            expires_in=3600
        )

        with patch.object(
            runner.mcp_client, "get_pending_tasks",
            side_effect=mock_get_tasks
        ), patch.object(
            runner.mcp_client, "authenticate",
            new_callable=AsyncMock
        ) as mock_auth:
            mock_auth.return_value = auth_result

            await runner._run_once()

            mock_auth.assert_called_once()
            assert call_count == 2


class TestRunnerProcessTask:
    """Tests for Runner._process_task()."""

    @pytest.mark.asyncio
    async def test_process_task_success(self, sample_config, sample_task):
        """Should process task successfully."""
        runner = Runner(sample_config)
        runner.prompt_builder = MagicMock()
        runner.prompt_builder.build.return_value = "test prompt"

        exec_start = ExecutionStartResult(
            execution_id="exec-001",
            started_at=datetime.now()
        )

        exec_result = ExecutionResult(
            exit_code=0,
            duration_seconds=10.5,
            log_file="/tmp/log.txt"
        )

        with patch.object(
            runner.mcp_client, "report_execution_start",
            new_callable=AsyncMock
        ) as mock_start, patch.object(
            runner.mcp_client, "report_execution_complete",
            new_callable=AsyncMock
        ) as mock_complete, patch.object(
            runner.executor, "execute"
        ) as mock_exec:
            mock_start.return_value = exec_start
            mock_exec.return_value = exec_result

            await runner._process_task(sample_task)

            mock_start.assert_called_once()
            mock_exec.assert_called_once()
            mock_complete.assert_called_once_with(
                "exec-001",
                0,
                10.5,
                "/tmp/log.txt",
                None  # no error message
            )

    @pytest.mark.asyncio
    async def test_process_task_execution_failure(self, sample_config, sample_task):
        """Should handle execution failure."""
        runner = Runner(sample_config)
        runner.prompt_builder = MagicMock()
        runner.prompt_builder.build.return_value = "test prompt"

        exec_start = ExecutionStartResult(
            execution_id="exec-001",
            started_at=datetime.now()
        )

        exec_result = ExecutionResult(
            exit_code=1,
            duration_seconds=5.0,
            log_file="/tmp/log.txt"
        )

        with patch.object(
            runner.mcp_client, "report_execution_start",
            new_callable=AsyncMock
        ) as mock_start, patch.object(
            runner.mcp_client, "report_execution_complete",
            new_callable=AsyncMock
        ) as mock_complete, patch.object(
            runner.executor, "execute"
        ) as mock_exec:
            mock_start.return_value = exec_start
            mock_exec.return_value = exec_result

            await runner._process_task(sample_task)

            # Should report with error message
            mock_complete.assert_called_once()
            call_args = mock_complete.call_args[0]
            assert call_args[4] is not None  # error_message
            assert "exit" in call_args[4].lower()


class TestRunnerLogPath:
    """Tests for log path generation."""

    def test_generate_log_path(self, sample_config):
        """Should generate unique log path."""
        runner = Runner(sample_config)

        path1 = runner._generate_log_path("task-001")
        path2 = runner._generate_log_path("task-001")

        assert "task-001" in path1
        assert path1.endswith(".log")
        # Paths should be in log directory
        assert str(runner.log_directory) in path1


class TestRunnerStop:
    """Tests for Runner.stop()."""

    def test_stop(self, sample_config):
        """Should stop the runner."""
        runner = Runner(sample_config)
        runner._running = True

        runner.stop()

        assert runner._running is False
