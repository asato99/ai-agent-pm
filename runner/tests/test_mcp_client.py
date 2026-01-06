# tests/test_mcp_client.py
# Tests for MCPClient

import json
import pytest
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch

from aiagent_runner.mcp_client import (
    AuthenticationError,
    AuthResult,
    ExecutionStartResult,
    MCPClient,
    MCPError,
    SessionExpiredError,
    TaskInfo,
)


class TestTaskInfo:
    """Tests for TaskInfo dataclass."""

    def test_task_info_full(self, sample_task):
        """Should create TaskInfo with all fields."""
        assert sample_task.task_id == "task-001"
        assert sample_task.project_id == "project-001"
        assert sample_task.title == "Test Task"
        assert sample_task.priority == "high"
        assert sample_task.context is not None
        assert sample_task.handoff is not None

    def test_task_info_minimal(self, sample_task_minimal):
        """Should create TaskInfo with minimal fields."""
        assert sample_task_minimal.task_id == "task-002"
        assert sample_task_minimal.working_directory is None
        assert sample_task_minimal.context is None
        assert sample_task_minimal.handoff is None


class TestMCPClientInit:
    """Tests for MCPClient initialization."""

    def test_init_default_socket(self):
        """Should use default socket path."""
        client = MCPClient()
        assert "AIAgentPM/mcp.sock" in client.socket_path

    def test_init_custom_socket(self):
        """Should use custom socket path."""
        client = MCPClient("/tmp/custom.sock")
        assert client.socket_path == "/tmp/custom.sock"


class TestMCPClientAuthenticate:
    """Tests for MCPClient.authenticate()."""

    @pytest.mark.asyncio
    async def test_authenticate_success(self):
        """Should authenticate successfully."""
        client = MCPClient("/tmp/test.sock")

        mock_response = {
            "success": True,
            "session_token": "token-12345",
            "expires_in": 3600,
            "agent_name": "Test Agent"
        }

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            result = await client.authenticate("agent-001", "passkey")

            assert isinstance(result, AuthResult)
            assert result.session_token == "token-12345"
            assert result.expires_in == 3600
            assert result.agent_name == "Test Agent"

            mock_call.assert_called_once_with("authenticate", {
                "agent_id": "agent-001",
                "passkey": "passkey"
            })

    @pytest.mark.asyncio
    async def test_authenticate_failure(self):
        """Should raise AuthenticationError on failure."""
        client = MCPClient("/tmp/test.sock")

        mock_response = {
            "success": False,
            "error": "Invalid credentials"
        }

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            with pytest.raises(AuthenticationError, match="Invalid credentials"):
                await client.authenticate("agent-001", "wrong-passkey")


class TestMCPClientGetPendingTasks:
    """Tests for MCPClient.get_pending_tasks()."""

    @pytest.mark.asyncio
    async def test_get_pending_tasks_success(self):
        """Should return list of pending tasks."""
        client = MCPClient("/tmp/test.sock")
        client._session_token = "test-session-token"  # Must be authenticated

        mock_response = {
            "success": True,
            "tasks": [
                {
                    "task_id": "task-001",
                    "project_id": "proj-001",
                    "title": "Task One",
                    "description": "First task",
                    "priority": "high",
                    "working_directory": "/tmp"
                },
                {
                    "task_id": "task-002",
                    "project_id": "proj-001",
                    "title": "Task Two",
                    "description": "Second task",
                    "priority": "medium"
                }
            ]
        }

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            # No agent_id argument - derived from session token internally
            tasks = await client.get_pending_tasks()

            assert len(tasks) == 2
            assert tasks[0].task_id == "task-001"
            assert tasks[0].title == "Task One"
            assert tasks[1].task_id == "task-002"
            assert tasks[1].working_directory is None

    @pytest.mark.asyncio
    async def test_get_pending_tasks_empty(self):
        """Should return empty list when no tasks."""
        client = MCPClient("/tmp/test.sock")
        client._session_token = "test-session-token"  # Must be authenticated

        mock_response = {
            "success": True,
            "tasks": []
        }

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            # No agent_id argument - derived from session token internally
            tasks = await client.get_pending_tasks()

            assert tasks == []

    @pytest.mark.asyncio
    async def test_get_pending_tasks_session_expired(self):
        """Should raise SessionExpiredError when session expired."""
        client = MCPClient("/tmp/test.sock")
        client._session_token = "test-session-token"  # Must be authenticated

        mock_response = {
            "success": False,
            "error": "Session expired"
        }

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            with pytest.raises(SessionExpiredError):
                # No agent_id argument - derived from session token internally
                await client.get_pending_tasks()


class TestMCPClientReportExecution:
    """Tests for execution reporting methods."""

    @pytest.mark.asyncio
    async def test_report_execution_start(self):
        """Should report execution start."""
        client = MCPClient("/tmp/test.sock")
        client._session_token = "test-session-token"  # Must be authenticated

        mock_response = {
            "success": True,
            "execution_log_id": "exec-001",
            "started_at": "2025-01-06T10:00:00Z"
        }

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            # No agent_id argument - derived from session token internally
            result = await client.report_execution_start("task-001")

            assert isinstance(result, ExecutionStartResult)
            assert result.execution_id == "exec-001"

    @pytest.mark.asyncio
    async def test_report_execution_complete(self):
        """Should report execution complete."""
        client = MCPClient("/tmp/test.sock")
        client._session_token = "test-session-token"  # Must be authenticated

        mock_response = {"success": True}

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            await client.report_execution_complete(
                execution_id="exec-001",
                exit_code=0,
                duration_seconds=120.5,
                log_file_path="/tmp/log.txt"
            )

            mock_call.assert_called_once()
            call_args = mock_call.call_args[0]
            assert call_args[0] == "report_execution_complete"
            assert call_args[1]["execution_log_id"] == "exec-001"
            assert call_args[1]["exit_code"] == 0
            assert call_args[1]["duration_seconds"] == 120.5


class TestMCPClientTaskOperations:
    """Tests for task operation methods."""

    @pytest.mark.asyncio
    async def test_update_task_status(self):
        """Should update task status."""
        client = MCPClient("/tmp/test.sock")

        mock_response = {"success": True}

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            await client.update_task_status("task-001", "done", "Task completed")

            mock_call.assert_called_once_with("update_task_status", {
                "task_id": "task-001",
                "status": "done",
                "reason": "Task completed"
            })

    @pytest.mark.asyncio
    async def test_save_context(self):
        """Should save task context."""
        client = MCPClient("/tmp/test.sock")

        mock_response = {"success": True}

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            await client.save_context(
                task_id="task-001",
                progress="50% complete",
                findings="Found bug",
                next_steps="Fix bug"
            )

            mock_call.assert_called_once()
            call_args = mock_call.call_args[0]
            assert call_args[1]["task_id"] == "task-001"
            assert call_args[1]["progress"] == "50% complete"
