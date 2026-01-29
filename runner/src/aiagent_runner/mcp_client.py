# src/aiagent_runner/mcp_client.py
# MCP client for communication with AI Agent PM server
# Reference: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-5
# Reference: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
# Reference: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - Phase 4.3

import asyncio
import json
import logging
import os
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

# HTTP transport support (optional dependency)
try:
    import aiohttp
    HAS_AIOHTTP = True
except ImportError:
    HAS_AIOHTTP = False

from aiagent_runner.platform import get_default_socket_path

logger = logging.getLogger(__name__)


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
class AgentActionResult:
    """Result of get_agent_action check."""
    action: str                          # "start", "hold", "stop", "restart"
    reason: Optional[str] = None         # Reason for the action
    provider: Optional[str] = None       # "claude", "gemini", "openai", "other"
    model: Optional[str] = None          # "claude-sonnet-4-5", "gemini-2.0-flash", etc.
    kick_command: Optional[str] = None   # Custom CLI command (takes priority if set)
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


@dataclass
class SkillDefinition:
    """Skill definition for agent capabilities.

    Reference: docs/design/AGENT_SKILLS.md

    Note: Skills are now stored as ZIP archives (archive_base64) instead of
    plain text content. The archive contains SKILL.md and optional scripts/templates.
    """
    id: str
    name: str
    directory_name: str
    archive_base64: str  # Base64 encoded ZIP archive


@dataclass
class SubordinateProfile:
    """Profile of a subordinate agent.

    Used by Coordinator to get agent's system_prompt for context directory setup.
    Reference: docs/design/AGENT_CONTEXT_DIRECTORY.md
    Reference: docs/design/AGENT_SKILLS.md
    """
    agent_id: str
    name: str
    role: str
    system_prompt: str
    agent_type: str = ""
    hierarchy_type: str = ""
    status: str = ""
    parent_agent_id: Optional[str] = None
    ai_type: Optional[str] = None
    kick_method: str = ""
    max_parallel_tasks: int = 1
    skills: list[SkillDefinition] = field(default_factory=list)


class MCPClient:
    """Client for MCP server communication.

    Handles authentication, task retrieval, and execution reporting.

    Supports two transport modes:
    - Unix socket: For local connections (default)
    - HTTP: For remote connections (multi-device operation)

    The transport is automatically selected based on the URL:
    - http:// or https:// → HTTP transport
    - Everything else → Unix socket transport
    """

    def __init__(
        self,
        socket_path: Optional[str] = None,
        coordinator_token: Optional[str] = None
    ):
        """Initialize MCP client.

        Args:
            socket_path: Path to MCP Unix socket, or HTTP URL for remote connections.
                        Unix socket: platform-specific (see aiagent_runner.platform)
                        HTTP URL: http://hostname:port/mcp (required for Windows)
                        Defaults to platform-specific location.
            coordinator_token: Token for Coordinator-only API calls (Phase 5).
                              If not provided, reads from MCP_COORDINATOR_TOKEN env var.
        """
        # Determine transport type based on URL scheme
        if socket_path and socket_path.startswith(("http://", "https://")):
            self._url = socket_path
            self._use_http = True
            logger.info(f"Using HTTP transport: {self._url}")
        else:
            # Unix socket path - expand tilde
            if socket_path:
                self._url = os.path.expanduser(socket_path)
            else:
                self._url = self._default_socket_path()
            self._use_http = False
            logger.info(f"Using Unix socket transport: {self._url}")

        # Backward compatibility
        self.socket_path = self._url if not self._use_http else None

        self._session_token: Optional[str] = None
        # Phase 5: Coordinator token for Coordinator-only API calls
        self._coordinator_token = coordinator_token or os.environ.get("MCP_COORDINATOR_TOKEN")

    def _default_socket_path(self) -> str:
        """Get default MCP socket path (platform-specific)."""
        return get_default_socket_path()

    async def _call_tool(self, tool_name: str, args: dict) -> dict:
        """Call an MCP tool via Unix socket or HTTP.

        Automatically selects the transport based on the URL scheme.

        Args:
            tool_name: Name of the tool to call
            args: Arguments for the tool

        Returns:
            Tool result as dictionary

        Raises:
            MCPError: If communication fails
        """
        if self._use_http:
            return await self._call_tool_http(tool_name, args)
        else:
            return await self._call_tool_unix(tool_name, args)

    async def _call_tool_unix(self, tool_name: str, args: dict) -> dict:
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
            reader, writer = await asyncio.open_unix_connection(self._url)
        except (ConnectionRefusedError, FileNotFoundError) as e:
            raise MCPError(f"Cannot connect to MCP server at {self._url}: {e}")

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

            return self._parse_response(data)
        finally:
            writer.close()
            await writer.wait_closed()

    async def _call_tool_http(self, tool_name: str, args: dict) -> dict:
        """Call an MCP tool via HTTP.

        Args:
            tool_name: Name of the tool to call
            args: Arguments for the tool

        Returns:
            Tool result as dictionary

        Raises:
            MCPError: If communication fails or aiohttp is not installed
        """
        if not HAS_AIOHTTP:
            raise MCPError(
                "HTTP transport requires aiohttp. Install with: pip install aiohttp"
            )

        request_body = {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {"name": tool_name, "arguments": args},
            "id": 1
        }

        headers = {"Content-Type": "application/json"}

        # Add coordinator token as Authorization header if available
        if self._coordinator_token:
            headers["Authorization"] = f"Bearer {self._coordinator_token}"

        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    self._url,
                    json=request_body,
                    headers=headers,
                    timeout=aiohttp.ClientTimeout(total=30)
                ) as response:
                    if response.status != 200:
                        text = await response.text()
                        raise MCPError(f"HTTP {response.status}: {text}")

                    data = await response.json()
                    return self._parse_response(data)

        except aiohttp.ClientError as e:
            raise MCPError(f"Cannot connect to MCP server at {self._url}: {e}")

    def _parse_response(self, data: dict) -> dict:
        """Parse MCP JSON-RPC response.

        Args:
            data: Raw JSON-RPC response

        Returns:
            Parsed tool result

        Raises:
            MCPError: If response contains an error
        """
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

    # ==========================================================================
    # Phase 4: Coordinator API
    # Reference: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
    # ==========================================================================

    async def health_check(self) -> HealthCheckResult:
        """Check MCP server health.

        The Coordinator calls this first to verify the server is available.
        Phase 5: Requires coordinator_token for authorization.

        Returns:
            HealthCheckResult with server status

        Raises:
            MCPError: If server is not available or unauthorized
        """
        args = {}
        if self._coordinator_token:
            args["coordinator_token"] = self._coordinator_token
        result = await self._call_tool("health_check", args)
        return HealthCheckResult(
            status=result.get("status", "ok"),
            version=result.get("version"),
            timestamp=result.get("timestamp")
        )

    async def list_active_projects_with_agents(
        self, root_agent_id: Optional[str] = None
    ) -> list[ProjectWithAgents]:
        """Get all active projects with their assigned agents.

        The Coordinator calls this to discover what (agent_id, project_id)
        combinations exist and need to be monitored.
        Phase 5: Requires coordinator_token for authorization.

        Multi-device operation:
        When root_agent_id is specified, the server uses that agent's
        working directories instead of the project defaults.

        Args:
            root_agent_id: Optional human agent ID for working directory resolution

        Returns:
            List of ProjectWithAgents

        Raises:
            MCPError: If request fails or unauthorized
        """
        args = {}
        if self._coordinator_token:
            args["coordinator_token"] = self._coordinator_token
            logger.debug("list_active_projects_with_agents: passing coordinator_token")
        else:
            logger.warning("list_active_projects_with_agents: NO coordinator_token set!")

        # Multi-device: Pass root_agent_id for working directory resolution
        if root_agent_id:
            args["root_agent_id"] = root_agent_id
            logger.debug(f"list_active_projects_with_agents: passing root_agent_id={root_agent_id}")

        result = await self._call_tool("list_active_projects_with_agents", args)
        logger.debug(f"list_active_projects_with_agents result: {result}")

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

    async def get_agent_action(self, agent_id: str, project_id: str) -> AgentActionResult:
        """Get the action an Agent Instance should take.

        The Coordinator calls this for each (agent_id, project_id) pair
        to determine what action to take.
        Phase 5: Requires coordinator_token for authorization.

        Args:
            agent_id: Agent ID
            project_id: Project ID

        Returns:
            AgentActionResult with action (start/hold/stop/restart), reason, provider, model, and kick_command

        Raises:
            MCPError: If request fails or unauthorized
        """
        args = {
            "agent_id": agent_id,
            "project_id": project_id
        }
        if self._coordinator_token:
            args["coordinator_token"] = self._coordinator_token
        result = await self._call_tool("get_agent_action", args)

        return AgentActionResult(
            action=result.get("action", "hold"),
            reason=result.get("reason"),
            provider=result.get("provider"),
            model=result.get("model"),
            kick_command=result.get("kick_command"),
            task_id=result.get("task_id")  # Phase 4: Coordinatorがログファイルパス登録に使用
        )

    async def register_execution_log_file(
        self, agent_id: str, task_id: str, log_file_path: str
    ) -> bool:
        """Register log file path for an execution log.

        Called by Coordinator after Agent Instance process completes.
        Phase 5: Requires coordinator_token for authorization.

        Args:
            agent_id: Agent ID
            task_id: Task ID
            log_file_path: Absolute path to the log file

        Returns:
            True if successful, False otherwise

        Raises:
            MCPError: If request fails or unauthorized
        """
        args = {
            "agent_id": agent_id,
            "task_id": task_id,
            "log_file_path": log_file_path
        }
        if self._coordinator_token:
            args["coordinator_token"] = self._coordinator_token
        result = await self._call_tool("register_execution_log_file", args)

        return result.get("success", False)

    async def invalidate_session(self, agent_id: str, project_id: str) -> bool:
        """Invalidate session for an agent-project pair.

        Called by Coordinator when Agent Instance process exits.
        This allows shouldStart to return True again for the next instance.
        Phase 5: Requires coordinator_token for authorization.

        Args:
            agent_id: Agent ID
            project_id: Project ID

        Returns:
            True if successful, False otherwise

        Raises:
            MCPError: If request fails or unauthorized
        """
        args = {
            "agent_id": agent_id,
            "project_id": project_id
        }
        if self._coordinator_token:
            args["coordinator_token"] = self._coordinator_token
        result = await self._call_tool("invalidate_session", args)

        return result.get("success", False)

    async def report_agent_error(
        self, agent_id: str, project_id: str, error_message: str
    ) -> bool:
        """Report agent error to chat.

        Called by Coordinator when Agent Instance process exits with error.
        The error message will be displayed in the chat.

        Args:
            agent_id: Agent ID
            project_id: Project ID
            error_message: Error message to display

        Returns:
            True if successful, False otherwise

        Raises:
            MCPError: If request fails or unauthorized
        """
        args = {
            "agent_id": agent_id,
            "project_id": project_id,
            "error_message": error_message
        }
        if self._coordinator_token:
            args["coordinator_token"] = self._coordinator_token
        result = await self._call_tool("report_agent_error", args)

        return result.get("success", False)

    async def get_subordinate_profile(self, agent_id: str) -> SubordinateProfile:
        """Get profile of a subordinate agent.

        Called by Coordinator to get agent's system_prompt for context directory setup.
        Reference: docs/design/AGENT_CONTEXT_DIRECTORY.md

        Args:
            agent_id: Agent ID to get profile for

        Returns:
            SubordinateProfile with agent details including system_prompt

        Raises:
            MCPError: If request fails or agent not found
        """
        args = {"agent_id": agent_id}
        if self._coordinator_token:
            args["coordinator_token"] = self._coordinator_token

        result = await self._call_tool("get_subordinate_profile", args)

        # Handle error response
        if isinstance(result, dict) and "error" in result:
            raise MCPError(result["error"])

        # Parse skills if present (archive format with Base64 ZIP)
        skills_data = result.get("skills", [])
        skills = [
            SkillDefinition(
                id=skill.get("id", ""),
                name=skill.get("name", ""),
                directory_name=skill.get("directory_name", ""),
                archive_base64=skill.get("archive_base64", "")
            )
            for skill in skills_data
        ]

        return SubordinateProfile(
            agent_id=result.get("id", agent_id),
            name=result.get("name", ""),
            role=result.get("role", ""),
            system_prompt=result.get("system_prompt", ""),
            agent_type=result.get("type", ""),
            hierarchy_type=result.get("hierarchy_type", ""),
            status=result.get("status", ""),
            parent_agent_id=result.get("parent_agent_id") if result.get("parent_agent_id") else None,
            ai_type=result.get("ai_type") if result.get("ai_type") else None,
            kick_method=result.get("kick_method", ""),
            max_parallel_tasks=result.get("max_parallel_tasks", 1),
            skills=skills
        )

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
