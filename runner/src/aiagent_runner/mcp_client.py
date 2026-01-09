# src/aiagent_runner/mcp_client.py
# MCP client for communication with AI Agent PM server
# Reference: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-5
# Reference: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md

import asyncio
import json
import os
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional


class AuthenticationError(Exception):
    """Raised when authentication fails."""
    pass


class SessionExpiredError(Exception):
    """Raised when session token has expired."""
    pass


class MCPError(Exception):
    """General MCP communication error."""
    pass


# Phase 4: Coordinator API data classes

@dataclass
class HealthCheckResult:
    """Result of health check."""
    status: str
    version: Optional[str] = None
    timestamp: Optional[str] = None


@dataclass
class ProjectWithAgents:
    """Project with its assigned agents."""
    project_id: str
    project_name: str
    working_directory: str
    agents: list[str] = field(default_factory=list)


@dataclass
class ShouldStartResult:
    """Result of should_start check."""
    should_start: bool
    provider: Optional[str] = None       # "claude", "gemini", "openai", "other"
    model: Optional[str] = None          # "claude-sonnet-4-5", "gemini-2.0-flash", etc.
    kick_command: Optional[str] = None   # Custom CLI command (takes priority if set)
    ai_type: Optional[str] = None        # Deprecated: use provider/model instead
    task_id: Optional[str] = None        # Phase 4: タスクID（ログファイル登録用）


# Phase 3/4: Agent API data classes

@dataclass
class AuthResult:
    """Result of authentication."""
    session_token: str
    expires_in: int
    agent_name: Optional[str] = None
    system_prompt: Optional[str] = None
    instruction: Optional[str] = None


@dataclass
class TaskInfo:
    """Information about a pending task."""
    task_id: str
    project_id: str
    title: str
    description: str
    priority: str
    working_directory: Optional[str] = None
    context: Optional[dict] = None
    handoff: Optional[dict] = None


@dataclass
class ExecutionStartResult:
    """Result of reporting execution start."""
    execution_id: str
    started_at: datetime


class MCPClient:
    """Client for MCP server communication.

    Handles authentication, task retrieval, and execution reporting.
    """

    def __init__(self, socket_path: Optional[str] = None):
        """Initialize MCP client.

        Args:
            socket_path: Path to MCP Unix socket. Defaults to standard location.
        """
        # Always expand tilde in socket path
        if socket_path:
            self.socket_path = os.path.expanduser(socket_path)
        else:
            self.socket_path = self._default_socket_path()
        self._session_token: Optional[str] = None

    def _default_socket_path(self) -> str:
        """Get default MCP socket path."""
        return os.path.expanduser(
            "~/Library/Application Support/AIAgentPM/mcp.sock"
        )

    async def _call_tool(self, tool_name: str, args: dict) -> dict:
        """Call an MCP tool via Unix socket.

        Args:
            tool_name: Name of the tool to call
            args: Arguments for the tool

        Returns:
            Tool result as dictionary

        Raises:
            MCPError: If communication fails
        """
        try:
            reader, writer = await asyncio.open_unix_connection(self.socket_path)
        except (ConnectionRefusedError, FileNotFoundError) as e:
            raise MCPError(f"Cannot connect to MCP server at {self.socket_path}: {e}")

        try:
            request = json.dumps({
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {"name": tool_name, "arguments": args},
                "id": 1
            })
            writer.write(request.encode() + b"\n")
            await writer.drain()

            response = await reader.readline()
            data = json.loads(response)

            if "error" in data:
                raise MCPError(data["error"].get("message", "Unknown error"))

            # Parse MCP protocol response format
            # MCP returns: {"result": {"content": [{"type": "text", "text": "JSON"}]}}
            result = data.get("result", {})
            content = result.get("content", [])
            if content and isinstance(content, list) and len(content) > 0:
                first_content = content[0]
                if isinstance(first_content, dict) and first_content.get("type") == "text":
                    text = first_content.get("text", "{}")
                    try:
                        return json.loads(text)
                    except json.JSONDecodeError:
                        return {"text": text}
            return result
        finally:
            writer.close()
            await writer.wait_closed()

    # ==========================================================================
    # Phase 4: Coordinator API
    # Reference: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    # ==========================================================================

    async def health_check(self) -> HealthCheckResult:
        """Check MCP server health.

        The Coordinator calls this first to verify the server is available.

        Returns:
            HealthCheckResult with server status

        Raises:
            MCPError: If server is not available
        """
        result = await self._call_tool("health_check", {})
        return HealthCheckResult(
            status=result.get("status", "ok"),
            version=result.get("version"),
            timestamp=result.get("timestamp")
        )

    async def list_active_projects_with_agents(self) -> list[ProjectWithAgents]:
        """Get all active projects with their assigned agents.

        The Coordinator calls this to discover what (agent_id, project_id)
        combinations exist and need to be monitored.

        Returns:
            List of ProjectWithAgents

        Raises:
            MCPError: If request fails
        """
        result = await self._call_tool("list_active_projects_with_agents", {})

        if not result.get("success", True):
            raise MCPError(result.get("error", "Failed to list projects"))

        projects = []
        for p in result.get("projects", []):
            projects.append(ProjectWithAgents(
                project_id=p.get("project_id", p.get("projectId", "")),
                project_name=p.get("project_name", p.get("projectName", p.get("name", ""))),
                working_directory=p.get("working_directory", p.get("workingDirectory", "")),
                agents=p.get("agents", [])
            ))
        return projects

    async def should_start(self, agent_id: str, project_id: str) -> ShouldStartResult:
        """Check if an Agent Instance should be started.

        The Coordinator calls this for each (agent_id, project_id) pair
        to determine if there's work to do.

        Args:
            agent_id: Agent ID
            project_id: Project ID

        Returns:
            ShouldStartResult with should_start flag, provider, model, and kick_command

        Raises:
            MCPError: If request fails
        """
        result = await self._call_tool("should_start", {
            "agent_id": agent_id,
            "project_id": project_id
        })

        return ShouldStartResult(
            should_start=result.get("should_start", False),
            provider=result.get("provider"),
            model=result.get("model"),
            kick_command=result.get("kick_command"),
            ai_type=result.get("ai_type"),  # Deprecated, kept for backwards compatibility
            task_id=result.get("task_id")  # Phase 4: Coordinatorがログファイルパス登録に使用
        )

    async def register_execution_log_file(
        self, agent_id: str, task_id: str, log_file_path: str
    ) -> bool:
        """Register log file path for an execution log.

        Called by Coordinator after Agent Instance process completes.
        No authentication required.

        Args:
            agent_id: Agent ID
            task_id: Task ID
            log_file_path: Absolute path to the log file

        Returns:
            True if successful, False otherwise

        Raises:
            MCPError: If request fails
        """
        result = await self._call_tool("register_execution_log_file", {
            "agent_id": agent_id,
            "task_id": task_id,
            "log_file_path": log_file_path
        })

        return result.get("success", False)

    async def invalidate_session(self, agent_id: str, project_id: str) -> bool:
        """Invalidate session for an agent-project pair.

        Called by Coordinator when Agent Instance process exits.
        This allows shouldStart to return True again for the next instance.
        No authentication required.

        Args:
            agent_id: Agent ID
            project_id: Project ID

        Returns:
            True if successful, False otherwise

        Raises:
            MCPError: If request fails
        """
        result = await self._call_tool("invalidate_session", {
            "agent_id": agent_id,
            "project_id": project_id
        })

        return result.get("success", False)

    # ==========================================================================
    # Phase 3/4: Agent Instance API
    # ==========================================================================

    async def authenticate(self, agent_id: str, passkey: str, project_id: str) -> AuthResult:
        """Authenticate with the MCP server.

        Args:
            agent_id: Agent ID
            passkey: Agent passkey
            project_id: Project ID (Phase 4: required for session management)

        Returns:
            AuthResult with session token

        Raises:
            AuthenticationError: If authentication fails
        """
        result = await self._call_tool("authenticate", {
            "agent_id": agent_id,
            "passkey": passkey,
            "project_id": project_id
        })

        if not result.get("success"):
            raise AuthenticationError(result.get("error", "Authentication failed"))

        self._session_token = result["session_token"]
        return AuthResult(
            session_token=result["session_token"],
            expires_in=result.get("expires_in", 3600),
            agent_name=result.get("agent_name"),
            system_prompt=result.get("system_prompt"),
            instruction=result.get("instruction")
        )

    async def get_pending_tasks(self) -> list[TaskInfo]:
        """Get pending tasks for the authenticated agent.

        Returns:
            List of pending TaskInfo objects

        Raises:
            SessionExpiredError: If session has expired
            MCPError: If request fails or not authenticated
        """
        if not self._session_token:
            raise MCPError("Not authenticated. Call authenticate() first.")

        result = await self._call_tool("get_pending_tasks", {
            "session_token": self._session_token
        })

        if not result.get("success"):
            error = result.get("error", "")
            if "expired" in error.lower() or "invalid" in error.lower():
                raise SessionExpiredError(error)
            raise MCPError(error)

        tasks = []
        for t in result.get("tasks", []):
            tasks.append(TaskInfo(
                task_id=t.get("task_id", t.get("taskId", t.get("id", ""))),
                project_id=t.get("project_id", t.get("projectId", "")),
                title=t.get("title", ""),
                description=t.get("description", ""),
                priority=t.get("priority", "medium"),
                working_directory=t.get("working_directory", t.get("workingDirectory")),
                context=t.get("context"),
                handoff=t.get("handoff")
            ))
        return tasks

    async def report_execution_start(
        self, task_id: str
    ) -> ExecutionStartResult:
        """Report that task execution has started.

        Args:
            task_id: Task ID being executed

        Returns:
            ExecutionStartResult with execution ID

        Raises:
            MCPError: If reporting fails or not authenticated
        """
        if not self._session_token:
            raise MCPError("Not authenticated. Call authenticate() first.")

        result = await self._call_tool("report_execution_start", {
            "session_token": self._session_token,
            "task_id": task_id
        })

        if not result.get("success"):
            raise MCPError(result.get("error", "Failed to report execution start"))

        started_at_str = result.get("started_at", datetime.now().isoformat())
        if started_at_str.endswith("Z"):
            started_at_str = started_at_str[:-1] + "+00:00"

        return ExecutionStartResult(
            execution_id=result.get("execution_log_id", result.get("execution_id", "")),
            started_at=datetime.fromisoformat(started_at_str)
        )

    async def report_execution_complete(
        self,
        execution_id: str,
        exit_code: int,
        duration_seconds: float,
        log_file_path: Optional[str] = None,
        error_message: Optional[str] = None
    ) -> None:
        """Report that task execution has completed.

        Args:
            execution_id: Execution log ID from report_execution_start
            exit_code: Exit code of the CLI process
            duration_seconds: Duration of execution in seconds
            log_file_path: Path to log file (optional)
            error_message: Error message if execution failed (optional)

        Raises:
            MCPError: If reporting fails or not authenticated
        """
        if not self._session_token:
            raise MCPError("Not authenticated. Call authenticate() first.")

        args = {
            "session_token": self._session_token,
            "execution_log_id": execution_id,
            "exit_code": exit_code,
            "duration_seconds": duration_seconds
        }
        if log_file_path:
            args["log_file_path"] = log_file_path
        if error_message:
            args["error_message"] = error_message

        result = await self._call_tool("report_execution_complete", args)

        if not result.get("success"):
            raise MCPError(result.get("error", "Failed to report execution complete"))

    async def update_task_status(
        self, task_id: str, status: str, reason: Optional[str] = None
    ) -> None:
        """Update task status.

        Args:
            task_id: Task ID to update
            status: New status (todo, in_progress, done, etc.)
            reason: Reason for status change (optional)

        Raises:
            MCPError: If update fails
        """
        args = {
            "task_id": task_id,
            "status": status
        }
        if reason:
            args["reason"] = reason

        result = await self._call_tool("update_task_status", args)

        if not result.get("success"):
            raise MCPError(result.get("error", "Failed to update task status"))

    async def save_context(
        self,
        task_id: str,
        progress: Optional[str] = None,
        findings: Optional[str] = None,
        blockers: Optional[str] = None,
        next_steps: Optional[str] = None,
        agent_id: Optional[str] = None
    ) -> None:
        """Save task context.

        Args:
            task_id: Task ID
            progress: Current progress description
            findings: Findings or discoveries
            blockers: Current blockers
            next_steps: Recommended next steps
            agent_id: Agent ID (optional)

        Raises:
            MCPError: If save fails
        """
        args = {"task_id": task_id}
        if progress:
            args["progress"] = progress
        if findings:
            args["findings"] = findings
        if blockers:
            args["blockers"] = blockers
        if next_steps:
            args["next_steps"] = next_steps
        if agent_id:
            args["agent_id"] = agent_id

        result = await self._call_tool("save_context", args)

        if not result.get("success"):
            raise MCPError(result.get("error", "Failed to save context"))
