# src/aiagent_runner/runner.py
# Main runner loop for AI Agent PM
# Reference: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-5

import asyncio
import logging
import os
from datetime import datetime
from pathlib import Path
from typing import Optional

from aiagent_runner.config import RunnerConfig
from aiagent_runner.executor import CLIExecutor, ExecutionResult
from aiagent_runner.mcp_client import (
    AuthenticationError,
    MCPClient,
    MCPError,
    SessionExpiredError,
    TaskInfo,
)
from aiagent_runner.prompt_builder import PromptBuilder

logger = logging.getLogger(__name__)


class Runner:
    """Main runner that polls for tasks and executes them.

    The runner operates in a polling loop:
    1. Authenticate with MCP server
    2. Poll for pending tasks
    3. Execute tasks using CLI
    4. Report execution results
    5. Wait for polling interval
    6. Repeat
    """

    def __init__(self, config: RunnerConfig):
        """Initialize runner.

        Args:
            config: Runner configuration
        """
        self.config = config
        self.mcp_client = MCPClient(config.mcp_socket_path)
        self.executor = CLIExecutor(config.cli_command, config.cli_args)
        self.prompt_builder: Optional[PromptBuilder] = None

        self._running = False
        self._authenticated = False
        self._agent_name: Optional[str] = None

    @property
    def log_directory(self) -> Path:
        """Get log directory, creating if needed."""
        if self.config.log_directory:
            log_dir = Path(self.config.log_directory)
        else:
            log_dir = Path.home() / ".aiagent-runner" / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        return log_dir

    @property
    def working_directory(self) -> str:
        """Get working directory."""
        return self.config.working_directory or os.getcwd()

    async def start(self) -> None:
        """Start the runner loop.

        Runs until stop() is called or an unrecoverable error occurs.
        """
        logger.info(
            f"Starting runner for agent {self.config.agent_id}, "
            f"polling every {self.config.polling_interval}s"
        )

        self._running = True

        while self._running:
            try:
                await self._run_once()
            except AuthenticationError as e:
                logger.error(f"Authentication failed: {e}")
                self._authenticated = False
                # Wait before retrying
                await asyncio.sleep(self.config.polling_interval)
            except MCPError as e:
                logger.error(f"MCP error: {e}")
                # Wait before retrying
                await asyncio.sleep(self.config.polling_interval)
            except Exception as e:
                logger.exception(f"Unexpected error: {e}")
                # Wait before retrying
                await asyncio.sleep(self.config.polling_interval)

            if self._running:
                await asyncio.sleep(self.config.polling_interval)

    def stop(self) -> None:
        """Stop the runner loop."""
        logger.info("Stopping runner")
        self._running = False

    async def _run_once(self) -> None:
        """Run one iteration of the polling loop."""
        # Ensure authenticated
        await self._ensure_authenticated()

        # Get pending tasks (agent_id is derived from session token)
        try:
            tasks = await self.mcp_client.get_pending_tasks()
        except SessionExpiredError:
            logger.info("Session expired, re-authenticating")
            self._authenticated = False
            await self._ensure_authenticated()
            tasks = await self.mcp_client.get_pending_tasks()

        if not tasks:
            logger.debug("No pending tasks")
            return

        logger.info(f"Found {len(tasks)} pending task(s)")

        # Process first task (one at a time)
        task = tasks[0]
        await self._process_task(task)

    async def _ensure_authenticated(self) -> None:
        """Ensure we have a valid session."""
        if self._authenticated:
            return

        logger.info(f"Authenticating agent {self.config.agent_id} for project {self.config.project_id}")
        result = await self.mcp_client.authenticate(
            self.config.agent_id,
            self.config.passkey,
            self.config.project_id
        )
        self._authenticated = True
        self._agent_name = result.agent_name
        self.prompt_builder = PromptBuilder(
            self.config.agent_id,
            self._agent_name
        )
        logger.info(
            f"Authenticated as {self._agent_name or self.config.agent_id}, "
            f"session expires in {result.expires_in}s"
        )

    async def _process_task(self, task: TaskInfo) -> None:
        """Process a single task.

        Args:
            task: Task to process
        """
        logger.info(f"Processing task {task.task_id}: {task.title}")

        # Report execution start (agent_id is derived from session token)
        try:
            start_result = await self.mcp_client.report_execution_start(
                task.task_id
            )
            execution_id = start_result.execution_id
        except MCPError as e:
            logger.error(f"Failed to report execution start: {e}")
            return

        # Build prompt
        prompt = self.prompt_builder.build(task)

        # Determine working directory
        work_dir = task.working_directory or self.working_directory

        # Generate log file path
        log_file = self._generate_log_path(task.task_id)

        # Execute CLI
        logger.info(f"Executing {self.config.cli_command} for task {task.task_id}")
        result = self.executor.execute(prompt, work_dir, log_file)

        # Report execution complete
        error_message = None
        if result.exit_code != 0:
            error_message = f"CLI exited with code {result.exit_code}"
            logger.warning(
                f"Task {task.task_id} execution failed: {error_message}"
            )
        else:
            logger.info(
                f"Task {task.task_id} execution completed in "
                f"{result.duration_seconds:.1f}s"
            )

        try:
            await self.mcp_client.report_execution_complete(
                execution_id,
                result.exit_code,
                result.duration_seconds,
                result.log_file,
                error_message
            )
        except MCPError as e:
            logger.error(f"Failed to report execution complete: {e}")

    def _generate_log_path(self, task_id: str) -> str:
        """Generate a log file path for a task execution.

        Args:
            task_id: Task ID

        Returns:
            Path to log file
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{task_id}_{timestamp}.log"
        return str(self.log_directory / filename)


async def run_async(config: RunnerConfig) -> None:
    """Run the runner asynchronously.

    Args:
        config: Runner configuration
    """
    runner = Runner(config)
    await runner.start()


def run(config: RunnerConfig) -> None:
    """Run the runner synchronously.

    Args:
        config: Runner configuration
    """
    asyncio.run(run_async(config))
