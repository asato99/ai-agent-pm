# src/aiagent_runner/mcp_client.py
# MCP client for communication with AI Agent PM server
# Reference: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-5

import asyncio
import json
import os
from dataclasses import dataclass
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


@dataclass
class AuthResult:
    """Result of authentication."""
    session_token: str
    expires_in: int
    agent_name: Optional[str] = None


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
        self.socket_path = socket_path or self._default_socket_path()
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

            return data.get("result", {})
        finally:
            writer.close()
            await writer.wait_closed()

    async def authenticate(self, agent_id: str, passkey: str) -> AuthResult:
        """Authenticate with the MCP server.

        Args:
            agent_id: Agent ID
            passkey: Agent passkey

        Returns:
            AuthResult with session token

        Raises:
            AuthenticationError: If authentication fails
        """
        result = await self._call_tool("authenticate", {
            "agent_id": agent_id,
            "passkey": passkey
        })

        if not result.get("success"):
            raise AuthenticationError(result.get("error", "Authentication failed"))

        self._session_token = result["session_token"]
        return AuthResult(
            session_token=result["session_token"],
            expires_in=result.get("expires_in", 3600),
            agent_name=result.get("agent_name")
        )

    async def get_pending_tasks(self, agent_id: str) -> list[TaskInfo]:
        """Get pending tasks for the agent.

        Args:
            agent_id: Agent ID to get tasks for

        Returns:
            List of pending TaskInfo objects

        Raises:
            SessionExpiredError: If session has expired
            MCPError: If request fails
        """
        result = await self._call_tool("get_pending_tasks", {
            "agent_id": agent_id
        })

        if not result.get("success"):
            error = result.get("error", "")
            if "expired" in error.lower() or "invalid" in error.lower():
                raise SessionExpiredError(error)
            raise MCPError(error)

        tasks = []
        for t in result.get("tasks", []):
            tasks.append(TaskInfo(
                task_id=t.get("task_id", t.get("taskId", "")),
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
        self, task_id: str, agent_id: str
    ) -> ExecutionStartResult:
        """Report that task execution has started.

        Args:
            task_id: Task ID being executed
            agent_id: Agent ID executing the task

        Returns:
            ExecutionStartResult with execution ID

        Raises:
            MCPError: If reporting fails
        """
        result = await self._call_tool("report_execution_start", {
            "task_id": task_id,
            "agent_id": agent_id
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
            MCPError: If reporting fails
        """
        args = {
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
