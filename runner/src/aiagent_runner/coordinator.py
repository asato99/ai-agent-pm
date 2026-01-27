# src/aiagent_runner/coordinator.py
# Coordinator - Single orchestrator for all Agent Instances
# Reference: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md

import asyncio
import json
import logging
import os
import subprocess
import tempfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional, TextIO

from aiagent_runner.cooldown import CooldownManager
from aiagent_runner.coordinator_config import CoordinatorConfig
from aiagent_runner.log_uploader import LogUploader, LogUploadConfig
from aiagent_runner.mcp_client import MCPClient, MCPError
from aiagent_runner.platform import get_data_directory, is_windows
from aiagent_runner.quota_detector import QuotaErrorDetector
from aiagent_runner.types import AgentInstanceKey

logger = logging.getLogger(__name__)


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
    mcp_config_file: Optional[str] = None      # Temp file for MCP config (Claude CLI)
    execution_log_id: Optional[str] = None     # ログアップロード用実行ログID
    prompt_file: Optional[str] = None          # Temp file for prompt (Windows + Gemini)


@dataclass
class _LogUploadInfo:
    """Internal info for async log upload task."""
    log_file_path: str
    execution_log_id: str
    agent_id: str
    task_id: str
    project_id: str


class Coordinator:
    """Single orchestrator that manages all Agent Instances.

    The Coordinator operates in a polling loop:
    1. health_check() - Verify MCP server is available
    2. list_active_projects_with_agents() - Get all projects and their agents
    3. For each (agent_id, project_id) pair:
       - Check if we have a passkey configured
       - get_agent_action(agent_id, project_id) - Check what action to take
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
        # Phase 5: Pass coordinator_token for Coordinator-only API authorization
        logger.debug(f"Initializing MCPClient with coordinator_token: {'set' if config.coordinator_token else 'NOT SET'}")
        self.mcp_client = MCPClient(
            config.mcp_socket_path,
            coordinator_token=config.coordinator_token
        )

        self._running = False
        self._instances: dict[AgentInstanceKey, AgentInstanceInfo] = {}

        # Phase 6: Log upload configuration
        # 参照: docs/design/LOG_TRANSFER_DESIGN.md
        self._pending_uploads: dict[str, asyncio.Task] = {}  # execution_log_id -> Task
        self.log_uploader: Optional[LogUploader] = None
        if hasattr(config, 'log_upload') and config.log_upload and config.log_upload.enabled:
            upload_config = LogUploadConfig(
                enabled=config.log_upload.enabled,
                endpoint=config.log_upload.endpoint,
                max_file_size_mb=getattr(config.log_upload, 'max_file_size_mb', 10),
                retry_count=getattr(config.log_upload, 'retry_count', 3),
                retry_delay_seconds=getattr(config.log_upload, 'retry_delay_seconds', 1.0)
            )
            self.log_uploader = LogUploader(upload_config, config.coordinator_token or "")
            logger.info("LogUploader initialized with endpoint: %s", upload_config.endpoint)

        # Error protection: Cooldown manager and quota detector
        # Reference: docs/design/SPAWN_ERROR_PROTECTION.md
        self._cooldown_manager: Optional[CooldownManager] = None
        self._quota_detector: Optional[QuotaErrorDetector] = None
        if config.error_protection.enabled:
            self._cooldown_manager = CooldownManager(
                default_seconds=config.error_protection.default_cooldown_seconds,
                max_seconds=config.error_protection.max_cooldown_seconds
            )
            if config.error_protection.quota_detection_enabled:
                self._quota_detector = QuotaErrorDetector(
                    max_seconds=config.error_protection.max_cooldown_seconds,
                    margin_percent=config.error_protection.quota_margin_percent
                )
            logger.info(
                "Error protection enabled: cooldown=%ds (max %ds), quota_detection=%s",
                config.error_protection.default_cooldown_seconds,
                config.error_protection.max_cooldown_seconds,
                "enabled" if self._quota_detector else "disabled"
            )

    @property
    def log_directory(self) -> Path:
        """Get log directory, creating if needed."""
        if self.config.log_directory:
            log_dir = Path(self.config.log_directory).expanduser()
        else:
            log_dir = Path.home() / ".aiagent-coordinator" / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        return log_dir

    def _get_log_directory(self, working_dir: Optional[str], agent_id: str) -> Path:
        """Get log directory for an agent.

        Args:
            working_dir: Project working directory (None or empty string for fallback)
            agent_id: Agent ID

        Returns:
            Path to log directory
        """
        if working_dir:
            # プロジェクトのワーキングディレクトリ基準
            log_dir = Path(working_dir) / ".aiagent" / "logs" / agent_id
        else:
            # フォールバック: プラットフォーム固有のデータディレクトリ
            log_dir = get_data_directory() / "agent_logs" / agent_id

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

        # Multi-device: Log root_agent_id if set
        if self.config.root_agent_id:
            logger.info(f"Multi-device mode: root_agent_id={self.config.root_agent_id}")

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
        # Multi-device: Pass root_agent_id for working directory resolution
        try:
            projects = await self.mcp_client.list_active_projects_with_agents(
                root_agent_id=self.config.root_agent_id
            )
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

        # Step 3: Clean up finished processes, register log file paths, and invalidate sessions
        finished_instances = self._cleanup_finished()
        for key, info, exit_code in finished_instances:
            # Register log file path (if available)
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

            # If process exited with error, report to chat
            if exit_code != 0 and info.log_file_path:
                error_msg = self._extract_error_from_log(info.log_file_path)
                if error_msg:
                    try:
                        success = await self.mcp_client.report_agent_error(
                            agent_id=key.agent_id,
                            project_id=key.project_id,
                            error_message=error_msg
                        )
                        if success:
                            logger.info(
                                f"Reported error for {key.agent_id}/{key.project_id}: {error_msg[:50]}..."
                            )
                        else:
                            logger.warning(
                                f"Failed to report error for {key.agent_id}/{key.project_id}"
                            )
                    except MCPError as e:
                        logger.error(
                            f"Error reporting error for {key.agent_id}/{key.project_id}: {e}"
                        )

            # Invalidate session so shouldStart returns True for next instance
            try:
                success = await self.mcp_client.invalidate_session(
                    agent_id=key.agent_id,
                    project_id=key.project_id
                )
                if success:
                    logger.info(
                        f"Invalidated session for {key.agent_id}/{key.project_id}"
                    )
                else:
                    logger.warning(
                        f"Failed to invalidate session for {key.agent_id}/{key.project_id}"
                    )
            except MCPError as e:
                logger.error(
                    f"Error invalidating session for {key.agent_id}/{key.project_id}: {e}"
                )

        # Step 4: For each (agent_id, project_id), check if should start
        for project in projects:
            project_id = project.project_id
            working_dir = project.working_directory

            logger.debug(f"Processing project {project_id}, agents: {project.agents}")

            for agent_id in project.agents:
                key = AgentInstanceKey(agent_id, project_id)
                logger.debug(f"Checking agent {agent_id} for project {project_id}")

                # Skip if we don't have passkey configured
                passkey = self.config.get_agent_passkey(agent_id)
                logger.debug(f"Passkey for {agent_id}: {'configured' if passkey else 'NOT FOUND'}")
                if not passkey:
                    logger.debug(f"No passkey configured for {agent_id}, skipping")
                    continue

                # Error protection: Check cooldown before spawning
                # Reference: docs/design/SPAWN_ERROR_PROTECTION.md
                if self._cooldown_manager:
                    cooldown_entry = self._cooldown_manager.check(key)
                    if cooldown_entry:
                        remaining = self._cooldown_manager.get_remaining_seconds(key)
                        logger.debug(
                            f"Skipping {agent_id}/{project_id}: in cooldown "
                            f"({cooldown_entry.reason}, {remaining:.0f}s remaining)"
                        )
                        continue

                # Check if instance is already running
                instance_running = key in self._instances

                # UC008: Always check get_agent_action for running instances to detect stop
                if instance_running:
                    logger.debug(f"Instance {agent_id}/{project_id} running, checking for stop action")
                    try:
                        result = await self.mcp_client.get_agent_action(agent_id, project_id)
                        logger.debug(f"get_agent_action for running instance: action={result.action}, reason={result.reason}")
                        if result.action == "stop":
                            logger.info(f"Stopping instance {agent_id}/{project_id} due to {result.reason}")
                            await self._stop_instance(key)
                    except MCPError as e:
                        logger.error(f"Failed to check stop action for {agent_id}/{project_id}: {e}")
                    continue

                # Skip if at max concurrent
                if len(self._instances) >= self.config.max_concurrent:
                    logger.debug(f"At max concurrent ({self.config.max_concurrent}), skipping")
                    break

                # Check what action to take
                logger.debug(f"Calling get_agent_action({agent_id}, {project_id})")
                try:
                    result = await self.mcp_client.get_agent_action(agent_id, project_id)
                    logger.debug(
                        f"get_agent_action result: action={result.action}, reason={result.reason}, "
                        f"provider: {result.provider}, model: {result.model}, "
                        f"kick_command: {result.kick_command}, task_id: {result.task_id}"
                    )
                    if result.action == "start":
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
                        logger.debug(f"get_agent_action returned action='{result.action}' (reason: {result.reason}) for {agent_id}/{project_id}")
                except MCPError as e:
                    logger.error(f"Failed to get_agent_action for {agent_id}/{project_id}: {e}")

    async def _stop_instance(self, key: AgentInstanceKey) -> None:
        """Stop a running Agent Instance.

        Args:
            key: The AgentInstanceKey identifying the instance to stop.
        """
        info = self._instances.get(key)
        if not info:
            logger.warning(f"Instance {key.agent_id}/{key.project_id} not found in _instances")
            return

        logger.info(f"Terminating instance {key.agent_id}/{key.project_id} (PID: {info.process.pid})")

        try:
            info.process.terminate()
            # Wait a short time for graceful shutdown
            try:
                info.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                logger.warning(f"Instance {key.agent_id}/{key.project_id} did not terminate, killing")
                info.process.kill()
        except Exception as e:
            logger.error(f"Error terminating process: {e}")

        # Close log file handle
        if info.log_file_handle:
            try:
                info.log_file_handle.close()
            except Exception:
                pass

        # Clean up MCP config temp file
        if info.mcp_config_file:
            try:
                os.unlink(info.mcp_config_file)
                logger.debug(f"Removed temp MCP config: {info.mcp_config_file}")
            except Exception:
                pass

        # Remove from instances
        del self._instances[key]
        logger.info(f"Instance {key.agent_id}/{key.project_id} stopped and removed")

    def _cleanup_finished(self) -> list[tuple[AgentInstanceKey, AgentInstanceInfo, int]]:
        """Clean up finished Agent Instance processes.

        Returns:
            List of (key, info, exit_code) tuples for finished instances
            that need log file path registration.
        """
        finished: list[tuple[AgentInstanceKey, AgentInstanceInfo, int]] = []
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
                # Clean up MCP config temp file
                if info.mcp_config_file:
                    try:
                        os.unlink(info.mcp_config_file)
                        logger.debug(f"Removed temp MCP config: {info.mcp_config_file}")
                    except Exception:
                        pass
                # Clean up prompt temp file (Windows + Gemini)
                if info.prompt_file:
                    try:
                        os.unlink(info.prompt_file)
                        logger.debug(f"Removed temp prompt file: {info.prompt_file}")
                    except Exception:
                        pass

                # Phase 6: Start async log upload (non-blocking)
                # 参照: docs/design/LOG_TRANSFER_DESIGN.md
                if (self.log_uploader and info.execution_log_id and
                    info.log_file_path and info.task_id):
                    upload_info = _LogUploadInfo(
                        log_file_path=info.log_file_path,
                        execution_log_id=info.execution_log_id,
                        agent_id=key.agent_id,
                        task_id=info.task_id,
                        project_id=key.project_id
                    )
                    task = asyncio.create_task(self._upload_log_async(upload_info))
                    self._pending_uploads[info.execution_log_id] = task
                    logger.debug(f"Started async log upload for {info.execution_log_id}")

                # Error protection: Set cooldown on error exit, clear on success
                # Reference: docs/design/SPAWN_ERROR_PROTECTION.md
                if self._cooldown_manager:
                    if retcode == 0:
                        # Successful exit - clear any existing cooldown
                        self._cooldown_manager.clear(key)
                        logger.debug(f"Cleared cooldown for {key.agent_id}/{key.project_id} (successful exit)")

                if retcode != 0 and self._cooldown_manager:
                    error_msg = self._extract_error_from_log(info.log_file_path) if info.log_file_path else None
                    cooldown_seconds: Optional[int] = None

                    # Check for quota error if detection is enabled
                    if self._quota_detector and info.log_file_path:
                        cooldown_seconds = self._quota_detector.detect_from_file(info.log_file_path)
                        if cooldown_seconds:
                            self._cooldown_manager.set_quota(
                                key=key,
                                cooldown_seconds=cooldown_seconds,
                                error_message=error_msg or f"Quota error (exit code {retcode})"
                            )
                            logger.warning(
                                f"Quota error detected for {key.agent_id}/{key.project_id}: "
                                f"cooldown {cooldown_seconds}s"
                            )

                    # If not a quota error, set regular error cooldown
                    if cooldown_seconds is None:
                        self._cooldown_manager.set_error(
                            key=key,
                            error_message=error_msg or f"Process exited with code {retcode}"
                        )
                        logger.warning(
                            f"Error cooldown set for {key.agent_id}/{key.project_id}: "
                            f"{self.config.error_protection.default_cooldown_seconds}s"
                        )

                finished.append((key, info, retcode))

        for key, _, _ in finished:
            del self._instances[key]

        return finished

    async def _upload_log_async(self, upload_info: _LogUploadInfo) -> None:
        """Upload log file asynchronously.

        On success: deletes local temp file
        On failure: registers local path via MCP as fallback

        Args:
            upload_info: Log upload information
        """
        try:
            result = await self.log_uploader.upload(
                log_file_path=upload_info.log_file_path,
                execution_log_id=upload_info.execution_log_id,
                agent_id=upload_info.agent_id,
                task_id=upload_info.task_id,
                project_id=upload_info.project_id
            )

            if result:
                # Upload succeeded - delete local temp file
                try:
                    Path(upload_info.log_file_path).unlink()
                    logger.info(f"Log uploaded and temp file deleted: {upload_info.execution_log_id}")
                except Exception as e:
                    logger.warning(f"Failed to delete temp log file: {e}")
            else:
                # Upload failed - register local path as fallback
                logger.warning(f"Log upload failed for {upload_info.execution_log_id}, registering local path")
                try:
                    await self.mcp_client.register_execution_log_file(
                        execution_log_id=upload_info.execution_log_id,
                        log_file_path=upload_info.log_file_path
                    )
                except Exception as e:
                    logger.error(f"Failed to register local log path: {e}")

        except Exception as e:
            logger.error(f"Async log upload error for {upload_info.execution_log_id}: {e}")
            # Try to register local path as fallback
            try:
                await self.mcp_client.register_execution_log_file(
                    execution_log_id=upload_info.execution_log_id,
                    log_file_path=upload_info.log_file_path
                )
            except Exception as e2:
                logger.error(f"Failed to register local log path as fallback: {e2}")

        finally:
            # Remove from pending uploads
            if upload_info.execution_log_id in self._pending_uploads:
                del self._pending_uploads[upload_info.execution_log_id]

    def _extract_error_from_log(self, log_file_path: str) -> Optional[str]:
        """Extract error message from log file.

        Looks for common error patterns in the last 50 lines of the log.

        Args:
            log_file_path: Path to the log file

        Returns:
            Error message if found, None otherwise
        """
        try:
            with open(log_file_path, "r") as f:
                lines = f.readlines()

            # Check last 50 lines for errors
            last_lines = lines[-50:] if len(lines) > 50 else lines

            error_patterns = [
                "[API Error:",
                "Error:",
                "ERROR:",
                "error:",
                "quota",
                "rate limit",
                "exhausted",
                "unauthorized",
                "authentication failed",
            ]

            for line in reversed(last_lines):
                line_lower = line.lower()
                for pattern in error_patterns:
                    if pattern.lower() in line_lower:
                        # Found an error line, return it (cleaned up)
                        return line.strip()

            # If no specific error found but process failed, return generic message
            return None
        except Exception as e:
            logger.warning(f"Failed to read log file {log_file_path}: {e}")
            return None

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

        # Generate log file path (use working_dir-based path for project context)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_dir = self._get_log_directory(working_dir, agent_id)
        log_file = log_dir / f"{timestamp}.log"

        # Build MCP config for Agent Instance
        # Agent Instance connects to the SAME MCP server that the app started
        # This ensures all components share the same database and state
        # Supports both Unix Socket and HTTP transport
        connection_path = self.config.mcp_socket_path
        if connection_path:
            # Always expand tilde in socket path (for Unix socket)
            if not connection_path.startswith("http"):
                connection_path = os.path.expanduser(connection_path)
        else:
            # Use platform-specific default socket path
            from aiagent_runner.platform import get_default_socket_path
            connection_path = get_default_socket_path()

        # Validate connection_path (empty on Windows without explicit config)
        if not connection_path:
            raise ValueError(
                "MCP connection path is required. "
                "On Windows, Unix sockets are not supported. "
                "Please set 'mcp_socket_path' to an HTTP URL (e.g., http://hostname:8081/mcp) "
                "in your coordinator.yaml configuration."
            )

        # Determine transport type based on connection path
        if connection_path.startswith("http://") or connection_path.startswith("https://"):
            # HTTP transport (SSE) - for remote/multi-device operation
            # Claude Code requires "type": "http" field for HTTP MCP servers
            # Also need "headers" with Authorization token for authentication
            mcp_server_config: dict = {
                "type": "http",
                "url": connection_path
            }
            # Add Authorization header if coordinator_token is configured
            if self.config.coordinator_token:
                mcp_server_config["headers"] = {
                    "Authorization": f"Bearer {self.config.coordinator_token}"
                }
            mcp_config_dict = {
                "mcpServers": {
                    "agent-pm": mcp_server_config
                }
            }
            transport_type = "HTTP"
        else:
            # Unix Socket transport - for local operation
            mcp_config_dict = {
                "mcpServers": {
                    "agent-pm": {
                        "command": "nc",
                        "args": ["-U", connection_path]
                    }
                }
            }
            transport_type = "Unix Socket"

        mcp_config_json = json.dumps(mcp_config_dict)

        # Debug: Log the MCP config
        logger.debug(f"MCP config: {mcp_config_json}")
        logger.info(f"Agent Instance will connect via {transport_type}: {connection_path}")

        # Handle provider-specific MCP configuration
        # Gemini CLI uses file-based config (.gemini/settings.json)
        # Claude CLI requires a file path for --mcp-config flag
        mcp_config_file_path: Optional[str] = None
        if provider == "gemini":
            self._prepare_gemini_mcp_config(working_dir, connection_path)
            logger.debug("Prepared Gemini MCP config file")
        else:
            # Write MCP config to a temp file for Claude CLI
            # Note: delete=False so the file persists during process lifetime
            with tempfile.NamedTemporaryFile(
                mode='w',
                suffix='.json',
                prefix='mcp_config_',
                delete=False
            ) as f:
                f.write(mcp_config_json)
                mcp_config_file_path = f.name
            logger.debug(f"Wrote MCP config to temp file: {mcp_config_file_path}")

        # Build command
        cmd = [
            cli_command,
            *cli_args,
        ]

        # Add MCP config (only for non-Gemini providers)
        # Gemini reads from .gemini/settings.json automatically
        if provider != "gemini" and mcp_config_file_path:
            cmd.extend(["--mcp-config", mcp_config_file_path])

        # Add model flag if specified
        # Note: Gemini uses -m, Claude uses --model
        if model:
            model_flag = "-m" if provider == "gemini" else "--model"
            cmd.extend([model_flag, model])
            logger.debug(f"Using model: {model} (flag: {model_flag})")

        # Add verbose flag for debugging if enabled
        if self.config.debug_mode:
            if provider == "gemini":
                cmd.append("--debug")
            else:
                cmd.append("--verbose")

        # Add prompt
        # Credentials are now passed via environment variables (AGENT_ID, PROJECT_ID, AGENT_PASSKEY)
        # so the prompt itself is simpler and safer to pass as command-line argument
        # Gemini: uses positional argument for one-shot mode (-p is deprecated)
        # Claude: uses -p flag
        #
        # Windows special handling:
        # On Windows with shell=True, multi-line prompts cause issues with cmd.exe.
        # We use stdin to pipe the prompt instead of command-line argument.
        # Both Gemini CLI and Claude Code support reading prompts from stdin.
        # See: docs/issues/WINDOWS_GEMINI_SPAWN_ISSUE.md
        prompt_file_path: Optional[str] = None

        if is_windows() and provider in ("gemini", "claude"):
            # Write prompt to temp file for piping via stdin
            prompt_fd, prompt_file_path = tempfile.mkstemp(
                suffix='.txt',
                prefix=f'{provider}_prompt_',
                text=True
            )
            with os.fdopen(prompt_fd, 'w', encoding='utf-8') as f:
                f.write(prompt)
            logger.debug(f"Created prompt temp file: {prompt_file_path}")
            # Don't add prompt to cmd; will pipe via stdin
        elif provider == "gemini":
            cmd.append(prompt)
        else:
            cmd.extend(["-p", prompt])

        model_desc = f"{provider}/{model}" if model else provider
        # Use current directory as fallback if working_dir is empty
        if not working_dir:
            working_dir = os.getcwd()
            logger.debug(f"Using fallback working_dir: {working_dir}")

        logger.info(
            f"Spawning {model_desc} instance for {agent_id}/{project_id} "
            f"at {working_dir}"
        )
        logger.debug(f"Command: {' '.join(cmd[:5])}...")

        # Ensure working directory exists
        Path(working_dir).mkdir(parents=True, exist_ok=True)

        # Open log file (keep handle open during process lifetime)
        log_f = open(log_file, "w")

        # Prepare environment
        spawn_env = {
            **os.environ,
            "AGENT_ID": agent_id,
            "PROJECT_ID": project_id,
            "AGENT_PASSKEY": passkey,
            "WORKING_DIRECTORY": working_dir,
        }

        # Spawn process
        # On Windows, shell=True is required to find commands in PATH
        # This is safe since cmd is constructed from configuration, not user input
        if prompt_file_path:
            # Windows: Use 'type' command to pipe prompt file content to stdin
            # Format: type "prompt.txt" | <cli_command> ...
            # Works for both Gemini CLI and Claude Code
            cmd_str = ' '.join(cmd)  # cmd doesn't include prompt yet
            shell_cmd = f'type "{prompt_file_path}" | {cmd_str}'
            logger.debug(f"Windows {provider} shell command: type ... | {cmd_str}")
            process = subprocess.Popen(
                shell_cmd,
                cwd=working_dir,
                stdout=log_f,
                stderr=subprocess.STDOUT,
                shell=True,
                env=spawn_env
            )
        else:
            process = subprocess.Popen(
                cmd,
                cwd=working_dir,
                stdout=log_f,
                stderr=subprocess.STDOUT,
                shell=is_windows(),
                env=spawn_env
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
            log_file_path=str(log_file),
            mcp_config_file=mcp_config_file_path,
            prompt_file=prompt_file_path
        )

        logger.info(f"Spawned instance {agent_id}/{project_id} (PID: {process.pid})")

    def _prepare_gemini_mcp_config(self, working_dir: str, connection_path: str) -> None:
        """Prepare MCP config file for Gemini CLI.

        Gemini CLI reads MCP configuration from .gemini/settings.json in the
        working directory, unlike Claude CLI which accepts --mcp-config flag.

        Args:
            working_dir: Working directory where .gemini/settings.json will be created
            connection_path: Unix socket path or HTTP URL for MCP connection
        """
        gemini_dir = Path(working_dir) / ".gemini"
        gemini_dir.mkdir(parents=True, exist_ok=True)

        # Determine transport type based on connection path
        if connection_path.startswith("http://") or connection_path.startswith("https://"):
            # HTTP transport (SSE) - for remote/multi-device operation
            mcp_server_config: dict = {
                "url": connection_path,
                "trust": True  # Auto-approve tool calls
            }
            # Add Authorization header if coordinator_token is configured
            if self.config.coordinator_token:
                mcp_server_config["headers"] = {
                    "Authorization": f"Bearer {self.config.coordinator_token}"
                }
            config = {
                "mcpServers": {
                    "agent-pm": mcp_server_config
                }
            }
        else:
            # Unix Socket transport - for local operation
            config = {
                "mcpServers": {
                    "agent-pm": {
                        "command": "nc",
                        "args": ["-U", connection_path],
                        "trust": True  # Auto-approve tool calls
                    }
                }
            }

        config_file = gemini_dir / "settings.json"
        with open(config_file, "w") as f:
            json.dump(config, f, indent=2)

        logger.debug(f"Created Gemini MCP config at {config_file}")

    def _build_agent_prompt(self, agent_id: str, project_id: str, passkey: str) -> str:
        """Build the prompt for an Agent Instance.

        The Agent Instance will use this prompt to know how to authenticate
        and what to do. Uses state-driven workflow control via get_next_action.

        Credentials are passed via environment variables for reliability
        (especially on Windows where multi-line command arguments can fail).

        Args:
            agent_id: Agent ID (for logging, actual value passed via env)
            project_id: Project ID (for logging, actual value passed via env)
            passkey: Agent passkey (for logging, actual value passed via env)

        Returns:
            Prompt string for the Agent Instance
        """
        return """You are an AI Agent Instance managed by the AI Agent PM system.

## Authentication (CRITICAL: First Step)
Your credentials are stored in environment variables. To authenticate:

1. Use Bash to read the environment variables:
   ```bash
   echo "AGENT_ID=$AGENT_ID"
   echo "AGENT_PASSKEY=$AGENT_PASSKEY"
   echo "PROJECT_ID=$PROJECT_ID"
   ```
2. Call `authenticate` with the actual values you obtained from step 1

Save the session_token from the response.

## Workflow (CRITICAL: Follow Exactly)
After authenticating, you MUST follow this loop WITHOUT exception:

1. Call `get_next_action` with your session_token
2. Read the `action` and `instruction` fields
3. Execute ONLY what the `instruction` tells you to do
4. Call `get_next_action` again (ALWAYS return to step 1)

NEVER skip step 4. ALWAYS call `get_next_action` after completing each instruction.

## Task Decomposition (Required)
Before executing any actual work, you MUST decompose the task into sub-tasks:
- When `get_next_action` returns action="create_subtasks", use `create_task` tool
- Create 2-5 concrete sub-tasks with `parent_task_id` set to the main task ID
- Only after sub-tasks are created will `get_next_action` guide you to execute them

## Important Rules
- ONLY follow instructions from `get_next_action` - do NOT execute task.description directly
- Task description is for context/understanding only, not for direct execution
- The system controls the workflow; you execute the steps
- If you receive a system_prompt from authenticate, adopt that role
- You are working in the project directory

Begin by reading environment variables with Bash, then call `authenticate`.
"""


async def run_coordinator_async(config: CoordinatorConfig) -> None:
    """Run the Coordinator asynchronously.

    Acquires a lock to prevent multiple Coordinator instances from running
    with the same configuration simultaneously.

    Args:
        config: Coordinator configuration

    Raises:
        SystemExit: If another Coordinator instance is already running.
    """
    from aiagent_runner.lock import CoordinatorLock, CoordinatorAlreadyRunningError

    # Use config_path for lock, fallback to a default identifier
    lock_identifier = config.config_path or "default"
    lock = CoordinatorLock(config_path=lock_identifier)

    try:
        lock.acquire()
        logger.info(f"Acquired coordinator lock: {lock.lock_file_path}")
    except CoordinatorAlreadyRunningError as e:
        logger.error(str(e))
        raise SystemExit(1)

    try:
        coordinator = Coordinator(config)
        await coordinator.start()
    finally:
        lock.release()
        logger.info("Released coordinator lock")


def run_coordinator(config: CoordinatorConfig) -> None:
    """Run the Coordinator synchronously.

    Acquires a lock to prevent multiple Coordinator instances from running
    with the same configuration simultaneously.

    Args:
        config: Coordinator configuration
    """
    asyncio.run(run_coordinator_async(config))
