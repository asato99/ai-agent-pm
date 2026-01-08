# src/aiagent_runner/coordinator.py
# Coordinator - Single orchestrator for all Agent Instances
# Reference: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md

import asyncio
import json
import logging
import os
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional, TextIO

from aiagent_runner.coordinator_config import CoordinatorConfig
from aiagent_runner.mcp_client import MCPClient, MCPError

logger = logging.getLogger(__name__)


@dataclass
class AgentInstanceKey:
    """Unique key for an Agent Instance: (agent_id, project_id)."""
    agent_id: str
    project_id: str

    def __hash__(self):
        return hash((self.agent_id, self.project_id))

    def __eq__(self, other):
        if not isinstance(other, AgentInstanceKey):
            return False
        return self.agent_id == other.agent_id and self.project_id == other.project_id


@dataclass
class AgentInstanceInfo:
    """Information about a running Agent Instance."""
    key: AgentInstanceKey
    process: subprocess.Popen
    working_directory: str
    provider: str                              # "claude", "gemini", "openai", "other"
    model: Optional[str]                       # "claude-sonnet-4-5", "gemini-2.0-flash", etc.
    started_at: datetime
    log_file_handle: Optional["TextIO"] = None  # Keep file handle open during process lifetime
    task_id: Optional[str] = None              # Phase 4: ログファイルパス登録用
    log_file_path: Optional[str] = None        # Phase 4: ログファイルパス


class Coordinator:
    """Single orchestrator that manages all Agent Instances.

    The Coordinator operates in a polling loop:
    1. health_check() - Verify MCP server is available
    2. list_active_projects_with_agents() - Get all projects and their agents
    3. For each (agent_id, project_id) pair:
       - Check if we have a passkey configured
       - should_start(agent_id, project_id) - Check if work exists
       - Spawn Agent Instance if needed
    4. Clean up finished processes
    5. Wait for polling interval
    6. Repeat

    Key differences from the old Runner:
    - Single instance manages ALL (agent_id, project_id) combinations
    - Does NOT authenticate - spawned Agent Instances do that
    - Tracks running processes to avoid duplicates
    """

    def __init__(self, config: CoordinatorConfig):
        """Initialize Coordinator.

        Args:
            config: Coordinator configuration with agents and ai_providers
        """
        self.config = config
        self.mcp_client = MCPClient(config.mcp_socket_path)

        self._running = False
        self._instances: dict[AgentInstanceKey, AgentInstanceInfo] = {}

    @property
    def log_directory(self) -> Path:
        """Get log directory, creating if needed."""
        if self.config.log_directory:
            log_dir = Path(self.config.log_directory)
        else:
            log_dir = Path.home() / ".aiagent-coordinator" / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        return log_dir

    async def start(self) -> None:
        """Start the Coordinator loop.

        Runs until stop() is called or an unrecoverable error occurs.
        """
        logger.info(
            f"Starting Coordinator, polling every {self.config.polling_interval}s, "
            f"max_concurrent={self.config.max_concurrent}"
        )
        logger.info(f"Configured agents: {list(self.config.agents.keys())}")

        self._running = True

        while self._running:
            try:
                await self._run_once()
            except MCPError as e:
                logger.error(f"MCP error: {e}")
            except Exception as e:
                logger.exception(f"Unexpected error: {e}")

            if self._running:
                await asyncio.sleep(self.config.polling_interval)

    def stop(self) -> None:
        """Stop the Coordinator loop."""
        logger.info("Stopping Coordinator")
        self._running = False

        # Terminate all running instances
        for key, info in list(self._instances.items()):
            logger.info(f"Terminating {key.agent_id}/{key.project_id}")
            try:
                info.process.terminate()
            except Exception as e:
                logger.warning(f"Failed to terminate {key}: {e}")

    async def _run_once(self) -> None:
        """Run one iteration of the polling loop."""
        # Step 1: Health check
        try:
            health = await self.mcp_client.health_check()
            if health.status != "ok":
                logger.warning(f"MCP server unhealthy: {health.status}")
                return
        except MCPError as e:
            logger.error(f"MCP server not available: {e}")
            return

        # Step 2: Get active projects with agents
        try:
            projects = await self.mcp_client.list_active_projects_with_agents()
        except MCPError as e:
            logger.error(f"Failed to get project list: {e}")
            return

        logger.debug(f"Found {len(projects)} active projects")

        # Debug: Log project details including agents
        for project in projects:
            logger.debug(
                f"Project {project.project_id}: agents={project.agents}, "
                f"working_dir={project.working_directory}"
            )

        # Step 3: Clean up finished processes and register log file paths
        finished_instances = self._cleanup_finished()
        for key, info in finished_instances:
            if info.task_id and info.log_file_path:
                try:
                    success = await self.mcp_client.register_execution_log_file(
                        agent_id=key.agent_id,
                        task_id=info.task_id,
                        log_file_path=info.log_file_path
                    )
                    if success:
                        logger.info(
                            f"Registered log file for {key.agent_id}/{key.project_id}: "
                            f"{info.log_file_path}"
                        )
                    else:
                        logger.warning(
                            f"Failed to register log file for {key.agent_id}/{key.project_id}"
                        )
                except MCPError as e:
                    logger.error(
                        f"Error registering log file for {key.agent_id}/{key.project_id}: {e}"
                    )

        # Step 4: For each (agent_id, project_id), check if should start
        for project in projects:
            project_id = project.project_id
            working_dir = project.working_directory

            logger.debug(f"Processing project {project_id}, agents: {project.agents}")

            for agent_id in project.agents:
                key = AgentInstanceKey(agent_id, project_id)
                logger.debug(f"Checking agent {agent_id} for project {project_id}")

                # Skip if already running
                if key in self._instances:
                    logger.debug(f"Instance {agent_id}/{project_id} already running")
                    continue

                # Skip if we don't have passkey configured
                passkey = self.config.get_agent_passkey(agent_id)
                logger.debug(f"Passkey for {agent_id}: {'configured' if passkey else 'NOT FOUND'}")
                if not passkey:
                    logger.debug(f"No passkey configured for {agent_id}, skipping")
                    continue

                # Skip if at max concurrent
                if len(self._instances) >= self.config.max_concurrent:
                    logger.debug(f"At max concurrent ({self.config.max_concurrent}), skipping")
                    break

                # Check if should start
                logger.debug(f"Calling should_start({agent_id}, {project_id})")
                try:
                    result = await self.mcp_client.should_start(agent_id, project_id)
                    logger.debug(
                        f"should_start result: {result.should_start}, "
                        f"provider: {result.provider}, model: {result.model}, "
                        f"kick_command: {result.kick_command}, task_id: {result.task_id}"
                    )
                    if result.should_start:
                        provider = result.provider or "claude"
                        self._spawn_instance(
                            agent_id=agent_id,
                            project_id=project_id,
                            passkey=passkey,
                            working_dir=working_dir,
                            provider=provider,
                            model=result.model,
                            kick_command=result.kick_command,
                            task_id=result.task_id
                        )
                    else:
                        logger.debug(f"should_start returned False for {agent_id}/{project_id}")
                except MCPError as e:
                    logger.error(f"Failed to check should_start for {agent_id}/{project_id}: {e}")

    def _cleanup_finished(self) -> list[tuple[AgentInstanceKey, AgentInstanceInfo]]:
        """Clean up finished Agent Instance processes.

        Returns:
            List of (key, info) tuples for finished instances
            that need log file path registration.
        """
        finished: list[tuple[AgentInstanceKey, AgentInstanceInfo]] = []
        for key, info in self._instances.items():
            retcode = info.process.poll()
            if retcode is not None:
                logger.info(
                    f"Instance {key.agent_id}/{key.project_id} finished with code {retcode}"
                )
                # Close log file handle
                if info.log_file_handle:
                    try:
                        info.log_file_handle.close()
                    except Exception:
                        pass
                finished.append((key, info))

        for key, _ in finished:
            del self._instances[key]

        return finished

    def _spawn_instance(
        self,
        agent_id: str,
        project_id: str,
        passkey: str,
        working_dir: str,
        provider: str,
        model: Optional[str] = None,
        kick_command: Optional[str] = None,
        task_id: Optional[str] = None
    ) -> None:
        """Spawn an Agent Instance process.

        The Agent Instance (Claude Code) will:
        1. authenticate(agent_id, passkey, project_id)
        2. get_my_task()
        3. Execute the task
        4. report_completed()
        5. Exit

        Args:
            agent_id: Agent ID
            project_id: Project ID
            passkey: Agent passkey
            working_dir: Working directory for the task
            provider: AI provider (claude, gemini, openai, other)
            model: Specific model (claude-sonnet-4-5, gemini-2.0-flash, etc.)
            kick_command: Custom CLI command (takes priority if set)
            task_id: Task ID (for log file path registration)
        """
        # kick_command takes priority over provider-based selection
        if kick_command:
            # Parse kick_command into command and args
            parts = kick_command.split()
            cli_command = parts[0]
            cli_args = parts[1:] if len(parts) > 1 else []
            logger.info(f"Using kick_command: {kick_command}")
        else:
            # Use provider-based CLI selection
            provider_config = self.config.get_provider(provider)
            cli_command = provider_config.cli_command
            cli_args = provider_config.cli_args

        # Build prompt for the Agent Instance
        prompt = self._build_agent_prompt(agent_id, project_id, passkey)

        # Generate log file path
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_file = self.log_directory / f"{agent_id}_{project_id}_{timestamp}.log"

        # Build MCP config for Agent Instance (stdio transport)
        # Each Claude instance spawns its own mcp-server-pm process
        mcp_server_command = self.config.mcp_server_command
        if not mcp_server_command:
            # Default to looking for mcp-server-pm in PATH
            mcp_server_command = "mcp-server-pm"

        mcp_config_dict = {
            "mcpServers": {
                "agent-pm": {
                    "command": mcp_server_command,
                    "args": ["serve"],
                    "env": {}
                }
            }
        }

        # Add database path to MCP server environment if configured
        if self.config.mcp_database_path:
            mcp_config_dict["mcpServers"]["agent-pm"]["env"]["AIAGENTPM_DB_PATH"] = \
                self.config.mcp_database_path

        mcp_config = json.dumps(mcp_config_dict)

        # Debug: Log the full MCP config to verify database path is included
        logger.debug(f"MCP config: {mcp_config}")
        if self.config.mcp_database_path:
            logger.info(f"Using database path: {self.config.mcp_database_path}")
        else:
            logger.warning("No mcp_database_path configured - MCP server will use default database!")

        # Build command with MCP config
        cmd = [
            cli_command,
            *cli_args,
            "--mcp-config", mcp_config,
            "-p", prompt
        ]

        model_desc = f"{provider}/{model}" if model else provider
        logger.info(
            f"Spawning {model_desc} instance for {agent_id}/{project_id} "
            f"at {working_dir}"
        )
        logger.debug(f"MCP server command: {mcp_server_command}")
        logger.debug(f"Command: {' '.join(cmd[:5])}...")

        # Ensure working directory exists
        Path(working_dir).mkdir(parents=True, exist_ok=True)

        # Open log file (keep handle open during process lifetime)
        log_f = open(log_file, "w")

        # Spawn process
        process = subprocess.Popen(
            cmd,
            cwd=working_dir,
            stdout=log_f,
            stderr=subprocess.STDOUT,
            env={
                **os.environ,
                "AGENT_ID": agent_id,
                "PROJECT_ID": project_id,
                "AGENT_PASSKEY": passkey,
                "WORKING_DIRECTORY": working_dir,
            }
        )

        key = AgentInstanceKey(agent_id, project_id)
        self._instances[key] = AgentInstanceInfo(
            key=key,
            process=process,
            working_directory=working_dir,
            provider=provider,
            model=model,
            started_at=datetime.now(),
            log_file_handle=log_f,
            task_id=task_id,
            log_file_path=str(log_file)
        )

        logger.info(f"Spawned instance {agent_id}/{project_id} (PID: {process.pid})")

    def _build_agent_prompt(self, agent_id: str, project_id: str, passkey: str) -> str:
        """Build the prompt for an Agent Instance.

        The Agent Instance will use this prompt to know how to authenticate
        and what to do.

        Args:
            agent_id: Agent ID
            project_id: Project ID
            passkey: Agent passkey

        Returns:
            Prompt string for the Agent Instance
        """
        return f"""You are an AI Agent Instance managed by the AI Agent PM system.

## Authentication Information
- Agent ID: {agent_id}
- Project ID: {project_id}
- Passkey: {passkey}

## Instructions

1. **Authenticate**: Call the `authenticate` tool with:
   - agent_id: "{agent_id}"
   - passkey: "{passkey}"
   - project_id: "{project_id}"

2. **Get your role**: The authenticate response will include your `system_prompt` which defines your role. Follow that role.

3. **Get your task**: Call `get_my_task` with your session_token to get the main task details.

4. **Decompose into sub-tasks**: Analyze the main task and break it down into 2-5 concrete, actionable sub-tasks.
   For each sub-task, call `create_task` with:
   - session_token: (from authenticate)
   - title: (sub-task title, e.g., "Step 1: Design API structure")
   - description: (detailed description of what to do)
   - priority: "medium" (or appropriate priority)
   - parent_task_id: (the main task ID from get_my_task)

5. **Execute sub-tasks sequentially**: For each sub-task you created:
   a. Call `update_task_status` to set the sub-task to "in_progress"
   b. Execute the work described in the sub-task
   c. Call `update_task_status` to set the sub-task to "done"
   d. Optionally call `save_context` to record progress

6. **Complete the main task**: After all sub-tasks are done:
   - Call `report_completed` with:
     - session_token: (from authenticate)
     - result: "success" | "failed" | "blocked"
     - summary: (brief description of what you accomplished)

7. **Exit**: After reporting, your work is done.

## Important Notes
- The main task stays in "in_progress" while you work on sub-tasks
- Each sub-task should be a concrete, verifiable step
- Sub-tasks are automatically assigned to you and linked to the main task
- You are working in the project directory

Begin by calling `authenticate`.
"""


async def run_coordinator_async(config: CoordinatorConfig) -> None:
    """Run the Coordinator asynchronously.

    Args:
        config: Coordinator configuration
    """
    coordinator = Coordinator(config)
    await coordinator.start()


def run_coordinator(config: CoordinatorConfig) -> None:
    """Run the Coordinator synchronously.

    Args:
        config: Coordinator configuration
    """
    asyncio.run(run_coordinator_async(config))
