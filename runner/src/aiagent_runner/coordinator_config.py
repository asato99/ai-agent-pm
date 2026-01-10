# src/aiagent_runner/coordinator_config.py
# Coordinator configuration management
# Reference: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import yaml


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
class CoordinatorConfig:
    """Coordinator configuration.

    The Coordinator is a single orchestrator that:
    1. Polls MCP server for active projects and their assigned agents
    2. Calls get_agent_action(agent_id, project_id) for each pair
    3. Spawns Agent Instances (Claude Code processes) as needed

    Unlike the old Runner which was tied to a single (agent_id, project_id),
    the Coordinator manages ALL agent-project combinations dynamically.
    """
    # Polling settings
    polling_interval: int = 10
    max_concurrent: int = 3

    # MCP connection (Unix socket - used by both Coordinator and Agent Instances)
    # All components connect to the SAME daemon started by the app
    mcp_socket_path: Optional[str] = None

    # Phase 5: Coordinator token for Coordinator-only API authorization
    # Reference: Sources/MCPServer/Authorization/ToolAuthorization.swift
    coordinator_token: Optional[str] = None

    # AI providers (how to launch each AI type)
    ai_providers: dict[str, AIProviderConfig] = field(default_factory=dict)

    # Agents (passkey only - ai_type, system_prompt come from MCP)
    agents: dict[str, AgentConfig] = field(default_factory=dict)

    # Logging
    log_directory: Optional[str] = None

    # Debug mode (adds --verbose to CLI commands)
    debug_mode: bool = True

    def __post_init__(self):
        """Validate configuration after initialization."""
        if self.polling_interval <= 0:
            raise ValueError("polling_interval must be positive")
        if self.max_concurrent <= 0:
            raise ValueError("max_concurrent must be positive")

        # Set default MCP socket path if not specified
        if self.mcp_socket_path is None:
            self.mcp_socket_path = os.path.expanduser(
                "~/Library/Application Support/AIAgentPM/mcp.sock"
            )

        # Phase 5: Set coordinator token from environment if not specified
        if self.coordinator_token is None:
            self.coordinator_token = os.environ.get("MCP_COORDINATOR_TOKEN")

        # Ensure default Claude provider exists
        if "claude" not in self.ai_providers:
            self.ai_providers["claude"] = AIProviderConfig(
                cli_command="claude",
                cli_args=["--dangerously-skip-permissions"]
            )

    @classmethod
    def from_yaml(cls, path: Path) -> "CoordinatorConfig":
        """Load configuration from YAML file.

        Example YAML:
        ```yaml
        polling_interval: 10
        max_concurrent: 3
        mcp_socket_path: ~/Library/Application Support/AIAgentPM/mcp.sock

        # Phase 5: Coordinator token for Coordinator-only API calls
        # Can also be set via MCP_COORDINATOR_TOKEN environment variable
        coordinator_token: ${MCP_COORDINATOR_TOKEN}

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

        return cls(
            polling_interval=data.get("polling_interval", 10),
            max_concurrent=data.get("max_concurrent", 3),
            mcp_socket_path=data.get("mcp_socket_path"),
            coordinator_token=coordinator_token,
            ai_providers=ai_providers,
            agents=agents,
            log_directory=data.get("log_directory"),
            debug_mode=data.get("debug_mode", True),
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
