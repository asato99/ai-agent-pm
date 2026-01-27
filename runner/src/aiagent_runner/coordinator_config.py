# src/aiagent_runner/coordinator_config.py
# Coordinator configuration management
# Reference: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import yaml

from aiagent_runner.log_uploader import LogUploadConfig
from aiagent_runner.platform import get_default_socket_path, get_log_directory


@dataclass
class AIProviderConfig:
    """AI provider configuration."""
    cli_command: str
    cli_args: list[str] = field(default_factory=list)


@dataclass
class AgentConfig:
    """Agent configuration (passkey only, other info from MCP)."""
    passkey: str


@dataclass
class ErrorProtectionConfig:
    """Error protection configuration for spawn cooldown.

    Reference: docs/design/SPAWN_ERROR_PROTECTION.md
    """
    # Enable/disable error protection
    enabled: bool = True

    # Default cooldown time for normal errors (seconds)
    default_cooldown_seconds: int = 60

    # Maximum cooldown time (seconds) - caps quota-based cooldowns
    max_cooldown_seconds: int = 3600

    # Enable quota error detection from logs
    quota_detection_enabled: bool = True

    # Safety margin for quota-based cooldowns (percent)
    quota_margin_percent: int = 10


@dataclass
class CoordinatorConfig:
    """Coordinator configuration.

    The Coordinator is a single orchestrator that:
    1. Polls MCP server for active projects and their assigned agents
    2. Calls get_agent_action(agent_id, project_id) for each pair
    3. Spawns Agent Instances (Claude Code processes) as needed

    Unlike the old Runner which was tied to a single (agent_id, project_id),
    the Coordinator manages ALL agent-project combinations dynamically.

    Multi-device operation:
    - When root_agent_id is set, the Coordinator authenticates as that human agent
    - This enables per-agent working directory resolution for remote operation
    - See: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md
    """
    # Polling settings
    polling_interval: int = 10
    max_concurrent: int = 3

    # Server URL (HTTP base URL for both MCP and REST API)
    # When specified, MCP endpoint is {server_url}/mcp, REST API is {server_url}/api/v1/...
    # For local Unix socket operation, leave this None and set mcp_socket_path instead
    server_url: Optional[str] = None

    # MCP connection (Unix socket path for local operation)
    # When server_url is set, this is ignored (MCP uses {server_url}/mcp)
    # When server_url is None, this specifies the Unix socket path
    mcp_socket_path: Optional[str] = None

    # Phase 5: Coordinator token for Coordinator-only API authorization
    # Reference: Sources/MCPServer/Authorization/ToolAuthorization.swift
    coordinator_token: Optional[str] = None

    # Multi-device: Root agent ID for authentication
    # When set, Coordinator authenticates as this human agent to get proper working directories
    root_agent_id: Optional[str] = None

    # AI providers (how to launch each AI type)
    ai_providers: dict[str, AIProviderConfig] = field(default_factory=dict)

    # Agents (passkey only - ai_type, system_prompt come from MCP)
    agents: dict[str, AgentConfig] = field(default_factory=dict)

    # Logging
    log_directory: Optional[str] = None

    # Log upload configuration
    log_upload: Optional[LogUploadConfig] = None

    # Debug mode (adds --verbose to CLI commands)
    debug_mode: bool = True

    # Error protection configuration
    error_protection: ErrorProtectionConfig = field(default_factory=ErrorProtectionConfig)

    # Path to config file (set automatically by from_yaml)
    config_path: Optional[str] = None

    def __post_init__(self):
        """Validate configuration after initialization."""
        if self.polling_interval <= 0:
            raise ValueError("polling_interval must be positive")
        if self.max_concurrent <= 0:
            raise ValueError("max_concurrent must be positive")

        # Set default MCP socket path if not specified and no server_url
        # Uses platform-specific default (empty on Windows - requires HTTP)
        if self.server_url is None and self.mcp_socket_path is None:
            self.mcp_socket_path = get_default_socket_path()

        # Phase 5: Set coordinator token from environment if not specified
        if self.coordinator_token is None:
            self.coordinator_token = os.environ.get("MCP_COORDINATOR_TOKEN")

        # Ensure default Claude provider exists
        if "claude" not in self.ai_providers:
            self.ai_providers["claude"] = AIProviderConfig(
                cli_command="claude",
                cli_args=["--dangerously-skip-permissions"]
            )

        # Set log_upload endpoint from REST API base URL
        if self.log_upload and self.log_upload.enabled and not self.log_upload.endpoint:
            base_url = self.get_rest_api_base_url()
            if base_url:
                self.log_upload.endpoint = f"{base_url}/api/v1/execution-logs/upload"
            else:
                raise ValueError(
                    "Cannot determine REST API URL for log_upload. "
                    "Set server_url or ensure AIAGENTPM_WEBSERVER_PORT is set."
                )

    def get_mcp_connection_path(self) -> str:
        """Get MCP connection path (HTTP URL or Unix socket).

        Returns:
            HTTP URL ({server_url}/mcp) if server_url is set,
            otherwise the Unix socket path.
        """
        if self.server_url:
            return f"{self.server_url.rstrip('/')}/mcp"
        return self.mcp_socket_path or ""

    def get_rest_api_base_url(self) -> Optional[str]:
        """Get REST API base URL.

        Returns:
            Base URL for REST API, or None if not determinable.
            - If server_url is set: returns server_url
            - If mcp_socket_path is Unix socket: returns http://localhost:{AIAGENTPM_WEBSERVER_PORT}
        """
        if self.server_url:
            return self.server_url.rstrip('/')

        # Unix socket means local operation - use localhost with REST port
        if self.mcp_socket_path and not self.mcp_socket_path.startswith("http"):
            port = os.environ.get("AIAGENTPM_WEBSERVER_PORT", "8080")
            return f"http://localhost:{port}"

        return None

    @classmethod
    def from_yaml(cls, path: Path) -> "CoordinatorConfig":
        """Load configuration from YAML file.

        Example YAML:
        ```yaml
        polling_interval: 10
        max_concurrent: 3

        # MCP connection: Unix socket (local) or HTTP URL (remote)
        # Local (macOS): ~/Library/Application Support/AIAgentPM/mcp.sock
        # Local (Linux): ~/.local/share/aiagent-runner/mcp.sock
        # Windows/Remote: http://192.168.1.100:8080/mcp (HTTP required)
        mcp_socket_path: http://192.168.1.100:8080/mcp

        # Phase 5: Coordinator token for Coordinator-only API calls
        # Can also be set via MCP_COORDINATOR_TOKEN environment variable
        coordinator_token: ${MCP_COORDINATOR_TOKEN}

        # Multi-device operation: Root agent for authentication
        # When set, Coordinator authenticates as this human agent
        # This enables per-agent working directory resolution
        root_agent_id: human-frontend-lead

        ai_providers:
          claude:
            cli_command: claude
            cli_args: ["--dangerously-skip-permissions"]
          gemini:
            cli_command: gemini-cli
            cli_args: ["--project", "my-project"]

        agents:
          agt_developer:
            passkey: secret123
          agt_reviewer:
            passkey: secret456
        ```

        Args:
            path: Path to YAML configuration file

        Returns:
            CoordinatorConfig instance
        """
        with open(path) as f:
            data = yaml.safe_load(f)

        # Parse AI providers
        ai_providers = {}
        for name, provider_data in data.get("ai_providers", {}).items():
            cli_args = provider_data.get("cli_args", [])
            if isinstance(cli_args, str):
                cli_args = cli_args.split()
            ai_providers[name] = AIProviderConfig(
                cli_command=provider_data.get("cli_command", name),
                cli_args=cli_args
            )

        # Parse agents
        agents = {}
        for agent_id, agent_data in data.get("agents", {}).items():
            passkey = agent_data.get("passkey", "")
            # Support environment variable expansion
            if passkey.startswith("${") and passkey.endswith("}"):
                env_var = passkey[2:-1]
                passkey = os.environ.get(env_var, "")
            agents[agent_id] = AgentConfig(passkey=passkey)

        # Parse coordinator_token (supports environment variable expansion)
        coordinator_token = data.get("coordinator_token")
        if coordinator_token and coordinator_token.startswith("${") and coordinator_token.endswith("}"):
            env_var = coordinator_token[2:-1]
            coordinator_token = os.environ.get(env_var)

        # Parse log_upload configuration (endpoint is derived from server_url or mcp_socket_path)
        log_upload = None
        log_upload_data = data.get("log_upload")
        if log_upload_data and log_upload_data.get("enabled"):
            log_upload = LogUploadConfig(
                enabled=True,
                max_file_size_mb=log_upload_data.get("max_file_size_mb", 10),
                retry_count=log_upload_data.get("retry_count", 3),
                retry_delay_seconds=log_upload_data.get("retry_delay_seconds", 1.0),
            )
            # Note: endpoint is set in __post_init__ via get_rest_api_base_url()

        # Parse error_protection configuration
        error_protection = ErrorProtectionConfig()
        error_protection_data = data.get("error_protection")
        if error_protection_data:
            error_protection = ErrorProtectionConfig(
                enabled=error_protection_data.get("enabled", True),
                default_cooldown_seconds=error_protection_data.get("default_cooldown_seconds", 60),
                max_cooldown_seconds=error_protection_data.get("max_cooldown_seconds", 3600),
                quota_detection_enabled=error_protection_data.get("quota_detection_enabled", True),
                quota_margin_percent=error_protection_data.get("quota_margin_percent", 10),
            )

        return cls(
            polling_interval=data.get("polling_interval", 10),
            max_concurrent=data.get("max_concurrent", 3),
            server_url=data.get("server_url"),
            mcp_socket_path=data.get("mcp_socket_path"),
            coordinator_token=coordinator_token,
            root_agent_id=data.get("root_agent_id"),
            ai_providers=ai_providers,
            agents=agents,
            log_directory=data.get("log_directory"),
            log_upload=log_upload,
            debug_mode=data.get("debug_mode", True),
            error_protection=error_protection,
            config_path=str(path),
        )

    def get_provider(self, ai_type: str) -> AIProviderConfig:
        """Get AI provider configuration.

        Args:
            ai_type: AI type (e.g., "claude", "gemini")

        Returns:
            AIProviderConfig for the specified type, or default Claude config
        """
        return self.ai_providers.get(ai_type, self.ai_providers.get("claude"))

    def get_agent_passkey(self, agent_id: str) -> Optional[str]:
        """Get passkey for an agent.

        Args:
            agent_id: Agent ID

        Returns:
            Passkey if configured, None otherwise
        """
        agent = self.agents.get(agent_id)
        return agent.passkey if agent else None
