# tests/integration/test_runner_integration.py
# Integration tests for Runner (with mocked MCP server)
# Reference: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-6

import asyncio
import pytest
from datetime import datetime
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

from aiagent_runner.config import RunnerConfig
from aiagent_runner.executor import ExecutionResult
from aiagent_runner.mcp_client import (
    AuthResult,
    ExecutionStartResult,
    MCPClient,
    SessionExpiredError,
    TaskInfo,
)
from aiagent_runner.runner import Runner


class MockMCPServer:
    """Mock MCP server for integration testing."""

    def __init__(self):
        self.agents = {}
        self.tasks = {}
        self.execution_logs = []
        self.contexts = {}
        self.sessions = {}

    def create_agent(self, agent_id: str, name: str, passkey: str):
        """Create a test agent."""
        self.agents[agent_id] = {
            "agent_id": agent_id,
            "name": name,
            "passkey": passkey
        }

    def create_task(
        self,
        task_id: str,
        project_id: str,
        title: str,
        description: str = "",
        assignee_id: str = None,
        status: str = "in_progress",
        priority: str = "medium"
    ):
        """Create a test task."""
        self.tasks[task_id] = {
            "task_id": task_id,
            "project_id": project_id,
            "title": title,
            "description": description,
            "assignee_id": assignee_id,
            "status": status,
            "priority": priority
        }

    async def authenticate(self, agent_id: str, passkey: str) -> dict:
        """Authenticate an agent."""
        agent = self.agents.get(agent_id)
        if not agent or agent["passkey"] != passkey:
            return {"success": False, "error": "Invalid credentials"}

        session_token = f"session_{agent_id}_{datetime.now().timestamp()}"
        self.sessions[session_token] = agent_id
        return {
            "success": True,
            "session_token": session_token,
            "expires_in": 3600,
            "agent_name": agent["name"]
        }

    async def get_pending_tasks(self, agent_id: str) -> dict:
        """Get pending tasks for an agent."""
        pending = [
            t for t in self.tasks.values()
            if t.get("assignee_id") == agent_id and t.get("status") == "in_progress"
        ]
        return {
            "success": True,
            "tasks": pending
        }

    async def report_execution_start(self, task_id: str, agent_id: str) -> dict:
        """Report execution start."""
        exec_id = f"exec_{task_id}_{len(self.execution_logs)}"
        log = {
            "execution_id": exec_id,
            "task_id": task_id,
            "agent_id": agent_id,
            "started_at": datetime.now().isoformat(),
            "status": "running"
        }
        self.execution_logs.append(log)
        return {
            "success": True,
            "execution_log_id": exec_id,
            "started_at": log["started_at"]
        }

    async def report_execution_complete(
        self,
        execution_id: str,
        exit_code: int,
        duration_seconds: float,
        log_file_path: str = None,
        error_message: str = None
    ) -> dict:
        """Report execution complete."""
        for log in self.execution_logs:
            if log["execution_id"] == execution_id:
                log["status"] = "completed" if exit_code == 0 else "failed"
                log["exit_code"] = exit_code
                log["duration_seconds"] = duration_seconds
                log["log_file_path"] = log_file_path
                log["error_message"] = error_message
                break
        return {"success": True}

    async def save_context(self, task_id: str, **kwargs) -> dict:
        """Save task context."""
        self.contexts[task_id] = kwargs
        return {"success": True}


@pytest.fixture
def mock_mcp_server():
    """Create a mock MCP server."""
    server = MockMCPServer()
    # Setup default test data
    server.create_agent(
        agent_id="agt_integration_test",
        name="Integration Test Agent",
        passkey="integration_secret"
    )
    server.create_task(
        task_id="tsk_integration_001",
        project_id="prj_integration",
        title="Integration Test Task",
        description="A task for integration testing",
        assignee_id="agt_integration_test",
        status="in_progress",
        priority="high"
    )
    return server


@pytest.fixture
def integration_config(tmp_path):
    """Create configuration for integration tests."""
    log_dir = tmp_path / "logs"
    log_dir.mkdir()
    work_dir = tmp_path / "workspace"
    work_dir.mkdir()

    return RunnerConfig(
        agent_id="agt_integration_test",
        passkey="integration_secret",
        polling_interval=1,
        cli_command="echo",  # Use echo for testing
        cli_args=[],
        working_directory=str(work_dir),
        log_directory=str(log_dir)
    )


class TestRunnerIntegration:
    """Integration tests for Runner with mocked MCP server."""

    @pytest.mark.asyncio
    async def test_full_task_execution_cycle(
        self, mock_mcp_server, integration_config
    ):
        """Test complete task execution cycle."""
        runner = Runner(integration_config)

        # Mock MCP client methods to use our mock server
        async def mock_authenticate(agent_id, passkey):
            result = await mock_mcp_server.authenticate(agent_id, passkey)
            if not result["success"]:
                from aiagent_runner.mcp_client import AuthenticationError
                raise AuthenticationError(result["error"])
            return AuthResult(
                session_token=result["session_token"],
                expires_in=result["expires_in"],
                agent_name=result.get("agent_name")
            )

        async def mock_get_pending_tasks():
            # agent_id is derived from session token internally
            agent_id = integration_config.agent_id
            result = await mock_mcp_server.get_pending_tasks(agent_id)
            return [
                TaskInfo(
                    task_id=t["task_id"],
                    project_id=t["project_id"],
                    title=t["title"],
                    description=t["description"],
                    priority=t["priority"]
                )
                for t in result["tasks"]
            ]

        async def mock_report_start(task_id):
            # agent_id is derived from session token internally
            agent_id = integration_config.agent_id
            result = await mock_mcp_server.report_execution_start(task_id, agent_id)
            return ExecutionStartResult(
                execution_id=result["execution_log_id"],
                started_at=datetime.fromisoformat(result["started_at"])
            )

        async def mock_report_complete(exec_id, exit_code, duration, log_path=None, error=None):
            await mock_mcp_server.report_execution_complete(
                exec_id, exit_code, duration, log_path, error
            )

        with patch.object(runner.mcp_client, "authenticate", mock_authenticate), \
             patch.object(runner.mcp_client, "get_pending_tasks", mock_get_pending_tasks), \
             patch.object(runner.mcp_client, "report_execution_start", mock_report_start), \
             patch.object(runner.mcp_client, "report_execution_complete", mock_report_complete):

            # Execute one cycle
            await runner._run_once()

            # Verify authentication occurred
            assert runner._authenticated is True
            assert runner._agent_name == "Integration Test Agent"

            # Verify execution log was created
            assert len(mock_mcp_server.execution_logs) == 1
            log = mock_mcp_server.execution_logs[0]
            assert log["task_id"] == "tsk_integration_001"
            assert log["status"] == "completed"
            assert log["exit_code"] == 0

    @pytest.mark.asyncio
    async def test_authentication_failure(self, mock_mcp_server, integration_config):
        """Test authentication failure handling."""
        # Use wrong passkey
        integration_config.passkey = "wrong_passkey"
        runner = Runner(integration_config)

        async def mock_authenticate(agent_id, passkey):
            result = await mock_mcp_server.authenticate(agent_id, passkey)
            if not result["success"]:
                from aiagent_runner.mcp_client import AuthenticationError
                raise AuthenticationError(result["error"])
            return AuthResult(
                session_token=result["session_token"],
                expires_in=result["expires_in"]
            )

        with patch.object(runner.mcp_client, "authenticate", mock_authenticate):
            from aiagent_runner.mcp_client import AuthenticationError
            with pytest.raises(AuthenticationError):
                await runner._ensure_authenticated()

    @pytest.mark.asyncio
    async def test_no_pending_tasks(self, mock_mcp_server, integration_config):
        """Test handling when no tasks are pending."""
        # Remove the task's assignee
        mock_mcp_server.tasks["tsk_integration_001"]["assignee_id"] = "other_agent"

        runner = Runner(integration_config)
        runner._authenticated = True
        runner.prompt_builder = MagicMock()

        async def mock_get_pending_tasks():
            # agent_id is derived from session token internally
            agent_id = integration_config.agent_id
            result = await mock_mcp_server.get_pending_tasks(agent_id)
            return []

        with patch.object(runner.mcp_client, "get_pending_tasks", mock_get_pending_tasks):
            # Should complete without error
            await runner._run_once()

            # No execution logs should be created
            assert len(mock_mcp_server.execution_logs) == 0

    @pytest.mark.asyncio
    async def test_multiple_tasks_processes_first(
        self, mock_mcp_server, integration_config
    ):
        """Test that only the first task is processed per cycle."""
        # Add another task
        mock_mcp_server.create_task(
            task_id="tsk_integration_002",
            project_id="prj_integration",
            title="Second Task",
            description="Another task",
            assignee_id="agt_integration_test",
            status="in_progress"
        )

        runner = Runner(integration_config)

        async def mock_authenticate(agent_id, passkey):
            result = await mock_mcp_server.authenticate(agent_id, passkey)
            return AuthResult(
                session_token=result["session_token"],
                expires_in=result["expires_in"],
                agent_name=result.get("agent_name")
            )

        async def mock_get_pending_tasks():
            # agent_id is derived from session token internally
            agent_id = integration_config.agent_id
            result = await mock_mcp_server.get_pending_tasks(agent_id)
            return [
                TaskInfo(
                    task_id=t["task_id"],
                    project_id=t["project_id"],
                    title=t["title"],
                    description=t["description"],
                    priority=t["priority"]
                )
                for t in result["tasks"]
            ]

        async def mock_report_start(task_id):
            # agent_id is derived from session token internally
            agent_id = integration_config.agent_id
            result = await mock_mcp_server.report_execution_start(task_id, agent_id)
            return ExecutionStartResult(
                execution_id=result["execution_log_id"],
                started_at=datetime.fromisoformat(result["started_at"])
            )

        async def mock_report_complete(exec_id, exit_code, duration, log_path=None, error=None):
            await mock_mcp_server.report_execution_complete(
                exec_id, exit_code, duration, log_path, error
            )

        with patch.object(runner.mcp_client, "authenticate", mock_authenticate), \
             patch.object(runner.mcp_client, "get_pending_tasks", mock_get_pending_tasks), \
             patch.object(runner.mcp_client, "report_execution_start", mock_report_start), \
             patch.object(runner.mcp_client, "report_execution_complete", mock_report_complete):

            # Execute one cycle
            await runner._run_once()

            # Only one task should be processed
            assert len(mock_mcp_server.execution_logs) == 1

    @pytest.mark.asyncio
    async def test_session_expiry_and_renewal(
        self, mock_mcp_server, integration_config
    ):
        """Test session expiry and automatic renewal."""
        runner = Runner(integration_config)

        call_count = {"auth": 0, "tasks": 0}

        async def mock_authenticate(agent_id, passkey):
            call_count["auth"] += 1
            result = await mock_mcp_server.authenticate(agent_id, passkey)
            return AuthResult(
                session_token=result["session_token"],
                expires_in=result["expires_in"],
                agent_name=result.get("agent_name")
            )

        async def mock_get_pending_tasks():
            # agent_id is derived from session token internally
            agent_id = integration_config.agent_id
            call_count["tasks"] += 1
            if call_count["tasks"] == 1:
                # First call raises session expired
                raise SessionExpiredError("Session expired")
            result = await mock_mcp_server.get_pending_tasks(agent_id)
            return []

        with patch.object(runner.mcp_client, "authenticate", mock_authenticate), \
             patch.object(runner.mcp_client, "get_pending_tasks", mock_get_pending_tasks):

            # First authenticate
            await runner._ensure_authenticated()
            assert call_count["auth"] == 1

            # Run once - should trigger re-auth
            await runner._run_once()

            # Should have authenticated twice (initial + renewal)
            assert call_count["auth"] == 2


class TestRunnerExecutionLogging:
    """Integration tests for execution logging."""

    @pytest.mark.asyncio
    async def test_log_file_created(self, mock_mcp_server, integration_config):
        """Test that log files are created during execution."""
        runner = Runner(integration_config)

        async def mock_authenticate(agent_id, passkey):
            result = await mock_mcp_server.authenticate(agent_id, passkey)
            return AuthResult(
                session_token=result["session_token"],
                expires_in=result["expires_in"],
                agent_name=result.get("agent_name")
            )

        async def mock_get_pending_tasks():
            # agent_id is derived from session token internally
            agent_id = integration_config.agent_id
            result = await mock_mcp_server.get_pending_tasks(agent_id)
            return [
                TaskInfo(
                    task_id=t["task_id"],
                    project_id=t["project_id"],
                    title=t["title"],
                    description=t["description"],
                    priority=t["priority"]
                )
                for t in result["tasks"]
            ]

        async def mock_report_start(task_id):
            # agent_id is derived from session token internally
            agent_id = integration_config.agent_id
            result = await mock_mcp_server.report_execution_start(task_id, agent_id)
            return ExecutionStartResult(
                execution_id=result["execution_log_id"],
                started_at=datetime.fromisoformat(result["started_at"])
            )

        async def mock_report_complete(exec_id, exit_code, duration, log_path=None, error=None):
            await mock_mcp_server.report_execution_complete(
                exec_id, exit_code, duration, log_path, error
            )

        with patch.object(runner.mcp_client, "authenticate", mock_authenticate), \
             patch.object(runner.mcp_client, "get_pending_tasks", mock_get_pending_tasks), \
             patch.object(runner.mcp_client, "report_execution_start", mock_report_start), \
             patch.object(runner.mcp_client, "report_execution_complete", mock_report_complete):

            await runner._run_once()

            # Check log file was created
            log_dir = Path(integration_config.log_directory)
            log_files = list(log_dir.glob("*.log"))
            assert len(log_files) == 1

            # Check log content
            log_content = log_files[0].read_text()
            assert "=== PROMPT ===" in log_content
            assert "=== OUTPUT ===" in log_content
            assert "Integration Test Task" in log_content

    @pytest.mark.asyncio
    async def test_execution_failure_logged(
        self, mock_mcp_server, integration_config
    ):
        """Test that execution failures are properly logged."""
        # Use a command that will fail
        integration_config.cli_command = "false"  # Always returns exit code 1
        integration_config.cli_args = []

        runner = Runner(integration_config)

        async def mock_authenticate(agent_id, passkey):
            result = await mock_mcp_server.authenticate(agent_id, passkey)
            return AuthResult(
                session_token=result["session_token"],
                expires_in=result["expires_in"],
                agent_name=result.get("agent_name")
            )

        async def mock_get_pending_tasks():
            # agent_id is derived from session token internally
            agent_id = integration_config.agent_id
            result = await mock_mcp_server.get_pending_tasks(agent_id)
            return [
                TaskInfo(
                    task_id=t["task_id"],
                    project_id=t["project_id"],
                    title=t["title"],
                    description=t["description"],
                    priority=t["priority"]
                )
                for t in result["tasks"]
            ]

        async def mock_report_start(task_id):
            # agent_id is derived from session token internally
            agent_id = integration_config.agent_id
            result = await mock_mcp_server.report_execution_start(task_id, agent_id)
            return ExecutionStartResult(
                execution_id=result["execution_log_id"],
                started_at=datetime.fromisoformat(result["started_at"])
            )

        async def mock_report_complete(exec_id, exit_code, duration, log_path=None, error=None):
            await mock_mcp_server.report_execution_complete(
                exec_id, exit_code, duration, log_path, error
            )

        with patch.object(runner.mcp_client, "authenticate", mock_authenticate), \
             patch.object(runner.mcp_client, "get_pending_tasks", mock_get_pending_tasks), \
             patch.object(runner.mcp_client, "report_execution_start", mock_report_start), \
             patch.object(runner.mcp_client, "report_execution_complete", mock_report_complete):

            await runner._run_once()

            # Verify failure was recorded
            log = mock_mcp_server.execution_logs[0]
            assert log["status"] == "failed"
            assert log["exit_code"] == 1
            assert log["error_message"] is not None


class TestRunnerPromptBuilding:
    """Integration tests for prompt building."""

    @pytest.mark.asyncio
    async def test_prompt_includes_task_details(
        self, mock_mcp_server, integration_config
    ):
        """Test that prompts include all task details."""
        runner = Runner(integration_config)

        captured_prompt = None

        original_execute = runner.executor.execute

        def capture_execute(prompt, working_dir, log_file):
            nonlocal captured_prompt
            captured_prompt = prompt
            return original_execute(prompt, working_dir, log_file)

        async def mock_authenticate(agent_id, passkey):
            result = await mock_mcp_server.authenticate(agent_id, passkey)
            return AuthResult(
                session_token=result["session_token"],
                expires_in=result["expires_in"],
                agent_name=result.get("agent_name")
            )

        async def mock_get_pending_tasks():
            # agent_id is derived from session token internally
            agent_id = integration_config.agent_id
            result = await mock_mcp_server.get_pending_tasks(agent_id)
            return [
                TaskInfo(
                    task_id=t["task_id"],
                    project_id=t["project_id"],
                    title=t["title"],
                    description=t["description"],
                    priority=t["priority"]
                )
                for t in result["tasks"]
            ]

        async def mock_report_start(task_id):
            # agent_id is derived from session token internally
            agent_id = integration_config.agent_id
            result = await mock_mcp_server.report_execution_start(task_id, agent_id)
            return ExecutionStartResult(
                execution_id=result["execution_log_id"],
                started_at=datetime.fromisoformat(result["started_at"])
            )

        async def mock_report_complete(exec_id, exit_code, duration, log_path=None, error=None):
            pass

        with patch.object(runner.mcp_client, "authenticate", mock_authenticate), \
             patch.object(runner.mcp_client, "get_pending_tasks", mock_get_pending_tasks), \
             patch.object(runner.mcp_client, "report_execution_start", mock_report_start), \
             patch.object(runner.mcp_client, "report_execution_complete", mock_report_complete), \
             patch.object(runner.executor, "execute", capture_execute):

            await runner._run_once()

            # Verify prompt content
            assert captured_prompt is not None
            assert "Integration Test Task" in captured_prompt
            assert "tsk_integration_001" in captured_prompt
            assert "prj_integration" in captured_prompt
            assert "agt_integration_test" in captured_prompt
            assert "high" in captured_prompt  # priority
