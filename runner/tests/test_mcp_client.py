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

    def test_init_with_coordinator_token(self):
        """Should store coordinator token for Coordinator-only API calls."""
        client = MCPClient("/tmp/test.sock", coordinator_token="test-token-123")
        assert client._coordinator_token == "test-token-123"

    def test_init_coordinator_token_from_env(self):
        """Should read coordinator token from environment if not provided."""
        import os
        original = os.environ.get("MCP_COORDINATOR_TOKEN")
        try:
            os.environ["MCP_COORDINATOR_TOKEN"] = "env-token-456"
            client = MCPClient("/tmp/test.sock")
            assert client._coordinator_token == "env-token-456"
        finally:
            if original:
                os.environ["MCP_COORDINATOR_TOKEN"] = original
            elif "MCP_COORDINATOR_TOKEN" in os.environ:
                del os.environ["MCP_COORDINATOR_TOKEN"]


class TestMCPClientAuthenticate:
    """Tests for MCPClient.authenticate()."""

    @pytest.mark.asyncio
    async def test_authenticate_success(self):
        """Should authenticate successfully with project_id (Phase 4)."""
        client = MCPClient("/tmp/test.sock")

        mock_response = {
            "success": True,
            "session_token": "token-12345",
            "expires_in": 3600,
            "agent_name": "Test Agent"
        }

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            result = await client.authenticate("agent-001", "passkey", "project-001")

            assert isinstance(result, AuthResult)
            assert result.session_token == "token-12345"
            assert result.expires_in == 3600
            assert result.agent_name == "Test Agent"

            mock_call.assert_called_once_with("authenticate", {
                "agent_id": "agent-001",
                "passkey": "passkey",
                "project_id": "project-001"
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
                await client.authenticate("agent-001", "wrong-passkey", "project-001")


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


class TestMCPClientCoordinatorAPI:
    """Tests for Coordinator-only API methods (Phase 5)."""

    @pytest.mark.asyncio
    async def test_health_check_with_coordinator_token(self):
        """Should pass coordinator_token for health_check."""
        client = MCPClient("/tmp/test.sock", coordinator_token="coord-token-123")

        mock_response = {
            "status": "ok",
            "version": "1.0.0",
            "timestamp": "2025-01-10T12:00:00Z"
        }

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            result = await client.health_check()

            assert result.status == "ok"
            assert result.version == "1.0.0"
            mock_call.assert_called_once_with("health_check", {
                "coordinator_token": "coord-token-123"
            })

    @pytest.mark.asyncio
    async def test_health_check_without_coordinator_token(self):
        """Should call health_check without token if not configured."""
        client = MCPClient("/tmp/test.sock")
        client._coordinator_token = None  # Ensure no token

        mock_response = {"status": "ok"}

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            await client.health_check()

            mock_call.assert_called_once_with("health_check", {})

    @pytest.mark.asyncio
    async def test_should_start_with_coordinator_token(self):
        """Should pass coordinator_token for should_start."""
        client = MCPClient("/tmp/test.sock", coordinator_token="coord-token-456")

        mock_response = {
            "should_start": True,
            "provider": "claude",
            "model": "claude-sonnet-4-5",
            "task_id": "task-789"
        }

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            result = await client.should_start("agent-001", "project-001")

            assert result.should_start is True
            assert result.provider == "claude"
            assert result.model == "claude-sonnet-4-5"
            assert result.task_id == "task-789"
            mock_call.assert_called_once_with("should_start", {
                "agent_id": "agent-001",
                "project_id": "project-001",
                "coordinator_token": "coord-token-456"
            })

    @pytest.mark.asyncio
    async def test_register_execution_log_file_with_coordinator_token(self):
        """Should pass coordinator_token for register_execution_log_file."""
        client = MCPClient("/tmp/test.sock", coordinator_token="coord-token-789")

        mock_response = {"success": True}

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            result = await client.register_execution_log_file(
                "agent-001", "task-001", "/tmp/log.txt"
            )

            assert result is True
            mock_call.assert_called_once_with("register_execution_log_file", {
                "agent_id": "agent-001",
                "task_id": "task-001",
                "log_file_path": "/tmp/log.txt",
                "coordinator_token": "coord-token-789"
            })

    @pytest.mark.asyncio
    async def test_invalidate_session_with_coordinator_token(self):
        """Should pass coordinator_token for invalidate_session."""
        client = MCPClient("/tmp/test.sock", coordinator_token="coord-token-abc")

        mock_response = {"success": True}

        with patch.object(client, "_call_tool", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = mock_response

            result = await client.invalidate_session("agent-001", "project-001")

            assert result is True
            mock_call.assert_called_once_with("invalidate_session", {
                "agent_id": "agent-001",
                "project_id": "project-001",
                "coordinator_token": "coord-token-abc"
            })
